import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ultron_mobile/core/security/action_gate.dart';
import 'package:ultron_mobile/core/security/auth_gate.dart';
import 'package:ultron_mobile/services/audit_log_service.dart';
import 'package:ultron_mobile/services/desktop_command_listener.dart';
import 'package:ultron_mobile/services/desktop_pairing_service.dart';
import 'package:ultron_mobile/services/device_control_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const channel = MethodChannel('com.viniciusnpaula.ultron_mobile/device');
  late List<MethodCall> nativeCalls;
  late _MemorySecureStorage storage;
  late AuditLogService audit;
  late AuthGate authGate;
  late DeviceControlService device;

  setUp(() async {
    nativeCalls = <MethodCall>[];
    storage = _MemorySecureStorage();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, singleInstance: false),
    );
    audit = await AuditLogService.open(database: db);
    authGate = AuthGate(auth: _FakeLocalAuth());
    await authGate.authenticateBiometric();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call);
      if (call.method == 'resolveContact') {
        final q = '${(call.arguments as Map?)?['query'] ?? ''}'.toLowerCase();
        if (q.contains('joão') || q.contains('joao')) {
          return {'found': true, 'name': 'João Silva', 'phone': '11999998888'};
        }
        if (q.contains('maria')) {
          return {'found': true, 'name': 'Maria Souza', 'phone': '11977776666'};
        }
        if (q.contains('ana')) {
          return {'found': true, 'name': 'Ana Costa', 'phone': '21988887777'};
        }
        return {'found': false, 'name': '', 'phone': ''};
      }
      if (call.method == 'placePhoneCall') {
        final target = (call.arguments as Map?)?['target'];
        return 'Ligação telefônica iniciada para $target.';
      }
      if (call.method == 'placeWhatsAppCall') {
        final target = (call.arguments as Map?)?['target'];
        final video = (call.arguments as Map?)?['video'] == true;
        return 'WhatsApp: ${video ? 'chamada de vídeo' : 'ligação'} iniciada para $target.';
      }
      return true;
    });

    device = DeviceControlService(
      channel: channel,
      storage: storage,
      authGate: authGate,
      auditLogProvider: () async => audit,
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await audit.close();
  });

  group('ActionGate mandatory confirmation for calls', () {
    const gate = ActionGate();

    test(
        'CALL_PHONE and WHATSAPP_CALL are sensitive and require confirmation even in sovereign mode',
        () {
      final phoneSim = gate.simulate('[ACTION:CALL_PHONE:João]');
      expect(phoneSim.actionCode, 'CALL_PHONE');
      expect(phoneSim.riskLevel, RiskLevel.sensitive);
      expect(phoneSim.requiresConfirmation, isTrue);

      final phoneDecision =
          gate.evaluatePrivilege(phoneSim, AccessLevel.sovereign);
      expect(phoneDecision.allowed, isTrue);
      expect(phoneDecision.requiresConfirmation, isTrue);

      final waSim = gate.simulate('[ACTION:WHATSAPP_CALL:Maria]');
      expect(waSim.actionCode, 'WHATSAPP_CALL');
      expect(waSim.riskLevel, RiskLevel.sensitive);
      expect(waSim.requiresConfirmation, isTrue);

      final waDecision = gate.evaluatePrivilege(waSim, AccessLevel.sovereign);
      expect(waDecision.allowed, isTrue);
      expect(waDecision.requiresConfirmation, isTrue);

      final waVideoSim = gate.simulate('[ACTION:WHATSAPP_CALL:Ana:video]');
      expect(waVideoSim.actionCode, 'WHATSAPP_CALL');
      expect(waVideoSim.description, contains('vídeo'));
      expect(waVideoSim.requiresConfirmation, isTrue);
    });
  });

  group('Natural voice commands for Phone & WhatsApp calls', () {
    test(
        '"ligar para João" resolves contact, asks confirmation with name+phone, and invokes placePhoneCall',
        () async {
      ActionSimulation? prompted;
      final res = await device.tryExecuteNaturalCommand(
        'Ultron, ligar para João',
        confirmAction: (sim) async {
          prompted = sim;
          return true;
        },
      );

      expect(res, isNotNull);
      expect(res!.handled, isTrue);
      expect(prompted, isNotNull);
      expect(prompted!.actionCode, 'CALL_PHONE');
      expect(prompted!.targetResource, contains('João Silva'));
      expect(prompted!.targetResource, contains('11999998888'));
      expect(
        nativeCalls.where((c) => c.method == 'placePhoneCall').length,
        1,
      );
      expect(
        (nativeCalls.firstWhere((c) => c.method == 'placePhoneCall').arguments
            as Map)['target'],
        'João',
      );
    });

    test('"ligar para 11988887777" invokes placePhoneCall after confirmation',
        () async {
      final res = await device.tryExecuteNaturalCommand(
        'ligar para 11988887777',
        confirmAction: (_) async => true,
      );

      expect(res, isNotNull);
      expect(res!.handled, isTrue);
      final call = nativeCalls.firstWhere((c) => c.method == 'placePhoneCall');
      expect((call.arguments as Map)['target'], '11988887777');
    });

    test(
        '"ligar para Maria pelo WhatsApp" invokes placeWhatsAppCall(video: false)',
        () async {
      ActionSimulation? prompted;
      final res = await device.tryExecuteNaturalCommand(
        'ligar para Maria pelo WhatsApp',
        confirmAction: (sim) async {
          prompted = sim;
          return true;
        },
      );

      expect(res, isNotNull);
      expect(res!.handled, isTrue);
      expect(prompted?.actionCode, 'WHATSAPP_CALL');
      expect(prompted?.targetResource, contains('Maria Souza'));
      final waCall =
          nativeCalls.firstWhere((c) => c.method == 'placeWhatsAppCall');
      expect((waCall.arguments as Map)['target'], 'Maria');
      expect((waCall.arguments as Map)['video'], isFalse);
    });

    test(
        '"fazer ligação de vídeo no whatsapp para Ana" invokes placeWhatsAppCall(video: true)',
        () async {
      final res = await device.tryExecuteNaturalCommand(
        'fazer ligação de vídeo no whatsapp para Ana',
        confirmAction: (_) async => true,
      );

      expect(res, isNotNull);
      expect(res!.handled, isTrue);
      final waCall =
          nativeCalls.firstWhere((c) => c.method == 'placeWhatsAppCall');
      expect((waCall.arguments as Map)['target'], 'Ana');
      expect((waCall.arguments as Map)['video'], isTrue);
    });

    test('denies call when operator cancels confirmation or when confirmAction is null (fail-closed)',
        () async {
      final cancelled = await device.tryExecuteNaturalCommand(
        'ligar para João pelo WhatsApp',
        confirmAction: (_) async => false,
      );
      expect(cancelled?.handled, isTrue);
      expect(cancelled?.message, contains('cancelada'));
      expect(
        nativeCalls.where((c) => c.method == 'placeWhatsAppCall'),
        isEmpty,
      );

      final failClosed = await device.tryExecuteNaturalCommand(
        'ligar para João',
      );
      expect(failClosed?.handled, isTrue);
      expect(failClosed?.message, contains('cancelada'));
      expect(
        nativeCalls.where((c) => c.method == 'placePhoneCall'),
        isEmpty,
      );
    });
  });

  group('AI tags & Desktop inbound for calls', () {
    test('executeAiActions runs CALL_PHONE and WHATSAPP_CALL with confirmation',
        () async {
      var confirmCount = 0;
      final exec = await device.executeAiActions(
        'Certo, iniciando agora.\n'
        '[ACTION:CALL_PHONE:Carlos]\n'
        '[ACTION:WHATSAPP_CALL:Maria:video]',
        confirmAction: (_) async {
          confirmCount++;
          return true;
        },
      );

      expect(confirmCount, 2);
      expect(
        nativeCalls.where((c) => c.method == 'placePhoneCall').length,
        1,
      );
      expect(
        nativeCalls.where((c) => c.method == 'placeWhatsAppCall').length,
        1,
      );
      expect(exec.executedLogs.length, 2);
    });

    test('DesktopCommandListener enforces confirmation on CALL_PHONE and WHATSAPP_CALL',
        () async {
      final pairing = DesktopPairingService(storage: storage);
      const config = DesktopPairingConfig(
        baseUrl: 'http://127.0.0.1:8765',
        deviceId: 'galaxy-a34',
        sharedSecret: 'secret-32-chars-desktop-bridge!!',
      );
      await pairing.savePairing(config);
      final fixedNow = DateTime(2026, 11, 27, 11, 30);

      final listener = DesktopCommandListener(
        pairingService: pairing,
        deviceService: device,
        authGate: authGate,
        now: () => fixedNow,
        confirmAction: (_) async => true,
      );

      final rPhone = await listener.handleVerifiedEnvelope(
        rawBody: jsonEncode({
          'command_id': 'cmd-call-1',
          'device_id': 'galaxy-a34',
          'command': 'CALL_PHONE',
          'args': {'target': 'João'},
          'timestamp': fixedNow.millisecondsSinceEpoch.toString(),
          'nonce': 'nonce-call-1',
        }),
        config: config,
      );
      expect(rPhone?.ok, isTrue);
      expect(
        nativeCalls.where((c) => c.method == 'placePhoneCall').length,
        1,
      );

      final rWa = await listener.handleVerifiedEnvelope(
        rawBody: jsonEncode({
          'command_id': 'cmd-call-2',
          'device_id': 'galaxy-a34',
          'command': 'WHATSAPP_CALL',
          'args': {'target': 'Maria', 'video': true},
          'timestamp': fixedNow.millisecondsSinceEpoch.toString(),
          'nonce': 'nonce-call-2',
        }),
        config: config,
      );
      expect(rWa?.ok, isTrue);
      final waCall =
          nativeCalls.firstWhere((c) => c.method == 'placeWhatsAppCall');
      expect((waCall.arguments as Map)['video'], isTrue);
    });
  });
}

class _FakeLocalAuth extends LocalAuthentication {
  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<bool> get canCheckBiometrics async => true;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<Object> authMessages = const <Object>[],
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async =>
      true;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async =>
      const [BiometricType.fingerprint];
}

class _MemorySecureStorage extends FlutterSecureStorage {
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
