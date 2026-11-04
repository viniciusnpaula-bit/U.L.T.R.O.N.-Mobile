import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/services/device_control_service.dart';

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

    final timeRes = await service.tryExecuteNaturalCommand('Ei Ultron, que horas são?');
    expect(timeRes?.handled, isTrue);
    expect(calls.last.method, 'speakOfflineFishVoice');

    final vadRes = await service.tryExecuteNaturalCommand('ativar sentinela de voz');
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

  test('reads, replies in background, and sends WhatsApp/SMS via natural language', () async {
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

  test('listenVoice invokes native speech recognizer and trims output', () async {
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

  test('parses and executes AI [ACTION:...] tags and cleans reply text', () async {
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
      expect(await service.verifyFileIntegrity(file, 'wrong_hash_value'), isFalse);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('prepares PC sync payload with HMAC-SHA256 signature', () {
    final service = DeviceControlService(channel: channel);
    final sync = service.preparePcSyncPayload(
      command: 'SYNC_TELEMETRY',
      data: const {'battery': 98, 'ram': 4096},
    );
    expect(sync['body'], contains('SYNC_TELEMETRY'));
    expect(sync['signature'], startsWith('sha256='));
    expect(sync['timestamp'], isNotEmpty);
  });
}
