import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'; // debugPrint
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Thin wrapper over the `record` package that yields raw bytes ready for
/// [NAtlasClient.transcribe].
///
/// Records Opus in an Ogg container at 16 kHz mono — the format the ASR models
/// want, so the gateway's ffmpeg step becomes a no-op and uploads stay small.
class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _path;

  /// Request microphone permission. Returns true if granted.
  ///
  /// Uses `record`'s own check rather than permission_handler. On iOS,
  /// permission_handler compiles each permission in or out via Podfile
  /// preprocessor macros (PERMISSION_MICROPHONE=1) and, since its 8.0.0,
  /// excludes everything by default — so an unconfigured build reports
  /// `denied` without ever showing the system prompt. `flutter create`
  /// regenerates the Podfile and silently drops any such config.
  ///
  /// `AudioRecorder.hasPermission()` asks the platform directly and prompts
  /// when needed, with no Podfile setup to lose.
  Future<bool> requestPermission() => _recorder.hasPermission();

  /// True while a recording is in progress.
  Future<bool> get isRecording => _recorder.isRecording();

  /// Container extension for [recordingEncoder]. Also sent to the gateway as
  /// the upload filename, which ffmpeg uses as a format hint.
  static const String fileExtension = 'wav';

  /// WAV, after both compressed formats failed on iOS.
  ///
  /// The history is worth keeping, because both failures were about the
  /// container rather than the codec:
  ///
  ///   * `opus` — `record` writes Opus into a **CAF** container on iOS, not
  ///     Ogg, and produced no usable file.
  ///   * `aacLc` — the .m4a arrived at the gateway with no `moov` atom. That
  ///     atom is the MP4 index and lives at the END of the file, written when
  ///     the recording is finalised. ffmpeg rejected every upload with
  ///     "moov atom not found". Waiting for the file size to settle did not
  ///     help, so the finalise step simply never happened.
  ///
  /// WAV has no index to write: a header followed by raw samples. Even if the
  /// header's length fields are stale, ffmpeg decodes to end-of-file, so a
  /// truncated WAV degrades instead of failing outright. At 16 kHz mono 16-bit
  /// it is also already the ASR models' native format — about 32 KB/s, so a
  /// ten-second clip is ~320 KB. Larger than AAC, and worth it for a format
  /// with nothing to go wrong.
  static const AudioEncoder recordingEncoder = AudioEncoder.wav;

  /// Start recording.
  ///
  /// Throws [StateError] with a specific reason if the microphone is denied or
  /// the recorder fails to engage.
  Future<void> start() async {
    if (!await requestPermission()) {
      throw StateError('Microphone permission denied');
    }

    if (!await _recorder.isEncoderSupported(recordingEncoder)) {
      throw StateError('This device cannot record ${recordingEncoder.name}');
    }

    final dir = await getTemporaryDirectory();
    _path =
        '${dir.path}/natlas_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';

    await _recorder.start(
      const RecordConfig(
        encoder: recordingEncoder,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: _path!,
    );

    // start() returning does not guarantee the recorder engaged. Without this
    // check a failure surfaces much later as an unexplained empty file.
    if (!await _recorder.isRecording()) {
      throw StateError('Recorder did not start');
    }
  }

  /// Wait until [file] exists and its size stops changing.
  ///
  /// An MP4/M4A container keeps its index — the `moov` atom — at the END of
  /// the file, written when the recording is finalised. `AudioRecorder.stop()`
  /// can return before iOS has flushed that, and reading the file at that
  /// moment yields something ffmpeg rejects with:
  ///
  ///     [mov,mp4,m4a,...] moov atom not found
  ///     Invalid data found when processing input
  ///
  /// Polling until the size is stable across two consecutive reads avoids
  /// uploading a half-written container.
  static Future<void> _waitForStableFile(
    File file, {
    Duration timeout = const Duration(seconds: 5),
    Duration interval = const Duration(milliseconds: 100),
  }) async {
    final deadline = DateTime.now().add(timeout);
    int lastSize = -1;
    int stableReads = 0;

    while (DateTime.now().isBefore(deadline)) {
      if (file.existsSync()) {
        final size = await file.length();
        if (size > 0 && size == lastSize) {
          if (++stableReads >= 2) return;
        } else {
          stableReads = 0;
        }
        lastSize = size;
      }
      await Future<void>.delayed(interval);
    }

    if (lastSize <= 0) {
      throw StateError('Recording file never appeared');
    }
    // Size still moving after the timeout — use it anyway rather than losing
    // the recording outright.
  }

  /// Stop recording and return the bytes.
  ///
  /// Throws [StateError] naming the step that failed, rather than returning
  /// null for every possible cause.
  Future<Uint8List> stop() async {
    final path = await _recorder.stop();
    if (path == null) {
      throw StateError('Recorder returned no file — was it recording?');
    }

    final file = File(path);

    // Do not read until the container has been finalised; see the note on
    // _waitForStableFile.
    await _waitForStableFile(file);

    if (!file.existsSync()) {
      throw StateError('Recording file missing at $path');
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('Recording was empty — hold the button while speaking');
    }

    // Log the container signature. The first bytes identify the format
    // unambiguously and have twice now been the fastest route to the real
    // problem: "RIFF" at offset 0 is WAV, "ftyp" at offset 4 is MP4/M4A.
    debugPrint('[natlas] recorded ${bytes.length} bytes at $path');
    debugPrint('[natlas] header: ${_describeHeader(bytes)}');

    // Clean up the temp file — the bytes are in memory now.
    try {
      await file.delete();
    } on FileSystemException {
      // Non-fatal: the OS will reclaim the temp directory.
    }
    return bytes;
  }

  /// Render the first 16 bytes as hex plus printable ASCII, and name the
  /// container if the signature is recognised.
  static String _describeHeader(Uint8List bytes) {
    final head = bytes.take(16).toList();
    final hex = head.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    final ascii = head
        .map((b) => (b >= 0x20 && b < 0x7F) ? String.fromCharCode(b) : '.')
        .join();

    String kind = 'unknown';
    if (ascii.startsWith('RIFF')) {
      kind = 'WAV (RIFF)';
    } else if (head.length >= 8 &&
        ascii.substring(4, 8) == 'ftyp') {
      kind = 'MP4/M4A (ftyp)';
    } else if (ascii.startsWith('caff')) {
      kind = 'CAF';
    } else if (ascii.startsWith('OggS')) {
      kind = 'Ogg';
    }
    return '$kind | $hex | $ascii';
  }

  /// Discard the current recording without returning bytes.
  Future<void> cancel() async {
    await _recorder.cancel();
    _path = null;
  }

  /// Stream of amplitude readings, for a live waveform.
  Stream<Amplitude> amplitudeStream() =>
      _recorder.onAmplitudeChanged(const Duration(milliseconds: 150));

  void dispose() => _recorder.dispose();
}
