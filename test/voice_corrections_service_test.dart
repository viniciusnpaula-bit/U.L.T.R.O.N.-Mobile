import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ultron_mobile/services/conversation_history.dart';
import 'package:ultron_mobile/services/voice_corrections_service.dart';

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

  test('normalizes accents/case, matches longest phrase first, and preserves word boundaries', () async {
    final history = await _inMemoryHistory();
    addTearDown(() async => (await history.database).close());
    final service = VoiceCorrectionsService(history: history);

    await service.add('leage', 'Liga');
    await service.add('rocket leage', 'Rocket League');
    await service.add('ão', 'Ação');

    expect(
      await service.apply('Abrir Rócket Leage agora'),
      'Abrir Rocket League agora',
    );
    // Must not break neighboring words containing "ão" like "avião"
    expect(await service.apply('avião no céu'), 'avião no céu');
  });

  test('extractFromSentence detects Brazilian Portuguese voice correction patterns', () {
    final d1 = VoiceCorrectionsService.extractFromSentence(
      'não é rocket leage, é Rocket League',
    );
    expect(d1?.wrongPhrase, 'rocket leage');
    expect(d1?.correctPhrase, 'Rocket League');

    final d2 = VoiceCorrectionsService.extractFromSentence(
      'corrija ultram para Ultron',
    );
    expect(d2?.wrongPhrase, 'ultram');
    expect(d2?.correctPhrase, 'Ultron');

    expect(VoiceCorrectionsService.extractFromSentence('que horas são?'), isNull);
  });

  test('supports CRUD and builds bounded Whisper prompt', () async {
    final history = await _inMemoryHistory();
    addTearDown(() async => (await history.database).close());
    final service = VoiceCorrectionsService(history: history);

    final c1 = await service.add('ultram', 'Ultron');
    final c2 = await service.add('obsidian', 'Obsidian');
    expect((await service.list()).length, 2);

    final prompt = await service.buildWhisperPrompt(maxChars: 900);
    expect(prompt, contains('Ultron'));
    expect(prompt, contains('Obsidian'));

    await service.remove(c1.id!);
    final remaining = await service.list();
    expect(remaining.map((e) => e.id), [c2.id]);
  });
}
