import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/security/action_gate.dart';
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
    this.unsupportedByServer = false,
    this.statusCode,
    this.responseBody,
    this.error,
    this.verifiedSignature = false,
  });

  final bool sent;
  final bool deniedByUser;
  final bool unsupportedByServer;
  final int? statusCode;
  final String? responseBody;
  final String? error;
  final bool verifiedSignature;
}

class ParsedPairingUri {
  const ParsedPairingUri({
    required this.config,
    required this.syncKillSwitch,
    this.killSwitchSecret,
  });

  final DesktopPairingConfig config;
  final bool syncKillSwitch;
  final String? killSwitchSecret;
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
        _nonceGenerator = nonceGenerator ?? generateNonce;

  static const _storageKey = 'ultron.desktop.pairing.v1';

  final FlutterSecureStorage _storage;
  final DateTime Function() _now;
  final String Function() _nonceGenerator;
  final Duration requestTimeout;

  static String generateNonce() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// Checks whether [rawUrl] is HTTP/HTTPS pointing to a LAN/loopback/`.local`
  /// host (or an HTTPS host if [allowNonPrivateHost] is explicitly true).
  /// Link-local / cloud metadata hosts (`169.254.0.0/16`, `0.0.0.0`,
  /// `fe80::/10`, `metadata.google.internal`) are always rejected.
  static bool isValidEndpoint(
    String rawUrl, {
    bool allowNonPrivateHost = false,
  }) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    if (uri.host.isEmpty) return false;
    if (ActionGate.isBlockedMetadataHost(uri.host)) return false;
    if (isLanOrLocalHost(uri.host)) return true;
    if (!allowNonPrivateHost) return false;
    return uri.scheme == 'https';
  }

  static bool isLanOrLocalHost(String host) {
    final lower = host.trim().toLowerCase();
    if (ActionGate.isBlockedMetadataHost(lower)) return false;
    if (lower == 'localhost' ||
        lower == '127.0.0.1' ||
        lower == '::1' ||
        lower.endsWith('.local') ||
        lower.endsWith('.ts.net')) {
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
    // 100.64.0.0/10 (Tailscale CGNAT)
    if (b0 == 100 && b1 >= 64 && b1 <= 127) return true;
    // 127.0.0.0/8
    if (b0 == 127) return true;
    // 172.16.0.0/12
    if (b0 == 172 && b1 >= 16 && b1 <= 31) return true;
    // 192.168.0.0/16
    if (b0 == 192 && b1 == 168) return true;
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
      throw ArgumentError(
          'Device ID e segredo compartilhado são obrigatórios.');
    }
    await _storage.write(
      key: _storageKey,
      value: jsonEncode(config.toJson()),
    );
  }

  Future<void> clearPairing() => _storage.delete(key: _storageKey);

  /// Faz parse e validação estrita de uma URI de pareamento `ultron://pair?...`
  /// emitida pelo U.L.T.R.O.N. Desktop (QR Code ou link copiável).
  static ParsedPairingUri parsePairingUri(
    String raw, {
    bool allowNonPrivateHost = false,
  }) {
    final trimmed = raw.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'ultron' ||
        uri.host.toLowerCase() != 'pair') {
      throw const FormatException(
        'Link inválido: esperado formato ultron://pair?url=...&device=...&secret=...',
      );
    }

    final baseUrl = (uri.queryParameters['url'] ?? '').trim();
    final deviceId = (uri.queryParameters['device'] ?? '').trim();
    final secret = (uri.queryParameters['secret'] ?? '').trim();
    final ksParam = (uri.queryParameters['ks'] ?? '').trim().toLowerCase();
    final ksSecretParam = (uri.queryParameters['ks_secret'] ?? '').trim();

    if (!isValidEndpoint(
      baseUrl,
      allowNonPrivateHost: allowNonPrivateHost,
    )) {
      throw const FormatException(
        'URL do Desktop inválida ou fora da rede local (LAN).',
      );
    }
    if (deviceId.isEmpty) {
      throw const FormatException('Device ID ausente no link de pareamento.');
    }
    if (secret.length < 16) {
      throw const FormatException(
        'Segredo HMAC ausente ou muito curto no link de pareamento.',
      );
    }

    final syncKillSwitch = ksParam == 'same' || ksSecretParam.isNotEmpty;
    final killSwitchSecret =
        ksSecretParam.isNotEmpty ? ksSecretParam : (ksParam == 'same' ? secret : null);

    return ParsedPairingUri(
      config: DesktopPairingConfig(
        baseUrl: baseUrl.replaceAll(RegExp(r'/+$'), ''),
        deviceId: deviceId,
        sharedSecret: secret,
        allowNonPrivateHost: allowNonPrivateHost,
      ),
      syncKillSwitch: syncKillSwitch,
      killSwitchSecret: killSwitchSecret,
    );
  }

  /// Salva o pareamento (e opcionalmente o Kill Switch LAN quando `ks=same`)
  /// a partir de uma URI `ultron://pair?...`.
  Future<DesktopPairingConfig> pairFromUri(
    String raw, {
    bool allowNonPrivateHost = false,
    Future<void> Function(
      String baseUrl,
      String secret, {
      bool allowNonPrivateHost,
    })? onConfigureKillSwitch,
  }) async {
    final parsed = parsePairingUri(
      raw,
      allowNonPrivateHost: allowNonPrivateHost,
    );
    await savePairing(parsed.config);
    if (parsed.syncKillSwitch && onConfigureKillSwitch != null) {
      await onConfigureKillSwitch(
        parsed.config.baseUrl,
        parsed.killSwitchSecret ?? parsed.config.sharedSecret,
        allowNonPrivateHost: parsed.config.allowNonPrivateHost,
      );
    }
    return parsed.config;
  }

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

  /// Constant-time verification for desktop response signatures (`X-Ultron-Signature`).
  static bool verifyResponseSignature({
    required String rawBody,
    required String signatureHeader,
    required String sharedSecret,
    String timestamp = '',
    String nonce = '',
  }) {
    if (sharedSecret.trim().isEmpty || signatureHeader.trim().isEmpty) {
      return false;
    }
    final provided = signatureHeader
        .trim()
        .replaceFirst(RegExp(r'^sha256=', caseSensitive: false), '')
        .toLowerCase();
    final bodyOnly = Hmac(sha256, utf8.encode(sharedSecret))
        .convert(utf8.encode(rawBody))
        .toString()
        .toLowerCase();
    if (_constantTimeEquals(provided, bodyOnly)) return true;
    if (timestamp.isNotEmpty || nonce.isNotEmpty) {
      final envelope = computeSignature(
        timestamp: timestamp,
        nonce: nonce,
        body: rawBody,
        sharedSecret: sharedSecret,
      ).toLowerCase();
      if (_constantTimeEquals(provided, envelope)) return true;
      if (nonce.isEmpty && timestamp.isNotEmpty) {
        final tsBody = Hmac(sha256, utf8.encode(sharedSecret))
            .convert(utf8.encode('$timestamp.$rawBody'))
            .toString()
            .toLowerCase();
        if (_constantTimeEquals(provided, tsBody)) return true;
      }
    }
    return false;
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static String _stripLeadingAppArticle(String raw) {
    var s = raw.trim().replaceFirst(RegExp(r'[.!?,;:]+$'), '').trim();
    var prev = '';
    final prefixRe = RegExp(
      r'^(?:o|a|os|as|um|uma|app|aplicativo|programa|jogo)\s+',
      caseSensitive: false,
    );
    while (s != prev && s.isNotEmpty) {
      prev = s;
      s = s.replaceFirst(prefixRe, '').trim();
    }
    return s;
  }

  /// Mapeia entrada do usuário (`/pc ...` ou tela Desktop) para o contrato exato
  /// aceito pelo U.L.T.R.O.N. Desktop (`PING`, `PC_OPEN_APP`, `PC_MEDIA`,
  /// `PC_CLIPBOARD_PUSH`, `PC_CLIPBOARD_PULL`, `PC_RUN_SKILL`), sem nunca enviar
  /// verbos crus em português como `ABRA`.
  static ({String command, Map<String, dynamic> args})? parsePcCommandInput(
    String raw,
  ) {
    var trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.toLowerCase().startsWith('/pc ')) {
      trimmed = trimmed.substring(4).trim();
    } else if (trimmed.toLowerCase() == '/pc') {
      return null;
    }
    if (trimmed.isEmpty) return null;

    if (RegExp(r'^[A-Za-z0-9_]+:').hasMatch(trimmed)) {
      final idx = trimmed.indexOf(':');
      final cmd = trimmed.substring(0, idx).trim().toUpperCase();
      final val = trimmed.substring(idx + 1).trim();
      return switch (cmd) {
        'PING' || 'STATUS' || 'PC_STATUS' => (
            command: 'PING',
            args: const <String, dynamic>{},
          ),
        'PC_OPEN_APP' when val.isNotEmpty => (
            command: 'PC_OPEN_APP',
            args: <String, dynamic>{'app': _stripLeadingAppArticle(val)},
          ),
        'PC_MEDIA' => (
            command: 'PC_MEDIA',
            args: <String, dynamic>{'action': val.isEmpty ? 'play_pause' : val},
          ),
        'PC_CLIPBOARD_PUSH' when val.isNotEmpty => (
            command: 'PC_CLIPBOARD_PUSH',
            args: <String, dynamic>{'text': val},
          ),
        'PC_CLIPBOARD_PULL' => (
            command: 'PC_CLIPBOARD_PULL',
            args: const <String, dynamic>{},
          ),
        'PC_LIST_SKILLS' || 'PC_SKILLS' => (
            command: 'PC_LIST_SKILLS',
            args: const <String, dynamic>{},
          ),
        'PC_SYNC_MOBILE_SKILLS' => (
            command: 'PC_SYNC_MOBILE_SKILLS',
            args: const <String, dynamic>{},
          ),
        'PC_RUN_SKILL' when val.isNotEmpty => _parsePcSkillTarget(val),
        'PC_THERMAL' || 'VERIFICAR_PROTECAO_TERMICA' => (
            command: 'PC_THERMAL',
            args: <String, dynamic>{
              'tool': 'verificar_protecao_termica',
              if (val.isNotEmpty) 'mode': val,
            },
          ),
        'PC_TEMP' || 'CPU_TEMP' => (
            command: 'PC_TEMP',
            args: const <String, dynamic>{},
          ),
        'PC_DELEGATE_TASK' when val.isNotEmpty => (
            command: 'PC_DELEGATE_TASK',
            args: <String, dynamic>{'query': val, 'objective': val},
          ),
        'PC_TASK_STATUS' || 'PC_TASKS' => (
            command: 'PC_TASK_STATUS',
            args: <String, dynamic>{
              if (val.isNotEmpty) 'task_id': val,
            },
          ),
        'PC_TASK_CANCEL' when val.isNotEmpty => (
            command: 'PC_TASK_CANCEL',
            args: <String, dynamic>{'task_id': val},
          ),
        'PC_SPOTIFY' => (
            command: 'PC_SPOTIFY',
            args: _parsePcSpotifyArgs(val),
          ),
        'PC_POWER_PLAN' || 'CONTROLAR_PLANO_ENERGIA' => (
            command: 'PC_POWER_PLAN',
            args: <String, dynamic>{
              'tool': 'controlar_plano_energia',
              'plan': val.isEmpty ? 'balanced' : val,
            },
          ),
        'PC_APP_VOLUME' || 'AJUSTAR_VOLUME_APP' || 'LISTAR_VOLUMES_APPS' => (
            command: 'PC_APP_VOLUME',
            args: _parseAppVolumeArgs(val),
          ),
        'PC_KILL_FROZEN' || 'ENCERRAR_APPS_TRAVADOS' => (
            command: 'PC_KILL_FROZEN',
            args: <String, dynamic>{
              'tool': 'encerrar_apps_travados',
              if (val.isNotEmpty) 'target': val,
            },
          ),
        'PC_BACKUP' || 'EXECUTAR_BACKUP_INCREMENTAL' => (
            command: 'PC_BACKUP',
            args: <String, dynamic>{
              'tool': 'executar_backup_incremental',
              if (val.isNotEmpty) 'target': val,
            },
          ),
        'PC_CLEAN_DISK' || 'LIMPAR_DISCO' => (
            command: 'PC_CLEAN_DISK',
            args: <String, dynamic>{
              'tool': 'limpar_disco',
              if (val.isNotEmpty) 'scope': val,
            },
          ),
        'PC_EJECT_USB' || 'EJETAR_USB_OCIOSO' => (
            command: 'PC_EJECT_USB',
            args: <String, dynamic>{
              'tool': 'ejetar_usb_ocioso',
              if (val.isNotEmpty) 'drive': val,
            },
          ),
        'PC_EXEC_TOOL' when val.isNotEmpty => (
            command: 'PC_EXEC_TOOL',
            args: _parseExecToolArgs(val),
          ),
        _ => null,
      };
    }

    final parts = trimmed.split(RegExp(r'\s+'));
    final first = parts.first.toLowerCase();
    final rest = parts.length > 1 ? parts.sublist(1).join(' ').trim() : '';

    switch (first) {
      case 'status':
      case 'ping':
      case 'pc_status':
        return (command: 'PING', args: const <String, dynamic>{});
      case 'thermal':
      case 'termico':
      case 'térmico':
      case 'telemetria':
      case 'pc_thermal':
      case 'verificar_protecao_termica':
        return (
          command: 'PC_THERMAL',
          args: <String, dynamic>{
            'tool': 'verificar_protecao_termica',
            if (rest.isNotEmpty) 'mode': rest,
          },
        );
      case 'temp':
      case 'temperatura':
      case 'cpu_temp':
      case 'pc_temp':
        return (
          command: 'PC_TEMP',
          args: const <String, dynamic>{},
        );
      case 'tarefa':
      case 'delegar':
      case 'pesquisa':
      case 'pesquisar':
      case 'delegate':
      case 'pc_delegate_task':
        if (rest.isEmpty) return null;
        return (
          command: 'PC_DELEGATE_TASK',
          args: <String, dynamic>{'query': rest, 'objective': rest},
        );
      case 'tarefas':
      case 'tasks':
      case 'task_status':
      case 'pc_tasks':
      case 'pc_task_status':
        return (
          command: 'PC_TASK_STATUS',
          args: <String, dynamic>{
            if (rest.isNotEmpty) 'task_id': rest,
          },
        );
      case 'cancelar_tarefa':
      case 'cancel_task':
      case 'pc_task_cancel':
        if (rest.isEmpty) return null;
        return (
          command: 'PC_TASK_CANCEL',
          args: <String, dynamic>{'task_id': rest},
        );
      case 'spotify':
      case 'pc_spotify':
        return (
          command: 'PC_SPOTIFY',
          args: _parsePcSpotifyArgs(rest),
        );
      case 'energia':
      case 'power':
      case 'power_plan':
      case 'plano_energia':
      case 'pc_power_plan':
      case 'controlar_plano_energia':
        return (
          command: 'PC_POWER_PLAN',
          args: <String, dynamic>{
            'tool': 'controlar_plano_energia',
            'plan': rest.isEmpty ? 'balanced' : rest,
          },
        );
      case 'volume_app':
      case 'app_volume':
      case 'volumes':
      case 'pc_app_volume':
      case 'ajustar_volume_app':
      case 'listar_volumes_apps':
        return (
          command: 'PC_APP_VOLUME',
          args: _parseAppVolumeArgs(rest),
        );
      case 'travados':
      case 'frozen':
      case 'kill_frozen':
      case 'pc_kill_frozen':
      case 'encerrar_apps_travados':
        return (
          command: 'PC_KILL_FROZEN',
          args: <String, dynamic>{
            'tool': 'encerrar_apps_travados',
            if (rest.isNotEmpty) 'target': rest,
          },
        );
      case 'backup':
      case 'pc_backup':
      case 'executar_backup_incremental':
        return (
          command: 'PC_BACKUP',
          args: <String, dynamic>{
            'tool': 'executar_backup_incremental',
            if (rest.isNotEmpty) 'target': rest,
          },
        );
      case 'limpar_disco':
      case 'clean_disk':
      case 'disco':
      case 'pc_clean_disk':
        return (
          command: 'PC_CLEAN_DISK',
          args: <String, dynamic>{
            'tool': 'limpar_disco',
            if (rest.isNotEmpty) 'scope': rest,
          },
        );
      case 'ejetar_usb':
      case 'eject_usb':
      case 'usb':
      case 'pc_eject_usb':
      case 'ejetar_usb_ocioso':
        return (
          command: 'PC_EJECT_USB',
          args: <String, dynamic>{
            'tool': 'ejetar_usb_ocioso',
            if (rest.isNotEmpty) 'drive': rest,
          },
        );
      case 'tool':
      case 'ferramenta':
      case 'exec_tool':
      case 'pc_exec_tool':
        if (rest.isEmpty) return null;
        return (
          command: 'PC_EXEC_TOOL',
          args: _parseExecToolArgs(rest),
        );
      case 'miniapp':
      case 'mini_app':
      case 'create_mini_app':
        if (rest.isEmpty) return null;
        final pipeParts = rest.split('|');
        final title = pipeParts.first.trim();
        final spec = pipeParts.length > 1
            ? pipeParts.skip(1).join('|').trim()
            : title;
        final req = MiniAppLaunchRequest(
          title: title,
          spec: spec,
        );
        return (
          command: 'PC_EXEC_TOOL',
          args: req.toToolArgs(),
        );
      case 'abrir':
      case 'abra':
      case 'abre':
      case 'iniciar':
      case 'inicia':
      case 'inicie':
      case 'executar':
      case 'executa':
      case 'execute':
      case 'open':
      case 'start':
      case 'launch':
      case 'pc_open_app':
        final app = _stripLeadingAppArticle(rest);
        if (app.isEmpty) return null;
        return (command: 'PC_OPEN_APP', args: <String, dynamic>{'app': app});
      case 'midia':
      case 'media':
      case 'pc_media':
        return (
          command: 'PC_MEDIA',
          args: <String, dynamic>{
            'action': _normalizePcMediaAction(rest),
          },
        );
      case 'play':
      case 'tocar':
      case 'continuar':
      case 'retomar':
      case 'pause':
      case 'pausar':
      case 'play_pause':
      case 'next':
      case 'proxima':
      case 'próxima':
      case 'avancar':
      case 'avançar':
      case 'previous':
      case 'anterior':
      case 'voltar':
      case 'stop':
      case 'parar':
      case 'mute':
      case 'mutar':
      case 'silenciar':
      case 'volume_up':
      case 'volume_down':
        return (
          command: 'PC_MEDIA',
          args: <String, dynamic>{'action': _normalizePcMediaAction(first)},
        );
      case 'copiar':
      case 'clipboard':
      case 'push':
      case 'pc_clipboard_push':
        if (rest.isEmpty) return null;
        return (
          command: 'PC_CLIPBOARD_PUSH',
          args: <String, dynamic>{'text': rest},
        );
      case 'colar':
      case 'pull':
      case 'pc_clipboard_pull':
        return (
          command: 'PC_CLIPBOARD_PULL',
          args: const <String, dynamic>{},
        );
      case 'listar':
      case 'skills':
      case 'listar_skills':
      case 'list_skills':
      case 'pc_list_skills':
        return (
          command: 'PC_LIST_SKILLS',
          args: const <String, dynamic>{},
        );
      case 'sync_skills':
      case 'sincronizar_skills':
      case 'pc_sync_mobile_skills':
        return (
          command: 'PC_SYNC_MOBILE_SKILLS',
          args: const <String, dynamic>{},
        );
      case 'skill':
      case 'rodar_skill':
      case 'ativar_skill':
      case 'pc_run_skill':
        if (rest.isEmpty) {
          return (
            command: 'PC_LIST_SKILLS',
            args: const <String, dynamic>{},
          );
        }
        return _parsePcSkillTarget(rest);
      default:
        return null;
    }
  }

  static ({String command, Map<String, dynamic> args}) _parsePcSkillTarget(
    String raw,
  ) {
    final clean = raw.trim();
    final pipeIdx = clean.indexOf('|');
    if (pipeIdx > 0) {
      final skillName = clean.substring(0, pipeIdx).trim();
      final argPart = clean.substring(pipeIdx + 1).trim();
      return (
        command: 'PC_RUN_SKILL',
        args: <String, dynamic>{
          'skill': skillName,
          if (argPart.isNotEmpty) 'args': argPart,
        },
      );
    }
    return (
      command: 'PC_RUN_SKILL',
      args: <String, dynamic>{'skill': clean},
    );
  }

  static Map<String, dynamic> _parsePcSpotifyArgs(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty) {
      return const <String, dynamic>{'action': 'status'};
    }
    final parts = clean.split(RegExp(r'\s+'));
    final first = parts.first.toLowerCase();
    final rest = parts.length > 1 ? parts.sublist(1).join(' ').trim() : '';
    return switch (first) {
      'play' || 'tocar' => <String, dynamic>{
          'action': 'play',
          if (rest.isNotEmpty) 'query': rest,
        },
      'pause' || 'pausar' => const <String, dynamic>{'action': 'pause'},
      'next' || 'proxima' || 'próxima' => const <String, dynamic>{'action': 'next'},
      'previous' || 'anterior' => const <String, dynamic>{'action': 'previous'},
      'playlist' || 'playlists' => <String, dynamic>{
          'action': rest.isEmpty ? 'playlists' : 'play_playlist',
          if (rest.isNotEmpty) 'playlist': rest,
        },
      'status' || 'estado' => const <String, dynamic>{'action': 'status'},
      _ => <String, dynamic>{'action': 'play', 'query': clean},
    };
  }

  static String _normalizePcMediaAction(String raw) {
    final clean = raw.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
    return switch (clean) {
      '' || 'play_pause' => 'play_pause',
      'tocar' || 'continuar' || 'retomar' || 'play' => 'play',
      'pausar' || 'pause' => 'pause',
      'proxima' || 'próxima' || 'avancar' || 'avançar' || 'next' => 'next',
      'anterior' || 'voltar' || 'previous' => 'previous',
      'parar' || 'stop' => 'stop',
      'mutar' || 'silenciar' || 'mute' => 'mute',
      'volume_up' || 'volume_down' => clean,
      _ => clean,
    };
  }

  static Map<String, dynamic> _parseAppVolumeArgs(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty ||
        clean.toLowerCase() == 'list' ||
        clean.toLowerCase() == 'listar') {
      return const <String, dynamic>{
        'tool': 'listar_volumes_apps',
        'action': 'list',
      };
    }
    // Ex: "spotify:50" ou "spotify 50" ou "chrome|30"
    final tokens = clean
        .split(RegExp(r'[:|\s]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (tokens.length >= 2) {
      final level = int.tryParse(tokens.last.replaceAll('%', ''));
      if (level != null) {
        final appName = tokens.sublist(0, tokens.length - 1).join(' ');
        return <String, dynamic>{
          'tool': 'ajustar_volume_app',
          'app': appName,
          'volume': level.clamp(0, 100),
        };
      }
    }
    return <String, dynamic>{
      'tool': 'ajustar_volume_app',
      'app': clean,
    };
  }

  static Map<String, dynamic> _parseExecToolArgs(String raw) {
    final clean = raw.trim();
    final pipeIdx = clean.indexOf('|');
    if (pipeIdx < 0) {
      // Verifica se há espaço seguido de JSON `{...}`
      final jsonIdx = clean.indexOf('{');
      if (jsonIdx > 0) {
        final toolName = clean.substring(0, jsonIdx).trim();
        final jsonStr = clean.substring(jsonIdx).trim();
        try {
          final decoded = jsonDecode(jsonStr);
          if (decoded is Map<String, dynamic>) {
            return <String, dynamic>{
              'tool': toolName,
              'params': decoded,
            };
          }
        } catch (_) {}
      }
      return <String, dynamic>{
        'tool': clean,
        'params': const <String, dynamic>{},
      };
    }

    final toolPart = clean.substring(0, pipeIdx).trim();
    final restPart = clean.substring(pipeIdx + 1).trim();
    var risk = '';
    var rawParams = restPart;

    // Suporta formato "nome_tool|ALTO|{\"k\":\"v\"}" ou "nome_tool|{\"k\":\"v\"}"
    if (restPart.contains('|')) {
      final secondPipe = restPart.indexOf('|');
      final candidateRisk = restPart.substring(0, secondPipe).trim().toUpperCase();
      if (candidateRisk == 'BAIXO' ||
          candidateRisk == 'MEDIO' ||
          candidateRisk == 'MÉDIO' ||
          candidateRisk == 'ALTO' ||
          candidateRisk == 'CRITICO' ||
          candidateRisk == 'CRÍTICO' ||
          candidateRisk == 'LOW' ||
          candidateRisk == 'MEDIUM' ||
          candidateRisk == 'HIGH' ||
          candidateRisk == 'CRITICAL') {
        risk = candidateRisk;
        rawParams = restPart.substring(secondPipe + 1).trim();
      }
    } else {
      final upperRest = restPart.toUpperCase();
      if (upperRest == 'ALTO' ||
          upperRest == 'CRITICO' ||
          upperRest == 'CRÍTICO' ||
          upperRest == 'HIGH' ||
          upperRest == 'CRITICAL' ||
          upperRest == 'BAIXO' ||
          upperRest == 'MEDIO') {
        risk = upperRest;
        rawParams = '';
      }
    }

    Map<String, dynamic> parsedParams = const <String, dynamic>{};
    if (rawParams.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawParams);
        if (decoded is Map<String, dynamic>) {
          parsedParams = decoded;
        } else {
          parsedParams = <String, dynamic>{'value': decoded};
        }
      } catch (_) {
        parsedParams = <String, dynamic>{'arg': rawParams};
      }
    }

    return <String, dynamic>{
      'tool': toolPart,
      if (risk.isNotEmpty) 'risk': risk,
      'params': parsedParams,
    };
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
      final body =
          await response.transform(utf8.decoder).join().timeout(requestTimeout);
      final respSig =
          response.headers.value('x-ultron-signature')?.trim() ?? '';
      final respTs = response.headers.value('x-ultron-timestamp')?.trim() ?? '';
      final respNonce = response.headers.value('x-ultron-nonce')?.trim() ?? '';
      var verified = false;
      if (respSig.isNotEmpty) {
        verified = verifyResponseSignature(
          rawBody: body,
          signatureHeader: respSig,
          sharedSecret: config.sharedSecret,
          timestamp: respTs,
          nonce: respNonce,
        );
        if (!verified) {
          return DesktopCommandResult(
            sent: false,
            statusCode: response.statusCode,
            error: 'Assinatura HMAC da resposta do desktop inválida.',
            verifiedSignature: false,
          );
        }
      }
      if (response.statusCode == 404 || response.statusCode == 501) {
        final toolLabel = args['tool']?.toString().trim().isNotEmpty == true
            ? '${args['tool']} ($command)'
            : command;
        return DesktopCommandResult(
          sent: false,
          unsupportedByServer: true,
          statusCode: response.statusCode,
          responseBody: body,
          error: redactSecret(
            'Ferramenta/endpoint "$toolLabel" não exposto pelo servidor Desktop conectado (HTTP ${response.statusCode}). Atualize o U.L.T.R.O.N. Desktop para v3.0.0+.',
            config.sharedSecret,
          ),
          verifiedSignature: verified,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return DesktopCommandResult(
          sent: false,
          statusCode: response.statusCode,
          error: redactSecret(
            'Falha HTTP ${response.statusCode}: $body',
            config.sharedSecret,
          ),
          verifiedSignature: verified,
        );
      }
      return DesktopCommandResult(
        sent: true,
        statusCode: response.statusCode,
        responseBody: body,
        verifiedSignature: verified,
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

/// Contrato tipado para criação de Mini-Apps locais sandboxed no U.L.T.R.O.N. Desktop
/// via `PC_EXEC_TOOL` (`create_mini_app`), com porta efêmera LAN/Tailscale, token e TTL.
class MiniAppLaunchRequest {
  MiniAppLaunchRequest({
    required String title,
    required String spec,
    String runtime = 'html',
    String? sourceCode,
    int ttlSeconds = 900,
    this.bindScope = 'lan_or_tailscale',
  })  : title = title.trim().isEmpty ? 'Mini-App Tático' : title.trim(),
        spec = spec.trim(),
        runtime = _normalizeRuntime(runtime),
        sourceCode = sourceCode?.trim(),
        ttlSeconds = ttlSeconds.clamp(60, 3600);

  static const Set<String> allowedRuntimes = <String>{'html', 'python'};

  static String _normalizeRuntime(String raw) {
    final lower = raw.trim().toLowerCase();
    if (allowedRuntimes.contains(lower)) return lower;
    throw ArgumentError(
      'Runtime inválido para Mini-App: "$raw". Permitidos: html, python.',
    );
  }

  final String title;
  final String spec;
  final String runtime;
  final String? sourceCode;
  final int ttlSeconds;
  final String bindScope;

  Map<String, dynamic> toToolArgs() => <String, dynamic>{
        'tool': 'create_mini_app',
        'params': <String, dynamic>{
          'title': title,
          'runtime': runtime,
          'spec': spec,
          if (sourceCode != null && sourceCode!.isNotEmpty)
            'source_code': sourceCode,
          'ttl_seconds': ttlSeconds,
          'bind_scope': bindScope,
          'sandboxed': true,
          'ephemeral_port': true,
          'require_session_token': true,
        },
      };
}

/// Resposta validada retornada pelo Desktop após subir o Mini-App sandboxed.
/// Rejeita qualquer URL fora da rede local privada (LAN/Tailscale) ou sem token de sessão.
class MiniAppLaunchResponse {
  const MiniAppLaunchResponse({
    required this.url,
    required this.sessionToken,
    required this.ttlSeconds,
    this.sandboxId,
    this.expiresAt,
  });

  final String url;
  final String sessionToken;
  final int ttlSeconds;
  final String? sandboxId;
  final DateTime? expiresAt;

  /// Faz parse da resposta JSON do Desktop e valida estritamente que:
  /// 1. A URL usa `http`/`https` em host LAN privado ou Tailscale (`100.64.0.0/10`, `.ts.net`).
  /// 2. Existe um token de sessão mínimo (>= 12 chars) na resposta ou na query `token=...`.
  static MiniAppLaunchResponse? tryParse(String? rawBody) {
    final body = (rawBody ?? '').trim();
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final map = Map<String, Object?>.from(decoded);
      final data = map['data'] is Map
          ? Map<String, Object?>.from(map['data'] as Map)
          : map;
      final rawUrl = (data['url'] ?? map['url'] ?? '').toString().trim();
      if (rawUrl.isEmpty) return null;
      if (!DesktopPairingService.isValidEndpoint(
        rawUrl,
        allowNonPrivateHost: false,
      )) {
        return null;
      }
      final uri = Uri.tryParse(rawUrl);
      if (uri == null || uri.port <= 0) return null;

      final bodyToken =
          (data['session_token'] ?? data['token'] ?? map['token'] ?? '')
              .toString()
              .trim();
      final queryToken = (uri.queryParameters['token'] ?? '').trim();
      final token = bodyToken.isNotEmpty ? bodyToken : queryToken;
      if (token.length < 12) return null;

      final finalUri = queryToken.isNotEmpty
          ? uri
          : uri.replace(
              queryParameters: <String, String>{
                ...uri.queryParameters,
                'token': token,
              },
            );

      final ttl = ((data['ttl_seconds'] ?? map['ttl_seconds']) as num?)
              ?.toInt() ??
          900;
      final expiresRaw =
          (data['expires_at'] ?? map['expires_at'])?.toString().trim();
      final sandboxId =
          (data['sandbox_id'] ?? map['sandbox_id'])?.toString().trim();

      return MiniAppLaunchResponse(
        url: finalUri.toString(),
        sessionToken: token,
        ttlSeconds: ttl.clamp(60, 3600),
        sandboxId: (sandboxId != null && sandboxId.isNotEmpty) ? sandboxId : null,
        expiresAt: expiresRaw != null ? DateTime.tryParse(expiresRaw) : null,
      );
    } catch (_) {
      return null;
    }
  }
}
