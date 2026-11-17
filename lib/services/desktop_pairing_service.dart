import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../ui/widgets/action_confirmation_dialog.dart';
import 'ai_provider_service.dart' show redactSecret;

class DesktopPairingConfig {
  const DesktopPairingConfig({
    required this.baseUrl,
    required this.deviceId,
    required this.sharedSecret,
    this.allowNonPrivateHost = false,
  });

  final String baseUrl;
  final String deviceId;
  final String sharedSecret;
  final bool allowNonPrivateHost;

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'deviceId': deviceId,
        'sharedSecret': sharedSecret,
        'allowNonPrivateHost': allowNonPrivateHost,
      };

  factory DesktopPairingConfig.fromJson(Map<String, dynamic> json) =>
      DesktopPairingConfig(
        baseUrl: (json['baseUrl'] as String? ?? '').trim(),
        deviceId: (json['deviceId'] as String? ?? '').trim(),
        sharedSecret: (json['sharedSecret'] as String? ?? ''),
        allowNonPrivateHost: json['allowNonPrivateHost'] == true,
      );
}

class DesktopCommandResult {
  const DesktopCommandResult({
    required this.sent,
    this.deniedByUser = false,
    this.statusCode,
    this.responseBody,
    this.error,
  });

  final bool sent;
  final bool deniedByUser;
  final int? statusCode;
  final String? responseBody;
  final String? error;
}

/// Manages authenticated LAN pairing with ULTRON Desktop using HMAC-SHA256
/// signed payloads (`timestamp` + `nonce` + body) and an explicit
/// [ConfirmationGate] before transmitting any command.
class DesktopPairingService {
  DesktopPairingService({
    FlutterSecureStorage? storage,
    DateTime Function()? now,
    String Function()? nonceGenerator,
    this.requestTimeout = const Duration(seconds: 10),
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _now = now ?? DateTime.now,
        _nonceGenerator = nonceGenerator ?? _defaultNonce;

  static const _storageKey = 'ultron.desktop.pairing.v1';

  final FlutterSecureStorage _storage;
  final DateTime Function() _now;
  final String Function() _nonceGenerator;
  final Duration requestTimeout;

  static String _defaultNonce() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// Checks whether [rawUrl] is HTTP/HTTPS pointing to a LAN/loopback/`.local`
  /// host (or any valid host if [allowNonPrivateHost] is explicitly true).
  static bool isValidEndpoint(
    String rawUrl, {
    bool allowNonPrivateHost = false,
  }) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    if (uri.host.isEmpty) return false;
    if (allowNonPrivateHost) return true;
    return isLanOrLocalHost(uri.host);
  }

  static bool isLanOrLocalHost(String host) {
    final lower = host.toLowerCase();
    if (lower == 'localhost' ||
        lower == '127.0.0.1' ||
        lower == '::1' ||
        lower.endsWith('.local')) {
      return true;
    }
    final parsedIp = InternetAddress.tryParse(lower);
    if (parsedIp == null || parsedIp.type != InternetAddressType.IPv4) {
      return false;
    }
    final bytes = parsedIp.rawAddress;
    if (bytes.length != 4) return false;
    final b0 = bytes[0];
    final b1 = bytes[1];
    // 10.0.0.0/8
    if (b0 == 10) return true;
    // 127.0.0.0/8
    if (b0 == 127) return true;
    // 172.16.0.0/12
    if (b0 == 172 && b1 >= 16 && b1 <= 31) return true;
    // 192.168.0.0/16
    if (b0 == 192 && b1 == 168) return true;
    // 169.254.0.0/16 link-local
    if (b0 == 169 && b1 == 254) return true;
    return false;
  }

  Future<DesktopPairingConfig?> loadPairing() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return DesktopPairingConfig.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw)),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> savePairing(DesktopPairingConfig config) async {
    if (!isValidEndpoint(
      config.baseUrl,
      allowNonPrivateHost: config.allowNonPrivateHost,
    )) {
      throw ArgumentError(
        'Endpoint inválido ou fora da rede local (LAN).',
      );
    }
    if (config.deviceId.trim().isEmpty || config.sharedSecret.trim().isEmpty) {
      throw ArgumentError('Device ID e segredo compartilhado são obrigatórios.');
    }
    await _storage.write(
      key: _storageKey,
      value: jsonEncode(config.toJson()),
    );
  }

  Future<void> clearPairing() => _storage.delete(key: _storageKey);

  static String computeSignature({
    required String timestamp,
    required String nonce,
    required String body,
    required String sharedSecret,
  }) {
    final message = '$timestamp.$nonce.$body';
    return Hmac(sha256, utf8.encode(sharedSecret))
        .convert(utf8.encode(message))
        .toString();
  }

  Future<DesktopCommandResult> sendCommand({
    required String command,
    Map<String, dynamic> args = const {},
    required ConfirmationGate confirm,
  }) async {
    final config = await loadPairing();
    if (config == null) {
      return const DesktopCommandResult(
        sent: false,
        error: 'Nenhum Desktop pareado.',
      );
    }
    if (!isValidEndpoint(
      config.baseUrl,
      allowNonPrivateHost: config.allowNonPrivateHost,
    )) {
      return const DesktopCommandResult(
        sent: false,
        error: 'Endpoint do Desktop inválido ou não-LAN.',
      );
    }

    final allowed = await confirm(
      ActionConfirmationRequest(
        title: 'Enviar comando ao Desktop',
        description:
            'Comando: $command\nDestino: ${config.baseUrl}\nDeseja autorizar este envio?',
        actionLabel: 'Enviar',
        danger: true,
      ),
    );
    if (!allowed) {
      return const DesktopCommandResult(sent: false, deniedByUser: true);
    }

    final timestamp = _now().millisecondsSinceEpoch.toString();
    final nonce = _nonceGenerator();
    final payload = jsonEncode(<String, dynamic>{
      'device_id': config.deviceId,
      'command': command,
      'args': args,
      'timestamp': timestamp,
      'nonce': nonce,
    });
    final signature = computeSignature(
      timestamp: timestamp,
      nonce: nonce,
      body: payload,
      sharedSecret: config.sharedSecret,
    );

    final base = config.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/api/mobile/command');

    final client = HttpClient()..connectionTimeout = requestTimeout;
    try {
      final req = await client.postUrl(uri).timeout(requestTimeout);
      req.headers.contentType = ContentType.json;
      req.headers.set('X-Ultron-Device', config.deviceId);
      req.headers.set('X-Ultron-Timestamp', timestamp);
      req.headers.set('X-Ultron-Nonce', nonce);
      req.headers.set('X-Ultron-Signature', signature);
      final encoded = utf8.encode(payload);
      req.contentLength = encoded.length;
      req.add(encoded);

      final response = await req.close().timeout(requestTimeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return DesktopCommandResult(
          sent: false,
          statusCode: response.statusCode,
          error: redactSecret(
            'Falha HTTP ${response.statusCode}: $body',
            config.sharedSecret,
          ),
        );
      }
      return DesktopCommandResult(
        sent: true,
        statusCode: response.statusCode,
        responseBody: body,
      );
    } catch (e) {
      return DesktopCommandResult(
        sent: false,
        error: redactSecret(e.toString(), config.sharedSecret),
      );
    } finally {
      client.close(force: true);
    }
  }
}
