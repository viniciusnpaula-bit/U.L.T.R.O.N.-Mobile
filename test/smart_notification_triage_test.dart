import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:ultron_mobile/core/security/auth_gate.dart';
import 'package:ultron_mobile/services/audio_capture_service.dart';
import 'package:ultron_mobile/services/obsidian_service.dart';
import 'package:ultron_mobile/services/smart_notification_triage_service.dart';
import 'package:ultron_mobile/services/stt_service.dart';
import 'package:ultron_mobile/services/voice_pipeline_controller.dart';
import 'package:ultron_mobile/services/voice_service.dart';

class _TrackingTts extends FlutterTts {
  int stopCalls = 0;

  @override
  Future<dynamic> setLanguage(String language) async => 1;

  @override
  Future<dynamic> setPitch(double pitch) async => 1;

  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;

  @override
  Future<dynamic> setVolume(double volume) async => 1;

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async => 1;

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async => 1;

  @override
  Future<dynamic> stop() async {
    stopCalls++;
    return 1;
  }
}

class _NoopCapture implements AudioCaptureSource {
  int stopCalls = 0;

  @override
  Stream<Never> get frames => const Stream.empty();

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<AudioEffectsReport> start({int sampleRate = 16000}) async =>
      const AudioEffectsReport();

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SmartNotificationTriageService', () {
    test('blocks self package, unmonitored apps, spam, and OTP codes', () {
      var now = DateTime(2026, 11, 23, 14, 0);
      final triage = SmartNotificationTriageService(now: () => now);
      const cfg = NotificationTriageConfig(enabled: true);

      // Auto-exclusão contra loop
      final selfEval = triage.evaluate(
        config: cfg,
        packageName: 'com.viniciusnpaula.ultron_mobile',
        appLabel: 'U.L.T.R.O.N.',
        sender: 'U.L.T.R.O.N.',
        text: 'Urgência: teste',
      );
      expect(selfEval.isUrgent, isFalse);
      expect(selfEval.suppressedReason, 'self_package');

      // Promoção/OTP filtrado mesmo no WhatsApp
      final promoEval = triage.evaluate(
        config: cfg,
        packageName: 'com.whatsapp',
        appLabel: 'WhatsApp',
        sender: 'Loja',
        text: 'Urgente! Cupom de desconto 50% hoje!',
      );
      expect(promoEval.isUrgent, isFalse);
      expect(promoEval.suppressedReason, 'noise_filtered');

      final otpEval = triage.evaluate(
        config: cfg,
        packageName: 'com.whatsapp',
        appLabel: 'WhatsApp',
        sender: 'Banco',
        text: 'Seu código de verificação é 482910. Não compartilhe.',
      );
      expect(otpEval.isUrgent, isFalse);
      expect(otpEval.suppressedReason, 'noise_filtered');
    });

    test('detects urgent keywords, VIP+time, burst messages, and deduplicates', () {
      var now = DateTime(2026, 11, 23, 15, 0);
      final triage = SmartNotificationTriageService(now: () => now);
      const cfg = NotificationTriageConfig(
        enabled: true,
        vipContacts: ['Mãe'],
        mutedSenders: ['Grupo Futebol'],
      );

      // Palavra crítica direta no Telegram
      final crit = triage.evaluate(
        config: cfg,
        packageName: 'org.telegram.messenger',
        appLabel: 'Telegram',
        sender: 'Carlos',
        text: 'Preciso falar com você urgente, o servidor fora do ar!',
      );
      expect(crit.isUrgent, isTrue);
      expect(crit.score, greaterThanOrEqualTo(0.70));

      // Mensagem idêntica logo em seguida é deduplicada
      final dup = triage.evaluate(
        config: cfg,
        packageName: 'org.telegram.messenger',
        appLabel: 'Telegram',
        sender: 'Carlos',
        text: 'Preciso falar com você urgente, o servidor fora do ar!',
      );
      expect(dup.isUrgent, isFalse);
      expect(dup.suppressedReason, 'duplicate');

      // VIP + palavra temporal ("hoje") cruza 0.70
      final vip = triage.evaluate(
        config: cfg,
        packageName: 'com.whatsapp',
        appLabel: 'WhatsApp',
        sender: 'Mãe',
        text: 'Preciso confirmar o horário de hoje',
      );
      expect(vip.isUrgent, isTrue);
      expect(vip.reasons, contains('VIP'));

      // Remetente silenciado é ignorado mesmo com "urgente"
      final muted = triage.evaluate(
        config: cfg,
        packageName: 'com.whatsapp',
        appLabel: 'WhatsApp',
        sender: 'Grupo Futebol',
        text: 'Urgente galera, jogo hoje!',
      );
      expect(muted.isUrgent, isFalse);
      expect(muted.suppressedReason, 'muted_sender');

      // Rajada: 3 mensagens em 60s com palavra temporal do mesmo remetente
      final b1 = triage.evaluate(
        config: cfg,
        packageName: 'com.whatsapp',
        appLabel: 'WhatsApp',
        sender: 'Pedro',
        text: 'Oi',
      );
      final b2 = triage.evaluate(
        config: cfg,
        packageName: 'com.whatsapp',
        appLabel: 'WhatsApp',
        sender: 'Pedro',
        text: 'Responde aqui',
      );
      final b3 = triage.evaluate(
        config: cfg,
        packageName: 'com.whatsapp',
        appLabel: 'WhatsApp',
        sender: 'Pedro',
        text: 'Cadê você agora??',
      );
      expect(b1.isUrgent, isFalse);
      expect(b2.isUrgent, isFalse);
      expect(b3.isUrgent, isTrue);
      expect(b3.reasons.any((r) => r.startsWith('rajada')), isTrue);
    });

