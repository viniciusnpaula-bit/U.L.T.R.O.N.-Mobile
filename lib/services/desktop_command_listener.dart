import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import '../core/security/action_gate.dart';
import '../core/security/auth_gate.dart';
import 'ai_provider_service.dart' show redactSecret;
import 'desktop_pairing_service.dart';
import 'device_control_service.dart';

/// Resultado da execução local de um comando enviado pelo U.L.T.R.O.N. Desktop.
class DesktopInboundResult {
  const DesktopInboundResult({
    required this.commandId,
    required this.command,
    required this.ok,
    required this.status,
    required this.message,
    this.data = const <String, dynamic>{},
  });

  final String commandId;
  final String command;
  final bool ok;
  final String status; // executed | denied | failed | unsupported
  final String message;
  final Map<String, dynamic> data;
}

/// Cliente de ponte reversa (Desktop -> Mobile) via HTTP Long-Polling na LAN.
///
/// Reutiliza o mesmo segredo compartilhado HMAC-SHA256 do pareamento QR Code,
/// validando assinatura, janela temporal e nonce anti-replay antes de passar
/// cada comando pelo [ActionGate] e [AuditLogService].
class DesktopCommandListener {
  DesktopCommandListener({
    required this.pairingService,
    required this.deviceService,
    required this.authGate,
    this.actionGate = const ActionGate(),
    this.confirmAction,
    this.onCommandHandled,
    this.pollWaitSeconds = 20,
    this.clockSkewMs = 60000,
    DateTime Function()? now,
    String Function()? nonceGenerator,
  })  : _now = now ?? DateTime.now,
        _nonceGenerator = nonceGenerator ?? DesktopPairingService.generateNonce;

  final DesktopPairingService pairingService;
  final DeviceControlService deviceService;
  final AuthGate authGate;
  final ActionGate actionGate;
  final Future<bool> Function(ActionSimulation simulation)? confirmAction;
  final void Function(DesktopInboundResult result)? onCommandHandled;
  final int pollWaitSeconds;
  final int clockSkewMs;
  final DateTime Function() _now;
  final String Function() _nonceGenerator;

  bool _running = false;
  bool _loopActive = false;
  HttpClient? _activeClient;
  Timer? _backoffTimer;
  Completer<void>? _backoffCompleter;
  final LinkedHashSet<String> _seenReplayKeys = LinkedHashSet<String>();

  bool get isRunning => _running;

  static const Set<String> _safeCommands = <String>{
    'PING',
    'STATUS',
    'DEVICE_STATUS',
    'OPEN_APP',
    'OPEN_CAMERA',
    'TORCH_ON',
    'TORCH_OFF',
    'TORCH_TOGGLE',
    'VOLUME_SET',
    'VOLUME_UP',
    'VOLUME_DOWN',
    'VOLUME_MUTE',
    'MEDIA',
    'MEDIA_PLAY',
    'MEDIA_PAUSE',
    'MEDIA_PLAY_PAUSE',
    'MEDIA_NEXT',
    'MEDIA_PREVIOUS',
    'MEDIA_STOP',
    'VIBRATE',
    'NOTE',
    'READ_CALENDAR',
    'READ_MESSAGES',
  };

  static const Set<String> _sensitiveCommands = <String>{
    'WHATSAPP',
    'SMS',
    'REPLY_MESSAGE',
    'DIAL',
    'CREATE_EVENT',
  };

  void start() {
    if (_running) {
      wakeUp();
      return;
    }
    _running = true;
    if (!_loopActive) {
      unawaited(_runLoop());
    }
  }

  /// Cancela imediatamente qualquer espera/backoff pendente para reconectar já.
  void wakeUp() {
    _backoffTimer?.cancel();
    _backoffTimer = null;
    if (_backoffCompleter != null && !_backoffCompleter!.isCompleted) {
      _backoffCompleter!.complete();
    }
    _backoffCompleter = null;
  }

