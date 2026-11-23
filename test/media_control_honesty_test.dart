import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/services/cognicao_service.dart';
import 'package:ultron_mobile/services/device_control_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Proactive & honest media control when Spotify is closed', () {
    const channel = MethodChannel('com.viniciusnpaula.ultron_mobile/device');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('proactively opens Spotify and confirms if playback started after launch',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'mediaControl') {
          return <String, Object>{
            'status': 'confirmed',
            'confirmed': true,
            'activePackage': 'com.spotify.music',
            'launchedApp': 'Spotify',
            'detail': 'Abri Spotify e retomei a reprodução.',
          };
        }
        return null;
      });

      final service = DeviceControlService(channel: channel);
      final res = await service.tryExecuteNaturalCommand(
        'continuar a música no spotify',
      );
      expect(res?.handled, isTrue);
      expect(res!.message, contains('abri o aplicativo e retomei'));
      expect(res.speakText, contains('Abri o Spotify'));
    });

    test('proactively opens Spotify and honestly tells user when app opened without auto-play',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'mediaControl') {
          return <String, Object>{
            'status': 'opened_needs_play',
            'confirmed': false,
            'activePackage': '',
            'launchedApp': 'Spotify',
            'detail': 'Spotify estava fechado; abri o aplicativo, mas o play automático não iniciou.',
          };
        }
        return null;
      });

      final service = DeviceControlService(channel: channel);
      final res = await service.tryExecuteNaturalCommand(
        'continuar a música no spotify',
      );
      expect(res?.handled, isTrue);
      expect(res!.message, contains('já abri o aplicativo'));
      expect(res.message, contains('toque em play'));
      expect(res.message, isNot(contains('retomada')));
    });

    test('falls back to Dart openApp proactively if native reports no_active_session on play',
        () async {
      String? launchedAppQuery;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'mediaControl') {
          return <String, Object>{
            'status': 'no_active_session',
            'confirmed': false,
            'activePackage': '',
            'detail': 'Nenhuma sessão ativa encontrada para spotify.',
          };
        }
        if (call.method == 'openApp') {
          final args = Map<Object?, Object?>.from(call.arguments as Map);
          launchedAppQuery = args['target'] as String?;
          return 'Spotify';
        }
        return null;
      });

      final service = DeviceControlService(channel: channel);
      final res = await service.tryExecuteNaturalCommand(
        'continuar a música no spotify',
      );
      expect(res?.handled, isTrue);
      expect(launchedAppQuery, 'spotify');
      expect(res!.message, contains('já abri o aplicativo'));
    });

    test('does NOT proactively open Spotify on pause when nothing is playing',
        () async {
      var opened = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'mediaControl') {
          return <String, Object>{
            'status': 'no_active_session',
            'confirmed': false,
            'activePackage': '',
            'detail': 'Nenhuma reprodução ativa.',
          };
        }
        if (call.method == 'openApp') {
          opened = true;
          return 'Spotify';
        }
        return null;
      });

      final service = DeviceControlService(channel: channel);
      final res = await service.tryExecuteNaturalCommand(
        'pausar música no spotify',
      );
      expect(res?.handled, isTrue);
      expect(opened, isFalse);
      expect(res!.message, contains('Nenhuma reprodução ativa'));
    });

    test('CognicaoService intercepts false LLM confirmation when app only opened awaiting play',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'mediaControl') {
          return <String, Object>{
            'status': 'opened_needs_play',
            'confirmed': false,
            'launchedApp': 'Spotify',
            'detail': 'Aberto sem auto-play.',
          };
        }
        return null;
      });

      final service = DeviceControlService(channel: channel);
      final exec = await service.executeAiActions(
        'Pronto! Continuei sua música no Spotify. [ACTION:MEDIA_PLAY]',
      );
      expect(exec.executedLogs.first, contains('aguardando play'));

      const cognicao = CognicaoService();
      final audit = cognicao.auditResponse(
        cleanReplyText: exec.cleanText,
        executedTools: exec.executedLogs,
      );
      expect(audit.hallucinatedExecution, isTrue);
      expect(audit.speakText, contains('abri para você'));
      expect(audit.speakText, contains('play'));
    });
  });
}
