/// A single message in a conversation.
class ChatMessage {
  /// One of `system`, `user`, or `assistant`.
  final String role;

  /// The message text.
  final String content;

  /// Creates a message with an explicit [role].
  ///
  /// Prefer [ChatMessage.user], [ChatMessage.assistant] or
  /// [ChatMessage.system] unless you need a role outside those three.
  const ChatMessage({required this.role, required this.content});

  /// Create a user message.
  factory ChatMessage.user(String content) =>
      ChatMessage(role: 'user', content: content);

  /// Create an assistant message.
  factory ChatMessage.assistant(String content) =>
      ChatMessage(role: 'assistant', content: content);

  /// Create a system message.
  factory ChatMessage.system(String content) =>
      ChatMessage(role: 'system', content: content);

  /// Serialises to the gateway's wire format.
  Map<String, dynamic> toJson() => {'role': role, 'content': content};

  /// Parses a message from the gateway's wire format.
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'] as String,
        content: json['content'] as String,
      );

  @override
  String toString() => 'ChatMessage(role: $role, content: $content)';
}
