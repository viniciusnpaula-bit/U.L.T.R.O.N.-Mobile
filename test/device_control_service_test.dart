import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ultron_mobile/services/audit_log_service.dart';
import 'package:ultron_mobile/services/device_control_service.dart';
import 'package:ultron_mobile/services/obsidian_service.dart';

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
}

class _RealHttpOverrides extends HttpOverrides {}
