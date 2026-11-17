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
  test('validates LAN/private hosts and rejects public or malformed URLs by default', () {
    expect(DesktopPairingService.isValidEndpoint('http://192.168.1.50:8765'), isTrue);
    expect(DesktopPairingService.isValidEndpoint('http://10.0.0.12:8765'), isTrue);
    expect(DesktopPairingService.isValidEndpoint('http://172.16.5.2:8765'), isTrue);
    expect(DesktopPairingService.isValidEndpoint('http://127.0.0.1:8765'), isTrue);
    expect(DesktopPairingService.isValidEndpoint('http://desktop.local:8765'), isTrue);

    expect(DesktopPairingService.isValidEndpoint('https://evil.example.com'), isFalse);
    expect(DesktopPairingService.isValidEndpoint('http://8.8.8.8:8765'), isFalse);
    expect(DesktopPairingService.isValidEndpoint('not-a-url'), isFalse);
    expect(
      DesktopPairingService.isValidEndpoint(
        'https://my-host.example.com:8765',
        allowNonPrivateHost: true,
      ),
      isTrue,
    );
  });

  test('signs payload with HMAC-SHA256 + timestamp + nonce and requires ConfirmationGate', () async {
    final receivedHeaders = <String, String>{};
    var receivedBody = '';
    var requestCount = 0;

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      requestCount += 1;
      req.headers.forEach((k, v) => receivedHeaders[k.toLowerCase()] = v.join(','));
      receivedBody = await utf8.decoder.bind(req).join();
      req.response
        ..statusCode = 200
        ..write(jsonEncode({'ok': true}));
      await req.response.close();
    });

    final storage = _InMemorySecureStorage();
    final service = DesktopPairingService(
      storage: storage,
      now: () => DateTime.fromMillisecondsSinceEpoch(1700000000123, isUtc: true),
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
  });
}
