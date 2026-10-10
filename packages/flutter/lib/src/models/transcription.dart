import '../language.dart';

/// Result of a speech-to-text transcription.
class TranscriptionResult {
  /// The transcribed text.
  final String text;

  /// The language the ASR model was run with.
  ///
  /// This echoes the language you requested — the models are per-language, so
  /// it is not detection. Sending the wrong one yields confident nonsense.
  final NAtlasLanguage language;

  /// Length of the submitted audio, in seconds.
  final double durationSeconds;

  /// Creates a transcription result.
  const TranscriptionResult({
    required this.text,
    required this.language,
    required this.durationSeconds,
  });

  /// Parses a `POST /v1/audio/transcriptions` response.
  factory TranscriptionResult.fromJson(Map<String, dynamic> json) {
    return TranscriptionResult(
      text: json['text'] as String? ?? '',
      language: NAtlasLanguage.fromCode(json['language'] as String? ?? 'en'),
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  String toString() =>
      'TranscriptionResult(text: "${text.length > 50 ? "${text.substring(0, 50)}…" : text}", '
      'language: ${language.code}, duration: ${durationSeconds}s)';
}

/// Result of a combined voice → text → LLM reply pipeline.
class VoiceChatResult {
  /// What the speaker said.
  final TranscriptionResult transcript;

  /// What N-ATLaS replied.
  final String reply;

  /// Creates a voice-chat result.
  const VoiceChatResult({required this.transcript, required this.reply});

  @override
  String toString() =>
      'VoiceChatResult(transcript: $transcript, reply: ${reply.length} chars)';
}
