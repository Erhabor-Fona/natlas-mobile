/// Non-streaming chat completion response.
class ChatResponse {
  final String id;
  final String content;
  final int promptTokens;
  final int completionTokens;

  const ChatResponse({
    required this.id,
    required this.content,
    required this.promptTokens,
    required this.completionTokens,
  });

  int get totalTokens => promptTokens + completionTokens;

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    final choices = json['choices'] as List<dynamic>;
    final message = choices.first['message'] as Map<String, dynamic>;
    final usage = (json['usage'] as Map<String, dynamic>?) ?? {};
    return ChatResponse(
      id: json['id'] as String? ?? '',
      content: message['content'] as String? ?? '',
      promptTokens: usage['prompt_tokens'] as int? ?? 0,
      completionTokens: usage['completion_tokens'] as int? ?? 0,
    );
  }

  @override
  String toString() => 'ChatResponse(id: $id, content: ${content.length} chars)';
}

/// A single streamed chunk from a chat completion.
class ChatStreamChunk {
  final String id;

  /// The new text in this chunk (delta only — not accumulated).
  final String delta;

  const ChatStreamChunk({required this.id, required this.delta});

  factory ChatStreamChunk.fromJson(Map<String, dynamic> json) {
    final choices = json['choices'] as List<dynamic>;
    final deltaMap = choices.first['delta'] as Map<String, dynamic>? ?? {};
    return ChatStreamChunk(
      id: json['id'] as String? ?? '',
      delta: deltaMap['content'] as String? ?? '',
    );
  }
}