  void stop() {
    _running = false;
    _backoffTimer?.cancel();
    _backoffTimer = null;
    if (_backoffCompleter != null && !_backoffCompleter!.isCompleted) {
      _backoffCompleter!.complete();
    }
    _backoffCompleter = null;
    try {
      _activeClient?.close(force: true);
    } catch (_) {}
    _activeClient = null;
  }

  Future<void> _sleepCancellable(Duration delay) async {
    if (!_running) return;
    final completer = Completer<void>();
    _backoffCompleter = completer;
    _backoffTimer = Timer(delay, () {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    await completer.future;
    _backoffTimer = null;
    if (identical(_backoffCompleter, completer)) {
      _backoffCompleter = null;
    }
  }

  Future<void> _runLoop() async {
    _loopActive = true;
    var backoff = const Duration(seconds: 2);
    try {
      while (_running) {
        final outcome = await pollOnce();
        if (!_running) break;
        if (outcome == DesktopPollOutcome.commandHandled ||
            outcome == DesktopPollOutcome.noContent) {
          backoff = const Duration(seconds: 1);
          continue;
        }
        if (outcome == DesktopPollOutcome.unpaired ||
            outcome == DesktopPollOutcome.locked ||
            outcome == DesktopPollOutcome.endpointUnsupported) {
          backoff = const Duration(seconds: 20);
        } else {
          final nextSec = (backoff.inSeconds * 2).clamp(2, 30);
          backoff = Duration(seconds: nextSec);
        }
        await _sleepCancellable(backoff);
      }
    } finally {
      _loopActive = false;
    }
  }

  /// Executa um ciclo único de long-poll em `GET <baseUrl>/api/mobile/poll`.
  Future<DesktopPollOutcome> pollOnce() async {
    if (!authGate.hasBiometricAccess) {
      return DesktopPollOutcome.locked;
    }
    final config = await pairingService.loadPairing();
    if (config == null ||
        !DesktopPairingService.isValidEndpoint(
          config.baseUrl,
          allowNonPrivateHost: config.allowNonPrivateHost,
        )) {
      return DesktopPollOutcome.unpaired;
    }

    final base = config.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final waitS = pollWaitSeconds.clamp(1, 30);
    final uri = Uri.parse('$base/api/mobile/poll?wait_s=$waitS');
    final ts = _now().millisecondsSinceEpoch.toString();
    final nonce = _nonceGenerator();
    final sig = DesktopPairingService.computeSignature(
      timestamp: ts,
      nonce: nonce,
      body: '',
      sharedSecret: config.sharedSecret,
    );

    final timeout = Duration(seconds: waitS + 8);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    _activeClient = client;
    try {
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 6));
      req.headers.set('X-Ultron-Device', config.deviceId);
      req.headers.set('X-Ultron-Timestamp', ts);
      req.headers.set('X-Ultron-Nonce', nonce);
      req.headers.set('X-Ultron-Signature', sig);

      final resp = await req.close().timeout(timeout);
      final rawBody =
          await resp.transform(utf8.decoder).join().timeout(timeout);

      if (resp.statusCode == 204) {
        return DesktopPollOutcome.noContent;
      }
      if (resp.statusCode == 404 || resp.statusCode == 405 || resp.statusCode == 501) {
        return DesktopPollOutcome.endpointUnsupported;
      }
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return DesktopPollOutcome.transientError;
      }
      if (rawBody.trim().isEmpty) {
        return DesktopPollOutcome.noContent;
      }

      final respSig = resp.headers.value('x-ultron-signature')?.trim() ?? '';
      final respTs = resp.headers.value('x-ultron-timestamp')?.trim() ?? '';
      final respNonce = resp.headers.value('x-ultron-nonce')?.trim() ?? '';
      if (respSig.isEmpty ||
          respTs.isEmpty ||
          respNonce.isEmpty ||
          !DesktopPairingService.verifyResponseSignature(
            rawBody: rawBody,
            signatureHeader: respSig,
            sharedSecret: config.sharedSecret,
            timestamp: respTs,
            nonce: respNonce,
          )) {
        await deviceService.recordAudit(
          actor: 'DESKTOP_LAN',
          action: 'INBOUND_POLL',
          target: config.deviceId,
          status: 'DENIED',
          detail: 'Assinatura/headers HMAC do Desktop ausentes ou inválidos',
        );
        return DesktopPollOutcome.transientError;
      }

      final result = await handleVerifiedEnvelope(
        rawBody: rawBody,
        config: config,
        headerTimestamp: respTs,
        headerNonce: respNonce,
      );
      if (result != null) {
        await _postResult(config, result);
        onCommandHandled?.call(result);
      }
      return DesktopPollOutcome.commandHandled;
    } catch (_) {
      return DesktopPollOutcome.transientError;
    } finally {
      if (identical(_activeClient, client)) {
        _activeClient = null;
      }
      client.close(force: true);
    }
  }

  /// Valida timestamp, device_id, anti-replay e executa o comando autorizado.
  Future<DesktopInboundResult?> handleVerifiedEnvelope({
    required String rawBody,
    required DesktopPairingConfig config,
    String headerTimestamp = '',
    String headerNonce = '',
  }) async {
    final Map<String, dynamic> envelope;
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is! Map) return null;
      envelope = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }

    final cmdId = (envelope['command_id'] as String? ?? '').trim();
    final targetDevice = (envelope['device_id'] as String? ?? '').trim();
    final rawCmd = (envelope['command'] as String? ?? '').trim().toUpperCase();
    final bodyTs = (envelope['timestamp']?.toString() ?? headerTimestamp).trim();
    final bodyNonce = (envelope['nonce'] as String? ?? headerNonce).trim();
    final rawArgs = envelope['args'];
    final args = rawArgs is Map
        ? Map<String, dynamic>.from(rawArgs)
        : const <String, dynamic>{};

    if (cmdId.isEmpty || rawCmd.isEmpty) return null;

    if (targetDevice.isNotEmpty && targetDevice != config.deviceId) {
      return DesktopInboundResult(
        commandId: cmdId,
        command: rawCmd,
        ok: false,
        status: 'denied',
        message: 'device_id divergente do pareamento local.',
      );
    }

    if ((headerTimestamp.isNotEmpty && bodyTs != headerTimestamp) ||
        (headerNonce.isNotEmpty && bodyNonce != headerNonce)) {
      await deviceService.recordAudit(
        actor: 'DESKTOP_LAN',
        action: rawCmd,
        target: cmdId,
        status: 'DENIED',
        detail: 'Divergência entre headers e payload (timestamp/nonce)',
      );
      return DesktopInboundResult(
        commandId: cmdId,
        command: rawCmd,
        ok: false,
        status: 'denied',
        message: 'Timestamp ou nonce divergente entre headers e corpo.',
      );
    }

    final tsMs = int.tryParse(bodyTs);
    final nowMs = _now().millisecondsSinceEpoch;
    if (tsMs == null || (nowMs - tsMs).abs() > clockSkewMs) {
      await deviceService.recordAudit(
        actor: 'DESKTOP_LAN',
        action: rawCmd,
        target: cmdId,
        status: 'DENIED',
        detail: 'Timestamp expirado ou inválido ($bodyTs)',
      );
      return DesktopInboundResult(
        commandId: cmdId,
        command: rawCmd,
        ok: false,
        status: 'denied',
        message: 'Timestamp do comando expirado.',
      );
    }

    final replayKey = '$cmdId:${bodyNonce.isEmpty ? tsMs : bodyNonce}';
    if (_seenReplayKeys.contains(replayKey)) {
      await deviceService.recordAudit(
        actor: 'DESKTOP_LAN',
        action: rawCmd,
        target: cmdId,
        status: 'DENIED',
        detail: 'Replay detectado',
      );
      return DesktopInboundResult(
        commandId: cmdId,
        command: rawCmd,
        ok: false,
        status: 'denied',
        message: 'Comando duplicado (anti-replay).',
      );
    }
    _rememberReplayKey(replayKey);

    if (!authGate.hasBiometricAccess) {
      await deviceService.recordAudit(
        actor: 'DESKTOP_LAN',
        action: rawCmd,
        target: cmdId,
        status: 'DENIED',
        detail: 'Sessão mobile sem acesso biométrico (Nível 3 exigido)',
      );
      return DesktopInboundResult(
        commandId: cmdId,
        command: rawCmd,
        ok: false,
        status: 'denied',
        message: 'Ponte Desktop requer autenticação biométrica (Nível 3) no celular.',
      );
    }

    if (!_safeCommands.contains(rawCmd) && !_sensitiveCommands.contains(rawCmd)) {
      await deviceService.recordAudit(
        actor: 'DESKTOP_LAN',
        action: rawCmd,
        target: cmdId,
        status: 'DENIED',
        detail: 'Comando fora da allowlist Desktop->Mobile',
      );
      return DesktopInboundResult(
        commandId: cmdId,
        command: rawCmd,
        ok: false,
        status: 'unsupported',
        message: 'Comando "$rawCmd" não permitido pela política do Mobile.',
      );
    }

    if (_sensitiveCommands.contains(rawCmd)) {
      final simTag = _buildActionTag(rawCmd, args);
      final sim = actionGate.simulate(simTag);
      final confirm = confirmAction;
      final approved = confirm != null ? await confirm(sim) : false;
      if (!approved) {
        await deviceService.recordAudit(
          actor: 'DESKTOP_LAN',
          action: rawCmd,
          target: cmdId,
          status: 'DENIED',
          detail: 'Confirmação no celular recusada/indisponível',
        );
        return DesktopInboundResult(
          commandId: cmdId,
          command: rawCmd,
          ok: false,
          status: 'cancelled',
          message:
              'Ação sensível ($rawCmd) cancelada ou sem confirmação no celular.',
        );
      }
    }

    try {
      final result = await _executeAllowedCommand(cmdId, rawCmd, args);
      await deviceService.recordAudit(
        actor: 'DESKTOP_LAN',
        action: rawCmd,
        target: cmdId,
        status: result.ok ? 'EXECUTED' : 'FAILED',
        detail: result.message,
      );
      return result;
    } catch (e) {
      final msg = redactSecret(e.toString(), config.sharedSecret);
      await deviceService.recordAudit(
        actor: 'DESKTOP_LAN',
        action: rawCmd,
        target: cmdId,
        status: 'FAILED',
        detail: msg,
      );
      return DesktopInboundResult(
        commandId: cmdId,
        command: rawCmd,
        ok: false,
        status: 'failed',
        message: 'Falha ao executar $rawCmd no celular: $msg',
      );
    }
  }

  void _rememberReplayKey(String key) {
    _seenReplayKeys.add(key);
    while (_seenReplayKeys.length > 512) {
      _seenReplayKeys.remove(_seenReplayKeys.first);
    }
  }

  String _buildActionTag(String cmd, Map<String, dynamic> args) {
    switch (cmd) {
      case 'WHATSAPP':
      case 'SMS':
      case 'REPLY_MESSAGE':
        return '[ACTION:$cmd:${args['target'] ?? ''}:${args['text'] ?? ''}]';
      case 'DIAL':
        return '[ACTION:DIAL:${args['number'] ?? ''}]';
      case 'CREATE_EVENT':
        return '[ACTION:CREATE_EVENT:${args['title'] ?? ''}:${args['start'] ?? ''}]';
      default:
        return '[ACTION:$cmd]';
    }
  }

  Future<DesktopInboundResult> _executeAllowedCommand(
    String cmdId,
    String cmd,
    Map<String, dynamic> args,
  ) async {
    switch (cmd) {
      case 'PING':
      case 'STATUS':
      case 'DEVICE_STATUS':
        final st = await deviceService.getStatus();
        return DesktopInboundResult(
          commandId: cmdId,
          command: cmd,
          ok: true,
          status: 'executed',
          message: st.formatSummary(),
          data: <String, dynamic>{
            'deviceModel': st.deviceModel,
            'androidVersion': st.androidVersion,
            'batteryLevel': st.batteryLevel,
            'isCharging': st.isCharging,
            'batteryTempC': st.batteryTempC,
            'torchOn': st.torchOn,
            'volumePercent': st.volumePercent,
            'ringerMode': st.ringerMode,
            'ramUsedMb': st.ramUsedMb,
            'ramTotalMb': st.ramTotalMb,
            'ramFreeMb': st.ramFreeMb,
            'wifiConnected': st.wifiConnected,
            'cellularConnected': st.cellularConnected,
          },
        );

      case 'OPEN_APP':
        final app = (args['app'] as String? ?? '').trim();
        if (app.isEmpty) {
          return DesktopInboundResult(
            commandId: cmdId,
            command: cmd,
            ok: false,
            status: 'failed',
            message: 'Nome do aplicativo vazio.',
          );
        }
        final opened = await deviceService.openApp(app);
        return DesktopInboundResult(
          commandId: cmdId,
          command: cmd,
          ok: true,
          status: 'executed',
          message: '📱 App aberto no celular: $opened',
          data: <String, dynamic>{'app': opened},
        );

      case 'OPEN_CAMERA':
        final opened = await deviceService.openApp('camera');
        return DesktopInboundResult(
          commandId: cmdId,
          command: cmd,
          ok: true,
          status: 'executed',
          message: '📷 Câmera aberta ($opened)',
        );

      case 'TORCH_ON':
        final state = await deviceService.setTorch(true);
        return DesktopInboundResult(
          commandId: cmdId,
          command: cmd,
          ok: true,
          status: 'executed',
          message: '🔦 Lanterna: ${state ? 'LIGADA' : 'DESLIGADA'}',
          data: <String, dynamic>{'torchOn': state},
        );

      case 'TORCH_OFF':
        final state = await deviceService.setTorch(false);
        return DesktopInboundResult(
          commandId: cmdId,
          command: cmd,
          ok: true,
          status: 'executed',
          message: '🔦 Lanterna: ${state ? 'LIGADA' : 'DESLIGADA'}',
          data: <String, dynamic>{'torchOn': state},
        );

      case 'TORCH_TOGGLE':
        final state = await deviceService.toggleTorch();
        return DesktopInboundResult(
          commandId: cmdId,
          command: cmd,
          ok: true,
          status: 'executed',
          message: '🔦 Lanterna: ${state ? 'LIGADA' : 'DESLIGADA'}',
          data: <String, dynamic>{'torchOn': state},
        );

      case 'VOLUME_SET':
        final pct = ((args['percent'] as num?)?.toInt() ?? 50).clamp(0, 100);
        final v = await deviceService.setVolume(pct);
        return DesktopInboundResult(
          commandId: cmdId,
          command: cmd,
          ok: true,
          status: 'executed',
          message: '🔊 Volume do celular ajustado para $v%',
          data: <String, dynamic>{'volumePercent': v},
        );

      case 'VOLUME_UP':
        final v = await deviceService.adjustVolume('up');
        return DesktopInboundResult(
          commandId: cmdId,
          command: cmd,
          ok: true,
          status: 'executed',
          message: '🔊 Volume do celular: $v%',
          data: <String, dynamic>{'volumePercent': v},
        );

      case 'VOLUME_DOWN':
        final v = await deviceService.adjustVolume('down');
        return DesktopInboundResult(
          commandId: cmdId,
          command: cmd,
          ok: true,
          status: 'executed',
          message: '🔉 Volume do celular: $v%',
          data: <String, dynamic>{'volumePercent': v},
        );

      case 'VOLUME_MUTE':
        await deviceService.adjustVolume('mute');
        return DesktopInboundResult(
          commandId: cmdId,
          command: cmd,
          ok: true,
          status: 'executed',
          message: '🔇 Áudio do celular silenciado.',
        );

      case 'MEDIA':
      case 'MEDIA_PLAY':
      case 'MEDIA_PAUSE':
      case 'MEDIA_PLAY_PAUSE':
      case 'MEDIA_NEXT':
      case 'MEDIA_PREVIOUS':
      case 'MEDIA_STOP':
        final action = cmd == 'MEDIA'
            ? (args['action'] as String? ?? 'play_pause').trim().toLowerCase()
            : cmd.replaceFirst('MEDIA_', '').toLowerCase();
        await deviceService.controlMedia(action);
        return DesktopInboundResult(
          commandId: cmdId,
          command: cmd,
          ok: true,
          status: 'executed',
          message: '🎵 Controle de mídia enviado ($action).',
        );

      case 'VIBRATE':
        final ms = ((args['durationMs'] as num?)?.toInt() ?? 280).clamp(50, 2000);
        await deviceService.vibrate(durationMs: ms);
        return DesktopInboundResult(
          commandId: cmdId,
          command: cmd,
          ok: true,
          status: 'executed',
          message: '📳 Vibração acionada (${ms}ms).',
        );

      case 'NOTE':
        final text = (args['text'] as String? ?? '').trim();
        if (text.isEmpty) {
          return DesktopInboundResult(
            commandId: cmdId,
            command: cmd,
            ok: false,
            status: 'failed',
            message: 'Texto da nota vazio.',
          );
        }
        final vault = await deviceService.getObsidianVault();
        await vault.dailyNote(_now(), text);
        return DesktopInboundResult(
          commandId: cmdId,
          command: cmd,
          ok: true,
          status: 'executed',
          message: '📝 Nota salva no cofre do celular.',
        );

      case 'READ_CALENDAR':
        final days = ((args['days'] as num?)?.toInt() ?? 1).clamp(1, 14);
        final events = await deviceService.getCalendarEvents(daysAhead: days);
        return DesktopInboundResult(
          commandId: cmdId,
          command: cmd,
          ok: true,
          status: 'executed',
          message: events.isEmpty
              ? '📅 Nenhum evento nos próximos $days dia(s).'
              : '📅 ${events.length} evento(s) encontrado(s).',
          data: <String, dynamic>{
            'events': events
                .map((e) => {
                      'title': e.title,
                      'startMs': e.startTime.millisecondsSinceEpoch,
                      'endMs': e.endTime.millisecondsSinceEpoch,
                      'location': e.location,
                      'allDay': e.allDay,
                    })
                .toList(),
          },
        );

      case 'READ_MESSAGES':
        final enabled = await deviceService.isNotificationListenerEnabled();
        if (!enabled) {
          return DesktopInboundResult(
            commandId: cmdId,
            command: cmd,
            ok: false,
            status: 'denied',
            message: 'Sentinela de notificações não está ativa no celular.',
          );
        }
        final msgs = await deviceService.getRecentMessages(limit: 10);
        return DesktopInboundResult(
          commandId: cmdId,
          command: cmd,
          ok: true,
          status: 'executed',
          message: '🔔 ${msgs.length} notificação(ões) recente(s).',
          data: <String, dynamic>{
            'messages': msgs
                .map((m) => {
                      'app': m.appLabel,
                      'sender': m.sender,
                      'text': m.text,
                      'timestamp': m.timestampMs,
                    })
                .toList(),
          },
        );

      case 'WHATSAPP':
        final target = (args['target'] as String? ?? '').trim();
        final text = (args['text'] as String? ?? '').trim();
        final msg = await deviceService.sendWhatsApp(target: target, text: text);
        return DesktopInboundResult(
          commandId: cmdId,
          command: cmd,
          ok: true,
          status: 'executed',
          message: msg,
        );

      case 'SMS':
        final target = (args['target'] as String? ?? '').trim();
        final text = (args['text'] as String? ?? '').trim();
        final msg = await deviceService.sendSms(target: target, text: text);
        return DesktopInboundResult(
          commandId: cmdId,
          command: cmd,
          ok: true,
          status: 'executed',
          message: msg,
        );

      case 'REPLY_MESSAGE':
        final target = (args['target'] as String? ?? '').trim();
        final text = (args['text'] as String? ?? '').trim();
        final msg =
            await deviceService.replyNotification(target: target, text: text);
        return DesktopInboundResult(
          commandId: cmdId,
          command: cmd,
          ok: true,
          status: 'executed',
          message: msg,
        );

      case 'DIAL':
        final number = (args['number'] as String? ?? '').trim();
        await deviceService.dialNumber(number);
        return DesktopInboundResult(
          commandId: cmdId,
          command: cmd,
          ok: true,
          status: 'executed',
          message: '📞 Discador aberto para $number.',
        );

      case 'CREATE_EVENT':
        final title = (args['title'] as String? ?? '').trim();
        final startStr = (args['start'] as String? ?? '').trim();
        final parsedStart = DateTime.tryParse(startStr);
        if (title.isEmpty || parsedStart == null) {
          return DesktopInboundResult(
            commandId: cmdId,
            command: cmd,
            ok: false,
            status: 'failed',
            message: 'Título ou data/hora ISO-8601 inválidos para evento.',
          );
        }
        await deviceService.createCalendarEvent(
          title: title,
          startTime: parsedStart,
        );
        return DesktopInboundResult(
          commandId: cmdId,
          command: cmd,
          ok: true,
          status: 'executed',
          message: '📅 Evento criado: $title',
        );

      default:
        return DesktopInboundResult(
          commandId: cmdId,
          command: cmd,
          ok: false,
          status: 'unsupported',
          message: 'Comando não suportado.',
        );
    }
  }

  Future<void> _postResult(
    DesktopPairingConfig config,
    DesktopInboundResult result,
  ) async {
    final base = config.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/api/mobile/result');
    final ts = _now().millisecondsSinceEpoch.toString();
    final nonce = _nonceGenerator();
    final payload = jsonEncode(<String, dynamic>{
      'device_id': config.deviceId,
      'command_id': result.commandId,
      'command': result.command,
      'ok': result.ok,
      'status': result.status,
      'message': result.message,
      'data': result.data,
      'timestamp': ts,
      'nonce': nonce,
    });
    final sig = DesktopPairingService.computeSignature(
      timestamp: ts,
      nonce: nonce,
      body: payload,
      sharedSecret: config.sharedSecret,
    );

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.postUrl(uri).timeout(const Duration(seconds: 6));
      req.headers.contentType = ContentType.json;
      req.headers.set('X-Ultron-Device', config.deviceId);
      req.headers.set('X-Ultron-Timestamp', ts);
      req.headers.set('X-Ultron-Nonce', nonce);
      req.headers.set('X-Ultron-Signature', sig);
      final encoded = utf8.encode(payload);
      req.contentLength = encoded.length;
      req.add(encoded);
      final resp = await req.close().timeout(const Duration(seconds: 6));
      await resp.drain<void>();
    } catch (_) {
    } finally {
      client.close(force: true);
    }
  }
}

enum DesktopPollOutcome {
  commandHandled,
  noContent,
  unpaired,
  locked,
  endpointUnsupported,
  transientError,
}
