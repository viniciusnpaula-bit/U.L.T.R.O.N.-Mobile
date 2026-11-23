import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/services/desktop_pairing_service.dart';
import 'package:ultron_mobile/ui/widgets/action_confirmation_dialog.dart';

class _InMemorySecureStorage extends FlutterSecureStorage {
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
  test(
      'validates LAN/private hosts and rejects public or malformed URLs by default',
      () {
    expect(DesktopPairingService.isValidEndpoint('http://192.168.1.50:8765'),
        isTrue);
    expect(
        DesktopPairingService.isValidEndpoint('http://10.0.0.12:8765'), isTrue);
    expect(DesktopPairingService.isValidEndpoint('http://172.16.5.2:8765'),
        isTrue);
    expect(
        DesktopPairingService.isValidEndpoint('http://127.0.0.1:8765'), isTrue);
    expect(DesktopPairingService.isValidEndpoint('http://desktop.local:8765'),
        isTrue);

    expect(DesktopPairingService.isValidEndpoint('https://evil.example.com'),
        isFalse);
    expect(
        DesktopPairingService.isValidEndpoint('http://8.8.8.8:8765'), isFalse);
    expect(
        DesktopPairingService.isValidEndpoint(
          'http://169.254.169.254/latest/meta-data',
          allowNonPrivateHost: true,
        ),
        isFalse);
    expect(
        DesktopPairingService.isValidEndpoint(
          'http://0.0.0.0:8765',
          allowNonPrivateHost: true,
        ),
        isFalse);
    expect(
        DesktopPairingService.isValidEndpoint(
          'http://metadata.google.internal/computeMetadata/v1',
          allowNonPrivateHost: true,
        ),
        isFalse);
    expect(
        DesktopPairingService.isValidEndpoint(
          'http://public.example.com:8765',
          allowNonPrivateHost: true,
        ),
        isFalse);
    expect(DesktopPairingService.isValidEndpoint('not-a-url'), isFalse);
    expect(
      DesktopPairingService.isValidEndpoint(
        'https://my-host.example.com:8765',
        allowNonPrivateHost: true,
      ),
      isTrue,
    );
  });

  test(
      'signs payload with HMAC-SHA256 + timestamp + nonce and requires ConfirmationGate',
      () async {
    final receivedHeaders = <String, String>{};
    var receivedBody = '';
    var requestCount = 0;

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      requestCount += 1;
      req.headers
          .forEach((k, v) => receivedHeaders[k.toLowerCase()] = v.join(','));
      receivedBody = await utf8.decoder.bind(req).join();
      final responsePayload = jsonEncode({'ok': true});
      final respTs = '1700000000999';
      final respNonce = 'resp-nonce-xyz';
      final respDigest = Hmac(sha256, utf8.encode('top-secret-pairing-key'))
          .convert(utf8.encode('$respTs.$respNonce.$responsePayload'))
          .toString();
      req.response
        ..statusCode = 200
        ..headers.set('X-Ultron-Timestamp', respTs)
        ..headers.set('X-Ultron-Nonce', respNonce)
        ..headers.set('X-Ultron-Signature', respDigest)
        ..write(responsePayload);
      await req.response.close();
    });

    final storage = _InMemorySecureStorage();
    final service = DesktopPairingService(
      storage: storage,
      now: () =>
          DateTime.fromMillisecondsSinceEpoch(1700000000123, isUtc: true),
      nonceGenerator: () => 'nonce-abc-123',
    );

    await service.savePairing(
      DesktopPairingConfig(
        baseUrl: 'http://127.0.0.1:${server.port}',
        deviceId: 'galaxy-a34',
        sharedSecret: 'top-secret-pairing-key',
      ),
    );

    final denied = await service.sendCommand(
      command: 'lock_workstation',
      args: const {'source': 'mobile'},
      confirm: (ActionConfirmationRequest req) async => false,
    );
    expect(denied.sent, isFalse);
    expect(denied.deniedByUser, isTrue);
    expect(requestCount, 0);

