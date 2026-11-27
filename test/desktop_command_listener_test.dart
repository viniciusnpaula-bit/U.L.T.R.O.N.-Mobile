import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ultron_mobile/core/security/auth_gate.dart';
import 'package:ultron_mobile/services/audit_log_service.dart';
import 'package:ultron_mobile/services/desktop_command_listener.dart';
import 'package:ultron_mobile/services/desktop_pairing_service.dart';
import 'package:ultron_mobile/services/device_control_service.dart';
import 'package:ultron_mobile/services/obsidian_service.dart';

class _RealHttpOverrides extends HttpOverrides {}

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

class _TestMemoryStorage extends FlutterSecureStorage {
  final Map<String, String> data = <String, String>{};

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
      data[key];

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
      data.remove(key);
    } else {
      data[key] = value;
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
    data.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.viniciusnpaula.ultron_mobile/device');
  late List<MethodCall> nativeCalls;
  late AuditLogService audit;
  HttpOverrides? previousHttpOverrides;

  setUp(() async {
    previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = _RealHttpOverrides();
    nativeCalls = <MethodCall>[];
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, singleInstance: false),
    );
    audit = await AuditLogService.open(database: db);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call);
      if (call.method == 'openApp') {
        final target = (call.arguments as Map)['target'] as String? ?? '';
        return 'App aberto: $target';
      }
      if (call.method == 'sendWhatsApp') {
        return 'WhatsApp iniciado para ${(call.arguments as Map)['target']}';
      }
      if (call.method == 'setTorch') {
        return (call.arguments as Map)['enabled'] as bool? ?? true;
      }
      return true;
    });
  });

  tearDown(() async {
    HttpOverrides.global = previousHttpOverrides;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await audit.close();
  });

  test('pollOnce verifies signed OPEN_APP from Desktop and posts signed result',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    const secret = 'desktop-bridge-secret-32-chars!!';
    final fixedNow = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    final storage = _TestMemoryStorage();
    final pairing = DesktopPairingService(
      storage: storage,
      now: () => fixedNow,
      nonceGenerator: () => '0123456789abcdef0123456789abcdef',
    );
    await pairing.savePairing(
      DesktopPairingConfig(
        baseUrl: 'http://127.0.0.1:${server.port}',
        deviceId: 'galaxy-a34',
        sharedSecret: secret,
      ),
    );

    final authGate = AuthGate(auth: _FakeLocalAuth());
    await authGate.authenticatePin('1234', (_) async => true);

    final listenerPinCheck = DesktopCommandListener(
      pairingService: pairing,
      deviceService: DeviceControlService(
        channel: channel,
        auditLogProvider: () async => audit,
      ),
      authGate: authGate,
      now: () => fixedNow,
      nonceGenerator: () => '0123456789abcdef0123456789abcdef',
    );
    // PIN-only (basic) must fail closed on Desktop->Mobile
    expect(await listenerPinCheck.pollOnce(), DesktopPollOutcome.locked);

    await authGate.authenticateBiometric();
    expect(authGate.level, AccessLevel.sovereign);

    Map<String, dynamic>? postedResultBody;
    String? postedSig;
    String? pollSig;
    String? pollTs;
    String? pollNonce;

    server.listen((req) async {
      if (req.method == 'GET' && req.uri.path == '/api/mobile/poll') {
        pollSig = req.headers.value('x-ultron-signature');
        pollTs = req.headers.value('x-ultron-timestamp');
        pollNonce = req.headers.value('x-ultron-nonce');
        final envTs = fixedNow.millisecondsSinceEpoch.toString();
        const envNonce = 'fedcba9876543210fedcba9876543210';
        final rawBody = jsonEncode({
          'command_id': 'cmd-100',
          'device_id': 'galaxy-a34',
          'command': 'OPEN_APP',
          'args': {'app': 'whatsapp'},
          'timestamp': envTs,
          'nonce': envNonce,
        });
        final respSig = DesktopPairingService.computeSignature(
          timestamp: envTs,
          nonce: envNonce,
          body: rawBody,
          sharedSecret: secret,
        );
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.headers.set('X-Ultron-Timestamp', envTs);
        req.response.headers.set('X-Ultron-Nonce', envNonce);
        req.response.headers.set('X-Ultron-Signature', 'sha256=$respSig');
        req.response.write(rawBody);
        await req.response.close();
      } else if (req.method == 'POST' && req.uri.path == '/api/mobile/result') {
        final raw = await utf8.decoder.bind(req).join();
        postedSig = req.headers.value('x-ultron-signature');
        postedResultBody = jsonDecode(raw) as Map<String, dynamic>;
        req.response.statusCode = 200;
        await req.response.close();
      }
    });

    DesktopInboundResult? handled;
    final listenerBiometric = DesktopCommandListener(
      pairingService: pairing,
      deviceService: DeviceControlService(
        channel: channel,
        auditLogProvider: () async => audit,
      ),
      authGate: authGate,
      now: () => fixedNow,
      nonceGenerator: () => '0123456789abcdef0123456789abcdef',
      onCommandHandled: (res) => handled = res,
    );

    final outcome = await listenerBiometric.pollOnce();

    expect(outcome, DesktopPollOutcome.commandHandled);
    final expectedPollSig = DesktopPairingService.computeSignature(
      timestamp: pollTs ?? '',
      nonce: pollNonce ?? '',
      body: '',
      sharedSecret: secret,
    );
    expect(pollSig, expectedPollSig);
    expect(nativeCalls.any((c) => c.method == 'openApp'), isTrue);
    expect(handled?.ok, isTrue);
    expect(handled?.command, 'OPEN_APP');
    expect(postedResultBody?['command_id'], 'cmd-100');
    expect(postedResultBody?['ok'], isTrue);
    expect(postedResultBody?['status'], 'executed');
    expect(postedSig, isNotEmpty);

    final audits = await audit.recent(limit: 5);
    expect(
      audits.any((a) => a.actor == 'DESKTOP_LAN' && a.action == 'OPEN_APP'),
      isTrue,
    );
  });

  test('fail-closed: rejects invalid HMAC signature, replay, and expired timestamp',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    const secret = 'desktop-bridge-secret-32-chars!!';
    final fixedNow = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    final storage = _TestMemoryStorage();
    final pairing = DesktopPairingService(
      storage: storage,
      now: () => fixedNow,
    );
    final config = DesktopPairingConfig(
      baseUrl: 'http://127.0.0.1:${server.port}',
      deviceId: 'galaxy-a34',
      sharedSecret: secret,
    );
    await pairing.savePairing(config);

    final authGate = AuthGate(auth: _FakeLocalAuth());
    await authGate.authenticatePin('1234', (_) async => true);

    final listenerPinCheck = DesktopCommandListener(
      pairingService: pairing,
      deviceService: DeviceControlService(
        channel: channel,
        auditLogProvider: () async => audit,
      ),
      authGate: authGate,
      now: () => fixedNow,
      nonceGenerator: () => '0123456789abcdef0123456789abcdef',
    );
    // PIN-only (basic) must fail closed on Desktop->Mobile
    expect(await listenerPinCheck.pollOnce(), DesktopPollOutcome.locked);

    await authGate.authenticateBiometric();
    expect(authGate.level, AccessLevel.sovereign);

    server.listen((req) async {
      if (req.uri.path == '/api/mobile/poll') {
        req.response.statusCode = 200;
        req.response.headers.set('X-Ultron-Signature', 'sha256=deadbeef');
        req.response.write(jsonEncode({
          'command_id': 'cmd-bad-sig',
          'device_id': 'galaxy-a34',
          'command': 'OPEN_APP',
          'args': {'app': 'whatsapp'},
          'timestamp': fixedNow.millisecondsSinceEpoch.toString(),
          'nonce': '11111111111111111111111111111111',
        }));
      } else {
        req.response.statusCode = 200;
      }
      await req.response.close();
    });

    final listener = DesktopCommandListener(
      pairingService: pairing,
      deviceService: DeviceControlService(
        channel: channel,
        auditLogProvider: () async => audit,
      ),
      authGate: authGate,
      now: () => fixedNow,
    );

    await listener.pollOnce();
    expect(nativeCalls.where((c) => c.method == 'openApp'), isEmpty);

    final validBody = jsonEncode({
      'command_id': 'cmd-replay-1',
      'device_id': 'galaxy-a34',
      'command': 'TORCH_ON',
      'args': {},
      'timestamp': fixedNow.millisecondsSinceEpoch.toString(),
      'nonce': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    });
    final first = await listener.handleVerifiedEnvelope(
      rawBody: validBody,
      config: config,
    );
    expect(first?.ok, isTrue);

    final replay = await listener.handleVerifiedEnvelope(
      rawBody: validBody,
      config: config,
    );
    expect(replay?.ok, isFalse);
    expect(replay?.status, 'denied');

    final expired = await listener.handleVerifiedEnvelope(
      rawBody: jsonEncode({
        'command_id': 'cmd-expired',
        'device_id': 'galaxy-a34',
        'command': 'TORCH_ON',
        'args': {},
        'timestamp': (fixedNow.millisecondsSinceEpoch - 120000).toString(),
        'nonce': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      }),
      config: config,
    );
    expect(expired?.ok, isFalse);
    expect(expired?.status, 'denied');

    final sensitiveDenied = await listener.handleVerifiedEnvelope(
      rawBody: jsonEncode({
        'command_id': 'cmd-wa-denied',
        'device_id': 'galaxy-a34',
        'command': 'WHATSAPP',
        'args': {'target': 'Carlos', 'text': 'Oi'},
        'timestamp': fixedNow.millisecondsSinceEpoch.toString(),
        'nonce': 'cccccccccccccccccccccccccccccccc',
      }),
      config: config,
    );
    expect(sensitiveDenied?.ok, isFalse);
    expect(sensitiveDenied?.status, 'cancelled');
    expect(nativeCalls.where((c) => c.method == 'sendWhatsApp'), isEmpty);

    final headerMismatch = await listener.handleVerifiedEnvelope(
      rawBody: jsonEncode({
        'command_id': 'cmd-hdr-mismatch',
        'device_id': 'galaxy-a34',
        'command': 'TORCH_ON',
        'args': {},
        'timestamp': fixedNow.millisecondsSinceEpoch.toString(),
        'nonce': 'dddddddddddddddddddddddddddddddd',
      }),
      config: config,
      headerTimestamp: fixedNow.millisecondsSinceEpoch.toString(),
      headerNonce: 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
    );
    expect(headerMismatch?.ok, isFalse);
    expect(headerMismatch?.status, 'denied');

    final confirmingListener = DesktopCommandListener(
      pairingService: pairing,
      deviceService: DeviceControlService(
        channel: channel,
        auditLogProvider: () async => audit,
      ),
      authGate: authGate,
      now: () => fixedNow,
      confirmAction: (_) async => true,
    );
    final sensitiveAllowed = await confirmingListener.handleVerifiedEnvelope(
      rawBody: jsonEncode({
        'command_id': 'cmd-wa-allowed',
        'device_id': 'galaxy-a34',
        'command': 'WHATSAPP',
        'args': {'target': 'Carlos', 'text': 'Oi'},
        'timestamp': fixedNow.millisecondsSinceEpoch.toString(),
        'nonce': 'ffffffffffffffffffffffffffffffff',
      }),
      config: config,
    );
    expect(sensitiveAllowed?.ok, isTrue);
    expect(sensitiveAllowed?.status, 'executed');
    expect(nativeCalls.where((c) => c.method == 'sendWhatsApp').length, 1);
  });

  test('LIST_SKILLS and RUN_SKILL allow Desktop to discover and trigger Mobile skills with ActionGate protection',
      () async {
    final tempVault =
        await Directory.systemTemp.createTemp('ultron_mobile_skills_bridge_');
    addTearDown(() async {
      if (await tempVault.exists()) {
        await tempVault.delete(recursive: true);
      }
    });
    final obs = ObsidianService(tempVault);
    await obs.initialize();
    await obs.createSkill(
      'enviar_aviso_wa',
      '# Enviar Aviso\n[ACTION:WHATSAPP:Carlos:Cheguei]',
    );

    final storage = _TestMemoryStorage();
    final pairing = DesktopPairingService(storage: storage);
    final config = const DesktopPairingConfig(
      baseUrl: 'http://127.0.0.1:8765',
      deviceId: 'galaxy-a34',
      sharedSecret: 'desktop-bridge-secret-32-chars!!',
    );
    await pairing.savePairing(config);

    final authGate = AuthGate(auth: _FakeLocalAuth());
    await authGate.authenticateBiometric();

    final fixedNow = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    final listener = DesktopCommandListener(
      pairingService: pairing,
      deviceService: DeviceControlService(
        channel: channel,
        auditLogProvider: () async => audit,
        obsidianProvider: () async => obs,
      ),
      authGate: authGate,
      now: () => fixedNow,
    );

    // 1. LIST_SKILLS returns Mobile skills with risk level metadata
    final listRes = await listener.handleVerifiedEnvelope(
      rawBody: jsonEncode({
        'command_id': 'cmd-list-skills',
        'device_id': 'galaxy-a34',
        'command': 'LIST_SKILLS',
        'args': {},
        'timestamp': fixedNow.millisecondsSinceEpoch.toString(),
        'nonce': '11112222333344445555666677778888',
      }),
      config: config,
    );
    expect(listRes?.ok, isTrue);
    final listedSkills = (listRes?.data['skills'] as List).cast<Map>();
    expect(listedSkills.any((s) => s['slug'] == 'alerta_tatico'), isTrue);
    final waSkill =
        listedSkills.firstWhere((s) => s['slug'] == 'enviar_aviso_wa');
    expect(waSkill['riskLevel'], 'sensitive');
    expect(waSkill['requiresConfirmation'], isTrue);

    // 2. RUN_SKILL executes safe skill (alerta_tatico) without friction
    final safeRun = await listener.handleVerifiedEnvelope(
      rawBody: jsonEncode({
        'command_id': 'cmd-run-safe-skill',
        'device_id': 'galaxy-a34',
        'command': 'RUN_SKILL',
        'args': {'skill': 'alerta tatico'},
        'timestamp': fixedNow.millisecondsSinceEpoch.toString(),
        'nonce': '22223333444455556666777788889999',
      }),
      config: config,
    );
    expect(safeRun?.ok, isTrue);
    expect(safeRun?.status, 'executed');
    expect(nativeCalls.any((c) => c.method == 'setTorch'), isTrue);

    // 3. RUN_SKILL blocks sensitive skill when confirmAction is missing/denied
    final deniedSensitive = await listener.handleVerifiedEnvelope(
      rawBody: jsonEncode({
        'command_id': 'cmd-run-wa-denied',
        'device_id': 'galaxy-a34',
        'command': 'RUN_SKILL',
        'args': {'skill': 'enviar_aviso_wa'},
        'timestamp': fixedNow.millisecondsSinceEpoch.toString(),
        'nonce': '33334444555566667777888899990000',
      }),
      config: config,
    );
    expect(deniedSensitive?.ok, isFalse);
    expect(deniedSensitive?.status, 'cancelled');
    expect(nativeCalls.where((c) => c.method == 'sendWhatsApp'), isEmpty);

    // 4. RUN_SKILL executes sensitive skill when confirmed by operator
    final confirmingListener = DesktopCommandListener(
      pairingService: pairing,
      deviceService: DeviceControlService(
        channel: channel,
        auditLogProvider: () async => audit,
        obsidianProvider: () async => obs,
      ),
      authGate: authGate,
      now: () => fixedNow,
      confirmAction: (_) async => true,
    );
    final allowedSensitive = await confirmingListener.handleVerifiedEnvelope(
      rawBody: jsonEncode({
        'command_id': 'cmd-run-wa-allowed',
        'device_id': 'galaxy-a34',
        'command': 'RUN_SKILL',
        'args': {'skill': 'enviar_aviso_wa'},
        'timestamp': fixedNow.millisecondsSinceEpoch.toString(),
        'nonce': '44445555666677778888999900001111',
      }),
      config: config,
    );
    expect(allowedSensitive?.ok, isTrue);
    expect(nativeCalls.where((c) => c.method == 'sendWhatsApp').length, 1);
  });
}
