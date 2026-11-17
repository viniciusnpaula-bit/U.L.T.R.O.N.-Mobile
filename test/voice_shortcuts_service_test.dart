import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ultron_mobile/services/conversation_history.dart';
import 'package:ultron_mobile/services/voice_shortcuts_service.dart';

Future<ConversationHistory> _inMemoryHistory() async {
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 2,
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

  test('creates, lists, matches, and removes voice shortcuts', () async {
    final history = await _inMemoryHistory();
    addTearDown(() async => (await history.database).close());
    final service = VoiceShortcutsService(history: history);

    final shortcut = await service.add(
      triggerPhrase: 'Abrir painel de segurança',
      actionType: 'open_security',
      actionPayload: '{}',
      requiresConfirmation: false,
    );
    expect((await service.list()).length, 1);

    final matched = await service.match('abrir painel de seguranca');
    expect(matched?.id, shortcut.id);
    expect(matched?.actionType, 'open_security');

    await service.remove(shortcut.id!);
    expect(await service.list(), isEmpty);
  });

  test('enforces fail-closed confirmation when requiresConfirmation is true', () async {
    final history = await _inMemoryHistory();
    addTearDown(() async => (await history.database).close());
    final service = VoiceShortcutsService(history: history);

    final shortcut = await service.add(
      triggerPhrase: 'Desligar computador',
      actionType: 'desktop_shutdown',
      actionPayload: '{"cmd":"shutdown"}',
      requiresConfirmation: true,
    );

    var executedCount = 0;
    var confirmCalls = 0;

    final denied = await service.execute(
      shortcut,
      confirm: (_) async {
        confirmCalls += 1;
        return false;
      },
      run: (_) async {
        executedCount += 1;
      },
    );
    expect(confirmCalls, 1);
    expect(executedCount, 0);
    expect(denied.executed, isFalse);
    expect(denied.deniedByUser, isTrue);

    final approved = await service.execute(
      shortcut,
      confirm: (_) async {
        confirmCalls += 1;
        return true;
      },
      run: (_) async {
        executedCount += 1;
      },
    );
    expect(confirmCalls, 2);
    expect(executedCount, 1);
    expect(approved.executed, isTrue);
  });
}