    final approved = await service.sendCommand(
      command: 'lock_workstation',
      args: const {'source': 'mobile'},
      confirm: (ActionConfirmationRequest req) async => true,
    );
    expect(approved.sent, isTrue);
    expect(requestCount, 1);

    expect(receivedHeaders['x-ultron-timestamp'], '1700000000123');
    expect(receivedHeaders['x-ultron-nonce'], 'nonce-abc-123');
    final expectedDigest = Hmac(sha256, utf8.encode('top-secret-pairing-key'))
        .convert(utf8.encode('1700000000123.nonce-abc-123.$receivedBody'))
        .toString();
    expect(receivedHeaders['x-ultron-signature'], expectedDigest);
    expect(approved.verifiedSignature, isTrue);
  });

  test('parsePairingUri and pairFromUri configure pairing and kill switch',
      () async {
    final storage = _InMemorySecureStorage();
    final service = DesktopPairingService(storage: storage);

    const validUri =
        'ultron://pair?url=http%3A%2F%2F192.168.1.50%3A8765&device=galaxy-a34&secret=super-secret-hmac-key-32-chars&ks=same';
    final parsed = DesktopPairingService.parsePairingUri(validUri);
    expect(parsed.config.baseUrl, 'http://192.168.1.50:8765');
    expect(parsed.config.deviceId, 'galaxy-a34');
    expect(parsed.config.sharedSecret, 'super-secret-hmac-key-32-chars');
    expect(parsed.syncKillSwitch, isTrue);

    String? configuredUrl;
    String? configuredSecret;
    await service.pairFromUri(
      validUri,
      onConfigureKillSwitch: (url, secret, {bool allowNonPrivateHost = false}) async {
        configuredUrl = url;
        configuredSecret = secret;
      },
    );

    final loaded = await service.loadPairing();
    expect(loaded?.baseUrl, 'http://192.168.1.50:8765');
    expect(loaded?.deviceId, 'galaxy-a34');
    expect(configuredUrl, 'http://192.168.1.50:8765');
    expect(configuredSecret, 'super-secret-hmac-key-32-chars');

    expect(
      () => DesktopPairingService.parsePairingUri('https://evil.example/pair'),
      throwsFormatException,
    );
    expect(
      () => DesktopPairingService.parsePairingUri(
        'ultron://pair?url=http://8.8.8.8:8765&device=a&secret=super-secret-hmac-key-32-chars',
      ),
      throwsFormatException,
    );
    expect(
      () => DesktopPairingService.parsePairingUri(
        'ultron://pair?url=http://192.168.1.50:8765&device=a&secret=short',
      ),
      throwsFormatException,
    );
  });

  test('parsePcCommandInput maps natural verbs to Desktop allowlisted commands',
      () {
    final p1 = DesktopPairingService.parsePcCommandInput('abra o navegador');
    expect(p1?.command, 'PC_OPEN_APP');
    expect(p1?.args, {'app': 'navegador'});

    final p2 =
        DesktopPairingService.parsePcCommandInput('/pc abra o rocket league');
    expect(p2?.command, 'PC_OPEN_APP');
    expect(p2?.args, {'app': 'rocket league'});

    final p3 = DesktopPairingService.parsePcCommandInput('abrir o app chrome');
    expect(p3?.command, 'PC_OPEN_APP');
    expect(p3?.args, {'app': 'chrome'});

    final p4 = DesktopPairingService.parsePcCommandInput('pausar');
    expect(p4?.command, 'PC_MEDIA');
    expect(p4?.args, {'action': 'pause'});

    final p5 = DesktopPairingService.parsePcCommandInput('/pc status');
    expect(p5?.command, 'PING');
    expect(p5?.args, isEmpty);

    // Unknown Portuguese verbs must return null instead of raw command like "ABRA"
    expect(DesktopPairingService.parsePcCommandInput('dancar'), isNull);
    expect(DesktopPairingService.parsePcCommandInput('abra'), isNull);
  });

  test(
      'Phase 4: parses all 8 new Desktop LAN commands and handles 404/501 gracefully with HMAC-SHA256 + timestamp + nonce',
      () async {
    // 1. Parsing of all 8 new commands
    final thermal = DesktopPairingService.parsePcCommandInput('/pc termico');
    expect(thermal?.command, 'PC_THERMAL');
    expect(thermal?.args['tool'], 'verificar_protecao_termica');

    final power = DesktopPairingService.parsePcCommandInput(
        '/pc energia high_performance');
    expect(power?.command, 'PC_POWER_PLAN');
    expect(power?.args, {
      'tool': 'controlar_plano_energia',
      'plan': 'high_performance',
    });

    final volList =
        DesktopPairingService.parsePcCommandInput('/pc volume_app listar');
    expect(volList?.command, 'PC_APP_VOLUME');
    expect(volList?.args['tool'], 'listar_volumes_apps');

    final volSet =
        DesktopPairingService.parsePcCommandInput('/pc volume_app spotify 45');
    expect(volSet?.command, 'PC_APP_VOLUME');
    expect(volSet?.args, {
      'tool': 'ajustar_volume_app',
      'app': 'spotify',
      'volume': 45,
    });

    final frozen = DesktopPairingService.parsePcCommandInput('/pc travados');
    expect(frozen?.command, 'PC_KILL_FROZEN');
    expect(frozen?.args['tool'], 'encerrar_apps_travados');

    final backup =
        DesktopPairingService.parsePcCommandInput('/pc backup projetos');
    expect(backup?.command, 'PC_BACKUP');
    expect(backup?.args, {
      'tool': 'executar_backup_incremental',
      'target': 'projetos',
    });

    final clean =
        DesktopPairingService.parsePcCommandInput('/pc limpar_disco temp');
    expect(clean?.command, 'PC_CLEAN_DISK');
    expect(clean?.args, {
      'tool': 'limpar_disco',
      'scope': 'temp',
    });

    final usb = DesktopPairingService.parsePcCommandInput('/pc ejetar_usb E:');
    expect(usb?.command, 'PC_EJECT_USB');
    expect(usb?.args, {
      'tool': 'ejetar_usb_ocioso',
      'drive': 'E:',
    });

    final genericTool = DesktopPairingService.parsePcCommandInput(
      '/pc tool auditar_rede|ALTO|{"porta":8765}',
    );
    expect(genericTool?.command, 'PC_EXEC_TOOL');
    expect(genericTool?.args['tool'], 'auditar_rede');
    expect(genericTool?.args['risk'], 'ALTO');
    expect(genericTool?.args['params'], {'porta': 8765});

    // 2. Signed transmission + graceful 404 / 501 handling when Desktop server does not expose the tool yet
    var nextStatusCode = 404;
    final capturedHeaders = <String, String>{};
    var capturedBody = '';

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      req.headers.forEach((k, v) => capturedHeaders[k.toLowerCase()] = v.join(','));
      capturedBody = await utf8.decoder.bind(req).join();
      req.response
        ..statusCode = nextStatusCode
        ..write('{"error":"tool_not_implemented"}');
      await req.response.close();
    });

    final storage = _InMemorySecureStorage();
    final service = DesktopPairingService(
      storage: storage,
      now: () =>
          DateTime.fromMillisecondsSinceEpoch(1700000099000, isUtc: true),
      nonceGenerator: () => 'nonce-phase4-xyz',
    );
    await service.savePairing(
      DesktopPairingConfig(
        baseUrl: 'http://127.0.0.1:${server.port}',
        deviceId: 'galaxy-a34',
        sharedSecret: 'phase4-secret-key-32-chars-minimum!',
      ),
    );

    final res404 = await service.sendCommand(
      command: 'PC_THERMAL',
      args: const {'tool': 'verificar_protecao_termica'},
      confirm: (_) async => true,
    );
    expect(res404.sent, isFalse);
    expect(res404.unsupportedByServer, isTrue);
    expect(res404.statusCode, 404);
    expect(res404.error, contains('não exposto pelo servidor Desktop'));
    expect(res404.error, contains('v3.0.0+'));

    // Verify HMAC-SHA256 + timestamp + nonce were sent on the wire
    expect(capturedHeaders['x-ultron-timestamp'], '1700000099000');
    expect(capturedHeaders['x-ultron-nonce'], 'nonce-phase4-xyz');
    final expectedSig = Hmac(
      sha256,
      utf8.encode('phase4-secret-key-32-chars-minimum!'),
    )
        .convert(utf8.encode('1700000099000.nonce-phase4-xyz.$capturedBody'))
        .toString();
    expect(capturedHeaders['x-ultron-signature'], expectedSig);

    nextStatusCode = 501;
    final res501 = await service.sendCommand(
      command: 'PC_EXEC_TOOL',
      args: const {'tool': 'ferramenta_futura'},
      confirm: (_) async => true,
    );
    expect(res501.sent, isFalse);
    expect(res501.unsupportedByServer, isTrue);
    expect(res501.statusCode, 501);
    expect(res501.error, contains('ferramenta_futura'));
  });

  test('Phase 5 MiniAppLaunchRequest & MiniAppLaunchResponse enforce LAN/Tailscale, sandbox, TTL and session token',
      () {
    expect(DesktopPairingService.isLanOrLocalHost('100.88.12.4'), isTrue);
    expect(DesktopPairingService.isLanOrLocalHost('ultron-pc.tail123.ts.net'), isTrue);
    expect(DesktopPairingService.isLanOrLocalHost('evil.example.com'), isFalse);

    final req = MiniAppLaunchRequest(
      title: 'Simulador RC',
      spec: 'Curva de carga capacitor RC',
      runtime: 'html',
      ttlSeconds: 99999,
    );
    final args = req.toToolArgs();
    expect(args['tool'], 'create_mini_app');
    final params = args['params'] as Map<String, dynamic>;
    expect(params['ttl_seconds'], 3600);
    expect(params['sandboxed'], isTrue);
    expect(params['ephemeral_port'], isTrue);
    expect(params['require_session_token'], isTrue);

    expect(
      () => MiniAppLaunchRequest(title: 'Bad', spec: 'x', runtime: 'bash'),
      throwsArgumentError,
    );

    final parsedCmd = DesktopPairingService.parsePcCommandInput(
      '/pc miniapp Conversor Ohm | Calculadora de resistor para LED',
    );
    expect(parsedCmd?.command, 'PC_EXEC_TOOL');
    expect(parsedCmd?.args['tool'], 'create_mini_app');

    // Valid Tailscale URL with session token
    final ok = MiniAppLaunchResponse.tryParse(
      jsonEncode({
        'ok': true,
        'data': {
          'sandbox_id': 'miniapp_abc123',
          'url': 'http://100.88.12.4:54321/',
          'session_token': 'tok_secure_1234567890',
          'ttl_seconds': 600,
        },
      }),
    );
    expect(ok, isNotNull);
    expect(ok!.url, contains('http://100.88.12.4:54321/'));
    expect(ok.url, contains('token=tok_secure_1234567890'));
    expect(ok.ttlSeconds, 600);

    // Rejects public external URL
    final badHost = MiniAppLaunchResponse.tryParse(
      jsonEncode({
        'url': 'https://evil.example.com:8443/?token=tok_secure_1234567890',
        'session_token': 'tok_secure_1234567890',
      }),
    );
    expect(badHost, isNull);

    // Rejects LAN URL without valid token
    final missingToken = MiniAppLaunchResponse.tryParse(
      jsonEncode({
        'url': 'http://192.168.1.50:54321/',
        'session_token': 'short',
      }),
    );
    expect(missingToken, isNull);
  });
}
