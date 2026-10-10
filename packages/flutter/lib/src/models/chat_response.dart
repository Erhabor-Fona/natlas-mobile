/// Non-streaming chat completion response.
class ChatResponse {
  /// Gateway-assigned completion id.
  final String id;

  /// The assistant's reply text.
  final String content;

  /// Tokens consumed by the prompt, including the injected language hint.
  final int promptTokens;

  /// Tokens produced by the model.
  final int completionTokens;

  /// Creates a chat response.
  const ChatResponse({
    required this.id,
    required this.content,
    required this.promptTokens,
    required this.completionTokens,
  });

  /// Prompt plus completion tokens.
  int get totalTokens => promptTokens + completionTokens;

  /// Parses a non-streaming `POST /v1/chat/completions` response.
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
  String toString() =>
      'ChatResponse(id: $id, content: ${content.length} chars)';
}

/// A single streamed chunk from a chat completion.
class ChatStreamChunk {
  /// Gateway-assigned completion id, shared by every chunk of one reply.
  final String id;

  /// The new text in this chunk (delta only — not accumulated).
  final String delta;

  /// Creates a stream chunk.
  const ChatStreamChunk({required this.id, required this.delta});

  /// Parses one `data:` line from the SSE stream.
  factory ChatStreamChunk.fromJson(Map<String, dynamic> json) {
    final choices = json['choices'] as List<dynamic>;
    final deltaMap = choices.first['delta'] as Map<String, dynamic>? ?? {};
    return ChatStreamChunk(
      id: json['id'] as String? ?? '',
      delta: deltaMap['content'] as String? ?? '',
    );
  }
}
