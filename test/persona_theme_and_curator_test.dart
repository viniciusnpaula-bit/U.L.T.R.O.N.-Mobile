import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ultron_mobile/models/assistant_persona.dart';
import 'package:ultron_mobile/models/chat_message.dart';
import 'package:ultron_mobile/models/tactical_mode.dart';
import 'package:ultron_mobile/services/conversation_history.dart';
import 'package:ultron_mobile/services/device_control_service.dart';
import 'package:ultron_mobile/services/music_curator_service.dart';
import 'package:ultron_mobile/services/obsidian_service.dart';
import 'package:ultron_mobile/services/slash_command_parser.dart';
import 'package:ultron_mobile/ui/theme/ultron_theme.dart';

void main() {
  sqfliteFfiInit();

  group('Persona Themes (Ultron, Jarvis, Visão, Edith)', () {
    test('each persona carries exact requested color palette and UltronTheme adapts',
        () {
      expect(AssistantPersona.ultron.accentColor, const Color(0xFFF10D28));
      expect(AssistantPersona.ultron.themeName, 'Vermelho Carmesim');

      expect(AssistantPersona.jarvis.accentColor, const Color(0xFF2563EB));
      expect(AssistantPersona.jarvis.themeName, 'Azul Cobalto');

      expect(AssistantPersona.visao.accentColor, const Color(0xFFF59E0B));
      expect(AssistantPersona.visao.themeName, 'Amarelo Âmbar');

      expect(AssistantPersona.edith.accentColor, const Color(0xFF14B8A6));
      expect(AssistantPersona.edith.themeName, 'Verde-Água');

      for (final persona in AssistantPersona.all) {
        final theme = UltronTheme.dark(persona: persona);
        expect(theme.colorScheme.primary, persona.accentColor);
      }

      // Amarelo Âmbar usa texto escuro no botão primário para alto contraste
      expect(
        UltronTheme.onAccentFor(AssistantPersona.visao.accentColor),
        const Color(0xFF0B0B0D),
      );
      expect(
        UltronTheme.onAccentFor(AssistantPersona.ultron.accentColor),
        UltronColors.textPrimary,
      );
    });
  });

  group('Long-term cross-session context', () {
    test('extractLongTermFacts captures durable operator preferences and deduplicates',
        () {
      final now = DateTime(2026, 11, 25);
      final msgs = <ChatMessage>[
        ChatMessage(
          id: 1,
          conversationId: 'default',
          role: ChatRole.user,
          content: 'Eu prefiro treinar ouvindo tech house em 132 BPM.',
          createdAt: now,
        ),
        ChatMessage(
          id: 2,
          conversationId: 'default',
          role: ChatRole.user,
          content: 'Eu prefiro treinar ouvindo tech house em 132 BPM.',
          createdAt: now,
        ),
        ChatMessage(
          id: 3,
          conversationId: 'default',
          role: ChatRole.user,
          content: 'Meu objetivo este ano é evoluir no supino e mixagem no djay.',
          createdAt: now,
        ),
        ChatMessage(
          id: 4,
          conversationId: 'default',
          role: ChatRole.user,
          content: '/status',
          createdAt: now,
        ),
      ];

      final facts = ConversationHistory.extractLongTermFacts(msgs);
      expect(facts.length, 2);
      expect(facts.join(' '), contains('132 BPM'));
      expect(facts.join(' '), contains('djay'));
    });

    test('recallRelevant supports 365-day cross-session recall and Obsidian profile injection',
        () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, version) async {
            for (final stmt in ConversationHistory.schema) {
              await db.execute(stmt);
            }
          },
        ),
      );
      addTearDown(db.close);

      final history = ConversationHistory.forDatabase(db);
      final now = DateTime.utc(2026, 11, 25, 18);
      await history.save(
        ChatMessage(
          id: null,
          conversationId: 'mode_musica',
          role: ChatRole.user,
          content: 'Uso controlador Pioneer rekordbox com playlists de afro house 124 bpm',
          createdAt: now.subtract(const Duration(days: 220)),
        ),
      );

      final matches = await history.recallRelevant(
        'qual controlador dj eu uso com afro house?',
        conversationId: 'default',
        maxDays: 365,
        includeCrossSession: true,
        now: now,
      );
      expect(matches, isNotEmpty);
      expect(matches.first.message.content, contains('rekordbox'));

      final tempDir =
          await Directory.systemTemp.createTemp('ultron_long_term_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final vault = ObsidianService(tempDir);
      final device = DeviceControlService(obsidianProvider: () async => vault);

      final saved = await device.persistLongTermSessionFacts([
        'Eu prefiro sets de melodic techno entre 126 e 132 BPM.',
      ]);
      expect(saved, 1);
      // Segunda inserção igual é deduplicada
      final savedAgain = await device.persistLongTermSessionFacts([
        'Eu prefiro sets de melodic techno entre 126 e 132 BPM.',
      ]);
      expect(savedAgain, 0);

      final prompt = await device.buildContextualSystemPrompt(
        mode: TacticalMode.musica,
        persona: AssistantPersona.jarvis,
        now: now,
      );
      expect(prompt, contains('PERFIL E CONTEXTO DE LONGO PRAZO'));
      expect(prompt, contains('melodic techno entre 126 e 132 BPM'));
      expect(prompt, contains('MOTOR CRIATIVO DE MÚSICA & DJ'));
    });
  });

  group('Expanded media players, DJ controllers & creative BPM/mood curator', () {
    test('detectPlayerMention resolves streaming, local and DJ controller apps accurately',
        () {
      expect(
        MusicCuratorService.detectPlayerMention('pausar no youtube music')?.id,
        'youtube music',
      );
      expect(
        MusicCuratorService.detectPlayerMention('tocar próxima no deezer')?.id,
        'deezer',
      );
      expect(
        MusicCuratorService.detectPlayerMention('abrir tidal')?.id,
        'tidal',
      );
      expect(
        MusicCuratorService.detectPlayerMention('tocar no poweramp')?.id,
        'poweramp',
      );
      expect(
        MusicCuratorService.detectPlayerMention('mixar no djay')?.id,
        'djay',
      );
      expect(
        MusicCuratorService.detectPlayerMention('abrir rekordbox no pc')?.id,
        'rekordbox',
      );
      expect(
        MusicCuratorService.detectPlayerMention('abrir serato dj')?.id,
        'serato',
      );
    });

    test('MusicCuratorService combines mood, BPM, context, Camelot wheel and Obsidian export',
        () async {
      const curator = MusicCuratorService();
      final plan = curator.curate(
        'treino 134bpm 8A no tidal',
        now: DateTime(2026, 11, 25, 19, 30),
        mode: TacticalMode.treino,
      );

      expect(plan.mood, MusicMood.treino);
      expect(plan.targetBpmMin, 130);
      expect(plan.targetBpmMax, 138);
      expect(plan.startCamelot, '8A');
      expect(plan.compatibleCamelot, contains('8B (relativo)'));
      expect(plan.compatibleCamelot, contains('9A (+1 energia)'));
      expect(plan.preferredPlayer, 'Tidal');

      final parsed = SlashCommandParser.parse('/dj transicao 8A');
      expect(parsed?.command, UltronCommand.dj);
      expect(parsed?.argument, 'transicao 8A');

      final tempDir =
          await Directory.systemTemp.createTemp('ultron_dj_curator_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final vault = ObsidianService(tempDir);
      final device = DeviceControlService(obsidianProvider: () async => vault);

      final res = await device.executeDjCommand(
        'salvar foco madrugada',
        mode: TacticalMode.musica,
        nightFocusMode: true,
      );
      expect(res.handled, isTrue);
      expect(res.message, contains(MusicCuratorService.setlistsNotePath));

      final note = await vault.readNote(MusicCuratorService.setlistsNotePath);
      expect(note, contains('BPM'));
    });
  });
}
