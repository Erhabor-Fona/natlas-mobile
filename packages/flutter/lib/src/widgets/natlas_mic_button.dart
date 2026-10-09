import 'dart:typed_data';

import 'package:flutter/material.dart';

/// A microphone button that manages recording state and invokes a callback
/// with the raw audio bytes when recording stops.
///
/// This widget handles UI state only. Plug in your platform audio recorder
/// (e.g. `record` package) via [onRecordingComplete].
///
/// ```dart
/// NAtlasMicButton(
///   language: NAtlasLanguage.hausa,
///   onRecordingComplete: (bytes) async {
///     final result = await client.voiceChat(
///       audio: bytes,
///       language: NAtlasLanguage.hausa,
///     );
///     setState(() => reply = result.reply);
///   },
/// )
/// ```
class NAtlasMicButton extends StatefulWidget {
  /// Called with raw audio bytes (ogg/opus by default) when recording stops.
  final Future<void> Function(Uint8List bytes) onRecordingComplete;

  /// Called when recording starts — use this to start your audio recorder.
  final Future<Uint8List> Function()? onStartRecording;

  /// Colour of the button when idle.
  final Color? idleColor;

  /// Colour of the button while recording.
  final Color? recordingColor;

  /// Size of the icon inside the button.
  final double iconSize;

  const NAtlasMicButton({
    super.key,
    required this.onRecordingComplete,
    this.onStartRecording,
    this.idleColor,
    this.recordingColor,
    this.iconSize = 32,
  });

  @override
  State<NAtlasMicButton> createState() => _NAtlasMicButtonState();
}

class _NAtlasMicButtonState extends State<NAtlasMicButton>
    with SingleTickerProviderStateMixin {
  bool _recording = false;
  bool _processing = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.stop();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_processing) return;

    if (!_recording) {
      // Start recording
      setState(() => _recording = true);
      _pulseController.repeat(reverse: true);
    } else {
      // Stop recording
      _pulseController.stop();
      setState(() {
        _recording = false;
        _processing = true;
      });

      try {
        // If caller provided a recorder, use it; otherwise return empty bytes
        // so the caller can substitute their own recorder implementation.
        final bytes = widget.onStartRecording != null
            ? await widget.onStartRecording!()
            : Uint8List(0);
        await widget.onRecordingComplete(bytes);
      } finally {
        if (mounted) setState(() => _processing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final idleColor = widget.idleColor ?? theme.colorScheme.primary;
    final recordingColor =
        widget.recordingColor ?? theme.colorScheme.error;

    final color = _recording ? recordingColor : idleColor;
    final icon = _processing
        ? null
        : Icon(
            _recording ? Icons.stop_rounded : Icons.mic_rounded,
            color: Colors.white,
            size: widget.iconSize,
          );

    return GestureDetector(
      onTap: _toggle,
      child: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (context, child) {
          final scale = _recording ? _pulseAnim.value : 1.0;
          return Transform.scale(
            scale: scale,
            child: child,
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: widget.iconSize * 2,
          height: widget.iconSize * 2,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: _recording
                ? [BoxShadow(color: color.withAlpha(128), blurRadius: 12, spreadRadius: 4)]
                : null,
          ),
          child: Center(
            child: _processing
                ? SizedBox(
                    width: widget.iconSize * 0.7,
                    height: widget.iconSize * 0.7,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : icon,
          ),
        ),
      ),
    );
  }
}
