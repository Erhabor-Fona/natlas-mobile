import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
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
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// True while a recording is in progress.
  Future<bool> get isRecording => _recorder.isRecording();

  /// Start recording. Throws [StateError] if permission is denied.
  Future<void> start() async {
    if (!await requestPermission()) {
      throw StateError('Microphone permission denied');
    }

    final dir = await getTemporaryDirectory();
    _path = '${dir.path}/natlas_${DateTime.now().millisecondsSinceEpoch}.ogg';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.opus,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: _path!,
    );
  }

  /// Stop recording and return the bytes. Returns null if nothing was recorded.
  Future<Uint8List?> stop() async {
    final path = await _recorder.stop();
    if (path == null) return null;

    final file = File(path);
    if (!file.existsSync()) return null;

    final bytes = await file.readAsBytes();
    // Clean up the temp file — the bytes are in memory now.
    try {
      await file.delete();
    } on FileSystemException {
      // Non-fatal: the OS will reclaim the temp directory.
    }
    return bytes;
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
