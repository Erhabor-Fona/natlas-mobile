import '../language.dart';

/// Result of a speech-to-text transcription.
class TranscriptionResult {
  final String text;
  final NAtlasLanguage language;
  final double durationSeconds;

  const TranscriptionResult({
    required this.text,
    required this.language,
    required this.durationSeconds,
  });

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
  final TranscriptionResult transcript;
  final String reply;

  const VoiceChatResult({required this.transcript, required this.reply});

  @override
  String toString() =>
      'VoiceChatResult(transcript: $transcript, reply: ${reply.length} chars)';
}