    test('respects night focus (22h-06h) unless VIP or critical >= 0.90', () {
      final nightTime = DateTime(2026, 11, 23, 23, 30);
      final triage = SmartNotificationTriageService(now: () => nightTime);
      const cfg = NotificationTriageConfig(
        enabled: true,
        respectNightFocus: true,
        vipContacts: ['Mãe'],
      );

      final nonVipNight = triage.evaluate(
        config: cfg,
        packageName: 'com.google.android.gm',
        appLabel: 'Gmail',
        sender: 'Trabalho',
        text: 'Relatório urgente para revisão',
      );
      expect(nonVipNight.isUrgent, isFalse);
      expect(nonVipNight.suppressedReason, 'night_focus');

      final vipNight = triage.evaluate(
        config: cfg,
        packageName: 'com.whatsapp',
        appLabel: 'WhatsApp',
        sender: 'Mãe',
        text: 'Me liga por favor',
      );
      expect(vipNight.isUrgent, isTrue);
    });

    test('redacts sensitive CPF, card, and OTP before cloud usage', () {
      final redacted = SmartNotificationTriageService.redactSensitiveForCloud(
        'CPF 123.456.789-00, cartão 4111 2222 3333 4444 e código: 928374',
      );
      expect(redacted, contains('[CPF_REDIGIDO]'));
      expect(redacted, contains('[CARTAO_REDIGIDO]'));
      expect(redacted, contains('[CODIGO_REDIGIDO]'));
      expect(redacted, isNot(contains('123.456.789-00')));
      expect(redacted, isNot(contains('928374')));
    });

    test('writes structured checklist entry to Obsidian Inbox/Urgencias_YYYY-MM-DD.md',
        () async {
      final dir = await Directory.systemTemp.createTemp('ultron_triage_vault_');
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });
      final vault = ObsidianService(dir);
      final event = UrgentNotificationEvent(
        appLabel: 'WhatsApp',
        packageName: 'com.whatsapp',
        sender: 'Mãe',
        text: 'Estou na porta agora',
        score: 0.92,
        reasons: 'VIP, estou na porta',
        timestamp: DateTime(2026, 11, 23, 18, 45),
      );

      final file = await SmartNotificationTriageService
          .appendUrgentEventToObsidian(event, obsidian: vault);
      expect(await file.exists(), isTrue);
      expect(file.path, contains('Urgencias_2026-11-23.md'));
      final content = await file.readAsString();
      expect(content, contains('- [ ] [18:45] **WhatsApp** · Mãe [92%'));
      expect(content, contains('Estou na porta agora'));
    });
  });

  group('Background TTS Continuity', () {
    test('VoicePipelineController pauses mic on background without stopping TTS',
        () async {
      final gate = AuthGate();
      await gate.authenticatePin('1234', (_) async => true);
      final tts = _TrackingTts();
      final capture = _NoopCapture();
      final controller = VoicePipelineController(
        gate: gate,
        capture: capture,
        stt: GroqWhisperSttService(
          config: const SttConfig(
            endpointUrl: 'http://127.0.0.1:1',
            apiKey: 'k',
          ),
        ),
        voiceService: VoiceService(tts: tts),
      );
      addTearDown(controller.dispose);

      controller.handleLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);

      expect(capture.stopCalls, greaterThanOrEqualTo(1));
      expect(tts.stopCalls, 0);
    });
  });
}
