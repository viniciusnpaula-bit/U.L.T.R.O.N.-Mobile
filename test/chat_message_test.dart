import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/models/chat_message.dart';

void main() {
  test('ChatMessage serializes and restores its fields', () {
    final createdAt = DateTime.utc(2026, 11, 2, 12, 30);
    final message = ChatMessage(
      id: 7,
      conversationId: 'default',
      role: ChatRole.user,
      content: 'Olá, U.L.T.R.O.N.',
      createdAt: createdAt,
    );

    final restored = ChatMessage.fromMap(message.toMap());

    expect(restored.id, 7);
    expect(restored.conversationId, 'default');
    expect(restored.role, ChatRole.user);
    expect(restored.content, 'Olá, U.L.T.R.O.N.');
    expect(restored.createdAt.toUtc(), createdAt);
  });

  test('unknown role falls back to system', () {
    final message = ChatMessage.fromMap({
      'id': 1,
      'conversation_id': 'default',
      'role': 'future_role',
      'content': 'test',
      'created_at': DateTime.utc(2026).toIso8601String(),
    });

    expect(message.role, ChatRole.system);
  });
}
