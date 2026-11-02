enum ChatRole { user, assistant, system }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final int? id;
  final String conversationId;
  final ChatRole role;
  final String content;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'conversation_id': conversationId,
        'role': role.name,
        'content': content,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory ChatMessage.fromMap(Map<String, Object?> map) => ChatMessage(
        id: map['id'] as int?,
        conversationId: map['conversation_id'] as String,
        role: ChatRole.values.firstWhere(
          (role) => role.name == map['role'],
          orElse: () => ChatRole.system,
        ),
        content: map['content'] as String,
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      );
}
