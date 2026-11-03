import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ultron_mobile/models/chat_message.dart';
import 'package:ultron_mobile/services/conversation_history.dart';

ChatMessage _message(
  String conversationId,
  String content,
  DateTime at, {
  ChatRole role = ChatRole.user,
}) =>
    ChatMessage(
      id: null,
      conversationId: conversationId,
      role: role,
      content: content,
      createdAt: at,
    );

Future<ConversationHistory> _open() async {
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      // inMemoryDatabasePath is cached by path, so without this every test
      // would share one database.
      singleInstance: false,
      onCreate: (db, _) async {
        for (final statement in ConversationHistory.schema) {
          await db.execute(statement);
        }
      },
    ),
  );
  return ConversationHistory.forDatabase(db);
}

void main() {
  sqfliteFfiInit();

  test('saves and reads back in chronological order', () async {
    final history = await _open();
    final start = DateTime.utc(2026, 1, 1, 12);
    await history.save(_message('a', 'primeira', start));
    await history.save(_message(
      'a',
      'segunda',
      start.add(const Duration(minutes: 1)),
      role: ChatRole.assistant,
    ));

    final rows = await history.messages();
    expect(rows.map((m) => m.content), ['primeira', 'segunda']);
    expect(rows.last.role, ChatRole.assistant);
    expect(rows.first.createdAt.toUtc(), start);
  });

  test('filters by conversation and keeps the newest window', () async {
    final history = await _open();
    final start = DateTime.utc(2026, 1, 1);
    for (var i = 0; i < 5; i++) {
      final at = start.add(Duration(minutes: i));
      await history.save(_message('a', 'a$i', at));
      await history.save(_message('b', 'b$i', at));
    }

    final a = await history.messages(conversationId: 'a');
    expect(a.map((m) => m.content), ['a0', 'a1', 'a2', 'a3', 'a4']);

    final newest = await history.messages(conversationId: 'a', limit: 2);
    expect(newest.map((m) => m.content), ['a3', 'a4']);
  });

  test('deletes one conversation or everything', () async {
    final history = await _open();
    await history.save(_message('a', 'x', DateTime.utc(2026)));
    await history.save(_message('b', 'y', DateTime.utc(2026)));

    expect(await history.deleteConversation('a'), 1);
    expect((await history.messages()).map((m) => m.conversationId), ['b']);

    expect(await history.clear(), 1);
    expect(await history.messages(), isEmpty);
  });
}
