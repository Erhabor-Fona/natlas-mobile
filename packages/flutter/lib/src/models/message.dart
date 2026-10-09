/// A single message in a conversation.
class ChatMessage {
  final String role;
  final String content;

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

  Map<String, dynamic> toJson() => {'role': role, 'content': content};

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'] as String,
        content: json['content'] as String,
      );

  @override
  String toString() => 'ChatMessage(role: $role, content: $content)';
}
