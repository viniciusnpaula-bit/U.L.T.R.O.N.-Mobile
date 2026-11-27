import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ultron_mobile/services/audit_log_service.dart';
import 'package:ultron_mobile/services/briefing_service.dart';
import 'package:ultron_mobile/services/desktop_pairing_service.dart';
import 'package:ultron_mobile/services/device_control_service.dart';
import 'package:ultron_mobile/services/obsidian_service.dart';
import 'package:ultron_mobile/services/reminder_service.dart';
import 'package:ultron_mobile/services/speech_text.dart';
import 'package:ultron_mobile/services/web_info_service.dart';
import 'package:ultron_mobile/services/workflow_scheduler_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.viniciusnpaula.ultron_mobile/device');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final args = (call.arguments as Map?) ?? const {};
      switch (call.method) {
        case 'setTorch':
          return args['enabled'] as bool? ?? false;
        case 'toggleTorch':
          return true;
        case 'setVolume':
          return args['percent'] as int? ?? 50;
        case 'adjustVolume':
          return 70;
        case 'openApp':
          return 'WhatsApp';
        case 'listenVoice':
          return 'ligar lanterna';
        case 'isNotificationListenerEnabled':
          return true;
        case 'getRecentMessages':
          return [
            {
              'id': 'm1',
              'packageName': 'com.whatsapp',
              'appLabel': 'WhatsApp',
              'sender': 'Carlos',
              'text': 'Reunião às 15h',
              'timestampMs': 1700000000000,
              'timeFormatted': '14:30',
              'canReplyInline': true,
            },
          ];
        case 'replyNotification':
          return 'Resposta enviada em segundo plano para Carlos (WhatsApp): "${args['text']}"';
        case 'sendWhatsApp':
          return 'WhatsApp aberto para ${args['target']}: "${args['text']}"';
        case 'sendSms':
          return 'SMS aberto para ${args['target']}: "${args['text']}"';
        case 'speakOfflineFishVoice':
          return 'Operador, agora são exatamente 23:35.';
        case 'setAudioSentinel':
          return args['enabled'] as bool? ?? false;
        case 'consumePendingBackgroundTurns':
          return [
            {
              'userText': 'ligar lanterna',
              'assistantText':
                  'Lanterna ligada.\n\n[Hardware: 🔦 Lanterna: ON]',
              'senderLabel': 'Hardware Bridge (2º plano)',
              'userTimestampMs': 1700000001000,
              'replyTimestampMs': 1700000002000,
            },
          ];
        default:
          return true;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('executes offline time readout and Eco-VAD sentinel toggle', () async {
    final service = DeviceControlService(channel: channel);

    final timeRes =
        await service.tryExecuteNaturalCommand('Ei Ultron, que horas são?');
    expect(timeRes?.handled, isTrue);
    expect(calls.last.method, 'speakOfflineFishVoice');

    final vadRes =
        await service.tryExecuteNaturalCommand('ativar sentinela de voz');
    expect(vadRes?.handled, isTrue);
    expect(calls.last.method, 'setAudioSentinel');
    expect(calls.last.arguments, {'enabled': true});

    var triggeredWake = false;
    service.setNativeEventHandlers(
      onWakeWord: (phrase) {
        if (phrase.contains('Ultron')) triggeredWake = true;
      },
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        const MethodCall('onWakeWordDetected', 'Ei Ultron'),
      ),
      (data) {},
    );
    expect(triggeredWake, isTrue);
  });

  test('wake word reliability: pending queue, diagnostics and boot opt-in',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'consumePendingWakeWord':
          return 'Ei Ultron que horas são';
        case 'getWakeWordDiagnostics':
          return {
            'running': true,
            'micPermission': true,
            'engine': 'sherpa-onnx Zipformer KWS (offline / CPU)',
            'dedicatedKws': false,
            'modelLoaded': false,
            'kwsErrors': 2,
            'kwsFrames': 11,
            'kwsDecodes': 9,
            'detections': 3,
            'voiceTriggers': 7,
            'lastError': 'nenhum',
            'noiseFloor': 310,
            'threshold': 992,
          };
        case 'setBootAutostart':
          return (call.arguments as Map)['enabled'] as bool;
      }
      return true;
    });
    final service = DeviceControlService(channel: channel);

    expect(await service.consumePendingWakeWord(), 'Ei Ultron que horas são');

    final diag = await service.getWakeWordDiagnostics();
    expect(diag.running, isTrue);
    expect(diag.detections, 3);
    expect(diag.threshold, 992);
    expect(diag.toReport(), contains('Ativações KWS: 3'));
    expect(diag.kwsErrors, 2);
    expect(diag.kwsFrames, 11);
    expect(diag.kwsDecodes, 9);
    expect(diag.toReport(), contains('Pipeline KWS: 11 janelas · 9 decodes'));
    expect(
        diag.toReport(), contains('FALHA: modelo sherpa-onnx não carregado'));
    // Sem modelo KWS carregado e sem captura confirmada: o relatório não pode fingir o contrário.
    expect(diag.dedicatedKws, isFalse);
    expect(diag.capturing, isFalse);
    expect(diag.toReport(), contains('INDISPONÍVEL'));
    expect(diag.toReport(), contains('NÃO confirmada'));

    expect(await service.setBootAutostart(true), isTrue);
    expect(calls.last.arguments, {'enabled': true});
  });

  test('wake word diagnostics degrade safely when native call fails', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'DEVICE_ERROR');
    });
    final service = DeviceControlService(channel: channel);
    expect(await service.consumePendingWakeWord(), isNull);
    final diag = await service.getWakeWordDiagnostics();
    expect(diag.running, isFalse);
    expect(diag.lastError, 'nenhum');
  });

  test(
      'reads, replies in background, and sends WhatsApp/SMS via natural language',
      () async {
    final service = DeviceControlService(channel: channel);

    final readRes = await service.tryExecuteNaturalCommand('ler mensagens');
    expect(readRes?.handled, isTrue);
    expect(readRes?.message, contains('Carlos'));

    final replyRes = await service.tryExecuteNaturalCommand(
      'responder: Chego em 10 minutos',
    );
    expect(replyRes?.handled, isTrue);
    expect(calls.last.method, 'replyNotification');
    expect(calls.last.arguments['text'], 'Chego em 10 minutos');

    final waRes = await service.tryExecuteNaturalCommand(
      'mandar whatsapp para Maria: Já estou a caminho',
    );
    expect(waRes?.handled, isTrue);
    expect(calls.last.method, 'sendWhatsApp');
    expect(calls.last.arguments['target'], 'Maria');
    expect(calls.last.arguments['text'], 'Já estou a caminho');
  });

  test('listenVoice invokes native speech recognizer and trims output',
      () async {
    final service = DeviceControlService(channel: channel);
    final spoken = await service.listenVoice();
    expect(spoken, 'ligar lanterna');
    expect(calls.last.method, 'listenVoice');
    expect(calls.last.arguments['locale'], 'pt-BR');
  });

  test('executes natural language torch and volume commands', () async {
    final service = DeviceControlService(channel: channel);

    final torchRes = await service.tryExecuteNaturalCommand('ligar lanterna');
    expect(torchRes?.handled, isTrue);
    expect(calls.last.method, 'setTorch');
    expect(calls.last.arguments, {'enabled': true});

    final volRes = await service.tryExecuteNaturalCommand('volume 85%');
    expect(volRes?.handled, isTrue);
    expect(calls.last.method, 'setVolume');
    expect(calls.last.arguments, {'percent': 85});
  });

  test('parses and executes AI [ACTION:...] tags and cleans reply text',
      () async {
    final service = DeviceControlService(channel: channel);

    final res = await service.executeAiActions(
      'Claro, ligando a lanterna e abrindo o WhatsApp. [ACTION:TORCH_ON] [ACTION:OPEN_APP:whatsapp]',
    );

    expect(res.cleanText, 'Claro, ligando a lanterna e abrindo o WhatsApp.');
    expect(res.executedLogs.length, 2);
    expect(calls.map((c) => c.method), ['setTorch', 'openApp']);
  });

  test('computes file SHA-256 and verifies integrity', () async {
    final service = DeviceControlService(channel: channel);
    final tempDir = await Directory.systemTemp.createTemp('ultron_hash_test_');
    try {
      final file = File('${tempDir.path}/test_payload.txt');
      await file.writeAsString('ULTRON_SECURE_PAYLOAD_TEST');
      final hash = await service.computeFileSha256(file);
      expect(hash.length, 64);
      expect(await service.verifyFileIntegrity(file, hash), isTrue);
      expect(
          await service.verifyFileIntegrity(file, 'wrong_hash_value'), isFalse);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('executes Obsidian Second Brain actions and builds contextual prompt',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('ultron_obsidian_test_dc_');
    try {
      final obs = ObsidianService(tempDir);
      await obs.initialize();
      final service = DeviceControlService(
        channel: channel,
        obsidianProvider: () async => obs,
      );

      // Natural command: capture thought to inbox
      final inboxRes = await service
          .tryExecuteNaturalCommand('ideia: Criar dashboard tático');
      expect(inboxRes?.handled, isTrue);
      expect(inboxRes?.message, contains('Inbox'));

      // Natural command: save long-term memory
      final memRes = await service
          .tryExecuteNaturalCommand('lembrar que meu codinome é Hawk');
      expect(memRes?.handled, isTrue);
      expect(memRes?.message, contains('Operador'));

      // Contextual prompt injection
      final prompt = await service.buildContextualSystemPrompt();
      expect(prompt,
          contains('SEGUNDO CÉREBRO — MEMÓRIA ATIVA DO COFRE OBSIDIAN'));
      expect(prompt, contains('Perfil do Operador'));

      // AI tags: INBOX, REMEMBER, OPEN_OBSIDIAN
      final aiExec = await service.executeAiActions(
        'Anotado no segundo cérebro. [ACTION:INBOX:Nova feature] [ACTION:REMEMBER:Tático:Plano delta] [ACTION:OPEN_OBSIDIAN]',
      );
      expect(aiExec.cleanText, 'Anotado no segundo cérebro.');
      expect(aiExec.executedLogs.length, 3);
      expect(aiExec.executedLogs[0], contains('Inbox'));
      expect(aiExec.executedLogs[1], contains('Segundo Cérebro'));
      expect(aiExec.executedLogs[2], contains('Obsidian'));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test(
      'prepares PC sync payload with HMAC-SHA256 signature and rejects empty secret',
      () {
    final service = DeviceControlService(channel: channel);
    final sync = service.preparePcSyncPayload(
      command: 'SYNC_TELEMETRY',
      data: const {'battery': 98, 'ram': 4096},
      secret: 'test-lan-secret-123',
    );
    expect(sync['body'], contains('SYNC_TELEMETRY'));
    expect(sync['signature'], startsWith('sha256='));
    expect(sync['timestamp'], isNotEmpty);

    expect(
      () => service.preparePcSyncPayload(
        command: 'SYNC_TELEMETRY',
        secret: '   ',
      ),
      throwsArgumentError,
    );
  });

  test('executeAiActions enforces ActionGate on sensitive actions', () async {
    final service = DeviceControlService(channel: channel);

    // Without confirmAction callback -> blocked fail-closed
    final blocked = await service.executeAiActions(
      'Enviando mensagem. [ACTION:WHATSAPP:Carlos:Oi]',
    );
    expect(blocked.executedLogs.single, contains('bloqueado'));
    expect(calls.where((c) => c.method == 'sendWhatsApp'), isEmpty);

    // With confirmAction returning false -> blocked
    final denied = await service.executeAiActions(
      'Enviando SMS. [ACTION:SMS:11999999999:Oi]',
      confirmAction: (_) async => false,
    );
    expect(denied.executedLogs.single, contains('bloqueado'));
    expect(calls.where((c) => c.method == 'sendSms'), isEmpty);

    // With confirmAction returning true -> executed
    final approved = await service.executeAiActions(
      'Enviando WhatsApp. [ACTION:WHATSAPP:Carlos:Confirmado]',
      confirmAction: (_) async => true,
    );
    expect(approved.executedLogs.single, contains('Carlos'));
    expect(calls.where((c) => c.method == 'sendWhatsApp').length, 1);
  });

  test('captureVisionImage decodes VisionAttachment from native MethodChannel',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'captureVisionImage') {
        return {
          'base64': 'QUJDRA==',
          'mimeType': 'image/jpeg',
          'width': 800,
          'height': 600,
          'byteSize': 4096,
          'source': call.arguments['source'],
        };
      }
      return true;
    });

    final service = DeviceControlService(channel: channel);
    final img = await service.captureVisionImage(source: 'gallery');
    expect(img, isNotNull);
    expect(img!.width, 800);
    expect(img.height, 600);
    expect(img.source, 'gallery');
    expect(img.sizeKbLabel, '4.0 KB');
  });

  test('executes natural media playback commands and AI MEDIA_* tags',
      () async {
    final service = DeviceControlService(channel: channel);

    final pauseRes = await service.tryExecuteNaturalCommand('pausar música');
    expect(pauseRes?.handled, isTrue);
    expect(calls.last.method, 'mediaControl');
    expect(calls.last.arguments, {'action': 'pause'});

    final playRes = await service.tryExecuteNaturalCommand('continuar música');
    expect(playRes?.handled, isTrue);
    expect(calls.last.arguments, {'action': 'play'});

    final nextRes = await service.tryExecuteNaturalCommand('próxima música');
    expect(nextRes?.handled, isTrue);
    expect(calls.last.arguments, {'action': 'next'});

    final prevRes = await service.tryExecuteNaturalCommand('música anterior');
    expect(prevRes?.handled, isTrue);
    expect(calls.last.arguments, {'action': 'previous'});

    final stopRes = await service.tryExecuteNaturalCommand('parar mídia');
    expect(stopRes?.handled, isTrue);
    expect(calls.last.arguments, {'action': 'stop'});

    // Must not hijack non-media sentinel phrases
    final sentinelRes =
        await service.tryExecuteNaturalCommand('parar sentinela de voz');
    expect(sentinelRes?.handled, isTrue);
    expect(calls.last.method, 'setAudioSentinel');

    final aiExec = await service.executeAiActions(
      'Avançando a faixa. [ACTION:MEDIA_NEXT] [ACTION:MEDIA_PAUSE]',
    );
    expect(aiExec.cleanText, 'Avançando a faixa.');
    expect(aiExec.executedLogs.length, 2);
    expect(calls.skip(calls.length - 2).map((c) => c.arguments['action']), [
      'next',
      'pause',
    ]);

    await expectLater(service.controlMedia('invalid_cmd'), throwsArgumentError);
  });

  test(
      'syncBackgroundVoiceConfig forwards encrypted-store credentials to native channel',
      () async {
    final service = DeviceControlService(channel: channel);
    await service.syncBackgroundVoiceConfig(
      sttUrl: 'https://api.groq.com/openai/v1/audio/transcriptions',
      sttKey: 'gsk_123',
      sttModel: 'whisper-large-v3-turbo',
      sttLanguage: 'pt',
      aiBaseUrl: 'https://api.groq.com/openai/v1',
      aiKey: 'gsk_123',
      aiModel: 'openai/gpt-oss-120b',
      fishEnabled: true,
      fishKey: 'fish_key',
      fishRefId: 'ultron_ref',
      fishLanguage: 'pt',
      fishModel: 's2.1-pro-free',
      whisperMode: false,
    );

    expect(calls.last.method, 'syncBackgroundVoiceConfig');
    final args = calls.last.arguments as Map;
    expect(args['sttKey'], 'gsk_123');
    expect(args['fishRefId'], 'ultron_ref');
    expect(args['fishModel'], 's2.1-pro-free');
  });

  test(
      'consumePendingBackgroundTurns parses background chat turns and handles onBackgroundTurnAvailable',
      () async {
    final service = DeviceControlService(channel: channel);
    var notified = false;
    service.setNativeEventHandlers(
      onBackgroundTurn: () => notified = true,
    );

    final codec = const StandardMethodCodec();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(const MethodCall('onBackgroundTurnAvailable')),
      (_) {},
    );
    expect(notified, isTrue);

    final turns = await service.consumePendingBackgroundTurns();
    expect(turns.length, 1);
    expect(turns.first.userText, 'ligar lanterna');
    expect(turns.first.assistantText, contains('[Hardware: 🔦 Lanterna: ON]'));
    expect(turns.first.senderLabel, 'Hardware Bridge (2º plano)');
  });

  test(
      'tryExecuteNaturalCommand strips courtesy suffixes and delegates multi-clause or non-app phrases to AI',
      () async {
    final service = DeviceControlService(channel: channel);

    // Strips courtesy phrasing around single-app command: "abra o whatsapp pra mim" -> openApp("whatsapp")
    final politeOpen =
        await service.tryExecuteNaturalCommand('abra o whatsapp pra mim.');
    expect(politeOpen?.handled, isTrue);
    expect(calls.last.method, 'openApp');
    expect(calls.last.arguments, {'target': 'whatsapp'});

    final politeLead = await service.tryExecuteNaturalCommand(
        'Ei Ultron, por favor você pode abrir o youtube aí agora?');
    expect(politeLead?.handled, isTrue);
    expect(calls.last.method, 'openApp');
    expect(calls.last.arguments, {'target': 'youtube'});

    // Multi-clause order delegates to AI instead of misparsing as literal app name
    final multiClause = await service.tryExecuteNaturalCommand(
        'abra o whatsapp pra mim e veja minhas mensagens');
    expect(multiClause, isNull);
  });

  test('parseNaturalCalendarEvent parses relative days, dates, and times', () {
    final now = DateTime(2026, 11, 19, 8, 0);

    final tomorrow = DeviceControlService.parseNaturalCalendarEvent(
      'agendar Reunião com Carlos amanhã às 15:30',
      now: now,
    );
    expect(tomorrow, isNotNull);
    expect(tomorrow!.title, 'Reunião com Carlos');
    expect(tomorrow.startTime, DateTime(2026, 11, 20, 15, 30));

    final iso = DeviceControlService.parseNaturalCalendarEvent(
      '2026-12-01 09:00 Revisão Trimestral',
      now: now,
    );
    expect(iso, isNotNull);
    expect(iso!.title, 'Revisão Trimestral');
    expect(iso.startTime, DateTime(2026, 12, 1, 9, 0));
  });

  test('reads and creates calendar events with ActionGate enforcement',
      () async {
    final evStart = DateTime(2026, 11, 19, 14, 0).millisecondsSinceEpoch;
    final evEnd = DateTime(2026, 11, 19, 15, 0).millisecondsSinceEpoch;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getCalendarEvents') {
        return [
          {
            'id': '101',
            'title': 'Review Sprint',
            'startMs': evStart,
            'endMs': evEnd,
            'allDay': false,
            'location': 'Sala 1',
            'calendarName': 'Trabalho',
          },
        ];
      }
      if (call.method == 'createCalendarEvent') {
        return {
          'created': true,
          'mode': 'direct',
          'eventId': '202',
          'calendarName': 'Trabalho',
          'title': call.arguments['title'],
        };
      }
      return true;
    });

    final service = DeviceControlService(channel: channel);
    final readNatural =
        await service.tryExecuteNaturalCommand('agenda de hoje');
    expect(readNatural?.handled, isTrue);
    expect(readNatural?.message, contains('Review Sprint'));

    // Blocked when ActionGate denies CREATE_EVENT
    final denied = await service.executeAiActions(
      'Criando evento. [ACTION:CREATE_EVENT:2026-11-20 10:00:Dentista]',
      confirmAction: (_) async => false,
    );
    expect(denied.executedLogs.single, contains('bloqueado'));
    expect(calls.where((c) => c.method == 'createCalendarEvent'), isEmpty);

    // Executed when ActionGate approves CREATE_EVENT
    final approved = await service.executeAiActions(
      'Criando evento. [ACTION:CREATE_EVENT:2026-11-20 10:00:Dentista]',
      confirmAction: (_) async => true,
    );
    expect(approved.executedLogs.single, contains('Dentista'));
    expect(calls.where((c) => c.method == 'createCalendarEvent').length, 1);
  });

  test(
      'executes HTTP bridge directives in Skills/*.md with ActionGate and immutable AuditLog',
      () async {
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = _RealHttpOverrides();
    addTearDown(() => HttpOverrides.global = previousOverrides);

    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, singleInstance: false),
    );
    final audit = await AuditLogService.open(database: db);
    addTearDown(() => audit.close());

    final receivedBodies = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      receivedBodies.add('${req.method} ${req.uri.path} $body');
      req.response
        ..statusCode = 200
        ..write('{"ok":true}');
      await req.response.close();
    });

    final tempDir = await Directory.systemTemp.createTemp('ultron_iot_skill_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final obs = ObsidianService(tempDir);
    await obs.initialize();
    final skillFile = File('${tempDir.path}/Skills/iot_noite.md');
    await skillFile.writeAsString(
      '# IoT Boa Noite\n'
      '[HTTP:GET:http://127.0.0.1:${server.port}/health]\n'
      '[HTTP:POST:http://127.0.0.1:${server.port}/webhook|{"entity":"light.sala"}]\n',
    );

    final service = DeviceControlService(
      channel: channel,
      obsidianProvider: () async => obs,
      auditLogProvider: () async => audit,
    );

    // Deny mutating POST -> GET on loopback still runs, POST denied & logged in AuditLog
    final partial = await service.executeAiActions(
      '[ACTION:SKILL:iot_noite]',
      confirmAction: (_) async => false,
    );
    expect(partial.executedLogs.single, contains('HTTP GET'));
    expect(partial.executedLogs.single, contains('bloqueado'));
    expect(receivedBodies.length, 1);

    // Approve mutating POST -> executes HTTP POST and records valid SHA-256 chain
    final full = await service.executeAiActions(
      '[ACTION:SKILL:iot_noite]',
      confirmAction: (_) async => true,
    );
    expect(full.executedLogs.single, contains('HTTP POST'));
    expect(receivedBodies.length, 3);
    expect(receivedBodies.last, contains('{"entity":"light.sala"}'));

    final verification = await audit.verifyChain();
    expect(verification.valid, isTrue);
    expect(verification.totalEntries, greaterThanOrEqualTo(4));
  });

  test('blocks SSRF metadata and cleartext external HTTP in Skill Bridge',
      () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, singleInstance: false),
    );
    final audit = await AuditLogService.open(database: db);
    addTearDown(() => audit.close());

    final service = DeviceControlService(
      channel: channel,
      auditLogProvider: () async => audit,
    );

    final metaRes = await service.executeAiActions(
      '[ACTION:HTTP_GET:http://169.254.169.254/latest/meta-data]',
      confirmAction: (_) async => true,
    );
    expect(metaRes.executedLogs.single, contains('Falha em HTTP_GET'));
    expect(metaRes.executedLogs.single, contains('anti-SSRF'));

    final cleartextExternal = await service.executeAiActions(
      '[ACTION:HTTP_GET:http://example.com/hook]',
      confirmAction: (_) async => true,
    );
    expect(cleartextExternal.executedLogs.single, contains('Falha em HTTP_GET'));
    expect(cleartextExternal.executedLogs.single, contains('HTTPS obrigatório'));
  });

  test('rejects non-LAN and metadata endpoints for Kill Switch', () async {
    final storage = _TestSecureStorage();
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, singleInstance: false),
    );
    final audit = await AuditLogService.open(database: db);
    addTearDown(() => audit.close());

    final service = DeviceControlService(
      channel: channel,
      storage: storage,
      auditLogProvider: () async => audit,
    );

    await expectLater(
      () => service.savePcKillSwitchUrl('http://8.8.8.8/kill'),
      throwsArgumentError,
    );
    await expectLater(
      () => service.savePcKillSwitchUrl('169.254.169.254'),
      throwsArgumentError,
    );

    final blockedPublic = await service.triggerPcKillSwitch(
      overrideUrl: 'http://8.8.8.8/kill',
      overrideSecret: 'secret-123',
    );
    expect(blockedPublic, contains('bloqueado'));

    final blockedMeta = await service.triggerPcKillSwitch(
      overrideUrl: 'http://169.254.169.254/latest/meta-data',
      overrideSecret: 'secret-123',
    );
    expect(blockedMeta, contains('bloqueado'));

    final entries = await audit.recent(limit: 5);
    expect(entries.where((e) => e.status == 'DENIED').length, 2);
  });

  test('enforces ActionGate + AuditLog on natural DIAL and refines replyMatch/missing skill',
      () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, singleInstance: false),
    );
    final audit = await AuditLogService.open(database: db);
    addTearDown(() => audit.close());

    final tempDir = await Directory.systemTemp.createTemp('ultron_ctrl_audit_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final obs = ObsidianService(tempDir);
    await obs.initialize();

    final service = DeviceControlService(
      channel: channel,
      obsidianProvider: () async => obs,
      auditLogProvider: () async => audit,
    );

    // DIAL blocked when confirmAction returns false
    final deniedDial = await service.tryExecuteNaturalCommand(
      'discar 11999999999',
      confirmAction: (_) async => false,
    );
    expect(deniedDial?.handled, isTrue);
    expect(deniedDial?.message, contains('cancelada'));
    expect(calls.where((c) => c.method == 'dialNumber'), isEmpty);

    // DIAL succeeds + logs when confirmed
    final okDial = await service.tryExecuteNaturalCommand(
      'discar 11999999999',
      confirmAction: (_) async => true,
    );
    expect(okDial?.handled, isTrue);
    expect(calls.where((c) => c.method == 'dialNumber').length, 1);

    // replyMatch must NOT hijack ordinary prompts starting with "Responda apenas:"
    final aiPromptRes = await service.tryExecuteNaturalCommand(
      'Responda apenas: OK auditoria',
      confirmAction: (_) async => true,
    );
    expect(aiPromptRes, isNull);

    final aiPromptRes2 = await service.tryExecuteNaturalCommand(
      'Responda em português: tudo certo?',
      confirmAction: (_) async => true,
    );
    expect(aiPromptRes2, isNull);

    // Valid background reply patterns still work
    final replyExplicit = await service.tryExecuteNaturalCommand(
      'responder para Carlos: Chego já',
      confirmAction: (_) async => true,
    );
    expect(replyExplicit?.handled, isTrue);
    expect(replyExplicit?.message, contains('Carlos'));

    // Unknown explicit skill returns handled feedback instead of silent null
    final missingSkill = await service.tryExecuteNaturalCommand(
      'executar skill inexistente_xyz',
    );
    expect(missingSkill?.handled, isTrue);
    expect(missingSkill?.message, contains('não encontrada'));

    final logEntries = await audit.recent(limit: 10);
    expect(logEntries.any((e) => e.action == 'DIAL' && e.status == 'DENIED'),
        isTrue);
    expect(logEntries.any((e) => e.action == 'DIAL' && e.status == 'EXECUTED'),
        isTrue);
  });

  test('buildContextualSystemPrompt injects real-time device date and clock',
      () async {
    final service = DeviceControlService(channel: channel);
    final fixedNow = DateTime(2026, 11, 19, 17, 13, 5); // quinta-feira

    final clockSection = DeviceControlService.formatClockContext(fixedNow);
    expect(clockSection, contains('Data atual: 2026-11-19 (quinta-feira)'));
    expect(clockSection, contains('Hora atual: 17:13:05'));
    expect(clockSection, contains('alarmes relativos'));

    final prompt = await service.buildContextualSystemPrompt(now: fixedNow);
    expect(prompt, contains('=== RELÓGIO DO DISPOSITIVO (TEMPO REAL) ==='));
    expect(prompt, contains('Data atual: 2026-11-19 (quinta-feira)'));
    expect(prompt, contains('Hora atual: 17:13:05'));
  });

  test('tryExecuteNaturalCommand handles natural phrases to open apps',
      () async {
    final service = DeviceControlService(channel: channel);

    final r1 =
        await service.tryExecuteNaturalCommand('No meu celular, abra o WhatsApp.');
    expect(r1?.handled, isTrue);
    expect(calls.last.method, 'openApp');
    expect(calls.last.arguments, {'target': 'whatsapp'});

    final r2 = await service
        .tryExecuteNaturalCommand('Ultron, por favor pode abrir o Spotify');
    expect(r2?.handled, isTrue);
    expect(calls.last.method, 'openApp');
    expect(calls.last.arguments, {'target': 'spotify'});
  });

  test('natural and AI-tag PC_OPEN_APP dispatch to DesktopPairingService via ActionGate',
      () async {
    final prevOverrides = HttpOverrides.current;
    HttpOverrides.global = _RealHttpOverrides();
    addTearDown(() => HttpOverrides.global = prevOverrides);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    final received = <Map<String, dynamic>>[];
    const secret = 'desktop-test-secret-32-chars-ok!';
    server.listen((req) async {
      final raw = await utf8.decoder.bind(req).join();
      received.add(jsonDecode(raw) as Map<String, dynamic>);
      req.response.statusCode = 200;
      req.response.write('{"ok":true}');
      await req.response.close();
    });

    final storage = _TestSecureStorage();
    final pairing = DesktopPairingService(storage: storage);
    await pairing.savePairing(
      DesktopPairingConfig(
        baseUrl: 'http://127.0.0.1:${server.port}',
        deviceId: 'galaxy-a34',
        sharedSecret: secret,
      ),
    );

    final service = DeviceControlService(
      channel: channel,
      desktopPairingProvider: () => pairing,
    );

    // Fail-closed if confirmation denied
    final denied = await service.tryExecuteNaturalCommand(
      'abra o Rocket League no meu PC',
      confirmAction: (_) async => false,
    );
    expect(denied?.handled, isTrue);
    expect(received, isEmpty);

    // Executes and sends PC_OPEN_APP when confirmed
    final ok = await service.tryExecuteNaturalCommand(
      'abra o Rocket League no meu PC',
      confirmAction: (_) async => true,
    );
    expect(ok?.handled, isTrue);
    expect(ok?.message, contains('rocket league'));

    final ai = await service.executeAiActions(
      'Abrindo agora. [ACTION:PC_OPEN_APP:chrome]',
      confirmAction: (_) async => true,
    );
    expect(ai.executedLogs.join(' '), contains('PC_OPEN_APP'));

    expect(received.length, 2);
    expect(received[0]['command'], 'PC_OPEN_APP');
    expect(received[0]['args'], {'app': 'rocket league'});
    expect(received[1]['command'], 'PC_OPEN_APP');
    expect(received[1]['args'], {'app': 'chrome'});
  });

  test(
      'executes Phase 1 Obsidian CRUD, UNDO, CANCEL_EVENT, and persistent Reminders via natural commands and AI tags',
      () async {
    sqfliteFfiInit();
    final remDb = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, singleInstance: false),
    );
    final reminderSvc = await ReminderService.open(
      database: remDb,
      channel: channel,
    );
    addTearDown(() => reminderSvc.close());

    final tempDir =
        await Directory.systemTemp.createTemp('ultron_phase1_dc_test_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final obs = ObsidianService(tempDir);
    await obs.initialize();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'deleteCalendarEvent') {
        return {
          'deleted': true,
          'deletedCount': 1,
          'eventId': '555',
          'title': (call.arguments['title'] as String?)?.isNotEmpty == true
              ? call.arguments['title']
              : 'Reunião Tática',
        };
      }
      if (call.method == 'scheduleReminderAlarm' ||
          call.method == 'cancelReminderAlarm') {
        return true;
      }
      return true;
    });

    final service = DeviceControlService(
      channel: channel,
      obsidianProvider: () async => obs,
      reminderProvider: () async => reminderSvc,
    );

    // 1. Obsidian Append + Tasks + Status + Read + List + Undo via AI tags & natural commands
    final aiObs = await service.executeAiActions(
      'Atualizando cofre. '
      '[ACTION:OBSIDIAN_APPEND:Memoria/Operador.md:- [ ] Testar sensor KWS] '
      '[ACTION:OBSIDIAN_TASKS:marcar:1] '
      '[ACTION:OBSIDIAN_LIST:Memoria] '
      '[ACTION:OBSIDIAN_READ:Memoria/Operador.md] '
      '[ACTION:OBSIDIAN_STATUS]',
    );
    expect(aiObs.executedLogs.length, 5);
    expect(aiObs.executedLogs[0], contains('Anexado em Operador.md'));
    expect(aiObs.executedLogs[1], contains('[x] Testar sensor KWS'));
    expect(aiObs.executedLogs[2], contains('Memoria/Operador.md'));
    expect(aiObs.executedLogs[3], contains('Perfil do Operador'));
    expect(aiObs.executedLogs[4], contains('notas'));

    // Undo via natural command reverts checkbox mark
    final undo1 = await service.tryExecuteNaturalCommand('desfazer');
    expect(undo1?.handled, isTrue);
    expect(undo1?.message, contains('OBSIDIAN_TASKS'));
    expect(
      await obs.readNote('Memoria/Operador.md'),
      contains('- [ ] Testar sensor KWS'),
    );

    // Undo via AI tag [ACTION:UNDO] reverts the append
    final undo2 = await service.executeAiActions('[ACTION:UNDO]');
    expect(undo2.executedLogs.single, contains('OBSIDIAN_APPEND'));
    expect(
      await obs.readNote('Memoria/Operador.md'),
      isNot(contains('Testar sensor KWS')),
    );

    // 2. Calendar CANCEL_EVENT enforces ActionGate (RiskLevel.sensitive)
    final deniedCancel = await service.executeAiActions(
      '[ACTION:CANCEL_EVENT:Reunião Tática]',
      confirmAction: (_) async => false,
    );
    expect(deniedCancel.executedLogs.single, contains('bloqueado'));
    expect(calls.where((c) => c.method == 'deleteCalendarEvent'), isEmpty);

    final approvedCancel = await service.executeAiActions(
      '[ACTION:CANCEL_EVENT:Reunião Tática]',
      confirmAction: (_) async => true,
    );
    expect(approvedCancel.executedLogs.single,
        contains('Evento removido: "Reunião Tática"'));
    expect(calls.where((c) => c.method == 'deleteCalendarEvent').length, 1);

    // 3. Persistent Reminders (REMINDER_CREATE, REMINDER_LIST, REMINDER_CANCEL)
    final createRem = await service.tryExecuteNaturalCommand(
      'me lembre de Revisar backup daqui 20 minutos',
    );
    expect(createRem?.handled, isTrue);
    expect(createRem?.message, contains('Revisar backup'));
    expect(calls.any((c) => c.method == 'scheduleReminderAlarm'), isTrue);

    final listRem =
        await service.tryExecuteNaturalCommand('listar lembretes');
    expect(listRem?.handled, isTrue);
    expect(listRem?.message, contains('Revisar backup'));

    final cancelRem = await service.executeAiActions(
      '[ACTION:REMINDER_CANCEL:1]',
    );
    expect(cancelRem.executedLogs.single, contains('Lembrete #1 cancelado'));
    expect(calls.any((c) => c.method == 'cancelReminderAlarm'), isTrue);
    expect(await service.listReminders(onlyPending: true), isEmpty);
  });

  test(
      'executes Phase 2 WEATHER, NEWS, WEB_SEARCH, SKILL_CREATE/DELETE, and FLOW_* via DeviceControlService',
      () async {
    sqfliteFfiInit();
    final flowDb = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, singleInstance: false),
    );
    final flowSvc = await WorkflowSchedulerService.open(
      database: flowDb,
      channel: channel,
    );
    addTearDown(() => flowSvc.close());

    final tempDir =
        await Directory.systemTemp.createTemp('ultron_phase2_dc_test_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final obs = ObsidianService(tempDir);
    await obs.initialize();

    final mockWebInfo = WebInfoService(
      briefingService: BriefingService(
        weatherFetcher: (city) async => WeatherSnapshot(
          city: city.isEmpty ? 'São Paulo' : city,
          tempC: 23,
          feelsLikeC: 24,
          condition: 'Céu aberto',
        ),
      ),
      httpGetText: (uri, {headers = const {}}) async {
        if (uri.host.contains('news.google.com')) {
          return '<rss><channel><item><title>IA avança no Brasil - TechBR</title><link>https://example.com</link></item></channel></rss>';
        }
        return '{"Heading":"Dart","AbstractText":"Linguagem otimizada para multiplataforma.","AbstractURL":"https://dart.dev"}';
      },
    );

    final service = DeviceControlService(
      channel: channel,
      obsidianProvider: () async => obs,
      webInfoProvider: () => mockWebInfo,
      workflowSchedulerProvider: () async => flowSvc,
    );

    // 1. WEATHER, NEWS, WEB_SEARCH
    final wNat =
        await service.tryExecuteNaturalCommand('clima em Florianópolis');
    expect(wNat?.handled, isTrue);
    expect(wNat?.message, contains('Florianópolis: 23°C'));

    final nNat =
        await service.tryExecuteNaturalCommand('notícias sobre tecnologia');
    expect(nNat?.handled, isTrue);
    expect(nNat?.message, contains('IA avança no Brasil'));

    final wsNat =
        await service.tryExecuteNaturalCommand('pesquisar_web Dart lang');
    expect(wsNat?.handled, isTrue);
    expect(wsNat?.message, contains('Linguagem otimizada'));

    // 2. SKILL_CREATE & SKILL_DELETE (requires confirmation as sensitive)
    final deniedSkill = await service.executeAiActions(
      '[ACTION:SKILL_CREATE:alerta_rapido|[ACTION:TORCH_ON]]',
      confirmAction: (_) async => false,
    );
    expect(deniedSkill.executedLogs.single, contains('bloqueado'));

    final createdSkill = await service.executeAiActions(
      '[ACTION:SKILL_CREATE:alerta_rapido|[ACTION:TORCH_ON]]',
      confirmAction: (_) async => true,
    );
    expect(createdSkill.executedLogs.single,
        contains('Skills/alerta_rapido.md'));
    expect(await obs.findSkill('alerta_rapido'), isNotNull);

    final deletedSkill = await service.executeAiActions(
      '[ACTION:SKILL_DELETE:alerta_rapido]',
      confirmAction: (_) async => true,
    );
    expect(
        deletedSkill.executedLogs.single, contains('Skill removida: alerta_rapido'));
    expect(await obs.findSkill('alerta_rapido'), isNull);

    // 3. FLOW_CREATE, FLOW_LIST, FLOW_RUN, FLOW_SCHEDULE, FLOW_DELETE
    final flowExec = await service.executeAiActions(
      '[ACTION:FLOW_CREATE:rotina_luz|TORCH_ON -> VOLUME_SET:65|daqui 30m] '
      '[ACTION:FLOW_LIST] '
      '[ACTION:FLOW_RUN:rotina_luz] '
      '[ACTION:FLOW_SCHEDULE:rotina_luz:a cada 60m] '
      '[ACTION:FLOW_DELETE:rotina_luz]',
      confirmAction: (_) async => true,
    );
    expect(flowExec.executedLogs.length, 5);
    expect(flowExec.executedLogs[0], contains('Fluxo #1 "rotina_luz" criado'));
    expect(flowExec.executedLogs[1], contains('1 fluxo(s)'));
    expect(flowExec.executedLogs[2], contains('Fluxo "rotina_luz" executado'));
    expect(flowExec.executedLogs[3], contains('a cada 60m'));
    expect(flowExec.executedLogs[4], contains('Fluxo "rotina_luz" removido'));
  });

  test(
      'executes Phase 5 Wake-Word Multi-Profile hot-swap and Floating Orb AuthGate sync',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getWakeWordProfile') return 'jarvis';
      if (call.method == 'setWakeWordProfile') {
        return {
          'id': call.arguments['profile'],
          'label': 'Jarvis',
          'hotSwapped': true,
        };
      }
      if (call.method == 'isFloatingOrbRunning') return true;
      if (call.method == 'setFloatingOrb') {
        return call.arguments['enabled'] == true;
      }
      if (call.method == 'consumePendingFloatingOrbTap') {
        return {'triggered': true, 'requiresUnlock': true};
      }
      return true;
    });

    final service = DeviceControlService(channel: channel);

    // 1. Multi-profile wake-word switch
    final updatedProfile =
        await service.setWakeWordProfile(WakeWordProfile.jarvis);
    expect(updatedProfile, WakeWordProfile.jarvis);
    expect(WakeWord.activeProfile, WakeWordProfile.jarvis);
    expect(calls.last.method, 'setWakeWordProfile');
    expect(calls.last.arguments['profile'], 'jarvis');

    // Reset back to ultron for clean global state
    await service.setWakeWordProfile(WakeWordProfile.ultron);
    expect(WakeWord.activeProfile, WakeWordProfile.ultron);

    // 2. Floating Orb start/stop, state update, and AuthGate lock sync
    expect(await service.setFloatingOrb(true), isTrue);
    expect(calls.last.method, 'setFloatingOrb');
    expect(calls.last.arguments['enabled'], isTrue);

    await service.updateFloatingOrbState('ouvindo');
    expect(calls.last.method, 'updateFloatingOrbState');
    expect(calls.last.arguments['state'], 'ouvindo');

    await service.syncFloatingOrbAuthState(
      locked: true,
      accessLevel: 'locked',
    );
    expect(calls.last.method, 'setFloatingOrbAuthState');
    expect(calls.last.arguments['locked'], isTrue);
    expect(calls.last.arguments['accessLevel'], 'locked');

    final pendingTap = await service.consumePendingFloatingOrbTap();
    expect(pendingTap?.triggered, isTrue);
    expect(pendingTap?.requiresUnlock, isTrue);

    bool? callbackRequiresUnlock;
    service.setNativeEventHandlers(
      onFloatingOrbTapped: (reqUnlock) => callbackRequiresUnlock = reqUnlock,
    );
    const codec = StandardMethodCodec();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(
        const MethodCall('onFloatingOrbTapped', {'requiresUnlock': true}),
      ),
      (_) {},
    );
    expect(callbackRequiresUnlock, isTrue);
  });
}

class _RealHttpOverrides extends HttpOverrides {}

class _TestSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _data = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }
}
