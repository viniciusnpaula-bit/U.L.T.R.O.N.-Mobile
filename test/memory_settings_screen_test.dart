import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ultron_mobile/services/conversation_history.dart';
import 'package:ultron_mobile/services/user_preferences_service.dart';
import 'package:ultron_mobile/services/voice_corrections_service.dart';
import 'package:ultron_mobile/services/voice_shortcuts_service.dart';
import 'package:ultron_mobile/ui/screens/memory_settings_screen.dart';

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

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition,
) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
    if (condition()) return;
  }
}

void main() {
  sqfliteFfiInit();

  testWidgets('MemorySettingsScreen displays saved entries and deletes individual items', (tester) async {
    late ConversationHistory history;
    late VoiceCorrectionsService corrections;
    late VoiceShortcutsService shortcuts;
    late UserPreferencesService preferences;

    await tester.runAsync(() async {
      history = await _inMemoryHistory();
      corrections = VoiceCorrectionsService(history: history);
      shortcuts = VoiceShortcutsService(history: history);
      preferences = UserPreferencesService(history: history);

      await corrections.add('ultram', 'Ultron');
      await shortcuts.add(
        triggerPhrase: 'Bloquear tela',
        actionType: 'lock_app',
        actionPayload: '{}',
      );
      await preferences.set('resposta_curta', 'sim');
    });

    addTearDown(() async {
      await (await history.database).close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MemorySettingsScreen(
          correctionsService: corrections,
          shortcutsService: shortcuts,
          preferencesService: preferences,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () => find.textContaining('ultram').evaluate().isNotEmpty,
    );

    expect(find.textContaining('ultram'), findsOneWidget);
    expect(find.textContaining('Ultron'), findsOneWidget);
    expect(find.textContaining('Bloquear tela'), findsOneWidget);
    expect(find.textContaining('resposta_curta'), findsOneWidget);

    await tester.tap(find.byTooltip('Remover correção').first);
    await _pumpUntil(
      tester,
      () => find.textContaining('ultram').evaluate().isEmpty,
    );
    await tester.runAsync(() async {
      expect(await corrections.list(), isEmpty);
    });

    await tester.tap(find.byTooltip('Remover atalho').first);
    await _pumpUntil(
      tester,
      () => find.textContaining('Bloquear tela').evaluate().isEmpty,
    );
    await tester.runAsync(() async {
      expect(await shortcuts.list(), isEmpty);
    });

    await tester.tap(find.byTooltip('Remover preferência').first);
    await _pumpUntil(
      tester,
      () => find.textContaining('resposta_curta').evaluate().isEmpty,
    );
    await tester.runAsync(() async {
      expect(await preferences.list(), isEmpty);
    });
  });
}
