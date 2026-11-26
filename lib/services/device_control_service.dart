import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/security/action_gate.dart';
import '../core/security/auth_gate.dart';
import '../models/assistant_persona.dart';
import '../models/tactical_mode.dart';
import 'audit_log_service.dart';
import 'briefing_service.dart';
import 'desktop_pairing_service.dart';
import 'eletrica_engine.dart';
import 'file_utilities_service.dart';
import 'music_curator_service.dart';
import 'obsidian_service.dart';
import 'opengym_service.dart';
import 'reminder_service.dart';
import 'speech_text.dart';
import 'spotify_service.dart';
import 'vault_search_service.dart';
import 'web_info_service.dart';
import 'workflow_scheduler_service.dart';

class DeviceStatus {
  const DeviceStatus({
    required this.batteryLevel,
    required this.isCharging,
    required this.batteryTempC,
    required this.torchOn,
    required this.volumePercent,
    required this.ringerMode,
    required this.ramUsedMb,
    required this.ramTotalMb,
    required this.ramFreeMb,
    required this.deviceModel,
    required this.androidVersion,
    required this.wifiConnected,
    required this.cellularConnected,
    this.bluetoothEnabled = false,
  });

  final int batteryLevel;
  final bool isCharging;
  final double batteryTempC;
  final bool torchOn;
  final int volumePercent;
  final String ringerMode;
  final int ramUsedMb;
  final int ramTotalMb;
  final int ramFreeMb;
  final String deviceModel;
  final String androidVersion;
  final bool wifiConnected;
  final bool cellularConnected;
  final bool bluetoothEnabled;

  factory DeviceStatus.fromMap(Map<Object?, Object?> map) => DeviceStatus(
        batteryLevel: (map['batteryLevel'] as num?)?.toInt() ?? -1,
        isCharging: map['isCharging'] as bool? ?? false,
        batteryTempC: (map['batteryTempC'] as num?)?.toDouble() ?? 0.0,
        torchOn: map['torchOn'] as bool? ?? false,
        volumePercent: (map['volumePercent'] as num?)?.toInt() ?? 0,
        ringerMode: (map['ringerMode'] as String?) ?? 'NORMAL',
        ramUsedMb: (map['ramUsedMb'] as num?)?.toInt() ?? 0,
        ramTotalMb: (map['ramTotalMb'] as num?)?.toInt() ?? 0,
        ramFreeMb: (map['ramFreeMb'] as num?)?.toInt() ?? 0,
        deviceModel: (map['deviceModel'] as String?) ?? 'Android Node',
        androidVersion: (map['androidVersion'] as String?) ?? 'Android',
        wifiConnected: map['wifiConnected'] as bool? ?? false,
        cellularConnected: map['cellularConnected'] as bool? ?? false,
        bluetoothEnabled: map['bluetoothEnabled'] as bool? ?? false,
      );

  String formatSummary() {
    final bat = batteryLevel >= 0 ? '$batteryLevel%' : 'N/D';
    final charge = isCharging ? 'Carregando ⚡' : 'Bateria';
    final temp =
        batteryTempC > 0 ? ' (${batteryTempC.toStringAsFixed(1)}°C)' : '';
    final net = wifiConnected
        ? 'Wi-Fi Conectado'
        : cellularConnected
            ? 'Dados Móveis (5G/4G)'
            : 'Offline';
    final torch = torchOn ? 'LIGADA' : 'DESLIGADA';
    return '• Modelo: $deviceModel ($androidVersion)\n'
        '• Energia: $bat [$charge]$temp\n'
        '• Memória RAM: $ramUsedMb MB / $ramTotalMb MB ($ramFreeMb MB livres)\n'
        '• Áudio: Volume $volumePercent% (Modo: $ringerMode)\n'
        '• Lanterna: $torch\n'
        '• Conectividade: $net';
  }
}

class DeviceActionResult {
  const DeviceActionResult({
    required this.handled,
    required this.message,
    this.speakText,
  });

  final bool handled;
  final String message;
  final String? speakText;
}

class AiActionExecution {
  const AiActionExecution({
    required this.cleanText,
    required this.executedLogs,
  });

  final String cleanText;
  final List<String> executedLogs;
}

class CapturedNotification {
  const CapturedNotification({
    required this.id,
    required this.packageName,
    required this.appLabel,
    required this.sender,
    required this.text,
    required this.timestampMs,
    required this.timeFormatted,
    required this.canReplyInline,
  });

  final String id;
  final String packageName;
  final String appLabel;
  final String sender;
  final String text;
  final int timestampMs;
  final String timeFormatted;
  final bool canReplyInline;

  factory CapturedNotification.fromMap(Map<Object?, Object?> map) =>
      CapturedNotification(
        id: (map['id'] as String?) ?? '',
        packageName: (map['packageName'] as String?) ?? '',
        appLabel: (map['appLabel'] as String?) ?? 'App',
        sender: (map['sender'] as String?) ?? 'Desconhecido',
        text: (map['text'] as String?) ?? '',
        timestampMs: (map['timestampMs'] as num?)?.toInt() ?? 0,
        timeFormatted: (map['timeFormatted'] as String?) ?? '',
        canReplyInline: (map['canReplyInline'] as bool?) ?? false,
      );
}

/// Compromisso lido do Android CalendarContract.
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    this.allDay = false,
    this.location = '',
    this.calendarName = '',
    this.description = '',
  });

  factory CalendarEvent.fromMap(Map<Object?, Object?> map) {
    final startMs = (map['startMs'] as num?)?.toInt() ?? 0;
    final endMs = (map['endMs'] as num?)?.toInt() ?? startMs;
    return CalendarEvent(
      id: (map['id'] as String?) ?? '',
      title: ((map['title'] as String?) ?? 'Sem título').trim(),
      startTime: DateTime.fromMillisecondsSinceEpoch(startMs),
      endTime: DateTime.fromMillisecondsSinceEpoch(
        endMs >= startMs ? endMs : startMs,
      ),
      allDay: (map['allDay'] as bool?) ?? false,
      location: ((map['location'] as String?) ?? '').trim(),
      calendarName: ((map['calendarName'] as String?) ?? '').trim(),
      description: ((map['description'] as String?) ?? '').trim(),
    );
  }

  final String id;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final bool allDay;
  final String location;
  final String calendarName;
  final String description;

  static String _two(int v) => v.toString().padLeft(2, '0');

  String get timeRangeLabel {
    if (allDay) return 'Dia inteiro';
    final s = '${_two(startTime.hour)}:${_two(startTime.minute)}';
    final e = '${_two(endTime.hour)}:${_two(endTime.minute)}';
    return s == e ? s : '$s–$e';
  }

  String get dateLabel => '${_two(startTime.day)}/${_two(startTime.month)}';

  String formatLine({bool includeDate = false}) {
    final prefix = includeDate ? '$dateLabel $timeRangeLabel' : timeRangeLabel;
    final loc = location.isEmpty ? '' : ' @ $location';
    return '• $prefix — $title$loc';
  }
}

/// Resultado de parsing determinístico de comando para criação de evento na agenda.
class ParsedCalendarDraft {
  const ParsedCalendarDraft({
    required this.title,
    required this.startTime,
    required this.endTime,
  });

  final String title;
  final DateTime startTime;
  final DateTime endTime;
}

/// Diagnóstico do sentinela sherpa-onnx KWS, vindo do serviço nativo.
class WakeWordDiagnostics {
  const WakeWordDiagnostics({
    this.running = false,
    this.capturing = false,
    this.paused = false,
    this.engine = 'desconhecido',
    this.dedicatedKws = false,
    this.modelLoaded = false,
    this.wakeWordProfile = 'ultron',
    this.wakeWordLabel = 'Ultron',
    this.sdk = 0,
    this.notificationsPermission = false,
    this.micPermission = false,
    this.overlayPermission = false,
    this.ignoringBatteryOptimizations = false,
    this.bootAutostart = false,
    this.recognitionAvailable = false,
    this.lastTrigger = 'Nenhum',
    this.voiceTriggers = 0,
    this.detections = 0,
    this.recognizerMisses = 0,
    this.recognizerErrors = 0,
    this.kwsErrors = 0,
    this.kwsFrames = 0,
    this.kwsDecodes = 0,
    this.captureRestarts = 0,
    this.micSilencedEvents = 0,
    this.lastError = 'nenhum',
    this.lastPhrase = '',
    this.noiseFloor = 0,
    this.threshold = 0,
    this.economyMode = false,
  });

  factory WakeWordDiagnostics.fromMap(Map<Object?, Object?> m) {
    bool b(String k) => m[k] == true;
    int i(String k) => (m[k] as num?)?.toInt() ?? 0;
    String s(String k, String fallback) => (m[k] as String?) ?? fallback;
    return WakeWordDiagnostics(
      running: b('running'),
      capturing: b('capturing'),
      paused: b('paused'),
      engine: s('engine', 'desconhecido'),
      dedicatedKws: b('dedicatedKws'),
      modelLoaded: b('modelLoaded'),
      wakeWordProfile: s('wakeWordProfile', 'ultron'),
      wakeWordLabel: s('wakeWordLabel', 'Ultron'),
      sdk: i('sdk'),
      notificationsPermission: b('notificationsPermission'),
      micPermission: b('micPermission'),
      overlayPermission: b('overlayPermission'),
      ignoringBatteryOptimizations: b('ignoringBatteryOptimizations'),
      bootAutostart: b('bootAutostart'),
      recognitionAvailable: b('recognitionAvailable'),
      lastTrigger: s('lastTrigger', 'Nenhum'),
      voiceTriggers: i('voiceTriggers'),
      detections: i('detections'),
      recognizerMisses: i('recognizerMisses'),
      recognizerErrors: i('recognizerErrors'),
      kwsErrors: i('kwsErrors'),
      kwsFrames: i('kwsFrames'),
      kwsDecodes: i('kwsDecodes'),
      captureRestarts: i('captureRestarts'),
      micSilencedEvents: i('micSilencedEvents'),
      lastError: s('lastError', 'nenhum'),
      lastPhrase: s('lastPhrase', ''),
      noiseFloor: i('noiseFloor'),
      threshold: i('threshold'),
      economyMode: b('economyMode'),
    );
  }

  final bool running;

  /// true somente com leitura real de áudio confirmada (não basta o serviço estar vivo).
  final bool capturing;
  final bool paused;

  /// Motor de detecção realmente em uso.
  final String engine;

  /// true somente quando o motor sherpa-onnx dedicado estiver realmente carregado.
  final bool dedicatedKws;
  final bool modelLoaded;
  final String wakeWordProfile;
  final String wakeWordLabel;
  final int sdk;
  final bool notificationsPermission;
  final bool micPermission;
  final bool overlayPermission;
  final bool ignoringBatteryOptimizations;
  final bool bootAutostart;
  final bool recognitionAvailable;
  final String lastTrigger;
  final int voiceTriggers;
  final int detections;
  final int recognizerMisses;
  final int recognizerErrors;
  final int kwsErrors;

  /// Janelas de áudio entregues ao decoder KWS.
  final int kwsFrames;

  /// Execuções de decode do KWS (prova que o pipeline nativo rodou).
  final int kwsDecodes;
  final int captureRestarts;
  final int micSilencedEvents;
  final String lastError;
  final String lastPhrase;
  final int noiseFloor;
  final int threshold;
  final bool economyMode;

  /// Resumo multilinha para exibir no HUD.
  String toReport() => [
        'Motor: $engine',
        'Perfil Wake-Word ativo: $wakeWordLabel ($wakeWordProfile)',
        if (!modelLoaded)
          'FALHA: modelo sherpa-onnx não carregado; escuta indisponível.',
        'Motor KWS dedicado: ${dedicatedKws ? "SIM" : "NÃO"} · Modelo: ${modelLoaded ? "CARREGADO" : "INDISPONÍVEL"}',
        'Captura real: ${capturing ? "CONFIRMADA" : "NÃO confirmada"} · Serviço: ${running ? "vivo" : "parado"}${paused ? " · PAUSADO" : ""}${economyMode ? " · economia" : ""}',
        'Android API $sdk · Notificações: ${notificationsPermission ? "permitidas" : "NEGADAS"}',
        'Microfone: ${micPermission ? "permitido" : "NEGADO"} · Reconhecedor de comando: ${recognitionAvailable ? "disponível" : "INDISPONÍVEL"}',
        'Sobrepor apps (abrir em 2º plano): ${overlayPermission ? "permitido" : "DESATIVADO"}',
        'Bateria: ${ignoringBatteryOptimizations ? "isento" : "sujeito a economia"} · Boot: ${bootAutostart ? "opt-in" : "off"}',
        'Ativações KWS: $detections · Última palavra: ${lastPhrase.isEmpty ? "nenhuma" : lastPhrase}',
        'Falhas KWS/captura: $kwsErrors · Religamentos: $captureRestarts · Mic silenciado: $micSilencedEvents',
        'Pipeline KWS: $kwsFrames janelas · $kwsDecodes decodes',
        'Falsos acionamentos: não mensuráveis automaticamente.',
        'Último gatilho: $lastTrigger',
        'Último erro: $lastError',
      ].join('\n');
}

class BackgroundConversationTurn {
  const BackgroundConversationTurn({
    required this.userText,
    required this.assistantText,
    required this.senderLabel,
    required this.userTimestamp,
    required this.replyTimestamp,
  });

  final String userText;
  final String assistantText;
  final String senderLabel;
  final DateTime userTimestamp;
  final DateTime replyTimestamp;

  factory BackgroundConversationTurn.fromMap(Map<Object?, Object?> map) =>
      BackgroundConversationTurn(
        userText: (map['userText'] as String? ?? '').trim(),
        assistantText: (map['assistantText'] as String? ?? '').trim(),
        senderLabel: (map['senderLabel'] as String? ?? 'U.L.T.R.O.N.').trim(),
        userTimestamp: DateTime.fromMillisecondsSinceEpoch(
          (map['userTimestampMs'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch,
        ),
        replyTimestamp: DateTime.fromMillisecondsSinceEpoch(
          (map['replyTimestampMs'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch,
        ),
      );
}

typedef ActionGateConfirmCallback = Future<bool> Function(
  ActionSimulation simulation,
);

/// Imagem capturada pela câmera ou galeria, já redimensionada e codificada em JPEG Base64.
class VisionAttachment {
  const VisionAttachment({
    required this.base64,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.byteSize,
    required this.source,
  });

  factory VisionAttachment.fromMap(Map<Object?, Object?> map) {
    return VisionAttachment(
      base64: map['base64'] as String? ?? '',
      mimeType: map['mimeType'] as String? ?? 'image/jpeg',
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
      byteSize: (map['byteSize'] as num?)?.toInt() ?? 0,
      source: map['source'] as String? ?? 'camera',
    );
  }

  final String base64;
  final String mimeType;
  final int width;
  final int height;
  final int byteSize;
  final String source;

  String get sizeKbLabel => '${(byteSize / 1024).toStringAsFixed(1)} KB';
}

class DeviceControlService {
  DeviceControlService({
    MethodChannel? channel,
    FlutterSecureStorage? storage,
    this.obsidianProvider,
    this.vaultSearchProvider,
    this.auditLogProvider,
    this.reminderProvider,
    this.webInfoProvider,
    this.workflowSchedulerProvider,
    this.spotifyProvider,
    this.desktopPairingProvider,
    this.fileUtilitiesProvider,
    this.authGate,
    this.onRequestElevation,
    this.actionGate = const ActionGate(),
  })  : _channel = channel ??
            const MethodChannel('com.viniciusnpaula.ultron_mobile/device'),
        _storage = storage ?? const FlutterSecureStorage();

  final MethodChannel _channel;
  final FlutterSecureStorage _storage;
  final Future<ObsidianService> Function()? obsidianProvider;
  final Future<VaultSearchService> Function()? vaultSearchProvider;
  final Future<AuditLogService> Function()? auditLogProvider;
  final Future<ReminderService> Function()? reminderProvider;
  final WebInfoService Function()? webInfoProvider;
  final Future<WorkflowSchedulerService> Function()? workflowSchedulerProvider;
  final SpotifyService Function()? spotifyProvider;
  final DesktopPairingService Function()? desktopPairingProvider;
  final FileUtilitiesService Function()? fileUtilitiesProvider;
  final AuthGate? authGate;
  final Future<bool> Function(AccessLevel requiredLevel, String reason)?
      onRequestElevation;
  final ActionGate actionGate;
  static const _pcEndpointKey = 'ultron.pc.killswitch.v1';
  static const _pcSecretKey = 'ultron.pc.killswitch.secret.v1';
  VaultSearchService? _cachedVaultSearch;
  String? _cachedVaultSearchRoot;

  void setNativeEventHandlers({
    VoidCallback? onFlip,
    void Function(String phrase)? onWakeWord,
    void Function(String partial)? onSpeechPartial,
    void Function(double rms)? onSpeechRms,
    VoidCallback? onBackgroundTurn,
    void Function(String uri)? onPairingUriReceived,
    void Function(int flowId)? onWorkflowTriggered,
    void Function(String uri)? onSpotifyCallbackReceived,
    void Function(bool requiresUnlock)? onFloatingOrbTapped,
    VoidCallback? onStopSpeakingRequested,
    VoidCallback? onUrgentNotificationDetected,
    VoidCallback? onTriageConfigChanged,
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onFlipToShush':
          onFlip?.call();
        case 'onWakeWordDetected':
          final phrase = (call.arguments as String?) ?? 'Ultron';
          onWakeWord?.call(phrase);
        case 'onSpeechPartial':
          final partial = (call.arguments as String?) ?? '';
          if (partial.isNotEmpty) {
            onSpeechPartial?.call(partial);
          }
        case 'onSpeechRms':
          final rms = (call.arguments as num?)?.toDouble() ?? 0.0;
          onSpeechRms?.call(rms.clamp(0.0, 1.0));
        case 'onBackgroundTurnAvailable':
          onBackgroundTurn?.call();
        case 'onPairingUriReceived':
          final uri = (call.arguments as String?) ?? '';
          if (uri.isNotEmpty) {
            onPairingUriReceived?.call(uri);
          }
        case 'onWorkflowTriggered':
          final flowId = (call.arguments as num?)?.toInt() ?? 0;
          if (flowId > 0) {
            onWorkflowTriggered?.call(flowId);
          }
        case 'onSpotifyCallbackUriReceived':
          final uri = (call.arguments as String?) ?? '';
          if (uri.isNotEmpty) {
            onSpotifyCallbackReceived?.call(uri);
          }
        case 'onFloatingOrbTapped':
          final map = call.arguments as Map<Object?, Object?>?;
          final requiresUnlock = (map?['requiresUnlock'] as bool?) ?? false;
          onFloatingOrbTapped?.call(requiresUnlock);
        case 'onStopSpeakingRequested':
          onStopSpeakingRequested?.call();
        case 'onUrgentNotificationDetected':
          onUrgentNotificationDetected?.call();
        case 'onTriageConfigChanged':
          onTriageConfigChanged?.call();
      }
      return null;
    });
  }

  /// Mantém respostas longas da IA e a fala (TTS) ativas em segundo plano no Android.
  Future<void> setBackgroundResponseState({
    required bool active,
    String phase = 'speaking',
    String preview = '',
  }) async {
    try {
      await _channel.invokeMethod<bool>('setBackgroundResponseState', {
        'active': active,
        'phase': phase,
        'preview': preview,
      });
    } catch (_) {}
  }

  /// Publica uma notificação expansível quando uma resposta termina em segundo plano no mudo.
  Future<void> notifyBackgroundResponseReady({
    required String title,
    required String body,
  }) async {
    try {
      await _channel.invokeMethod<bool>('notifyBackgroundResponseReady', {
        'title': title,
        'body': body,
      });
    } catch (_) {}
  }

  /// Sincroniza a configuração da Triagem Inteligente de Notificações com o Android nativo.
  Future<void> configureSmartNotificationTriage(
    Map<String, dynamic> config,
  ) async {
    try {
      await _channel.invokeMethod<bool>(
        'configureSmartNotificationTriage',
        config,
      );
    } catch (_) {}
  }

  /// Lê a configuração atual da Triagem Inteligente salva no Android nativo.
  Future<Map<Object?, Object?>?> getSmartNotificationTriageConfig() async {
    try {
      return await _channel.invokeMethod<Map<Object?, Object?>>(
        'getSmartNotificationTriageConfig',
      );
    } catch (_) {
      return null;
    }
  }

  /// Consome eventos urgentes triados em tempo real para persistir no Obsidian e no feed.
  Future<List<Map<Object?, Object?>>> consumePendingUrgentNotifications() async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>(
        'consumePendingUrgentNotifications',
      );
      if (raw == null) return const [];
      return raw.whereType<Map<Object?, Object?>>().toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  void setFlipToShushHandler(VoidCallback? onFlip) {
    setNativeEventHandlers(onFlip: onFlip);
  }

  Future<ObsidianService> _getObsidian() => obsidianProvider != null
      ? obsidianProvider!()
      : ObsidianService.openDefaultVault();

  /// Retorna a instância do serviço do cofre Obsidian (Segundo Cérebro).
  Future<ObsidianService> getObsidianVault() => _getObsidian();

  /// Abre o cofre do Obsidian diretamente no aplicativo oficial.
  Future<bool> openObsidianVault() async {
    try {
      final vault = await _getObsidian();
      final openedUri = await openUrl(vault.obsidianOpenUri);
      if (openedUri) return true;
    } catch (_) {}
    try {
      final app = await openApp('obsidian');
      return app.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<VaultSearchService> _getVaultSearch() async {
    if (vaultSearchProvider != null) {
      return vaultSearchProvider!();
    }
    final vault = await _getObsidian();
    if (_cachedVaultSearch != null &&
        _cachedVaultSearchRoot == vault.vaultPath) {
      return _cachedVaultSearch!;
    }
    if (_cachedVaultSearch != null) {
      await _cachedVaultSearch!.close();
    }
    _cachedVaultSearch = await VaultSearchService.open(
      vaultRoot: Directory(vault.vaultPath),
    );
    _cachedVaultSearchRoot = vault.vaultPath;
    return _cachedVaultSearch!;
  }

  void invalidateVaultSearchCache() =>
      _cachedVaultSearch?.invalidateSyncCache();

  Future<ReminderService?> _getReminderServiceOrNull() async {
    try {
      if (reminderProvider != null) {
        return await reminderProvider!();
      }
      return await ReminderService.instance(channel: _channel);
    } catch (_) {
      return null;
    }
  }

  WebInfoService _getWebInfo() => webInfoProvider != null
      ? webInfoProvider!()
      : WebInfoService(
          briefingService: BriefingService(
            deviceService: this,
            storage: _storage,
          ),
        );

  Future<WorkflowSchedulerService?> _getWorkflowSchedulerOrNull() async {
    try {
      if (workflowSchedulerProvider != null) {
        return await workflowSchedulerProvider!();
      }
      return await WorkflowSchedulerService.instance(channel: _channel);
    } catch (_) {
      return null;
    }
  }

  SpotifyService getSpotifyService() => spotifyProvider != null
      ? spotifyProvider!()
      : SpotifyService(storage: _storage);

  /// Consome um link `ultron://spotify-callback?...` pendente recebido via Intent/deep link.
  Future<String?> consumePendingSpotifyCallbackUri() async {
    try {
      final res =
          await _channel.invokeMethod<String>('consumePendingSpotifyCallbackUri');
      final trimmed = res?.trim() ?? '';
      return trimmed.isEmpty ? null : trimmed;
    } catch (_) {
      return null;
    }
  }

  /// P5: Acesso seguro ao log imutável de auditoria (nunca quebra em ambiente headless sem sqflite).
  Future<AuditLogService?> _getAuditLogOrNull() async {
    try {
      if (auditLogProvider != null) {
        return await auditLogProvider!();
      }
      return await AuditLogService.instance();
    } catch (_) {
      return null;
    }
  }

  Future<void> recordAudit({
    required String actor,
    required String action,
    String target = '',
    required String status,
    String detail = '',
  }) async {
    try {
      final audit = await _getAuditLogOrNull();
      await audit?.record(
        actor: actor,
        action: action,
        target: target,
        status: status,
        detail: detail,
      );
    } catch (_) {}
  }

  /// P1: Busca léxica (SQLite FTS5/BM25) nas notas Markdown do cofre Obsidian.
  Future<List<VaultSearchHit>> searchObsidianVault(
    String query, {
    int limit = 5,
  }) async {
    final search = await _getVaultSearch();
    await search.sync(force: true);
    return search.search(query, limit: limit);
  }

  /// Abre o leitor de QR Code nativo para escanear `ultron://pair?...` do Desktop.
  Future<String?> scanPairingQr() async {
    final res = await _channel.invokeMethod<String>('scanPairingQr');
    final trimmed = res?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Consome um link `ultron://pair?...` pendente recebido via Intent/deep link.
  Future<String?> consumePendingPairingUri() async {
    final res = await _channel.invokeMethod<String>('consumePendingPairingUri');
    final trimmed = res?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  /// P2: Captura ou seleciona imagem (câmera ou galeria), já redimensionada em JPEG Base64.
  Future<VisionAttachment?> captureVisionImage({
    String source = 'camera',
  }) async {
    final normalized =
        source.trim().toLowerCase() == 'gallery' ? 'gallery' : 'camera';
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'captureVisionImage',
      {'source': normalized},
    );
    if (raw == null) return null;
    final attachment = VisionAttachment.fromMap(raw);
    return attachment.base64.isEmpty ? null : attachment;
  }

  /// Formata data, hora, dia da semana e fuso horário locais do dispositivo para
  /// injeção em tempo real no prompt de sistema.
  static String formatClockContext(DateTime now) {
    const weekdays = <String>[
      'segunda-feira',
      'terça-feira',
      'quarta-feira',
      'quinta-feira',
      'sexta-feira',
      'sábado',
      'domingo',
    ];
    final weekday = weekdays[(now.weekday - 1).clamp(0, 6)];
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    final offset = now.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final absMins = offset.inMinutes.abs();
    final offH = (absMins ~/ 60).toString().padLeft(2, '0');
    final offM = (absMins % 60).toString().padLeft(2, '0');
    final tzName = now.timeZoneName.trim();
    final tzSuffix =
        tzName.isEmpty ? 'UTC$sign$offH:$offM' : '$tzName, UTC$sign$offH:$offM';

    return '=== RELÓGIO DO DISPOSITIVO (TEMPO REAL) ===\n'
        'Data atual: $y-$m-$d ($weekday)\n'
        'Hora atual: $hh:$mm:$ss ($tzSuffix)\n'
        'Use esta data e hora reais para calcular alarmes relativos ("daqui X minutos/horas"), '
        'timers, datas ("hoje", "amanhã") e agendamentos sem perguntar o horário ao usuário.';
  }

  DesktopPairingService _getDesktopPairing() => desktopPairingProvider != null
      ? desktopPairingProvider!()
      : DesktopPairingService(storage: _storage);

  Future<bool> _hasDesktopPairedSafe() async {
    try {
      return (await _getDesktopPairing().loadPairing()) != null;
    } catch (_) {
      return false;
    }
  }

  /// Avalia o estágio de privilégio ([AuthGate]) e confirmação ([ActionGate]).
  /// - Nível 1 (`basic` / PIN): só ações `safe` locais.
  /// - Nível 2 (`elevated` / NFC): libera ações sensíveis no celular (com confirmação).
  /// - Nível 3 (`sovereign` / Biometria): libera tudo sem fricção, confirmando apenas críticas/autodestrutivas.
  Future<bool> authorizeAction(
    ActionSimulation sim, {
    ActionGateConfirmCallback? confirmAction,
    String actor = 'OPERATOR',
  }) async {
    final gate = authGate;
    if (gate == null) {
      if (!sim.requiresConfirmation) return true;
      final allowed = confirmAction != null ? await confirmAction(sim) : false;
      if (!allowed) {
        await recordAudit(
          actor: actor,
          action: sim.actionCode,
          target: sim.targetResource,
          status: 'DENIED',
          detail: sim.description,
        );
      }
      return allowed;
    }

    var decision = actionGate.evaluatePrivilege(sim, gate.level);
    if (!decision.allowed) {
      if (onRequestElevation != null) {
        await onRequestElevation!(decision.requiredLevel, decision.reason);
        decision = actionGate.evaluatePrivilege(sim, gate.level);
      }
      if (!decision.allowed) {
        await recordAudit(
          actor: actor,
          action: sim.actionCode,
          target: sim.targetResource,
          status: 'DENIED',
          detail: decision.reason.isEmpty ? sim.description : decision.reason,
        );
        return false;
      }
    }

    if (decision.requiresConfirmation) {
      final allowed = confirmAction != null ? await confirmAction(sim) : false;
      if (!allowed) {
        await recordAudit(
          actor: actor,
          action: sim.actionCode,
          target: sim.targetResource,
          status: 'DENIED',
          detail: sim.description,
        );
        return false;
      }
    }
    return true;
  }

  /// Envia um comando autenticado via HMAC para o U.L.T.R.O.N. Desktop pareado,
  /// aplicando [ActionGate] e registrando auditoria local.
  Future<DesktopCommandResult> sendDesktopBridgeCommand({
    required String command,
    Map<String, dynamic> args = const {},
    ActionGateConfirmCallback? confirmAction,
    String actor = 'OPERATOR',
    bool skipLocalConfirm = false,
  }) async {
    final upper = command.trim().toUpperCase();
    final riskTag = args['risk']?.toString() ?? '';
    final argPreview = [
      args['tool']?.toString() ??
          args['app']?.toString() ??
          args['skill']?.toString() ??
          args['action']?.toString() ??
          args['plan']?.toString() ??
          '',
      if (riskTag.isNotEmpty) riskTag,
    ].where((s) => s.isNotEmpty).join('|');
    final tag =
        argPreview.isEmpty ? '[ACTION:$upper]' : '[ACTION:$upper:$argPreview]';
    final sim = actionGate.simulate(tag);
    if (!skipLocalConfirm) {
      final allowed = await authorizeAction(
        sim,
        confirmAction: confirmAction,
        actor: actor,
      );
      if (!allowed) {
        return const DesktopCommandResult(sent: false, deniedByUser: true);
      }
    }

    final res = await _getDesktopPairing().sendCommand(
      command: upper,
      args: args,
      confirm: (_) async => true,
    );
    await recordAudit(
      actor: actor,
      action: upper,
      target: 'Desktop LAN ($argPreview)',
      status: res.sent
          ? 'EXECUTED'
          : (res.unsupportedByServer ? 'UNSUPPORTED' : 'FAILED'),
      detail: 'HTTP ${res.statusCode ?? '-'}${res.error == null ? '' : ' • ${res.error}'}',
    );
    return res;
  }

  /// Monta o System Prompt filtrado de acordo com o [TacticalMode] ativo,
  /// economizando tokens e evitando confusão de ferramentas em modelos menores.
  static String buildSystemPromptForMode(TacticalMode mode) {
    if (mode.isGeneral) return aiSystemPrompt;
    final cats = <TacticalActionCategory>{
      TacticalActionCategory.core,
      ...mode.allowedCategories,
    };
    final sb = StringBuffer()
      ..writeln(
        'Você é U.L.T.R.O.N. 2.0 Mobile — ${mode.label}. '
        'Responda sempre em português do Brasil, de forma direta, inteligente e concisa.',
      )
      ..writeln(mode.personaDirective);
    if (mode.vaultPathPrefix != null) {
      sb.writeln(
        'Escopo de memória ativo no Obsidian: `${mode.vaultPathPrefix}/`.',
      );
    }
    sb
      ..writeln()
      ..writeln(
        'Tags de ação habilitadas neste modo (inclua no final da resposta apenas quando o usuário pedir a ação):',
      )
      ..writeln(
        '- Salvar nota rápida no Obsidian: [ACTION:NOTE:texto da anotação]\n'
        '- Ler nota no Obsidian: [ACTION:OBSIDIAN_READ:${mode.vaultPathPrefix ?? 'Memoria'}/Nota.md]\n'
        '- Anexar texto a nota no Obsidian: [ACTION:OBSIDIAN_APPEND:${mode.vaultPathPrefix ?? 'Memoria'}/Nota.md:novo conteúdo]\n'
        '- Criar/listar lembrete persistente: [ACTION:REMINDER_CREATE:YYYY-MM-DD HH:MM:Título], [ACTION:REMINDER_LIST]\n'
        '- Criar timer (segundos:Título): [ACTION:TIMER:1500:Foco]\n'
        '- Volume: [ACTION:VOLUME_SET:50], [ACTION:VOLUME_MUTE]',
      );
    if (cats.contains(TacticalActionCategory.obsidian)) {
      sb.writeln(
        '- Listar notas / tarefas / status / desfazer no Obsidian: '
        '[ACTION:OBSIDIAN_LIST:${mode.vaultPathPrefix ?? 'Memoria'}], '
        '[ACTION:OBSIDIAN_TASKS], [ACTION:OBSIDIAN_STATUS], [ACTION:UNDO]',
      );
    }
    if (cats.contains(TacticalActionCategory.webAndInfo)) {
      sb.writeln(
        '- Pesquisa web resumida / clima / notícias: '
        '[ACTION:WEB_SEARCH:termo], [ACTION:WEATHER:cidade], [ACTION:NEWS:tema]',
      );
    }
    if (cats.contains(TacticalActionCategory.calendar)) {
      sb.writeln(
        '- Agenda local: [ACTION:READ_CALENDAR:3], '
        '[ACTION:CREATE_EVENT:YYYY-MM-DD HH:MM:Título], [ACTION:CANCEL_EVENT:Título]',
      );
    }
    if (cats.contains(TacticalActionCategory.spotify)) {
      sb.writeln(
        '- Spotify: [ACTION:SPOTIFY_STATE], [ACTION:SPOTIFY_PLAY:busca_ou_uri], [ACTION:SPOTIFY_SEARCH:termo]',
      );
    }
    if (cats.contains(TacticalActionCategory.desktop)) {
      sb.writeln(
        '- Ponte Desktop LAN (HMAC-SHA256): [ACTION:PC_STATUS], [ACTION:PC_CLIPBOARD_PUSH:texto], '
        '[ACTION:PC_CLIPBOARD_PULL], [ACTION:PC_RUN_SKILL:nome_skill], '
        '[ACTION:PC_EXEC_TOOL:nome_ferramenta|{"param":"valor"}]',
      );
    }
    return sb.toString().trim();
  }

  /// Constrói o System Prompt contextual injetando data/hora atual, memória de longo prazo
  /// e trechos relevantes do cofre Obsidian (RAG lexical local via FTS5).
  Future<String> buildContextualSystemPrompt({
    String? userQuery,
    DateTime? now,
    TacticalMode? mode,
    AssistantPersona? persona,
    SpeechStyle? speechStyle,
    String? lexicalRecallContext,
    String? compactedHistoryDigest,
    bool nightFocusMode = false,
  }) async {
    final activeMode = mode ?? TacticalMode.geral;
    final sections = <String>[
      buildSystemPromptForMode(activeMode),
      if (persona != null) persona.promptDirective,
      if (speechStyle != null) 'Estilo de fala ativo: ${speechStyle.promptDirective}',
      if (activeMode == TacticalMode.musica)
        MusicCuratorService.buildPromptGuidance(
          now: now,
          mode: activeMode,
          nightFocusMode: nightFocusMode,
        ),
      'Registro emocional TTS: você pode abrir sua resposta com UMA tag curta opcional '
          '([neutro], [lamento], [encorajador], [alerta], [comemorando], [serio] ou [duvida]) '
          'para modular o tom de voz automaticamente (a tag será removida antes de exibir).',
      formatClockContext(now ?? DateTime.now()),
    ];
    if (compactedHistoryDigest != null &&
        compactedHistoryDigest.trim().isNotEmpty) {
      sections.add(
        '=== RESUMO COMPACTADO DA SESSÃO ===\n'
        '${compactedHistoryDigest.trim()}\n'
        '=== FIM DO RESUMO ===',
      );
    }
    if (lexicalRecallContext != null &&
        lexicalRecallContext.trim().isNotEmpty) {
      sections.add(
        '=== MEMÓRIA LEXICAL LOCAL (ÚLTIMOS 365 DIAS) ===\n'
        '${lexicalRecallContext.trim()}\n'
        '=== FIM DA MEMÓRIA LEXICAL ===',
      );
    }
    try {
      final vault = await _getObsidian();
      try {
        final rawFacts =
            await vault.readNote('Memoria/Sessoes/Contexto_Longo_Prazo.md');
        final cleanFacts = ObsidianService.sanitizeForExternalAi(rawFacts);
        if (cleanFacts.trim().isNotEmpty) {
          final clipped = cleanFacts.length > 900
              ? cleanFacts.substring(cleanFacts.length - 900)
              : cleanFacts;
          sections.add(
            '=== PERFIL E CONTEXTO DE LONGO PRAZO (SESSÕES ANTERIORES) ===\n'
            '${clipped.trim()}\n'
            '=== FIM DO PERFIL DE LONGO PRAZO ===',
          );
        }
      } catch (_) {}
      final rawMemory = await vault.readLongTermMemory(
        maxChars: activeMode.isGeneral ? 2000 : 800,
      );
      final memory = ObsidianService.sanitizeForExternalAi(rawMemory);
      if (memory.trim().isNotEmpty) {
        sections.add(
          '=== SEGUNDO CÉREBRO — MEMÓRIA ATIVA DO COFRE OBSIDIAN ===\n'
          'As informações abaixo são notas e memórias reais do operador gravadas no Obsidian:\n'
          '$memory\n'
          '=== FIM DA MEMÓRIA DO COFRE ===',
        );
      }
    } catch (_) {}

    final query = userQuery?.trim() ?? '';
    if (query.isNotEmpty) {
      try {
        final search = await _getVaultSearch();
        await search.sync(minInterval: const Duration(seconds: 30));
        final rawRag = await search.buildRagContext(
          query,
          limit: 3,
          maxChars: 1400,
          pathPrefix: activeMode.vaultPathPrefix,
        );
        final rag = ObsidianService.sanitizeForExternalAi(rawRag);
        if (rag.trim().isNotEmpty) {
          final scopeLabel = activeMode.vaultPathPrefix != null
              ? ' (${activeMode.vaultPathPrefix} · RAG FTS5)'
              : ' (RAG FTS5)';
          sections.add(
            '=== NOTAS RELEVANTES DO COFRE$scopeLabel ===\n'
            '$rag\n'
            '=== FIM DO CONTEXTO RAG ===',
          );
        }
      } catch (_) {}
    }

    return sections.join('\n\n');
  }

  /// Normaliza host/IP digitado para URL do endpoint `/killswitch`.
  static String normalizeKillSwitchUrl(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    return (t.startsWith('http://') || t.startsWith('https://'))
        ? t
        : 'http://$t/killswitch';
  }

  Future<String> loadPcKillSwitchUrl() async =>
      (await _storage.read(key: _pcEndpointKey))?.trim() ?? '';

  Future<void> savePcKillSwitchUrl(
    String url, {
    bool allowNonPrivateHost = false,
  }) async {
    final normalized = normalizeKillSwitchUrl(url);
    if (normalized.isEmpty) {
      await _storage.write(key: _pcEndpointKey, value: '');
      return;
    }
    if (!DesktopPairingService.isValidEndpoint(
      normalized,
      allowNonPrivateHost: allowNonPrivateHost,
    )) {
      throw ArgumentError(
        'Endpoint do Kill Switch inválido ou fora da rede local (LAN).',
      );
    }
    await _storage.write(key: _pcEndpointKey, value: normalized);
  }

  Future<String> loadPcLanSecret() async =>
      (await _storage.read(key: _pcSecretKey))?.trim() ?? '';

  Future<void> savePcLanSecret(String secret) =>
      _storage.write(key: _pcSecretKey, value: secret.trim());

  Future<String> generatePcLanSecret() async {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
    final rng = Random.secure();
    final secret = List.generate(
      32,
      (_) => alphabet[rng.nextInt(alphabet.length)],
    ).join();
    await savePcLanSecret(secret);
    return secret;
  }

  Future<String> triggerPcKillSwitch({
    String? overrideUrl,
    String? overrideSecret,
    String? reason,
    bool allowNonPrivateHost = false,
  }) async {
    final target = (overrideUrl ?? await loadPcKillSwitchUrl()).trim();
    if (target.isEmpty) {
      return '⚠️ Kill Switch Local: Endpoint do PC não configurado (sessão mobile bloqueada).';
    }
    final normalized = normalizeKillSwitchUrl(target);
    if (!DesktopPairingService.isValidEndpoint(
      normalized,
      allowNonPrivateHost: allowNonPrivateHost,
    )) {
      await recordAudit(
        actor: 'OPERATOR',
        action: 'KILL_SWITCH',
        target: target,
        status: 'DENIED',
        detail: 'Endpoint bloqueado por política LAN/anti-SSRF',
      );
      return '🚫 Kill Switch bloqueado: endpoint inválido ou fora da rede local (LAN).';
    }
    final secret = (overrideSecret ?? await loadPcLanSecret()).trim();
    if (secret.isEmpty) {
      return '🚫 Kill Switch bloqueado: configure a chave secreta HMAC LAN na aba Segurança antes de disparar.';
    }
    final uri = Uri.parse(normalized);
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final payload = jsonEncode({
      'command': 'LOCK_WORKSTATION',
      'source': 'ULTRON_MOBILE',
      'reason': reason ?? 'manual',
      'timestamp': timestamp,
    });
    final signature = ActionGate.signPayload(payload, secret: secret);

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.postUrl(uri).timeout(const Duration(seconds: 8));
      req.headers.contentType = ContentType.json;
      req.headers.set('X-Ultron-Signature', 'sha256=$signature');
      req.headers.set('X-Ultron-Timestamp', timestamp);
      req.write(payload);
      final resp = await req.close().timeout(const Duration(seconds: 8));
      await resp.drain<void>();
      final summary =
          '🚨 Pacote Kill Switch enviado para ${uri.host} (HTTP ${resp.statusCode}).';
      await recordAudit(
        actor: 'OPERATOR',
        action: 'KILL_SWITCH',
        target: uri.host,
        status: resp.statusCode < 400 ? 'EXECUTED' : 'FAILED',
        detail: 'HTTP ${resp.statusCode} (${reason ?? 'manual'})',
      );
      return summary;
    } catch (e) {
      await recordAudit(
        actor: 'OPERATOR',
        action: 'KILL_SWITCH',
        target: uri.host,
        status: 'FAILED',
        detail: '$e',
      );
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  /// Calcula hash SHA-256 de um arquivo local para verificação de integridade tática.
  Future<String> computeFileSha256(File file) async {
    if (!await file.exists()) {
      throw FileSystemException('Arquivo não encontrado', file.path);
    }
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  /// Valida se o hash SHA-256 do arquivo confere com o esperado.
  Future<bool> verifyFileIntegrity(File file, String expectedSha256) async {
    final actual = await computeFileSha256(file);
    return actual.toLowerCase().trim() == expectedSha256.toLowerCase().trim();
  }

  /// Prepara payload assinado com HMAC-SHA256 para sincronização com o nó PC.
  Map<String, String> preparePcSyncPayload({
    required String command,
    Map<String, dynamic> data = const {},
    required String secret,
  }) {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final body = jsonEncode({
      'command': command,
      'source': 'ULTRON_MOBILE',
      'timestamp': timestamp,
      'payload': data,
    });
    final signature = ActionGate.signPayload(body, secret: secret);
    return {
      'body': body,
      'signature': 'sha256=$signature',
      'timestamp': timestamp,
    };
  }

  static const aiSystemPrompt = '''
Você é U.L.T.R.O.N. 2.0 Mobile, um assistente tático autônomo rodando nativamente em um smartphone Android (500x mais capaz que assistentes comuns).
Responda sempre em português do Brasil, de forma direta, inteligente e concisa.
Você possui controle direto sobre o hardware, mensagens (WhatsApp, Telegram, SMS, Notificações), cofre Obsidian e o sistema Android do usuário através de tags de ação.
Sempre que o usuário pedir para realizar uma ação no celular (ler mensagens, responder notificação em segundo plano, enviar WhatsApp/SMS, ligar/desligar lanterna, mudar volume, salvar uma nota no Obsidian, rodar uma skill, abrir um aplicativo, abrir câmera, abrir configurações, criar alarme, criar timer, vibrar, discar número ou pesquisar na web), inclua a tag correspondente no final da sua resposta:
- Ler mensagens/notificações recentes: [ACTION:READ_MESSAGES]
- Responder mensagem/notificação em 2º plano (RemoteInput): [ACTION:REPLY_MESSAGE:ultimo_ou_nome:texto da resposta]
- Enviar mensagem no WhatsApp (busca contato na agenda ou número): [ACTION:WHATSAPP:nome_ou_numero:texto da mensagem]
- Enviar SMS (busca contato na agenda ou número): [ACTION:SMS:nome_ou_numero:texto da mensagem]
- Ligar lanterna/flash: [ACTION:TORCH_ON]
- Desligar lanterna/flash: [ACTION:TORCH_OFF]
- Alternar lanterna: [ACTION:TORCH_TOGGLE]
- Definir volume (0 a 100): [ACTION:VOLUME_SET:80]
- Aumentar volume: [ACTION:VOLUME_UP]
- Diminuir volume: [ACTION:VOLUME_DOWN]
- Silenciar / mudo: [ACTION:VOLUME_MUTE]
- Controlar reprodução de mídia: [ACTION:MEDIA_PLAY], [ACTION:MEDIA_PAUSE], [ACTION:MEDIA_PLAY_PAUSE], [ACTION:MEDIA_NEXT], [ACTION:MEDIA_PREVIOUS], [ACTION:MEDIA_STOP]
- Salvar nota rápida no Cofre Obsidian: [ACTION:NOTE:texto da anotação]
- Listar notas do Cofre Obsidian (opcional pasta Diario, Memoria, Inbox, Skills): [ACTION:OBSIDIAN_LIST:Memoria]
- Ler nota específica do Cofre Obsidian: [ACTION:OBSIDIAN_READ:Memoria/Operador.md]
- Anexar texto a nota existente no Obsidian: [ACTION:OBSIDIAN_APPEND:Memoria/Operador.md:novo conteúdo]
- Listar ou alternar tarefas Markdown (- [ ] / - [x]) no Obsidian: [ACTION:OBSIDIAN_TASKS] ou [ACTION:OBSIDIAN_TASKS:marcar:1]
- Status e estatísticas do Cofre Obsidian: [ACTION:OBSIDIAN_STATUS]
- Desfazer última alteração no Cofre Obsidian: [ACTION:UNDO]
- Executar Skill Mobile (.md): [ACTION:SKILL:modo_estudo]
- Criar nova Skill procedural (.md): [ACTION:SKILL_CREATE:nome_skill|conteúdo markdown com tags ACTION]
- Excluir Skill procedural (.md): [ACTION:SKILL_DELETE:nome_skill]
- Abrir aplicativo (ex: whatsapp, youtube, instagram, chrome, spotify, calculadora, camera, relogio, maps): [ACTION:OPEN_APP:whatsapp]
- Abrir câmera: [ACTION:OPEN_CAMERA]
- Abrir configurações (wifi, bluetooth, display, sound, battery, location, security, apps, general): [ACTION:OPEN_SETTINGS:wifi]
- Criar alarme (HH:MM:Título): [ACTION:ALARM:07:30:Acordar]
- Criar timer em segundos (segundos:Título): [ACTION:TIMER:300:Timer]
- Vibrar celular: [ACTION:VIBRATE]
- Discar número: [ACTION:DIAL:11999999999]
- Abrir pesquisa no navegador web: [ACTION:SEARCH:termo de busca]
- Pesquisa web textual resumida direto no chat: [ACTION:WEB_SEARCH:termo de busca]
- Consultar clima atual (cidade opcional): [ACTION:WEATHER:São Paulo]
- Consultar notícias recentes via RSS (tema opcional): [ACTION:NEWS:tecnologia]
- Ler agenda do celular (dias à frente): [ACTION:READ_CALENDAR:1]
- Criar evento na agenda (YYYY-MM-DD HH:MM:Título): [ACTION:CREATE_EVENT:2026-11-20 15:00:Reunião Tática]
- Cancelar evento da agenda por ID ou título: [ACTION:CANCEL_EVENT:Reunião Tática]
- Criar lembrete persistente com alarme local: [ACTION:REMINDER_CREATE:daqui 30 minutos:Tomar água]
- Listar lembretes pendentes: [ACTION:REMINDER_LIST]
- Cancelar lembrete por ID ou título: [ACTION:REMINDER_CANCEL:1]
- Fluxos Dinâmicos Agendados (encadeando ações/skills com AuthGate):
  * Criar fluxo: [ACTION:FLOW_CREATE:rotina_manha|TORCH_OFF -> VOLUME_SET:40|diario 07:00]
  * Listar fluxos: [ACTION:FLOW_LIST]
  * Executar fluxo: [ACTION:FLOW_RUN:rotina_manha]
  * Agendar fluxo: [ACTION:FLOW_SCHEDULE:rotina_manha:a cada 60m]
  * Excluir fluxo: [ACTION:FLOW_DELETE:rotina_manha]
- Spotify Web API (OAuth 2.0 PKCE):
  * Buscar faixas no Spotify: [ACTION:SPOTIFY_SEARCH:termo]
  * Estado atual do player Spotify: [ACTION:SPOTIFY_STATE]
  * Tocar faixa ou URI no Spotify: [ACTION:SPOTIFY_PLAY:uri_ou_busca]
  * Listar playlists do Spotify: [ACTION:SPOTIFY_PLAYLISTS]
  * Adicionar faixa (ou música atual) a playlist: [ACTION:SPOTIFY_ADD_PLAYLIST:nome_ou_id_playlist|track_uri_opcional]
- Controlar PC / Desktop pareado via LAN (HMAC-SHA256 + timestamp + nonce):
  * Abrir app/jogo no PC: [ACTION:PC_OPEN_APP:chrome]
  * Status do PC: [ACTION:PC_STATUS]
  * Mídia do PC (play_pause|next|previous|stop|mute): [ACTION:PC_MEDIA:play_pause]
  * Copiar texto para clipboard do PC: [ACTION:PC_CLIPBOARD_PUSH:texto]
  * Ler clipboard do PC: [ACTION:PC_CLIPBOARD_PULL]
  * Executar skill no PC: [ACTION:PC_RUN_SKILL:nome_skill]
  * Proteção térmica e telemetria CPU/GPU/RAM do PC: [ACTION:PC_THERMAL]
  * Plano de energia do PC (high_performance|balanced|power_saver): [ACTION:PC_POWER_PLAN:high_performance]
  * Volume de app no PC (listar ou app:0-100): [ACTION:PC_APP_VOLUME:spotify:50]
  * Encerrar apps travados no PC: [ACTION:PC_KILL_FROZEN]
  * Executar backup incremental no PC: [ACTION:PC_BACKUP]
  * Limpar arquivos temporários/disco no PC: [ACTION:PC_CLEAN_DISK]
  * Ejetar armazenamento USB ocioso no PC: [ACTION:PC_EJECT_USB]
  * Despachar ferramenta Desktop v3.0.0: [ACTION:PC_EXEC_TOOL:nome_ferramenta|{"param":"valor"}]
''';

  Future<bool> setTorch(bool enabled) async {
    final res = await _channel.invokeMethod<bool>(
      'setTorch',
      {'enabled': enabled},
    );
    return res ?? enabled;
  }

  Future<bool> toggleTorch() async {
    final res = await _channel.invokeMethod<bool>('toggleTorch');
    return res ?? false;
  }

  Future<DeviceStatus> getStatus() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'getDeviceStatus',
    );
    return DeviceStatus.fromMap(raw ?? const {});
  }

  Future<int> setVolume(int percent) async {
    final res = await _channel.invokeMethod<int>(
      'setVolume',
      {'percent': percent.clamp(0, 100)},
    );
    return res ?? percent;
  }

  Future<int> adjustVolume(String direction) async {
    final res = await _channel.invokeMethod<int>(
      'adjustVolume',
      {'direction': direction},
    );
    return res ?? 50;
  }

  static const Set<String> supportedMediaActions = <String>{
    'play',
    'pause',
    'play_pause',
    'next',
    'previous',
    'stop',
  };

  /// Sends a verified media control command to the active Android MediaSession
  /// (Spotify, YouTube, players) and confirms whether playback state actually changed.
  Future<MediaControlResult> controlMediaDetailed(
    String action, {
    String preferredApp = '',
  }) async {
    final normalized = action.trim().toLowerCase();
    if (!supportedMediaActions.contains(normalized)) {
      throw ArgumentError.value(action, 'action', 'Ação de mídia inválida');
    }
    final raw = await _channel.invokeMethod<Object?>(
      'mediaControl',
      {
        'action': normalized,
        if (preferredApp.trim().isNotEmpty)
          'preferredApp': preferredApp.trim().toLowerCase(),
      },
    );
    if (raw is Map<Object?, Object?>) {
      return MediaControlResult.fromMap(raw);
    }
    if (raw == true) {
      return const MediaControlResult(
        status: MediaControlStatus.confirmed,
        confirmed: true,
      );
    }
    return const MediaControlResult(
      status: MediaControlStatus.noActiveSession,
      confirmed: false,
      detail: 'Nenhuma sessão de mídia ativa respondeu ao comando.',
    );
  }

  /// Sends an Android hardware media key event (`AudioManager.dispatchMediaKeyEvent`)
  /// to the active media session (Spotify, YouTube, players, podcasts).
  Future<bool> controlMedia(String action, {String preferredApp = ''}) async =>
      (await controlMediaDetailed(action, preferredApp: preferredApp))
          .confirmed;

  Future<void> vibrate({int durationMs = 200}) async {
    await _channel.invokeMethod<bool>(
      'vibrate',
      {'durationMs': durationMs},
    );
  }

  Future<void> openSystemSettings(String target) async {
    await _channel.invokeMethod<bool>(
      'openSystemSettings',
      {'target': target},
    );
  }

  Future<String> openApp(String target) async {
    final res = await _channel.invokeMethod<String>(
      'openApp',
      {'target': target},
    );
    return res ?? target;
  }

  Future<void> setAlarm({
    required int hour,
    required int minute,
    String message = 'U.L.T.R.O.N.',
  }) async {
    await _channel.invokeMethod<bool>('setAlarm', {
      'hour': hour,
      'minute': minute,
      'message': message,
    });
  }

  Future<void> setTimer({
    required int seconds,
    String message = 'U.L.T.R.O.N. Timer',
  }) async {
    await _channel.invokeMethod<bool>('setTimer', {
      'seconds': seconds,
      'message': message,
    });
  }

  Future<bool> openUrl(String url) async {
    final res = await _channel.invokeMethod<bool>('openUrl', {'url': url});
    return res ?? false;
  }

  Future<void> webSearch(String query) async {
    final encoded = Uri.encodeQueryComponent(query.trim());
    await openUrl('https://www.google.com/search?q=$encoded');
  }

  Future<void> dialNumber(String number) async {
    await _channel.invokeMethod<bool>('dialNumber', {'number': number});
  }

  Future<void> shareText(String text) async {
    await _channel.invokeMethod<bool>('shareText', {'text': text});
  }

  Future<String> listenVoice({
    String prompt = 'U.L.T.R.O.N. escutando (fale seu comando)...',
    String locale = 'pt-BR',
  }) async {
    final res = await _channel.invokeMethod<String>('listenVoice', {
      'prompt': prompt,
      'locale': locale,
    });
    return (res ?? '').trim();
  }

  Future<void> stopListeningVoice() async {
    try {
      await _channel.invokeMethod<bool>('stopListeningVoice');
    } catch (_) {}
  }

  Future<bool> isNotificationListenerEnabled() async {
    final res = await _channel.invokeMethod<bool>(
      'isNotificationListenerEnabled',
    );
    return res ?? false;
  }

  Future<void> openNotificationListenerSettings() async {
    await _channel.invokeMethod<bool>('openNotificationListenerSettings');
  }

  Future<List<CapturedNotification>> getRecentMessages({int limit = 20}) async {
    final raw = await _channel.invokeMethod<List<Object?>>(
      'getRecentMessages',
      {'limit': limit},
    );
    if (raw == null) return const [];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(CapturedNotification.fromMap)
        .toList();
  }

  Future<void> clearRecentMessages() async {
    await _channel.invokeMethod<bool>('clearRecentMessages');
  }

  Future<String> replyNotification({
    required String text,
    String target = '',
  }) async {
    final res = await _channel.invokeMethod<String>('replyNotification', {
      'target': target,
      'text': text,
    });
    return res ?? 'Resposta enviada.';
  }

  Future<String> sendWhatsApp({
    required String target,
    required String text,
  }) async {
    final res = await _channel.invokeMethod<String>('sendWhatsApp', {
      'target': target,
      'text': text,
    });
    return res ?? 'WhatsApp iniciado.';
  }

  Future<String> sendSms({
    required String target,
    required String text,
  }) async {
    final res = await _channel.invokeMethod<String>('sendSms', {
      'target': target,
      'text': text,
    });
    return res ?? 'SMS iniciado.';
  }

  Future<bool> requestContactsPermission() async {
    final res = await _channel.invokeMethod<bool>('requestContactsPermission');
    return res ?? false;
  }

  /// Lê compromissos da agenda Android (`CalendarContract.Instances`).
  Future<List<CalendarEvent>> getCalendarEvents({
    DateTime? from,
    DateTime? to,
    int daysAhead = 1,
    int limit = 20,
  }) async {
    final base = from ?? DateTime.now();
    final start = from ?? DateTime(base.year, base.month, base.day);
    final safeDays = daysAhead.clamp(1, 30);
    final end = to ??
        DateTime(start.year, start.month, start.day)
            .add(Duration(days: safeDays));
    final raw = await _channel.invokeListMethod<Object?>(
      'getCalendarEvents',
      {
        'startMs': start.millisecondsSinceEpoch,
        'endMs': end.millisecondsSinceEpoch,
        'limit': limit.clamp(1, 50),
      },
    );
    if (raw == null || raw.isEmpty) return const [];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(CalendarEvent.fromMap)
        .toList();
  }

  /// Cria um evento na agenda Android (`CalendarContract.Events`).
  Future<Map<String, dynamic>> createCalendarEvent({
    required String title,
    required DateTime startTime,
    DateTime? endTime,
    String description = '',
    String location = '',
    bool allDay = false,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw ArgumentError('Título do evento não pode ser vazio.');
    }
    final resolvedEnd = endTime != null && endTime.isAfter(startTime)
        ? endTime
        : startTime.add(const Duration(hours: 1));
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'createCalendarEvent',
      {
        'title': cleanTitle,
        'startMs': startTime.millisecondsSinceEpoch,
        'endMs': resolvedEnd.millisecondsSinceEpoch,
        'description': description.trim(),
        'location': location.trim(),
        'allDay': allDay,
      },
    );
    return (raw ?? const {}).map(
      (k, v) => MapEntry(k.toString(), v),
    );
  }

  /// Remove um evento da agenda Android (`CalendarContract.Events`) por ID ou título.
  Future<Map<String, dynamic>> cancelCalendarEvent({
    String eventId = '',
    String title = '',
  }) async {
    final cleanId = eventId.trim();
    final cleanTitle = title.trim();
    if (cleanId.isEmpty && cleanTitle.isEmpty) {
      throw ArgumentError('Informe o ID ou título do evento para cancelar.');
    }
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'deleteCalendarEvent',
      {
        'eventId': cleanId,
        'title': cleanTitle,
      },
    );
    return (raw ?? const {}).map(
      (k, v) => MapEntry(k.toString(), v),
    );
  }

  /// OBSIDIAN_LIST: Lista notas Markdown do cofre por pasta (`Diario/`, `Memoria/`, `Inbox/`, `Skills/`).
  Future<List<ObsidianNoteSummary>> listObsidianNotes({String? folder}) async {
    final vault = await _getObsidian();
    return vault.listNotes(folder: folder);
  }

  /// OBSIDIAN_READ: Lê conteúdo de uma nota específica com sanitização contra path traversal.
  Future<String> readObsidianNote(String notePath) async {
    final vault = await _getObsidian();
    return vault.readNote(notePath);
  }

  /// OBSIDIAN_APPEND: Anexa texto a uma nota existente (ou cria se [createIfMissing] for true).
  Future<File> appendObsidianNote(
    String notePath,
    String text, {
    bool createIfMissing = false,
  }) async {
    final vault = await _getObsidian();
    final file = await vault.appendToNote(
      notePath,
      text,
      createIfMissing: createIfMissing,
    );
    invalidateVaultSearchCache();
    return file;
  }

  /// OBSIDIAN_TASKS: Lista checkboxes Markdown (`- [ ]` / `- [x]`) do cofre.
  Future<List<ObsidianTaskItem>> listObsidianTasks({
    String? notePath,
    bool? onlyCompleted,
  }) async {
    final vault = await _getObsidian();
    return vault.listTasks(
      notePath: notePath,
      onlyCompleted: onlyCompleted,
    );
  }

  /// OBSIDIAN_TASKS: Marca ou desmarca uma tarefa Markdown (`- [ ]` <-> `- [x]`).
  Future<ObsidianTaskItem> toggleObsidianTask({
    String? notePath,
    int? taskIndex,
    String? queryText,
    bool? completed,
  }) async {
    final vault = await _getObsidian();
    final updated = await vault.setTaskCompletion(
      notePath: notePath,
      taskIndex: taskIndex,
      queryText: queryText,
      completed: completed,
    );
    invalidateVaultSearchCache();
    return updated;
  }

  /// OBSIDIAN_STATUS: Retorna estatísticas do cofre e engine de busca ativa.
  Future<ObsidianVaultStatus> getObsidianStatus() async {
    final vault = await _getObsidian();
    var engine = VaultSearchEngine.fts5;
    try {
      final search = await _getVaultSearch();
      engine = search.engine;
    } catch (_) {}
    return vault.getVaultStatus(searchEngine: engine);
  }

  /// UNDO: Desfaz a última operação mutável no cofre Obsidian.
  Future<ObsidianUndoResult> undoLastObsidianMutation() async {
    final vault = await _getObsidian();
    final res = await vault.undoLastMutation();
    if (res.undone) {
      invalidateVaultSearchCache();
    }
    return res;
  }

  /// REMINDER_CREATE: Cria lembrete persistente em SQLite + alarme local nativo (`AlarmManager`).
  Future<ReminderItem> createReminder({
    required String title,
    required DateTime scheduledAt,
    DateTime? now,
  }) async {
    final svc = await _getReminderServiceOrNull();
    if (svc == null) {
      throw StateError('Serviço de lembretes indisponível neste ambiente.');
    }
    return svc.createReminder(
      title: title,
      scheduledAt: scheduledAt,
      now: now,
    );
  }

  /// REMINDER_LIST: Lista lembretes pendentes (ou todos).
  Future<List<ReminderItem>> listReminders({bool onlyPending = true}) async {
    final svc = await _getReminderServiceOrNull();
    if (svc == null) return const [];
    return svc.listReminders(onlyPending: onlyPending);
  }

  /// REMINDER_CANCEL: Cancela lembrete por ID ou trecho do título.
  Future<ReminderItem?> cancelReminder(String idOrQuery) async {
    final svc = await _getReminderServiceOrNull();
    if (svc == null) return null;
    return svc.cancelReminder(idOrQuery);
  }

  /// Expõe o serviço de coleta web (clima, RSS e pesquisa resumida).
  WebInfoService getWebInfoService() => _getWebInfo();

  /// WEATHER: Consulta isolada de clima reutilizando `BriefingService.fetchWeather()`.
  Future<WeatherSnapshot?> fetchWeather({String? city}) =>
      _getWebInfo().fetchWeather(city: city);

  /// NEWS: Consulta manchetes de notícias via feeds RSS públicos.
  Future<List<NewsArticle>> fetchNews({String topic = '', int limit = 5}) =>
      _getWebInfo().fetchNews(topic: topic, limit: limit);

  /// WEB_SEARCH: Consulta textual resumida na web sem abrir o navegador.
  Future<WebSearchSummary> searchWebSummary(String query, {int limit = 4}) =>
      _getWebInfo().searchWebSummary(query, limit: limit);

  /// SKILL_CREATE: Cria ou atualiza uma Skill em `Skills/<nome>.md`.
  Future<MobileSkill> createObsidianSkill(String name, String content) async {
    final vault = await _getObsidian();
    final skill = await vault.createSkill(name, content);
    invalidateVaultSearchCache();
    return skill;
  }

  /// SKILL_DELETE: Remove uma Skill de `Skills/<nome>.md`.
  Future<bool> deleteObsidianSkill(String name) async {
    final vault = await _getObsidian();
    final deleted = await vault.deleteSkill(name);
    if (deleted) {
      invalidateVaultSearchCache();
    }
    return deleted;
  }

  /// FLOW_CREATE: Cria ou atualiza um fluxo encadeado no `WorkflowSchedulerService`.
  Future<WorkflowDefinition> createWorkflow({
    required String name,
    required String stepsPayload,
    String scheduleSpec = '',
  }) async {
    final svc = await _getWorkflowSchedulerOrNull();
    if (svc == null) {
      throw StateError('Agendador de fluxos indisponível neste ambiente.');
    }
    return svc.createFlow(
      name: name,
      stepsPayload: stepsPayload,
      scheduleSpec: scheduleSpec,
    );
  }

  /// FLOW_SCHEDULE: Agenda ou reagenda um fluxo existente.
  Future<WorkflowDefinition> scheduleWorkflow({
    required String nameOrId,
    required String scheduleSpec,
  }) async {
    final svc = await _getWorkflowSchedulerOrNull();
    if (svc == null) {
      throw StateError('Agendador de fluxos indisponível neste ambiente.');
    }
    return svc.scheduleFlow(nameOrId: nameOrId, scheduleSpec: scheduleSpec);
  }

  /// FLOW_LIST: Lista fluxos cadastrados.
  Future<List<WorkflowDefinition>> listWorkflows() async {
    final svc = await _getWorkflowSchedulerOrNull();
    if (svc == null) return const [];
    return svc.listFlows();
  }

  /// FLOW_DELETE: Exclui um fluxo e cancela seu alarme nativo.
  Future<WorkflowDefinition?> deleteWorkflow(String nameOrId) async {
    final svc = await _getWorkflowSchedulerOrNull();
    if (svc == null) return null;
    return svc.deleteFlow(nameOrId);
  }

  /// FLOW_RUN: Executa um fluxo validando cada passo pelo `AuthGate` e `ActionGate`.
  Future<WorkflowExecutionResult> runWorkflow(
    String nameOrId, {
    ActionGateConfirmCallback? confirmAction,
    bool isBackgroundTrigger = false,
  }) async {
    final svc = await _getWorkflowSchedulerOrNull();
    if (svc == null) {
      throw StateError('Agendador de fluxos indisponível neste ambiente.');
    }
    final res = await svc.runFlow(
      nameOrId,
      authGate: authGate,
      isBackgroundTrigger: isBackgroundTrigger,
      executor: (stepsPayload, {required isBackgroundTrigger}) async {
        // Em disparo em 2º plano sem UI, nunca exibe prompt interativo (fail-closed)
        final exec = await executeAiActions(
          stepsPayload,
          confirmAction: isBackgroundTrigger ? null : confirmAction,
          actor: isBackgroundTrigger ? 'FLOW_BG' : 'FLOW_RUN',
        );
        return exec.executedLogs;
      },
    );
    await recordAudit(
      actor: isBackgroundTrigger ? 'FLOW_BG' : 'FLOW_RUN',
      action: 'FLOW_RUN',
      target: res.flowName,
      status: res.blockedByAuthGate
          ? 'DENIED'
          : (res.executed ? 'EXECUTED' : 'FAILED'),
      detail: res.message,
    );
    return res;
  }

  /// Consome IDs de fluxos disparados pelo `WorkflowAlarmReceiver` em 2º plano.
  Future<List<int>> consumePendingWorkflowIds() async {
    try {
      final raw =
          await _channel.invokeListMethod<Object?>('consumePendingWorkflowIds');
      if (raw == null) return const [];
      return raw.whereType<num>().map((n) => n.toInt()).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Extrai data, horário e título de instruções naturais como
  /// `"agendar reunião com Carlos amanhã às 15:30"` ou `"marcar 2026-11-20 09:00 Daily"`.
  static ParsedCalendarDraft? parseNaturalCalendarEvent(
    String rawText, {
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    var body = rawText.trim();
    body = body
        .replaceFirst(
          RegExp(
            r'^(?:ultron[,\s]+)?(?:agendar|marcar|criar|adicionar)\s+(?:(?:um|uma)\s+)?(?:(?:novo\s+)?evento|compromisso|lembrete\s+na\s+agenda)?\s*:?\s*',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    if (body.isEmpty) return null;

    var targetDate = DateTime(ref.year, ref.month, ref.day);
    var dateMatched = false;

    final isoDate = RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b').firstMatch(body);
    if (isoDate != null) {
      final y = int.parse(isoDate.group(1)!);
      final m = int.parse(isoDate.group(2)!);
      final d = int.parse(isoDate.group(3)!);
      targetDate = DateTime(y, m, d);
      body = body.replaceRange(isoDate.start, isoDate.end, ' ');
      dateMatched = true;
    } else {
      final brDate =
          RegExp(r'\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b').firstMatch(body);
      if (brDate != null) {
        final d = int.parse(brDate.group(1)!);
        final m = int.parse(brDate.group(2)!);
        var y = ref.year;
        if (brDate.group(3) != null) {
          final parsedY = int.parse(brDate.group(3)!);
          y = parsedY < 100 ? 2000 + parsedY : parsedY;
        }
        targetDate = DateTime(y, m, d);
        body = body.replaceRange(brDate.start, brDate.end, ' ');
        dateMatched = true;
      } else {
        final afterTomorrow = RegExp(
          r'(?:^|\s)(?:para\s+)?depois\s+de\s+amanh[aã](?=\s|$)',
          caseSensitive: false,
        );
        final tomorrow = RegExp(
          r'(?:^|\s)(?:para\s+)?amanh[aã](?=\s|$)',
          caseSensitive: false,
        );
        final today = RegExp(
          r'(?:^|\s)(?:para\s+)?hoje(?=\s|$)',
          caseSensitive: false,
        );
        if (afterTomorrow.hasMatch(body)) {
          targetDate = targetDate.add(const Duration(days: 2));
          body = body.replaceAll(afterTomorrow, ' ');
          dateMatched = true;
        } else if (tomorrow.hasMatch(body)) {
          targetDate = targetDate.add(const Duration(days: 1));
          body = body.replaceAll(tomorrow, ' ');
          dateMatched = true;
        } else if (today.hasMatch(body)) {
          body = body.replaceAll(today, ' ');
          dateMatched = true;
        }
      }
    }

    int? hour;
    int minute = 0;
    final timeMatch = RegExp(
      r'(?:(?:^|\s)(?:para\s+)?(?:[àa]s?|as)\s+|\b)(\d{1,2})(?:[:h](\d{2})|h)(?:\s*h(?:oras?)?)?(?=\s|$)',
      caseSensitive: false,
    ).firstMatch(body);
    if (timeMatch != null) {
      final h = int.tryParse(timeMatch.group(1)!);
      final min =
          timeMatch.group(2) != null ? int.tryParse(timeMatch.group(2)!) : 0;
      if (h != null &&
          h >= 0 &&
          h <= 23 &&
          min != null &&
          min >= 0 &&
          min <= 59) {
        hour = h;
        minute = min;
        body = body.replaceRange(timeMatch.start, timeMatch.end, ' ');
      }
    }

    if (hour == null) {
      final fallbackStart = dateMatched
          ? DateTime(targetDate.year, targetDate.month, targetDate.day, 9, 0)
          : ref.add(const Duration(hours: 1));
      hour = fallbackStart.hour;
      minute = dateMatched ? 0 : fallbackStart.minute;
    }

    var start = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
      hour,
      minute,
    );
    if (!dateMatched && !start.isAfter(ref)) {
      start = start.add(const Duration(days: 1));
    }

    final cleanTitle = body
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceFirst(RegExp(r'^[-:,\s]+'), '')
        .replaceFirst(RegExp(r'[-:,\s]+$'), '')
        .trim();
    if (cleanTitle.isEmpty) return null;

    return ParsedCalendarDraft(
      title: cleanTitle,
      startTime: start,
      endTime: start.add(const Duration(hours: 1)),
    );
  }

  Future<bool> isAudioSentinelRunning() async {
    final res = await _channel.invokeMethod<bool>('isAudioSentinelRunning');
    return res ?? false;
  }

  Future<bool> setAudioSentinel(bool enabled) async {
    final res = await _channel.invokeMethod<bool>('setAudioSentinel', {
      'enabled': enabled,
    });
    return res ?? false;
  }

  /// Wake word detectada enquanto o app estava fechado/bloqueado (válida por 30 s), ou null.
  Future<String?> consumePendingWakeWord() async {
    try {
      final res = await _channel.invokeMethod<String>('consumePendingWakeWord');
      return (res == null || res.trim().isEmpty) ? null : res;
    } catch (_) {
      return null;
    }
  }

  /// Estado do sentinela de voz para o painel de diagnóstico (v1.2.1).
  Future<WakeWordDiagnostics> getWakeWordDiagnostics() async {
    try {
      final raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('getWakeWordDiagnostics');
      return WakeWordDiagnostics.fromMap(raw ?? const {});
    } catch (_) {
      return const WakeWordDiagnostics();
    }
  }

  Future<bool> setBootAutostart(bool enabled) async {
    final res = await _channel.invokeMethod<bool>('setBootAutostart', {
      'enabled': enabled,
    });
    return res ?? false;
  }

  /// Abre o diálogo do sistema para isentar o app da economia de bateria.
  /// Retorna true se o app já estiver isento.
  Future<bool> requestIgnoreBatteryOptimizations() async {
    final res =
        await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
    return res ?? false;
  }

  Future<WakeWordProfile> getWakeWordProfile() async {
    try {
      final raw = await _channel.invokeMethod<String>('getWakeWordProfile');
      final profile = WakeWordProfile.fromId(raw);
      WakeWord.setActiveProfile(profile);
      return profile;
    } catch (_) {
      return WakeWord.activeProfile;
    }
  }

  Future<WakeWordProfile> setWakeWordProfile(WakeWordProfile profile) async {
    WakeWord.setActiveProfile(profile);
    try {
      await _channel.invokeMethod<Object?>('setWakeWordProfile', {
        'profile': profile.id,
      });
    } catch (_) {}
    return profile;
  }

  Future<bool> isFloatingOrbRunning() async {
    try {
      final res = await _channel.invokeMethod<bool>('isFloatingOrbRunning');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setFloatingOrb(bool enabled) async {
    try {
      final res = await _channel.invokeMethod<bool>('setFloatingOrb', {
        'enabled': enabled,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> updateFloatingOrbState(String state) async {
    try {
      await _channel.invokeMethod<bool>('updateFloatingOrbState', {
        'state': state,
      });
    } catch (_) {}
  }

  Future<void> syncFloatingOrbAuthState({
    required bool locked,
    required String accessLevel,
  }) async {
    try {
      await _channel.invokeMethod<bool>('setFloatingOrbAuthState', {
        'locked': locked,
        'accessLevel': accessLevel,
      });
    } catch (_) {}
  }

  Future<({bool triggered, bool requiresUnlock})?>
      consumePendingFloatingOrbTap() async {
    try {
      final raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('consumePendingFloatingOrbTap');
      if (raw == null || raw['triggered'] != true) return null;
      return (
        triggered: true,
        requiresUnlock: (raw['requiresUnlock'] as bool?) ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> isDynamicIslandRunning() async {
    try {
      final res = await _channel.invokeMethod<bool>('isDynamicIslandRunning');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setDynamicIsland(bool enabled) async {
    try {
      final res = await _channel.invokeMethod<bool>('setDynamicIsland', {
        'enabled': enabled,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> updateDynamicIslandState({
    required String mode,
    String title = '',
    String detail = '',
  }) async {
    try {
      await _channel.invokeMethod<bool>('updateDynamicIslandState', {
        'mode': mode,
        'title': title,
        'detail': detail,
      });
    } catch (_) {}
  }

  Future<void> setDynamicIslandAccent(int colorArgb) async {
    try {
      await _channel.invokeMethod<bool>('setDynamicIslandAccent', {
        'colorArgb': colorArgb,
      });
    } catch (_) {}
  }

  OpenGymService getOpenGymService() => OpenGymService(channel: _channel);

  static const String longTermProfileNotePath =
      'Memoria/Sessoes/Contexto_Longo_Prazo.md';

  /// Salva fatos/preferências duradouros extraídos de conversas no Obsidian
  /// (com deduplicação) para enriquecer respostas de sessões futuras.
  Future<int> persistLongTermSessionFacts(List<String> facts) async {
    if (facts.isEmpty) return 0;
    try {
      final vault = await _getObsidian();
      await vault.initialize();
      var existing = '';
      try {
        existing = await vault.readNote(longTermProfileNotePath);
      } catch (_) {}
      final existingLower = existing.toLowerCase();
      final toAdd = <String>[];
      for (final fact in facts) {
        final clean = fact.trim();
        if (clean.length < 12) continue;
        if (existingLower.contains(clean.toLowerCase())) continue;
        toAdd.add(clean);
      }
      if (toAdd.isEmpty) return 0;
      final now = DateTime.now();
      final stamp =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final block = toAdd.map((f) => '- [$stamp] $f').join('\n');
      await vault.appendToNote(
        longTermProfileNotePath,
        existing.trim().isEmpty
            ? '# Contexto de Longo Prazo do Operador\n\n$block\n'
            : '$block\n',
        createIfMissing: true,
      );
      _cachedVaultSearch?.invalidateSyncCache();
      return toAdd.length;
    } catch (_) {
      return 0;
    }
  }

  Future<DeviceActionResult> executeDjCommand(
    String rawArg, {
    TacticalMode mode = TacticalMode.musica,
    bool nightFocusMode = false,
    ActionGateConfirmCallback? confirmAction,
  }) async {
    const curator = MusicCuratorService();
    final arg = rawArg.trim();
    final lower = arg.toLowerCase();

    if (lower == 'players' || lower == 'apps' || lower == 'controladores') {
      return DeviceActionResult(
        handled: true,
        message: curator.formatSupportedPlayersList(),
        speakText:
            'Integro Spotify, YouTube Music, Deezer, Apple Music, SoundCloud, Tidal, Poweramp, VLC, djay, edjing, Cross DJ, rekordbox, Traktor, Serato e VirtualDJ.',
      );
    }

    final camelotMatch = RegExp(
      r'^(?:transi[cç][aã]o|camelot|tom|chave)\s+(1[0-2]|[1-9])([ab])$',
      caseSensitive: false,
    ).firstMatch(arg);
    if (camelotMatch != null) {
      final key =
          '${camelotMatch.group(1)}${camelotMatch.group(2)!.toUpperCase()}';
      final compat = MusicCuratorService.compatibleCamelotKeys(key);
      return DeviceActionResult(
        handled: true,
        message: 'Mixagem Harmônica (Roda de Camelot) — Chave $key:\n'
            '${compat.map((k) => '• $k').join('\n')}',
        speakText: 'Para a chave $key, as transições harmônicas são ${compat.take(4).join(', ')}.',
      );
    }

    if (lower.startsWith('pc ')) {
      final appName = arg.substring(3).trim();
      if (appName.isNotEmpty) {
        final res = await sendDesktopBridgeCommand(
          command: 'PC_OPEN_APP',
          args: <String, dynamic>{'app': appName},
          confirmAction: confirmAction,
        );
        return DeviceActionResult(
          handled: true,
          message: res.sent
              ? 'Comando enviado ao Desktop LAN para abrir $appName.'
              : 'Não foi possível abrir $appName no PC (${res.error ?? 'Desktop não pareado ou ação cancelada'}).',
          speakText: res.sent
              ? 'Abrindo $appName no computador.'
              : 'Não consegui abrir $appName no computador.',
        );
      }
    }

    final shouldSave = lower.startsWith('salvar ') || lower == 'salvar';
    final effectiveQuery =
        shouldSave ? arg.replaceFirst(RegExp(r'^salvar\s*', caseSensitive: false), '') : arg;

    var plan = curator.curate(
      effectiveQuery,
      mode: mode,
      nightFocusMode: nightFocusMode,
    );
    if (shouldSave) {
      try {
        final vault = await _getObsidian();
        plan = await curator.saveSetlistToObsidian(plan, vault);
        _cachedVaultSearch?.invalidateSyncCache();
      } catch (_) {}
    }
    return DeviceActionResult(
      handled: true,
      message: plan.formatChatOutput(),
      speakText: plan.speakText,
    );
  }

  Future<DeviceActionResult> executeOpenGymCommand(String rawArg) async {
    final arg = rawArg.trim();
    final lower = arg.toLowerCase();

    if (lower == 'abrir' || lower == 'open' || lower == 'app') {
      try {
        final label = await openApp('opengym');
        return DeviceActionResult(
          handled: true,
          message: 'Abrindo $label (ch.duartesantos.opengym).',
          speakText: 'Abrindo OpenGym.',
        );
      } catch (e) {
        return DeviceActionResult(
          handled: true,
          message:
              'Não encontrei o app openGym instalado (ch.duartesantos.opengym). Detalhe: $e',
          speakText: 'Não encontrei o aplicativo OpenGym instalado.',
        );
      }
    }

    if (lower == 'resumo' || lower == 'status' || lower == 'prs' || lower == 'pr') {
      try {
        final vault = await _getObsidian();
        final content = await vault.readNote(OpenGymService.summaryNotePath);
        if (content.trim().isEmpty) {
          return const DeviceActionResult(
            handled: true,
            message:
                'Nenhum backup do openGym importado ainda. Use `/opengym importar` para escolher o JSON/CSV exportado do app openGym.',
            speakText: 'Nenhum backup do OpenGym foi importado ainda.',
          );
        }
        return DeviceActionResult(
          handled: true,
          message: content,
          speakText: 'Aqui está o resumo mais recente do OpenGym salvo no Modo Treino.',
        );
      } catch (_) {
        return const DeviceActionResult(
          handled: true,
          message:
              'Nenhum resumo do openGym encontrado em `${OpenGymService.summaryNotePath}`. '
              'Exporte o backup JSON/CSV dentro do app openGym e execute `/opengym importar`.',
          speakText:
              'Nenhum resumo do OpenGym encontrado. Exporte o backup no OpenGym e use importar.',
        );
      }
    }

    final openGym = getOpenGymService();
    File? sourceFile;
    if (arg.isNotEmpty &&
        lower != 'importar' &&
        lower != 'import' &&
        lower != 'sync' &&
        lower != 'sincronizar' &&
        lower != 'auto') {
      final direct = File(arg);
      if (await direct.exists()) {
        sourceFile = direct;
      }
    }

    if (sourceFile == null) {
      if (lower == 'auto') {
        sourceFile = await openGym.findLatestLocalBackup();
      } else {
        sourceFile = await openGym.pickBackupFileSaf() ??
            await openGym.findLatestLocalBackup();
      }
    }

    if (sourceFile == null) {
      return const DeviceActionResult(
        handled: true,
        message:
            'Nenhum arquivo de backup do openGym selecionado ou encontrado em Downloads.\n'
            'Como sincronizar offline:\n'
            '1. Abra o openGym > Configurações > Exportar backup JSON (`opengym-state.json`) ou CSV.\n'
            '2. Execute `/opengym importar` (ou `/opengym auto` após salvar em Downloads).',
        speakText:
            'Nenhum backup do OpenGym selecionado. Exporte o JSON ou CSV no OpenGym e tente novamente.',
      );
    }

    try {
      final vault = await _getObsidian();
      final summary = await openGym.importFile(sourceFile, obsidian: vault);
      _cachedVaultSearch?.invalidateSyncCache();
      await recordAudit(
        actor: 'OPERATOR',
        action: 'OPENGYM_IMPORT',
        target: summary.savedNotePath ?? sourceFile.path,
        status: summary.isEmpty ? 'EMPTY' : 'EXECUTED',
        detail:
            'workouts=${summary.workouts.length}, prs=${summary.personalRecords.length}, weights=${summary.weightEntries.length}',
      );
      return DeviceActionResult(
        handled: true,
        message: summary.formatChatSummary(),
        speakText: summary.speakText,
      );
    } catch (e) {
      return DeviceActionResult(
        handled: true,
        message: 'Falha ao importar backup do openGym: $e',
        speakText: 'Falha ao ler o arquivo do OpenGym.',
      );
    }
  }

  Future<bool> canDrawOverlays() async {
    try {
      final res = await _channel.invokeMethod<bool>('canDrawOverlays');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestOverlayPermission() async {
    try {
      final res = await _channel.invokeMethod<bool>('requestOverlayPermission');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<String> speakOfflineFishVoice(String text) async {
    final res = await _channel.invokeMethod<String>('speakOfflineFishVoice', {
      'text': text,
    });
    return res ?? text;
  }

  /// Sincroniza com o serviço nativo em 2º plano (criptografado no Keystore) as
  /// credenciais de STT não-Google, IA e Fish Audio para responder com app fechado.
  Future<void> syncBackgroundVoiceConfig({
    required String sttUrl,
    required String sttKey,
    required String sttModel,
    required String sttLanguage,
    required String aiBaseUrl,
    required String aiKey,
    required String aiModel,
    required bool fishEnabled,
    required String fishKey,
    required String fishRefId,
    required String fishLanguage,
    required String fishModel,
    required bool whisperMode,
    String? wakeWordProfile,
    List<Map<String, String>>? recentHistory,
  }) async {
    try {
      await _channel.invokeMethod<bool>('syncBackgroundVoiceConfig', {
        'sttUrl': sttUrl,
        'sttKey': sttKey,
        'sttModel': sttModel,
        'sttLanguage': sttLanguage,
        'aiBaseUrl': aiBaseUrl,
        'aiKey': aiKey,
        'aiModel': aiModel,
        'fishEnabled': fishEnabled,
        'fishKey': fishKey,
        'fishRefId': fishRefId,
        'fishLanguage': fishLanguage,
        'fishModel': fishModel,
        'whisperMode': whisperMode,
        'wakeWordProfile': wakeWordProfile ?? WakeWord.activeProfile.id,
        if (recentHistory != null) 'recentHistory': recentHistory,
      });
    } catch (_) {}
  }

  /// Consome turnos de conversa executados em 2º plano pelo serviço nativo
  /// para salvar no histórico criptografado (SQLCipher) e atualizar o chat.
  Future<List<BackgroundConversationTurn>>
      consumePendingBackgroundTurns() async {
    try {
      final raw = await _channel.invokeListMethod<Object?>(
        'consumePendingBackgroundTurns',
      );
      if (raw == null || raw.isEmpty) return const [];
      return raw
          .whereType<Map<Object?, Object?>>()
          .map(BackgroundConversationTurn.fromMap)
          .where((t) => t.userText.isNotEmpty && t.assistantText.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static final RegExp _trailingCourtesyRegex = RegExp(
    r'(?:\s+(?:para\s+mim|pra\s+mim|por\s+favor|por\s+gentileza|pfv|aqui|a[ií]|agora|r[aá]pido|logo|se\s+puder|se\s+conseguir|por\s+obs[eé]quio|ok|t[aá]|viu|ultron))+$',
    caseSensitive: false,
  );

  static String _stripCourtesyPhrasing(String input) {
    var current = input.trim().replaceFirst(RegExp(r'[.!?,;:]+$'), '').trim();
    final leading = <RegExp>[
      RegExp(
        r'^(?:(?:ei|oi|ol[aá]|ok|e\s*a[ií]|fala)\s+)?ultron[,\s]+',
        caseSensitive: false,
      ),
      RegExp(
        r'^(?:por\s+favor|pfv|por\s+gentileza)[,\s]+',
        caseSensitive: false,
      ),
      RegExp(
        r'^(?:voc[eê]|vc)\s+(?:pode|poderia|consegue)\s+',
        caseSensitive: false,
      ),
      RegExp(
        r'^(?:pode|poderia|consegue|tem\s+como|faz\s+o\s+favor\s+de|quero\s+que(?:\s+voc[eê]|\s+vc)?)\s+',
        caseSensitive: false,
      ),
    ];
    String prev;
    do {
      prev = current;
      for (final p in leading) {
        current = current.replaceFirst(p, '').trim();
      }
      current = current.replaceFirst(_trailingCourtesyRegex, '').trim();
    } while (current != prev && current.isNotEmpty);
    return current;
  }

  /// Parses direct natural-language hardware commands so they execute immediately
  /// with zero latency and even without internet/API keys.
  Future<DeviceActionResult?> tryExecuteNaturalCommand(
    String rawInput, {
    ActionGateConfirmCallback? confirmAction,
  }) async {
    final text = _stripCourtesyPhrasing(rawInput);
    if (text.isEmpty) return null;
    final lower = text.toLowerCase();

    // Frases compostas / multi-intenção seguem para a IA executar todas as ações com contexto.
    if (RegExp(
      r'\b(?:e\s+(?:tamb[eé]m|depois|j[aá]|me|liga|desliga|abre|abra|aumenta|diminui|abaixa|pausa|toca|coloca|bota|manda|envia|v[eê]|veja|leia)|ent[aã]o|mas\s|antes\s+de|depois\s+de)\b',
    ).hasMatch(lower)) {
      return null;
    }

    try {
      // 0. Atalhos locais Zero-LLM (hora local, data, clima/temperatura, notícias e temperatura do PC)
      if (RegExp(
        r'^(?:que\s+horas?\s+s[aã]o|qual\s+(?:[eé]\s+)?a\s+hora|me\s+(?:diz|fala|informe)\s+as?\s+horas?|horas?\s+agora|que\s+hora\s+[eé]\s+agora)\??$',
      ).hasMatch(lower)) {
        try {
          final nativeReply = await speakOfflineFishVoice('que horas são');
          if (nativeReply.trim().isNotEmpty) {
            return DeviceActionResult(
              handled: true,
              message: '🔊 [Voz Offline Fish Audio + TTS Nativo]: $nativeReply',
            );
          }
        } catch (_) {
          // Fallback puro em Dart (0 ms, sem LLM) se canal nativo estiver indisponível.
        }
        final now = DateTime.now();
        final hh = now.hour.toString().padLeft(2, '0');
        final mm = now.minute.toString().padLeft(2, '0');
        final spoken = now.minute == 0
            ? 'São exatamente ${now.hour} horas.'
            : 'Agora são ${now.hour} horas e ${now.minute} minutos.';
        return DeviceActionResult(
          handled: true,
          message: 'Horário local: $hh:$mm.',
          speakText: spoken,
        );
      }

      if (RegExp(
        r'^(?:que\s+dia\s+[eé]\s+hoje|qual\s+(?:[eé]\s+)?a\s+data(?:\s+de\s+hoje)?|hoje\s+[eé]\s+que\s+dia)\??$',
      ).hasMatch(lower)) {
        final now = DateTime.now();
        const weekdays = <String>[
          'segunda-feira',
          'terça-feira',
          'quarta-feira',
          'quinta-feira',
          'sexta-feira',
          'sábado',
          'domingo',
        ];
        const months = <String>[
          'janeiro',
          'fevereiro',
          'março',
          'abril',
          'maio',
          'junho',
          'julho',
          'agosto',
          'setembro',
          'outubro',
          'novembro',
          'dezembro',
        ];
        final wd = weekdays[now.weekday - 1];
        final mo = months[now.month - 1];
        final sentence = 'Hoje é $wd, ${now.day} de $mo de ${now.year}.';
        return DeviceActionResult(
          handled: true,
          message: sentence,
          speakText: sentence,
        );
      }

      if (RegExp(
        r'\b(?:temperatura|termico|t[eé]rmico|cpu|gpu)\b.*\b(?:pc|computador|desktop)\b|\b(?:pc|computador|desktop)\b.*\b(?:temperatura|quente|cpu|gpu)\b',
      ).hasMatch(lower)) {
        final pcRes = await sendDesktopBridgeCommand(
          command: 'PC_TEMP',
          args: const <String, dynamic>{'tool': 'verificar_protecao_termica'},
          confirmAction: confirmAction,
        );
        final msg = pcRes.sent
            ? ((pcRes.responseBody ?? '').trim().isNotEmpty
                ? pcRes.responseBody!.trim()
                : 'Temperatura do PC consultada via ponte LAN.')
            : 'Não foi possível ler a temperatura do PC: ${pcRes.error ?? 'Desktop não pareado ou offline'}.';
        return DeviceActionResult(
          handled: true,
          message: msg,
          speakText: msg,
        );
      }

      final weatherMatch = RegExp(
        r'^(?:qual\s+(?:[eé]\s+)?a\s+temperatura|como\s+est[aá]\s+o\s+(?:clima|tempo)|previs[aã]o\s+do\s+tempo|vai\s+chover(?:\s+hoje)?)(?:\s+(?:hoje|agora))?(?:\s+(?:em|de|no|na)\s+(.+))?\??$',
      ).firstMatch(lower);
      if (weatherMatch != null) {
        final city = weatherMatch.group(1)?.trim();
        final snap = await fetchWeather(
          city: (city == null || city.isEmpty) ? null : city,
        );
        if (snap != null) {
          return DeviceActionResult(
            handled: true,
            message: snap.summaryLine,
            speakText: snap.spokenLine,
          );
        }
        return const DeviceActionResult(
          handled: true,
          message: 'Não consegui consultar o clima agora. Verifique a conexão.',
          speakText: 'Não consegui consultar o clima agora.',
        );
      }

      final newsMatch = RegExp(
        r'^(?:quais\s+(?:s[aã]o\s+)?as\s+not[ií]cias|[uú]ltimas\s+not[ií]cias|me\s+(?:d[eê]|conte|leia)\s+as\s+not[ií]cias)(?:\s+(?:de\s+hoje|hoje))?(?:\s+(?:sobre|de)\s+(.+))?\??$',
      ).firstMatch(lower);
      if (newsMatch != null) {
        final topic = newsMatch.group(1)?.trim() ?? '';
        final articles = await fetchNews(topic: topic, limit: 4);
        if (articles.isNotEmpty) {
          final header = topic.isEmpty
              ? 'Últimas notícias:'
              : 'Notícias sobre $topic:';
          final lines = articles.map((a) => a.formatLine()).join('\n');
          final spoken = articles.take(3).map((a) => a.title).join('. ');
          return DeviceActionResult(
            handled: true,
            message: '$header\n$lines',
            speakText: '$header $spoken.',
          );
        }
        return const DeviceActionResult(
          handled: true,
          message: 'Nenhuma manchete disponível no momento.',
          speakText: 'Não encontrei manchetes no momento.',
        );
      }

      // 0B. Offline openGym integration shortcuts
      if (RegExp(
        r'^(?:importar|sincronizar|conectar|atualizar)\s+(?:o\s+|os\s+dados\s+do\s+)?open\s*gym$',
      ).hasMatch(lower)) {
        return await executeOpenGymCommand('importar');
      }
      if (RegExp(
        r'^(?:resumo|prs?|recordes?|treinos?)\s+(?:do\s+)?open\s*gym$',
      ).hasMatch(lower)) {
        return await executeOpenGymCommand('resumo');
      }
      if (RegExp(r'^abrir\s+(?:o\s+)?open\s*gym$').hasMatch(lower)) {
        return await executeOpenGymCommand('abrir');
      }

      // 0C. Creative Music/DJ Curator & Camelot shortcuts
      final djNatural = RegExp(
        r'^(?:(?:sugerir|recomendar|montar|criar)\s+(?:um\s+|uma\s+)?(?:set|setlist|playlist|mix|m[uú]sicas?)\s*(?:para|de|pro|pra)?\s*(.*)|transi[cç][aã]o\s+camelot\s+(1[0-2]|[1-9][ab]))$',
      ).firstMatch(lower);
      if (djNatural != null) {
        final camelotArg = djNatural.group(2);
        if (camelotArg != null && camelotArg.isNotEmpty) {
          return await executeDjCommand('transicao $camelotArg');
        }
        return await executeDjCommand(djNatural.group(1) ?? '');
      }

      // 1. Flashlight / Torch
      if (RegExp(
        r'\b(ligar|acender|ativar|liga|acende)\b.*\b(lanterna|flash|luz)\b|\b(lanterna|flash)\s+(on|ligar|acesa)\b',
      ).hasMatch(lower)) {
        final on = await setTorch(true);
        return DeviceActionResult(
          handled: true,
          message:
              '🔦 Lanterna do dispositivo ativada (Estado: ${on ? 'ON' : 'OFF'}).',
          speakText: 'Lanterna ligada.',
        );
      }

      if (RegExp(
        r'\b(desligar|apagar|desativar|desliga|apaga)\b.*\b(lanterna|flash|luz)\b|\b(lanterna|flash)\s+(off|desligar|apagada)\b',
      ).hasMatch(lower)) {
        final on = await setTorch(false);
        return DeviceActionResult(
          handled: true,
          message:
              '🔦 Lanterna do dispositivo desativada (Estado: ${on ? 'ON' : 'OFF'}).',
          speakText: 'Lanterna desligada.',
        );
      }

      if (lower == 'lanterna' ||
          lower == 'alternar lanterna' ||
          lower == 'flash') {
        final on = await toggleTorch();
        return DeviceActionResult(
          handled: true,
          message: '🔦 Lanterna alternada: ${on ? 'LIGADA' : 'DESLIGADA'}.',
          speakText: on ? 'Lanterna ligada.' : 'Lanterna desligada.',
        );
      }

      // 2. Volume Control
      final volMatch = RegExp(
        r'\bvolume\s*(?:em|para|a)?\s*(\d{1,3})\s*%?',
      ).firstMatch(lower);
      if (volMatch != null) {
        final target = int.parse(volMatch.group(1)!).clamp(0, 100);
        final current = await setVolume(target);
        return DeviceActionResult(
          handled: true,
          message: '🔊 Volume de mídia ajustado para $current%.',
          speakText: 'Volume em $current por cento.',
        );
      }

      if (RegExp(
        r'\b(aumentar|subir|aumenta|sobe|mais)\s+(?:o\s+)?volume\b|^volume\s*\+$',
      ).hasMatch(lower)) {
        final current = await adjustVolume('up');
        return DeviceActionResult(
          handled: true,
          message: '🔊 Volume aumentado para $current%.',
          speakText: 'Volume $current por cento.',
        );
      }

      if (RegExp(
        r'\b(diminuir|abaixar|baixar|diminui|abaixa|baixa|menos)\s+(?:o\s+)?volume\b|^volume\s*-$',
      ).hasMatch(lower)) {
        final current = await adjustVolume('down');
        return DeviceActionResult(
          handled: true,
          message: '🔉 Volume reduzido para $current%.',
          speakText: 'Volume $current por cento.',
        );
      }

      if (RegExp(
        r'\b(silenciar|mutar|mudo|deixar no mudo|tirar o som)\b',
      ).hasMatch(lower)) {
        await adjustVolume('mute');
        return const DeviceActionResult(
          handled: true,
          message: '🔇 Áudio de mídia silenciado.',
          speakText: 'Áudio silenciado.',
        );
      }

      // 2B. Media Playback Control (Spotify, YouTube Music, Deezer, Apple Music, Tidal, SoundCloud, Poweramp, VLC, DJ apps)
      final mediaMatch = _matchMediaNaturalCommand(lower);
      if (mediaMatch != null) {
        final detectedPlayer = MusicCuratorService.detectPlayerMention(lower);
        final preferredApp = detectedPlayer?.id ?? '';
        final mediaRes = await controlMediaDetailed(
          mediaMatch.action,
          preferredApp: preferredApp,
        );
        final appLabel = detectedPlayer?.label ?? 'player de mídia';
        if (mediaRes.status == MediaControlStatus.confirmed) {
          await recordAudit(
            actor: 'OPERATOR',
            action: 'MEDIA_${mediaMatch.action.toUpperCase()}',
            target: mediaRes.activePackage.isNotEmpty
                ? mediaRes.activePackage
                : (mediaRes.launchedApp.isNotEmpty
                    ? mediaRes.launchedApp
                    : appLabel),
            status: ExecutionOutcome.confirmed.auditStatus,
            detail: mediaRes.detail,
          );
          if (mediaRes.launchedApp.isNotEmpty) {
            return DeviceActionResult(
              handled: true,
              message:
                  '▶️ O ${mediaRes.launchedApp} estava fechado — abri o aplicativo e retomei a reprodução!',
              speakText:
                  'Abri o ${mediaRes.launchedApp} e retomei a reprodução.',
            );
          }
          return DeviceActionResult(
            handled: true,
            message: mediaMatch.message,
            speakText: mediaMatch.speakText,
          );
        }
        if (mediaRes.status == MediaControlStatus.openedNeedsPlay) {
          final openedName =
              mediaRes.launchedApp.isNotEmpty ? mediaRes.launchedApp : appLabel;
          await recordAudit(
            actor: 'OPERATOR',
            action: 'MEDIA_${mediaMatch.action.toUpperCase()}',
            target: openedName,
            status: ExecutionOutcome.uncertain.auditStatus,
            detail: mediaRes.detail,
          );
          return DeviceActionResult(
            handled: true,
            message:
                '📱 O $openedName estava fechado — já abri o aplicativo para você! Ele ainda não iniciou a reprodução automaticamente (toque em play).',
            speakText:
                'O $openedName estava fechado, então abri o aplicativo para você. Toque em play para continuar.',
          );
        }
        if (mediaRes.status == MediaControlStatus.noActiveSession) {
          final isStartAction = const {
            'play',
            'play_pause',
            'next',
            'previous',
          }.contains(mediaMatch.action);
          if (isStartAction && preferredApp.isNotEmpty) {
            try {
              final openedLabel = await openApp(preferredApp);
              await recordAudit(
                actor: 'OPERATOR',
                action: 'OPEN_APP',
                target: openedLabel,
                status: ExecutionOutcome.uncertain.auditStatus,
                detail: 'Abertura proativa após $appLabel fechado em MEDIA_${mediaMatch.action.toUpperCase()}',
              );
              return DeviceActionResult(
                handled: true,
                message:
                    '📱 O $openedLabel estava fechado — já abri o aplicativo para você! Toque em play para iniciar a música.',
                speakText:
                    'O $openedLabel estava fechado, então abri o aplicativo para você.',
              );
            } catch (_) {}
          }
          await recordAudit(
            actor: 'OPERATOR',
            action: 'MEDIA_${mediaMatch.action.toUpperCase()}',
            target: appLabel,
            status: ExecutionOutcome.failed.auditStatus,
            detail: mediaRes.detail,
          );
          return DeviceActionResult(
            handled: true,
            message:
                '⚠️ Nenhuma reprodução ativa encontrada no $appLabel.',
            speakText:
                'Não há nenhuma música tocando no $appLabel no momento.',
          );
        }
        await recordAudit(
          actor: 'OPERATOR',
          action: 'MEDIA_${mediaMatch.action.toUpperCase()}',
          target: mediaRes.activePackage.isNotEmpty
              ? mediaRes.activePackage
              : appLabel,
          status: ExecutionOutcome.uncertain.auditStatus,
          detail: mediaRes.detail,
        );
        return DeviceActionResult(
          handled: true,
          message:
              '❔ Comando de mídia enviado ao Android, mas não foi possível confirmar se o $appLabel respondeu.',
          speakText:
              'Enviei o comando de mídia, mas não consegui confirmar se o $appLabel respondeu.',
        );
      }

      // 3. Battery & System Status
      if (RegExp(
        r'^(bateria|status da bateria|nivel da bateria|nível da bateria|quanta bateria|status do celular|status do sistema|telemetria|memoria ram|memória ram)$',
      ).hasMatch(lower)) {
        final status = await getStatus();
        return DeviceActionResult(
          handled: true,
          message: '📊 TELEMETRIA DO DISPOSITIVO:\n${status.formatSummary()}',
          speakText:
              'Bateria em ${status.batteryLevel} por cento. ${status.ramFreeMb} megabytes de memória livre.',
        );
      }

      // 4. Camera
      if (RegExp(
        r'^(abrir\s+c[aâ]mera|tirar\s+foto|c[aâ]mera)$',
      ).hasMatch(lower)) {
        await openApp('camera');
        return const DeviceActionResult(
          handled: true,
          message: '📷 Câmera do sistema iniciada.',
          speakText: 'Abrindo câmera.',
        );
      }

      // 5. System Settings (Wi-Fi, Bluetooth, Brilho, Som, Segurança)
      if (RegExp(
        r'\b(abrir|configurar|painel|ajustar)\s+(?:o\s+)?(wi-?fi|internet)\b|^wi-?fi$',
      ).hasMatch(lower)) {
        await openSystemSettings('wifi');
        return const DeviceActionResult(
          handled: true,
          message: '📶 Painel de Wi-Fi aberto.',
          speakText: 'Abrindo painel Wi-Fi.',
        );
      }

      if (RegExp(
        r'\b(abrir|configurar|painel|ajustar)\s+(?:o\s+)?bluetooth\b|^bluetooth$',
      ).hasMatch(lower)) {
        await openSystemSettings('bluetooth');
        return const DeviceActionResult(
          handled: true,
          message: '🦷 Configurações de Bluetooth abertas.',
          speakText: 'Abrindo Bluetooth.',
        );
      }

      if (RegExp(
        r'\b(configurar|ajustar|abrir)\s+(?:o\s+)?(brilho|tela|display)\b',
      ).hasMatch(lower)) {
        await openSystemSettings('display');
        return const DeviceActionResult(
          handled: true,
          message: '🔆 Configurações de Tela e Brilho abertas.',
          speakText: 'Abrindo configurações de tela.',
        );
      }

      // 6. Alarm (e.g. "criar alarme 07:30", "alarme 6:45")
      final alarmMatch = RegExp(
        r'\b(?:alarme|despertador)\s+(?:para\s+|às\s+|as\s+)?(\d{1,2})[:h](\d{2})\b',
      ).firstMatch(lower);
      if (alarmMatch != null) {
        final h = int.parse(alarmMatch.group(1)!).clamp(0, 23);
        final m = int.parse(alarmMatch.group(2)!).clamp(0, 59);
        final hh = h.toString().padLeft(2, '0');
        final mm = m.toString().padLeft(2, '0');
        await setAlarm(hour: h, minute: m);
        return DeviceActionResult(
          handled: true,
          message: '⏰ Alarme configurado para $hh:$mm.',
          speakText: 'Alarme definido para $hh e $mm.',
        );
      }

      // 7. Timer (e.g. "timer 5 minutos", "cronômetro 30 segundos")
      final timerMatch = RegExp(
        r'\b(?:timer|temporizador|cron[oô]metro)\s+(?:de\s+)?(\d+)\s*(seg|segundo|segundos|s|min|minuto|minutos|m)?\b',
      ).firstMatch(lower);
      if (timerMatch != null) {
        final amount = int.parse(timerMatch.group(1)!);
        final unit = timerMatch.group(2) ?? 'm';
        final isSeconds = unit.startsWith('s');
        final totalSeconds = isSeconds ? amount : amount * 60;
        await setTimer(seconds: totalSeconds);
        return DeviceActionResult(
          handled: true,
          message:
              '⏱️ Timer iniciado para $amount ${isSeconds ? 'segundos' : 'minutos'}.',
          speakText: 'Timer iniciado.',
        );
      }

      // 8. Vibrate
      if (lower == 'vibrar' ||
          lower == 'testar vibração' ||
          lower == 'vibracao') {
        await vibrate(durationMs: 350);
        return const DeviceActionResult(
          handled: true,
          message: '📳 Pulso de vibração enviado ao motor háptico.',
          speakText: 'Vibrando dispositivo.',
        );
      }

      // 9. Dial phone number
      final dialMatch = RegExp(
        r'^(?:ligar para|discar|telefonar para)\s+([0-9+\-\s()]{3,})$',
      ).firstMatch(lower);
      if (dialMatch != null) {
        final number = dialMatch.group(1)!.trim();
        final sim = actionGate.simulate('DIAL:$number');
        final allowed = await authorizeAction(
          sim,
          confirmAction: confirmAction ?? (_) async => true,
        );
        if (!allowed) {
          return const DeviceActionResult(
            handled: true,
            message: '🚫 Ligação cancelada ou bloqueada pelo nível de acesso.',
            speakText: 'Ligação bloqueada.',
          );
        }
        await dialNumber(number);
        await recordAudit(
          actor: 'OPERATOR',
          action: 'DIAL',
          target: sim.targetResource,
          status: 'EXECUTED',
          detail: 'Discador aberto para $number',
        );
        return DeviceActionResult(
          handled: true,
          message: '📞 Discador aberto para $number.',
          speakText: 'Abrindo discador.',
        );
      }

      // 10. Web search
      final searchMatch = RegExp(
        r'^(?:pesquisar|buscar na web|procurar no google)\s+(.+)$',
        caseSensitive: false,
      ).firstMatch(text);
      if (searchMatch != null) {
        final query = searchMatch.group(1)!.trim();
        await webSearch(query);
        return DeviceActionResult(
          handled: true,
          message: '🌐 Pesquisa aberta no navegador: "$query".',
          speakText: 'Pesquisando $query.',
        );
      }

      // 11. Obsidian Quick Capture ("anote: ...", "ultron, anote: ...", "nota: ...")
      final noteMatch = RegExp(
        r'^(?:ultron[,\s]+)?(?:anote|anotar|nota r[aá]pida|salvar nota)[:\s]+(.+)$',
        caseSensitive: false,
      ).firstMatch(text);
      if (noteMatch != null) {
        final noteText = noteMatch.group(1)!.trim();
        final vault = await _getObsidian();
        final file = await vault.dailyNote(DateTime.now(), noteText);
        invalidateVaultSearchCache();
        return DeviceActionResult(
          handled: true,
          message:
              '📝 Quick Capture salvo no Cofre Obsidian (${file.uri.pathSegments.last}):\n"$noteText"',
          speakText: 'Nota registrada no cofre.',
        );
      }

      // 12. Mobile Skills (.md) ("skill modo_estudo", "executar skill ...", "modo estudo", "listar skills")
      if (RegExp(
        r'^(?:listar\s+skills|skills\s+locais|quais\s+skills)$',
        caseSensitive: false,
      ).hasMatch(lower)) {
        final vault = await _getObsidian();
        final skills = await vault.listSkills();
        final summary = skills.isEmpty
            ? 'Nenhuma skill encontrada em Skills/.'
            : skills.map((s) => '• ${s.id}.md (${s.title})').join('\n');
        return DeviceActionResult(
          handled: true,
          message: '⚡ Skills Procedurais Mobile (Skills/*.md):\n$summary',
          speakText: '${skills.length} skills disponíveis.',
        );
      }
      final skillMatch = RegExp(
        r'^(?:executar\s+skill|rodar\s+skill|ativar\s+skill|skill)\s+(.+)$|^(modo\s+estudo|foco\s+noturno|alerta\s+t[aá]tico)$',
        caseSensitive: false,
      ).firstMatch(text);
      if (skillMatch != null) {
        final query = (skillMatch.group(1) ?? skillMatch.group(2) ?? '').trim();
        final vault = await _getObsidian();
        final skill = await vault.findSkill(query);
        if (skill != null) {
          final exec = await executeAiActions(
            skill.content,
            confirmAction: confirmAction,
          );
          return DeviceActionResult(
            handled: true,
            message:
                '⚡ Skill Mobile "${skill.title}" (${skill.id}.md) executada!\n'
                '${exec.executedLogs.isEmpty ? exec.cleanText : exec.executedLogs.join(' • ')}',
            speakText: 'Skill ${skill.title} ativada.',
          );
        }
        if (skillMatch.group(1) != null) {
          return DeviceActionResult(
            handled: true,
            message:
                '⚠️ Skill "$query" não encontrada em Skills/. Use /skills para listar as disponíveis.',
            speakText: 'Skill $query não encontrada.',
          );
        }
      }

      // 12b. Lexical Search / RAG in Obsidian Vault ("buscar nas notas: <termo>")
      final vaultSearchMatch = RegExp(
        r'^(?:buscar|pesquisar|procurar)\s+(?:n[ao]s?\s+)?(?:notas|cofre|obsidian|mem[oó]rias?)\s*:?\s+(.+)$',
        caseSensitive: false,
      ).firstMatch(text);
      if (vaultSearchMatch != null) {
        final query = vaultSearchMatch.group(1)?.trim() ?? '';
        if (query.isNotEmpty) {
          final hits = await searchObsidianVault(query, limit: 5);
          if (hits.isEmpty) {
            return DeviceActionResult(
              handled: true,
              message: '🔍 Nenhuma nota encontrada no cofre para "$query".',
              speakText: 'Não encontrei notas sobre $query no cofre.',
            );
          }
          final summary = hits
              .map(
                (h) => '• ${h.title} (${h.path})\n  ${h.snippet}',
              )
              .join('\n\n');
          return DeviceActionResult(
            handled: true,
            message:
                '🔍 ${hits.length} nota(s) encontrada(s) para "$query":\n\n$summary',
            speakText:
                'Encontrei ${hits.length} notas sobre $query. A principal é ${hits.first.title}.',
          );
        }
      }

      // 13. PC Remote Kill Switch
      if (RegExp(
        r'^(travar\s+pc|bloquear\s+pc|kill\s*switch)$',
        caseSensitive: false,
      ).hasMatch(lower)) {
        final sim = actionGate.simulate('KILL_SWITCH');
        final allowed = await authorizeAction(
          sim,
          confirmAction: confirmAction ?? (_) async => true,
        );
        if (!allowed) {
          return const DeviceActionResult(
            handled: true,
            message: '🚫 Kill Switch cancelado ou bloqueado pelo nível de acesso.',
            speakText: 'Kill switch bloqueado.',
          );
        }
        final resultMsg = await triggerPcKillSwitch();
        return DeviceActionResult(
          handled: true,
          message: resultMsg,
          speakText: 'Kill switch enviado ao computador.',
        );
      }

      // 14. Read Messages / Notifications ("ler mensagens", "ler notificações", "quais mensagens", "tem mensagem nova")
      if (RegExp(
        r'\b(ler|ver|checar|mostrar|quais|tem)\s+(?:as\s+|minhas\s+|novas\s+)?(mensagens|mensagem|notifica[cç][oõ]es|whatsapp)\b|^mensagens$|^notifica[cç][oõ]es$',
        caseSensitive: false,
      ).hasMatch(lower)) {
        final enabled = await isNotificationListenerEnabled();
        if (!enabled) {
          await openNotificationListenerSettings();
          return const DeviceActionResult(
            handled: true,
            message:
                '🔓 Permissão de Sentinela necessária: Ative "U.L.T.R.O.N. Sentinela de Mensagens" na tela do Android que acabou de abrir para ler e responder WhatsApp, Telegram e SMS em 2º plano.',
            speakText:
                'Ative a permissão de leitura de notificações para o Ultron.',
          );
        }
        final msgs = await getRecentMessages(limit: 8);
        if (msgs.isEmpty) {
          return const DeviceActionResult(
            handled: true,
            message: '📭 Nenhuma mensagem ou notificação recente capturada.',
            speakText: 'Você não tem novas mensagens no momento.',
          );
        }
        final formatted = msgs
            .take(5)
            .map(
              (m) =>
                  '• [${m.timeFormatted}] ${m.appLabel} — ${m.sender}: "${m.text}"${m.canReplyInline ? ' [↩️ Responde em 2º plano]' : ''}',
            )
            .join('\n');
        final spoken = msgs
            .take(3)
            .map((m) => '${m.appLabel} de ${m.sender}: ${m.text}')
            .join('. ');
        return DeviceActionResult(
          handled: true,
          message:
              '📨 SENTINELA DE MENSAGENS (${msgs.length} recentes):\n$formatted\n\n💡 Diga "responder: <texto>" para responder instantaneamente sem abrir o app!',
          speakText: 'Você tem ${msgs.length} mensagens. $spoken',
        );
      }

      // 15. Inline Background Reply ("responder: ...", "responder para Nome: ...", "responder mensagem: ...")
      final replyMatch = RegExp(
        r'^(?:ultron[,\s]+)?(?:responder|responda|responde)(?:\s+(?:para\s+([^:]+)|(?:a\s+)?(?:mensagem|notifica[cç][aã]o|whatsapp|sms)(?:\s+de\s+([^:]+))?))?\s*:\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(text);
      if (replyMatch != null) {
        final target =
            (replyMatch.group(1) ?? replyMatch.group(2) ?? '').trim();
        final replyBody = replyMatch.group(3)!.trim();
        final sim = actionGate.simulate(
          'REPLY_MESSAGE:${target.isEmpty ? 'ultimo' : target}:$replyBody',
        );
        final allowed = await authorizeAction(
          sim,
          confirmAction: confirmAction ?? (_) async => true,
        );
        if (!allowed) {
          return const DeviceActionResult(
            handled: true,
            message: '🚫 Resposta cancelada ou bloqueada pelo nível de acesso.',
            speakText: 'Envio bloqueado.',
          );
        }
        try {
          final status = await replyNotification(
            target: target,
            text: replyBody,
          );
          await recordAudit(
            actor: 'OPERATOR',
            action: 'REPLY_MESSAGE',
            target: sim.targetResource,
            status: 'EXECUTED',
            detail: status,
          );
          return DeviceActionResult(
            handled: true,
            message: '↩️ $status',
            speakText: 'Resposta enviada em segundo plano.',
          );
        } catch (err) {
          if (target.isNotEmpty) {
            final waStatus =
                await sendWhatsApp(target: target, text: replyBody);
            await recordAudit(
              actor: 'OPERATOR',
              action: 'WHATSAPP',
              target: sim.targetResource,
              status: 'EXECUTED',
              detail: waStatus,
            );
            return DeviceActionResult(
              handled: true,
              message: '💬 $waStatus',
              speakText: 'Abrindo WhatsApp para enviar a resposta.',
            );
          }
          await recordAudit(
            actor: 'OPERATOR',
            action: 'REPLY_MESSAGE',
            target: sim.targetResource,
            status: 'FAILED',
            detail: '$err',
          );
          rethrow;
        }
      }

      // 16. Send WhatsApp Message ("mandar whatsapp para Nome: texto", "enviar mensagem para Nome dizendo texto")
      final waMatch = RegExp(
        r'^(?:ultron[,\s]+)?(?:mandar|enviar|manda|envia)\s+(?:um\s+|uma\s+)?(?:whatsapp|zap|mensagem(?:\s+no\s+whatsapp)?)\s+para\s+([^:]+?)(?:\s+dizendo\s+|\s*:\s*)(.+)$',
        caseSensitive: false,
      ).firstMatch(text);
      if (waMatch != null) {
        final target = waMatch.group(1)!.trim();
        final body = waMatch.group(2)!.trim();
        final sim = actionGate.simulate('WHATSAPP:$target:$body');
        final allowed = await authorizeAction(
          sim,
          confirmAction: confirmAction ?? (_) async => true,
        );
        if (!allowed) {
          return const DeviceActionResult(
            handled: true,
            message: '🚫 WhatsApp cancelado ou bloqueado pelo nível de acesso.',
            speakText: 'Envio bloqueado.',
          );
        }
        final status = await sendWhatsApp(target: target, text: body);
        return DeviceActionResult(
          handled: true,
          message: '💬 $status',
          speakText: 'Enviando mensagem para $target.',
        );
      }

      // 17. Send SMS ("enviar sms para Nome: texto", "mandar sms para 119999: texto")
      final smsMatch = RegExp(
        r'^(?:ultron[,\s]+)?(?:mandar|enviar|manda|envia)\s+(?:um\s+)?sms\s+para\s+([^:]+?)(?:\s+dizendo\s+|\s*:\s*)(.+)$',
        caseSensitive: false,
      ).firstMatch(text);
      if (smsMatch != null) {
        final target = smsMatch.group(1)!.trim();
        final body = smsMatch.group(2)!.trim();
        final sim = actionGate.simulate('SMS:$target:$body');
        final allowed = await authorizeAction(
          sim,
          confirmAction: confirmAction ?? (_) async => true,
        );
        if (!allowed) {
          return const DeviceActionResult(
            handled: true,
            message: '🚫 SMS cancelado ou bloqueado pelo nível de acesso.',
            speakText: 'Envio bloqueado.',
          );
        }
        final status = await sendSms(target: target, text: body);
        return DeviceActionResult(
          handled: true,
          message: '📲 $status',
          speakText: 'Abrindo SMS para $target.',
        );
      }

      // 18. Offline Time / Date & Fish Audio Voice ("ei ultron que horas são", "que horas são", "testar voz offline")
      if (RegExp(
        r'\b(que\s+horas\s+s[aã]o|qual\s+(?:[eé]\s+)?a\s+hora|testar\s+voz\s+offline|voz\s+offline)\b',
        caseSensitive: false,
      ).hasMatch(lower)) {
        final reply = await speakOfflineFishVoice('que horas são');
        return DeviceActionResult(
          handled: true,
          message: '🔊 [Voz Offline Fish Audio + TTS Nativo]: $reply',
        );
      }

      // 19. Eco-VAD Voice Sentinel Toggle ("ativar sentinela de voz", "desativar sentinela de voz")
      if (RegExp(
        r'\b(ativar|ligar|iniciar)\s+(?:o\s+|a\s+)?(?:sentinela\s+de\s+voz|escuta\s+24h|escuta\s+em\s+segundo\s+plano)\b',
        caseSensitive: false,
      ).hasMatch(lower)) {
        final running = await setAudioSentinel(true);
        return DeviceActionResult(
          handled: true,
          message: running
              ? '🎙️ Sentinela Eco-VAD ativado em 2º plano (Duty-Cycle 82% Sleep • Consumo < 1% bateria).'
              : '⚠️ Conceda a permissão de microfone na janela do Android e tente novamente.',
          speakText: running
              ? 'Sentinela Eco VAD ativado.'
              : 'Permissão de microfone necessária.',
        );
      }

      if (RegExp(
        r'\b(desativar|desligar|parar)\s+(?:o\s+|a\s+)?(?:sentinela\s+de\s+voz|escuta\s+24h|escuta\s+em\s+segundo\s+plano)\b',
        caseSensitive: false,
      ).hasMatch(lower)) {
        await setAudioSentinel(false);
        return const DeviceActionResult(
          handled: true,
          message: '⏹️ Sentinela Eco-VAD em 2º plano desligado.',
          speakText: 'Sentinela de voz desativado.',
        );
      }

      // 20. Obsidian Second Brain ("abrir obsidian", "abrir cofre", "meu segundo cérebro")
      if (RegExp(
        r'\b(abrir|acessar)\s+(?:o\s+)?(?:obsidian|cofre|segundo\s+c[eé]rebro)\b|^(?:obsidian|cofre|segundo\s+c[eé]rebro)$',
        caseSensitive: false,
      ).hasMatch(lower)) {
        final opened = await openObsidianVault();
        return DeviceActionResult(
          handled: true,
          message: opened
              ? '📓 Aplicativo Obsidian aberto com o cofre do Segundo Cérebro.'
              : '⚠️ Não foi possível abrir o app Obsidian (verifique se está instalado).',
          speakText: opened ? 'Obsidian aberto.' : 'Obsidian não disponível.',
        );
      }

      // 21. Quick Inbox Capture ("ideia: ...", "capturar ideia: ...", "inbox: ...")
      final inboxMatch = RegExp(
        r'^(?:capturar\s+ideia|anotar\s+ideia|ideia|inbox)\s*[:]\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(text);
      if (inboxMatch != null) {
        final body = inboxMatch.group(1)?.trim() ?? '';
        if (body.isNotEmpty) {
          final vault = await _getObsidian();
          await vault.captureToInbox(body);
          return DeviceActionResult(
            handled: true,
            message: '💡 Ideia capturada no Inbox do Obsidian:\n"$body"',
            speakText: 'Ideia salva no Inbox do seu segundo cérebro.',
          );
        }
      }

      // 22. Long-term memory save ("lembrar que ...", "guardar na memória: ...")
      final memMatch = RegExp(
        r'^(?:lembrar\s+que|memorizar|guardar\s+na\s+mem[oó]ria|guardar\s+fato)\s*[:]?\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(text);
      if (memMatch != null) {
        final body = memMatch.group(1)?.trim() ?? '';
        if (body.isNotEmpty) {
          final vault = await _getObsidian();
          await vault.saveMemory('Operador', body);
          return DeviceActionResult(
            handled: true,
            message:
                '🧠 Memória persistida no perfil do Operador (Obsidian):\n"$body"',
            speakText: 'Memória guardada no seu segundo cérebro.',
          );
        }
      }

      // 22b. Calendar read/write/cancel ("minha agenda", "agenda de amanhã", "agendar reunião às 15:00", "cancelar evento ...")
      final calRes = await _tryHandleCalendarNaturalCommand(
        text,
        lower,
        confirmAction: confirmAction,
      );
      if (calRes != null) return calRes;

      // 22b-2. Obsidian CRUD & Undo natural commands ("listar notas", "ler nota ...", "anexar em ...", "tarefas do obsidian", "status do cofre", "desfazer")
      final obsCrudRes = await _tryHandleObsidianCrudNaturalCommand(
        text,
        lower,
        confirmAction: confirmAction,
      );
      if (obsCrudRes != null) return obsCrudRes;

      // 22b-3. Reminders ("me lembre de ...", "listar lembretes", "cancelar lembrete ...")
      final remRes = await _tryHandleReminderNaturalCommand(
        text,
        lower,
        confirmAction: confirmAction,
      );
      if (remRes != null) return remRes;

      // 22b-4. Web Info: Weather, RSS News & Web Search Summary ("clima em ...", "notícias sobre ...", "pesquisar na web resumo: ...")
      final webInfoRes = await _tryHandleWebInfoNaturalCommand(text, lower);
      if (webInfoRes != null) return webInfoRes;

      // 22b-5. Dynamic Skills & Scheduled Workflows ("criar skill ...", "excluir skill ...", "criar fluxo ...", "listar fluxos", "executar fluxo ...")
      final flowRes = await _tryHandleSkillAndWorkflowNaturalCommand(
        text,
        lower,
        confirmAction: confirmAction,
      );
      if (flowRes != null) return flowRes;

      // 22b-6. Spotify Web API natural commands ("tocar ... no spotify", "buscar no spotify ...", "estado do spotify", "minhas playlists do spotify", "adicionar à playlist ...")
      final spotifyRes = await _tryHandleSpotifyNaturalCommand(text, lower);
      if (spotifyRes != null) return spotifyRes;

      // 22b-7. Utilitários de arquivos SAF/Downloads ("limpar duplicados", "converter imagens", "organizar pdfs")
      final fileUtilRes = await _tryHandleFileUtilitiesNaturalCommand(
        text,
        lower,
        confirmAction: confirmAction,
      );
      if (fileUtilRes != null) return fileUtilRes;

      // 22c. Abrir aplicativo no PC/Desktop pareado ("abra o rocket league no pc", "no computador abra o chrome")
      final pcOpenMatchA = RegExp(
        r'^(?:(?:ei|ok|oi)\s+)?(?:ultron\s*[,\s]+)?(?:(?:por\s+favor|pfv|pode|poderia|quero|vai|agora)\s+)*(?:abrir|iniciar|executar|abre|abra)\s+(?:o\s+|a\s+|app\s+|aplicativo\s+|jogo\s+)?(.+?)\s+(?:no|pelo)\s+(?:meu\s+)?(?:pc|computador|desktop|notebook)(?:\s+(?:para\s+mim|pra\s+mim|por\s+favor|pfv))?[.!?,;:]*$',
      ).firstMatch(lower);
      final pcOpenMatchB = RegExp(
        r'^(?:(?:ei|ok|oi)\s+)?(?:ultron\s*[,\s]+)?(?:no|pelo)\s+(?:meu\s+)?(?:pc|computador|desktop|notebook)\s*[,\s]+(?:(?:por\s+favor|pfv|pode|poderia|quero)\s+)*(?:abrir|iniciar|executar|abre|abra)\s+(?:o\s+|a\s+|app\s+|aplicativo\s+|jogo\s+)?(.+?)[.!?,;:]*$',
      ).firstMatch(lower);
      final pcRawApp = (pcOpenMatchA ?? pcOpenMatchB)?.group(1)?.trim() ?? '';
      if (pcRawApp.isNotEmpty) {
        final cleanApp = pcRawApp
            .replaceFirst(RegExp(r'[.!?,;:]+$'), '')
            .replaceFirst(_trailingCourtesyRegex, '')
            .replaceFirst(RegExp(r'^(?:o|a|um|uma|app|aplicativo|jogo)\s+'), '')
            .trim();
        if (cleanApp.isNotEmpty) {
          final res = await sendDesktopBridgeCommand(
            command: 'PC_OPEN_APP',
            args: {'app': cleanApp},
            confirmAction: confirmAction,
            actor: 'NATURAL',
          );
          if (res.deniedByUser) {
            return const DeviceActionResult(
              handled: true,
              message: '🚫 Abertura de app no Desktop cancelada no Action Gate.',
            );
          }
          if (res.sent) {
            return DeviceActionResult(
              handled: true,
              message: '💻 App iniciado no Desktop: $cleanApp (HTTP ${res.statusCode ?? 200}).',
              speakText: 'Abrindo $cleanApp no computador.',
            );
          }
          return DeviceActionResult(
            handled: true,
            message: '⚠️ Desktop recusou abrir "$cleanApp": ${res.error ?? 'HTTP ${res.statusCode}'}',
            speakText: 'O computador recusou abrir $cleanApp.',
          );
        }
      }

      // 23. Open any installed app ("abrir whatsapp", "no meu celular, abra o whatsapp", "pode abrir o youtube")
      final openMatch = RegExp(
        r'^(?:(?:ei|ok|oi)\s+)?(?:ultron\s*[,\s]+)?(?:(?:aqui\s+)?no\s+(?:meu\s+)?celular\s*[,\s]+)?(?:(?:por\s+favor|pfv|pode|poderia|queria|quero|vai|agora|me\s+ajuda\s+a)\s+)*(?:abrir|iniciar|executar|abre|abra)\s+(?:o\s+|a\s+|app\s+|aplicativo\s+)?(.+)$',
      ).firstMatch(lower);
      if (openMatch != null) {
        final rawTarget = openMatch
            .group(1)!
            .replaceFirst(RegExp(r'[.!?,;:]+$'), '')
            .replaceFirst(_trailingCourtesyRegex, '')
            .replaceFirst(
              RegExp(r'^(?:o|a|um|uma|app|aplicativo)\s+'),
              '',
            )
            .replaceFirst(RegExp(r'[.!?,;:]+$'), '')
            .trim();
        final words =
            rawTarget.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        if (rawTarget.isNotEmpty &&
            words <= 3 &&
            rawTarget != 'palco' &&
            rawTarget != 'documento') {
          try {
            final opened = await openApp(rawTarget);
            return DeviceActionResult(
              handled: true,
              message: '📱 Aplicativo iniciado: $opened.',
              speakText: 'Abrindo $opened.',
            );
          } catch (_) {
            // Não encontrou aplicativo literal: cai para a IA interpretar o contexto da frase.
            return null;
          }
        }
      }
    } catch (e) {
      return DeviceActionResult(
        handled: true,
        message: '⚠️ Comando de dispositivo reconhecido, mas falhou: $e',
      );
    }

    return null;
  }

  /// Parses `[ACTION:...]` tags and `[HTTP:METHOD:URL|JSON]` bridge directives
  /// emitted by the AI model or `Skills/*.md`, executes them on Android/LAN,
  /// enforces `ActionGate`, records tamper-evident audit entries, and returns
  /// cleaned reply text + execution logs.
  Future<AiActionExecution> executeAiActions(
    String rawReply, {
    ActionGateConfirmCallback? confirmAction,
    String actor = 'AI_TAG',
  }) async {
    final pattern = RegExp(
      r'\[(?:ACTION:((?:(?:\[\s*[xX ]?\s*\])|[^\]])+)|HTTP:(GET|POST|PUT|PATCH|DELETE):([^\]]+))\]',
      caseSensitive: false,
    );
    final matches = pattern.allMatches(rawReply).toList();
    if (matches.isEmpty) {
      return AiActionExecution(
          cleanText: rawReply.trim(), executedLogs: const []);
    }

    final logs = <String>[];
    for (final match in matches) {
      final isHttpDirective = match.group(2) != null;
      final content = isHttpDirective
          ? 'HTTP_${match.group(2)!.toUpperCase()}:${match.group(3)!.trim()}'
          : (match.group(1)?.trim() ?? '');
      final parts = content.split(':');
      final cmd = parts.first.toUpperCase();
      final arg1 = parts.length > 1 ? parts[1].trim() : '';
      final arg2 = parts.length > 2 ? parts[2].trim() : '';
      final arg3 = parts.length > 3 ? parts.sublist(3).join(':').trim() : '';

      final sim = actionGate.simulate('[ACTION:$content]');
      final allowed = await authorizeAction(
        sim,
        confirmAction: confirmAction,
        actor: actor,
      );
      if (!allowed) {
        logs.add('🚫 $cmd bloqueado pelo Action Gate');
        continue;
      }

      try {
        switch (cmd) {
          case 'TORCH_ON':
            await setTorch(true);
            logs.add('🔦 Lanterna ligada');
            break;
          case 'TORCH_OFF':
            await setTorch(false);
            logs.add('🔦 Lanterna desligada');
            break;
          case 'TORCH_TOGGLE':
            final on = await toggleTorch();
            logs.add('🔦 Lanterna: ${on ? 'ON' : 'OFF'}');
            break;
          case 'VOLUME_SET':
            final v = int.tryParse(arg1) ?? 50;
            final updated = await setVolume(v);
            logs.add('🔊 Volume: $updated%');
            break;
          case 'VOLUME_UP':
            final updated = await adjustVolume('up');
            logs.add('🔊 Volume: $updated%');
            break;
          case 'VOLUME_DOWN':
            final updated = await adjustVolume('down');
            logs.add('🔉 Volume: $updated%');
            break;
          case 'VOLUME_MUTE':
            await adjustVolume('mute');
            logs.add('🔇 Áudio silenciado');
            break;
          case 'MEDIA_PLAY':
          case 'MEDIA_PAUSE':
          case 'MEDIA_PLAY_PAUSE':
          case 'MEDIA_NEXT':
          case 'MEDIA_PREVIOUS':
          case 'MEDIA_STOP':
            final mediaSpec = _mediaActionSpecs[cmd]!;
            final mRes = await controlMediaDetailed(
              mediaSpec.action,
              preferredApp: arg1,
            );
            if (mRes.status == MediaControlStatus.confirmed) {
              logs.add(
                mRes.launchedApp.isNotEmpty
                    ? '▶️ ${mRes.launchedApp} aberto e reprodução retomada'
                    : mediaSpec.logLabel,
              );
            } else if (mRes.status == MediaControlStatus.openedNeedsPlay) {
              logs.add(
                '📱 ${mRes.launchedApp.isNotEmpty ? mRes.launchedApp : 'Player'} estava fechado e foi aberto (aguardando play)',
              );
            } else if (mRes.status == MediaControlStatus.noActiveSession) {
              logs.add(
                '⚠️ $cmd não concluído: nenhum player/sessão de mídia ativa (app fechado)',
              );
            } else {
              logs.add(
                '❔ $cmd enviado, mas reprodução não confirmada',
              );
            }
            break;
          case 'OPEN_CAMERA':
            await openApp('camera');
            logs.add('📷 Câmera aberta');
            break;
          case 'OPEN_APP':
            if (arg1.isNotEmpty) {
              final opened = await openApp(arg1);
              logs.add('📱 App aberto: $opened');
            }
            break;
          case 'OPEN_SETTINGS':
            await openSystemSettings(arg1.isEmpty ? 'general' : arg1);
            logs.add('⚙️ Configurações abertas ($arg1)');
            break;
          case 'ALARM':
            final h = int.tryParse(arg1) ?? 7;
            final m = int.tryParse(arg2) ?? 0;
            await setAlarm(
              hour: h,
              minute: m,
              message: arg3.isEmpty ? 'U.L.T.R.O.N.' : arg3,
            );
            logs.add(
              '⏰ Alarme ${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}',
            );
            break;
          case 'TIMER':
            final secs = int.tryParse(arg1) ?? 60;
            await setTimer(
              seconds: secs,
              message: arg2.isEmpty ? 'U.L.T.R.O.N. Timer' : arg2,
            );
            logs.add('⏱️ Timer (${secs}s)');
            break;
          case 'VIBRATE':
            await vibrate(durationMs: 280);
            logs.add('📳 Vibração');
            break;
          case 'DIAL':
            if (arg1.isNotEmpty) {
              await dialNumber(arg1);
              logs.add('📞 Discar: $arg1');
            }
            break;
          case 'SEARCH':
            final q = parts.skip(1).join(':').trim();
            if (q.isNotEmpty) {
              await webSearch(q);
              logs.add('🌐 Busca: $q');
            }
            break;
          case 'NOTE':
            final noteBody = parts.skip(1).join(':').trim();
            if (noteBody.isNotEmpty) {
              final vault = await _getObsidian();
              await vault.dailyNote(DateTime.now(), noteBody);
              logs.add('📝 Nota salva no Obsidian');
            }
            break;
          case 'INBOX':
            final inboxBody = parts.skip(1).join(':').trim();
            if (inboxBody.isNotEmpty) {
              final vault = await _getObsidian();
              await vault.captureToInbox(inboxBody);
              logs.add('💡 Ideia salva no Inbox do Obsidian');
            }
            break;
          case 'REMEMBER':
          case 'MEMORY':
            final topic = arg1.isNotEmpty ? arg1 : 'Operador';
            final memoryBody = parts.length > 2
                ? parts.skip(2).join(':').trim()
                : parts.skip(1).join(':').trim();
            if (memoryBody.isNotEmpty) {
              final vault = await _getObsidian();
              await vault.saveMemory(topic, memoryBody);
              logs.add('🧠 Memória gravada no Segundo Cérebro ($topic)');
            }
            break;
          case 'OPEN_OBSIDIAN':
            final opened = await openObsidianVault();
            logs.add(
                opened ? '📓 Obsidian aberto' : '⚠️ Obsidian não encontrado');
            break;
          case 'OBSIDIAN_LIST':
          case 'OBSIDIAN_NOTAS':
            final folderArg = parts.skip(1).join(':').trim();
            final notes = await listObsidianNotes(
              folder: folderArg.isEmpty ? null : folderArg,
            );
            if (notes.isEmpty) {
              logs.add(
                '📓 Nenhuma nota em ${folderArg.isEmpty ? 'cofre' : folderArg}',
              );
            } else {
              final preview =
                  notes.take(5).map((n) => n.relativePath).join(', ');
              logs.add('📓 ${notes.length} nota(s): $preview');
            }
            break;
          case 'OBSIDIAN_READ':
          case 'OBSIDIAN_LER':
            final targetPath = parts.skip(1).join(':').trim();
            if (targetPath.isNotEmpty) {
              final content = await readObsidianNote(targetPath);
              final snippet = content.trim().replaceAll(RegExp(r'\s+'), ' ');
              final shortSnippet = snippet.length > 120
                  ? '${snippet.substring(0, 120)}…'
                  : snippet;
              logs.add('📖 $targetPath: $shortSnippet');
            }
            break;
          case 'OBSIDIAN_APPEND':
          case 'OBSIDIAN_ANEXAR':
            final targetPath = arg1;
            final appendBody = parts.skip(2).join(':').trim();
            if (targetPath.isNotEmpty && appendBody.isNotEmpty) {
              final updatedFile =
                  await appendObsidianNote(targetPath, appendBody);
              final relName = updatedFile.uri.pathSegments.last;
              logs.add('✍️ Anexado em $relName');
              await recordAudit(
                actor: actor,
                action: 'OBSIDIAN_APPEND',
                target: targetPath,
                status: 'EXECUTED',
                detail: appendBody,
              );
            }
            break;
          case 'OBSIDIAN_TASKS':
          case 'OBSIDIAN_TAREFAS':
            final subOp = arg1.toLowerCase();
            if (subOp == 'check' ||
                subOp == 'marcar' ||
                subOp == 'done' ||
                subOp == 'uncheck' ||
                subOp == 'desmarcar' ||
                subOp == 'toggle' ||
                subOp == 'alternar') {
              final completed = (subOp == 'check' ||
                      subOp == 'marcar' ||
                      subOp == 'done')
                  ? true
                  : (subOp == 'uncheck' || subOp == 'desmarcar')
                      ? false
                      : null;
              final selector = parts.skip(2).join(':').trim();
              final asIdx = int.tryParse(selector);
              final item = await toggleObsidianTask(
                taskIndex: asIdx,
                queryText: asIdx == null ? selector : null,
                completed: completed,
              );
              logs.add(
                '☑️ Tarefa #${item.index} [${item.completed ? 'x' : ' '}] ${item.text}',
              );
            } else {
              final filterPath = parts.skip(1).join(':').trim();
              final tasks = await listObsidianTasks(
                notePath: filterPath.isEmpty ? null : filterPath,
              );
              if (tasks.isEmpty) {
                logs.add('☑️ Nenhuma tarefa Markdown encontrada');
              } else {
                final doneCount = tasks.where((t) => t.completed).length;
                logs.add(
                  '☑️ ${tasks.length} tarefa(s) ($doneCount concluída(s))',
                );
              }
            }
            break;
          case 'OBSIDIAN_STATUS':
            final status = await getObsidianStatus();
            logs.add(
              '📊 Cofre ${status.vaultName}: ${status.totalNotes} notas (${status.sizeLabel}) • Engine ${status.searchEngine.name}',
            );
            break;
          case 'UNDO':
          case 'DESFAZER':
            final undoRes = await undoLastObsidianMutation();
            logs.add(undoRes.message);
            if (undoRes.undone) {
              await recordAudit(
                actor: actor,
                action: 'UNDO',
                target: undoRes.relativePath,
                status: 'EXECUTED',
                detail: undoRes.message,
              );
            }
            break;
          case 'SKILL':
            if (arg1.isNotEmpty) {
              final vault = await _getObsidian();
              final skill = await vault.findSkill(arg1);
              if (skill != null) {
                final sub = await executeAiActions(
                  skill.content,
                  confirmAction: confirmAction,
                  actor: 'SKILL:${skill.id}',
                );
                logs.add('⚡ Skill ${skill.id}: ${sub.executedLogs.join(', ')}');
                await recordAudit(
                  actor: actor,
                  action: 'SKILL',
                  target: skill.id,
                  status: 'EXECUTED',
                  detail: sub.executedLogs.join(' • '),
                );
              }
            }
            break;
          case 'SKILL_CREATE':
            final rawSpec = parts.skip(1).join(':').trim();
            final pipeIdx = rawSpec.indexOf('|');
            final namePart =
                (pipeIdx >= 0 ? rawSpec.substring(0, pipeIdx) : arg1).trim();
            final contentPart = (pipeIdx >= 0
                    ? rawSpec.substring(pipeIdx + 1)
                    : parts.skip(2).join(':'))
                .trim();
            if (namePart.isNotEmpty && contentPart.isNotEmpty) {
              final created = await createObsidianSkill(namePart, contentPart);
              logs.add('⚡ Skill criada: Skills/${created.id}.md (${created.title})');
              await recordAudit(
                actor: actor,
                action: 'SKILL_CREATE',
                target: 'Skills/${created.id}.md',
                status: 'EXECUTED',
                detail: created.title,
              );
            }
            break;
          case 'SKILL_DELETE':
            final targetSkill = parts.skip(1).join(':').trim();
            if (targetSkill.isNotEmpty) {
              final deleted = await deleteObsidianSkill(targetSkill);
              logs.add(
                deleted
                    ? '🗑️ Skill removida: $targetSkill'
                    : '⚠️ Skill não encontrada: $targetSkill',
              );
              await recordAudit(
                actor: actor,
                action: 'SKILL_DELETE',
                target: targetSkill,
                status: deleted ? 'EXECUTED' : 'NOT_FOUND',
                detail: deleted ? 'Removida' : 'Não encontrada',
              );
            }
            break;
          case 'WEATHER':
          case 'CLIMA':
            final cityArg = parts.skip(1).join(':').trim();
            final snap = await fetchWeather(
              city: cityArg.isEmpty ? null : cityArg,
            );
            if (snap == null) {
              logs.add(
                '🌤️ Clima indisponível${cityArg.isEmpty ? '' : ' para "$cityArg"'}',
              );
            } else {
              logs.add('🌤️ ${snap.summaryLine}');
            }
            break;
          case 'NEWS':
          case 'NOTICIAS':
            final topicArg = parts.skip(1).join(':').trim();
            final articles = await fetchNews(topic: topicArg, limit: 4);
            if (articles.isEmpty) {
              logs.add(
                '📰 Nenhuma notícia encontrada${topicArg.isEmpty ? '' : ' para "$topicArg"'}',
              );
            } else {
              final headlines =
                  articles.take(3).map((a) => a.title).join(' | ');
              logs.add('📰 Notícias (${articles.length}): $headlines');
            }
            break;
          case 'WEB_SEARCH':
          case 'PESQUISAR_WEB':
            final queryArg = parts.skip(1).join(':').trim();
            if (queryArg.isNotEmpty) {
              final summary = await searchWebSummary(queryArg, limit: 3);
              if (summary.isEmpty) {
                logs.add('🌐 Sem resumo textual para "$queryArg"');
              } else {
                final top = summary.items.first;
                logs.add('🌐 ${top.title}: ${top.snippet}');
              }
            }
            break;
          case 'FLOW_CREATE':
            final rawFlow = parts.skip(1).join(':').trim();
            final flowSegments =
                rawFlow.contains('|') ? rawFlow.split('|') : parts.skip(1).toList();
            final flowName = flowSegments.isNotEmpty ? flowSegments[0].trim() : '';
            final flowSteps = flowSegments.length > 1 ? flowSegments[1].trim() : '';
            final flowSched =
                flowSegments.length > 2 ? flowSegments.sublist(2).join('|').trim() : '';
            if (flowName.isNotEmpty && flowSteps.isNotEmpty) {
              final flow = await createWorkflow(
                name: flowName,
                stepsPayload: flowSteps,
                scheduleSpec: flowSched,
              );
              logs.add(
                '⚙️ Fluxo #${flow.id} "${flow.name}" criado (${flow.formattedNextRun})',
              );
              await recordAudit(
                actor: actor,
                action: 'FLOW_CREATE',
                target: flow.name,
                status: 'EXECUTED',
                detail: '${flow.stepsPayload} [${flow.formattedNextRun}]',
              );
            }
            break;
          case 'FLOW_LIST':
            final flows = await listWorkflows();
            if (flows.isEmpty) {
              logs.add('⚙️ Nenhum fluxo cadastrado');
            } else {
              final preview = flows
                  .take(4)
                  .map((f) => '#${f.id} ${f.name} (${f.formattedNextRun})')
                  .join(' | ');
              logs.add('⚙️ ${flows.length} fluxo(s): $preview');
            }
            break;
          case 'FLOW_RUN':
            final flowTarget = parts.skip(1).join(':').trim();
            if (flowTarget.isNotEmpty) {
              final res = await runWorkflow(
                flowTarget,
                confirmAction: confirmAction,
                isBackgroundTrigger: actor == 'FLOW_BG',
              );
              logs.add(res.message);
            }
            break;
          case 'FLOW_SCHEDULE':
            final rawSched = parts.skip(1).join(':').trim();
            final schedParts = rawSched.contains('|')
                ? rawSched.split('|')
                : [arg1, parts.skip(2).join(':').trim()];
            final targetFlow = schedParts.first.trim();
            final spec = schedParts.length > 1
                ? schedParts.sublist(1).join(':').trim()
                : '';
            if (targetFlow.isNotEmpty && spec.isNotEmpty) {
              final updated = await scheduleWorkflow(
                nameOrId: targetFlow,
                scheduleSpec: spec,
              );
              logs.add(
                '⏰ Fluxo "${updated.name}" agendado: ${updated.formattedNextRun}',
              );
              await recordAudit(
                actor: actor,
                action: 'FLOW_SCHEDULE',
                target: updated.name,
                status: 'EXECUTED',
                detail: updated.formattedNextRun,
              );
            }
            break;
          case 'FLOW_DELETE':
            final delTarget = parts.skip(1).join(':').trim();
            if (delTarget.isNotEmpty) {
              final removed = await deleteWorkflow(delTarget);
              logs.add(
                removed != null
                    ? '🗑️ Fluxo "${removed.name}" removido'
                    : '⚠️ Fluxo "$delTarget" não encontrado',
              );
              await recordAudit(
                actor: actor,
                action: 'FLOW_DELETE',
                target: delTarget,
                status: removed != null ? 'EXECUTED' : 'NOT_FOUND',
                detail: removed?.name ?? 'Não encontrado',
              );
            }
            break;
          case 'CLEAN_DUPLICATES':
          case 'LIMPAR_DUPLICADOS':
            final dirArg = parts.skip(1).join(':').trim();
            final report = await getFileUtilitiesService().cleanDuplicates(
              directoryPath: dirArg.isEmpty ? null : dirArg,
              dryRun: false,
            );
            logs.add(report.formatSummary());
            await recordAudit(
              actor: actor,
              action: 'CLEAN_DUPLICATES',
              target: report.directoryPath,
              status: 'EXECUTED',
              detail: '${report.deletedCount} duplicado(s) removido(s)',
            );
            break;
          case 'CONVERT_IMAGES':
          case 'CONVERTER_IMAGENS':
            final rawConv = parts.skip(1).join(':').trim();
            final convSegs = rawConv.contains('|')
                ? rawConv.split('|')
                : <String>[rawConv];
            var targetFmt = 'jpg';
            String? convDir;
            if (convSegs.isNotEmpty && convSegs.first.trim().isNotEmpty) {
              final firstToken = convSegs.first.trim().toLowerCase();
              if (firstToken == 'jpg' ||
                  firstToken == 'jpeg' ||
                  firstToken == 'png' ||
                  firstToken == '.jpg' ||
                  firstToken == '.png') {
                targetFmt = firstToken.contains('png') ? 'png' : 'jpg';
                if (convSegs.length > 1 && convSegs[1].trim().isNotEmpty) {
                  convDir = convSegs.sublist(1).join('|').trim();
                }
              } else {
                convDir = convSegs.first.trim();
              }
            }
            final convReport = await getFileUtilitiesService().convertImages(
              directoryPath: convDir,
              targetFormat: targetFmt,
            );
            logs.add(convReport.formatSummary());
            await recordAudit(
              actor: actor,
              action: 'CONVERT_IMAGES',
              target: convReport.directoryPath,
              status: 'EXECUTED',
              detail:
                  '${convReport.convertedFiles.length} convertida(s) para .$targetFmt',
            );
            break;
          case 'ORGANIZE_PDFS':
          case 'ORGANIZAR_PDF_DOWNLOADS':
            final rawPdf = parts.skip(1).join(':').trim();
            final pdfSegs =
                rawPdf.contains('|') ? rawPdf.split('|') : <String>[rawPdf];
            final pdfDir = pdfSegs.isNotEmpty && pdfSegs.first.trim().isNotEmpty
                ? pdfSegs.first.trim()
                : null;
            final pdfSubj = pdfSegs.length > 1 && pdfSegs[1].trim().isNotEmpty
                ? pdfSegs.sublist(1).join('|').trim()
                : null;
            final pdfReport =
                await getFileUtilitiesService().organizePdfDownloads(
              directoryPath: pdfDir,
              subjectHint: pdfSubj,
            );
            logs.add(pdfReport.formatSummary());
            await recordAudit(
              actor: actor,
              action: 'ORGANIZE_PDFS',
              target: pdfReport.directoryPath,
              status: 'EXECUTED',
              detail: '${pdfReport.renamedFiles.length} PDF(s) renomeado(s)',
            );
            break;
          case 'KILL_SWITCH':
            await triggerPcKillSwitch();
            logs.add('🚨 Kill Switch PC disparado');
            break;
          case 'PC_STATUS':
          case 'PC_OPEN_APP':
          case 'PC_MEDIA':
          case 'PC_CLIPBOARD_PUSH':
          case 'PC_CLIPBOARD_PULL':
          case 'PC_RUN_SKILL':
          case 'PC_THERMAL':
          case 'PC_TEMP':
          case 'PC_DELEGATE_TASK':
          case 'PC_TASK_STATUS':
          case 'PC_TASK_CANCEL':
          case 'PC_SPOTIFY':
          case 'PC_POWER_PLAN':
          case 'PC_APP_VOLUME':
          case 'PC_KILL_FROZEN':
          case 'PC_BACKUP':
          case 'PC_CLEAN_DISK':
          case 'PC_EJECT_USB':
          case 'PC_EXEC_TOOL':
            final pcPayload = parts.skip(1).join(':').trim();
            final parsedPc =
                DesktopPairingService.parsePcCommandInput('$cmd:$pcPayload');
            final Map<String, dynamic> pcArgs = parsedPc?.args ??
                switch (cmd) {
                  'PC_OPEN_APP' => {'app': pcPayload},
                  'PC_MEDIA' => {
                      'action': pcPayload.isEmpty ? 'play_pause' : pcPayload,
                    },
                  'PC_CLIPBOARD_PUSH' => {'text': pcPayload},
                  'PC_RUN_SKILL' => {'skill': pcPayload},
                  'PC_THERMAL' => {'tool': 'verificar_protecao_termica'},
                  'PC_TEMP' => const <String, dynamic>{},
                  'PC_DELEGATE_TASK' => {
                      'query': pcPayload,
                      'objective': pcPayload,
                    },
                  'PC_TASK_STATUS' => {
                      if (pcPayload.isNotEmpty) 'task_id': pcPayload,
                    },
                  'PC_TASK_CANCEL' => {'task_id': pcPayload},
                  'PC_SPOTIFY' => {
                      'action': pcPayload.isEmpty ? 'status' : 'play',
                      if (pcPayload.isNotEmpty) 'query': pcPayload,
                    },
                  'PC_POWER_PLAN' => {
                      'tool': 'controlar_plano_energia',
                      'plan': pcPayload.isEmpty ? 'balanced' : pcPayload,
                    },
                  'PC_APP_VOLUME' => {
                      'tool': pcPayload.isEmpty
                          ? 'listar_volumes_apps'
                          : 'ajustar_volume_app',
                    },
                  'PC_KILL_FROZEN' => {'tool': 'encerrar_apps_travados'},
                  'PC_BACKUP' => {'tool': 'executar_backup_incremental'},
                  'PC_CLEAN_DISK' => {'tool': 'limpar_disco'},
                  'PC_EJECT_USB' => {'tool': 'ejetar_usb_ocioso'},
                  'PC_EXEC_TOOL' => {'tool': pcPayload},
                  _ => const <String, dynamic>{},
                };
            final pcRes = await sendDesktopBridgeCommand(
              command: cmd == 'PC_STATUS' ? 'PING' : cmd,
              args: pcArgs,
              actor: actor,
              skipLocalConfirm: true,
            );
            if (pcRes.sent &&
                cmd == 'PC_EXEC_TOOL' &&
                '${pcArgs['tool']}'.toLowerCase() == 'create_mini_app') {
              final miniApp =
                  MiniAppLaunchResponse.tryParse(pcRes.responseBody);
              if (miniApp != null) {
                var opened = false;
                try {
                  opened = await openUrl(miniApp.url);
                } catch (_) {}
                logs.add(
                  '🧩 Mini-App LAN ativo (${miniApp.ttlSeconds}s): ${miniApp.url}'
                  '${opened ? ' [aberto no navegador]' : ''}',
                );
                break;
              }
            }
            logs.add(
              pcRes.sent
                  ? '💻 $cmd OK${(pcRes.responseBody ?? '').trim().isNotEmpty ? '' : ' (HTTP ${pcRes.statusCode ?? 200})'}'
                  : '⚠️ $cmd: ${pcRes.error ?? 'HTTP ${pcRes.statusCode}'}',
            );
            break;
          case 'READ_MESSAGES':
            final msgs = await getRecentMessages(limit: 5);
            if (msgs.isEmpty) {
              logs.add('📭 Sem novas mensagens');
            } else {
              final preview = msgs
                  .take(3)
                  .map((m) => '${m.sender} (${m.appLabel}): ${m.text}')
                  .join(' | ');
              logs.add('📨 Mensagens: $preview');
            }
            break;
          case 'REPLY_MESSAGE':
            final target = arg1 == 'ultimo' || arg1 == 'último' ? '' : arg1;
            final replyText = parts.skip(2).join(':').trim();
            if (replyText.isNotEmpty) {
              final res = await replyNotification(
                target: target,
                text: replyText,
              );
              logs.add('↩️ $res');
            }
            break;
          case 'WHATSAPP':
            final body = parts.skip(2).join(':').trim();
            if (body.isNotEmpty) {
              final res = await sendWhatsApp(target: arg1, text: body);
              logs.add('💬 $res');
            }
            break;
          case 'SMS':
            final body = parts.skip(2).join(':').trim();
            if (body.isNotEmpty) {
              final res = await sendSms(target: arg1, text: body);
              logs.add('📲 $res');
            }
            break;
          case 'READ_CALENDAR':
            final days = (int.tryParse(arg1) ?? 1).clamp(1, 30);
            final events = await getCalendarEvents(daysAhead: days);
            if (events.isEmpty) {
              logs.add('📅 Agenda livre');
            } else {
              logs.add(
                '📅 ${events.length} evento(s): ${events.take(3).map((e) => '${e.timeRangeLabel} ${e.title}').join(' | ')}',
              );
            }
            break;
          case 'CREATE_EVENT':
          case 'CALENDAR_EVENT':
            final rawSpec = parts.skip(1).join(':').trim();
            final draft = parseNaturalCalendarEvent(rawSpec);
            if (draft != null) {
              final created = await createCalendarEvent(
                title: draft.title,
                startTime: draft.startTime,
                endTime: draft.endTime,
              );
              final mode =
                  created['mode'] == 'direct' ? 'direto' : 'app Agenda';
              final detail =
                  '${draft.title} (${CalendarEvent._two(draft.startTime.day)}/${CalendarEvent._two(draft.startTime.month)} ${CalendarEvent._two(draft.startTime.hour)}:${CalendarEvent._two(draft.startTime.minute)}) [$mode]';
              logs.add('📅 Evento "$detail"');
              await recordAudit(
                actor: actor,
                action: 'CREATE_EVENT',
                target: draft.title,
                status: 'EXECUTED',
                detail: detail,
              );
            }
            break;
          case 'CANCEL_EVENT':
          case 'CANCELAR_EVENTO':
            final targetSpec = parts.skip(1).join(':').trim();
            if (targetSpec.isNotEmpty) {
              final isNumericId = RegExp(r'^\d+$').hasMatch(targetSpec);
              final res = await cancelCalendarEvent(
                eventId: isNumericId ? targetSpec : '',
                title: isNumericId ? '' : targetSpec,
              );
              final deleted = res['deleted'] == true;
              final label = (res['title'] as String?)?.trim().isNotEmpty == true
                  ? res['title'] as String
                  : targetSpec;
              logs.add(
                deleted
                    ? '🗑️ Evento removido: "$label"'
                    : '⚠️ Evento não encontrado: "$targetSpec"',
              );
              await recordAudit(
                actor: actor,
                action: 'CANCEL_EVENT',
                target: targetSpec,
                status: deleted ? 'EXECUTED' : 'NOT_FOUND',
                detail: deleted ? 'Removido: $label' : 'Não encontrado',
              );
            }
            break;
          case 'REMINDER_CREATE':
            final rawRem = parts.skip(1).join(':').trim();
            final draft = ReminderService.parseReminderSpec(rawRem);
            if (draft != null) {
              final item = await createReminder(
                title: draft.title,
                scheduledAt: draft.scheduledAt,
              );
              logs.add(
                '⏰ Lembrete #${item.id} (${item.formattedSchedule}): ${item.title}',
              );
              await recordAudit(
                actor: actor,
                action: 'REMINDER_CREATE',
                target: '#${item.id} ${item.title}',
                status: 'EXECUTED',
                detail: item.formattedSchedule,
              );
            }
            break;
          case 'REMINDER_LIST':
            final items = await listReminders(onlyPending: true);
            if (items.isEmpty) {
              logs.add('⏰ Nenhum lembrete pendente');
            } else {
              final preview = items
                  .take(3)
                  .map((r) => '#${r.id} ${r.formattedSchedule} ${r.title}')
                  .join(' | ');
              logs.add('⏰ ${items.length} lembrete(s): $preview');
            }
            break;
          case 'REMINDER_CANCEL':
            final cancelSpec = parts.skip(1).join(':').trim();
            if (cancelSpec.isNotEmpty) {
              final cancelled = await cancelReminder(cancelSpec);
              logs.add(
                cancelled != null
                    ? '🗑️ Lembrete #${cancelled.id} cancelado: "${cancelled.title}"'
                    : '⚠️ Lembrete não encontrado: "$cancelSpec"',
              );
              await recordAudit(
                actor: actor,
                action: 'REMINDER_CANCEL',
                target: cancelSpec,
                status: cancelled != null ? 'EXECUTED' : 'NOT_FOUND',
                detail: cancelled?.title ?? 'Não encontrado',
              );
            }
            break;
          case 'SPOTIFY_SEARCH':
          case 'SPOTIFY_BUSCAR':
            final q = parts.skip(1).join(':').trim();
            final sp = getSpotifyService();
            if (!await sp.isConnected()) {
              final paired = await _hasDesktopPairedSafe();
              logs.add(sp.buildNotConfiguredMessage(hasDesktopPaired: paired));
            } else if (q.isNotEmpty) {
              final tracks = await sp.searchTracks(q, limit: 4);
              if (tracks.isEmpty) {
                logs.add('🎵 Nenhuma faixa no Spotify para "$q"');
              } else {
                final top = tracks
                    .take(3)
                    .map((t) => '${t.name} (${t.artist})')
                    .join(' | ');
                logs.add('🎵 Spotify (${tracks.length}): $top');
              }
            }
            break;
          case 'SPOTIFY_STATE':
          case 'SPOTIFY_ESTADO':
            final sp = getSpotifyService();
            if (!await sp.isConnected()) {
              final paired = await _hasDesktopPairedSafe();
              logs.add(sp.buildNotConfiguredMessage(hasDesktopPaired: paired));
            } else {
              final st = await sp.getPlaybackState();
              logs.add(st.formatSummary());
            }
            break;
          case 'SPOTIFY_PLAY':
          case 'SPOTIFY_TOCAR':
            final target = parts.skip(1).join(':').trim();
            final sp = getSpotifyService();
            if (!await sp.isConnected()) {
              final paired = await _hasDesktopPairedSafe();
              logs.add(sp.buildNotConfiguredMessage(hasDesktopPaired: paired));
            } else {
              final msg = await sp.play(target);
              logs.add(msg);
            }
            break;
          case 'SPOTIFY_PLAYLISTS':
          case 'SPOTIFY_LISTAR_PLAYLISTS':
            final sp = getSpotifyService();
            if (!await sp.isConnected()) {
              final paired = await _hasDesktopPairedSafe();
              logs.add(sp.buildNotConfiguredMessage(hasDesktopPaired: paired));
            } else {
              final pls = await sp.listUserPlaylists(limit: 10);
              if (pls.isEmpty) {
                logs.add('🎵 Nenhuma playlist encontrada no Spotify');
              } else {
                final preview =
                    pls.take(4).map((p) => '${p.name} (${p.tracksTotal})').join(' | ');
                logs.add('🎵 Playlists (${pls.length}): $preview');
              }
            }
            break;
          case 'SPOTIFY_ADD_PLAYLIST':
          case 'SPOTIFY_ADICIONAR_PLAYLIST':
            final rawSpec = parts.skip(1).join(':').trim();
            final sp = getSpotifyService();
            if (!await sp.isConnected()) {
              final paired = await _hasDesktopPairedSafe();
              logs.add(sp.buildNotConfiguredMessage(hasDesktopPaired: paired));
            } else if (rawSpec.isNotEmpty) {
              final pipeIdx = rawSpec.indexOf('|');
              final plTarget = (pipeIdx >= 0
                      ? rawSpec.substring(0, pipeIdx)
                      : rawSpec)
                  .trim();
              final trackTarget =
                  pipeIdx >= 0 ? rawSpec.substring(pipeIdx + 1).trim() : '';
              final msg = await sp.addTrackToPlaylist(
                playlistIdOrName: plTarget,
                trackUriOrQuery: trackTarget,
              );
              logs.add(msg);
            }
            break;
          case 'HTTP_GET':
          case 'HTTP_POST':
          case 'HTTP_PUT':
          case 'HTTP_PATCH':
          case 'HTTP_DELETE':
            final method = cmd.substring('HTTP_'.length);
            final spec = parts.skip(1).join(':').trim();
            final httpSummary = await _dispatchHttpBridge(
              method: method,
              spec: spec,
            );
            logs.add(httpSummary);
            await recordAudit(
              actor: actor,
              action: cmd,
              target: sim.targetResource,
              status: 'EXECUTED',
              detail: httpSummary,
            );
            break;
        }
        if (cmd == 'WHATSAPP' ||
            cmd == 'SMS' ||
            cmd == 'REPLY_MESSAGE' ||
            cmd == 'DIAL') {
          await recordAudit(
            actor: actor,
            action: cmd,
            target: sim.targetResource,
            status: 'EXECUTED',
            detail: logs.isEmpty ? cmd : logs.last,
          );
        }
      } catch (e) {
        logs.add('⚠️ Falha em $cmd: $e');
        await recordAudit(
          actor: actor,
          action: cmd,
          target: sim.targetResource,
          status: 'FAILED',
          detail: '$e',
        );
      }
    }

    final clean = rawReply.replaceAll(pattern, '').trim();
    return AiActionExecution(
      cleanText: clean.isEmpty ? 'Comando executado no dispositivo.' : clean,
      executedLogs: logs,
    );
  }

  /// Dispara requisição HTTP/HTTPS configurada em `Skills/*.md` (`[HTTP:POST:url|json]`)
  /// para integrações IoT (Home Assistant, ESPHome, Node-RED, webhooks locais).
  Future<String> _dispatchHttpBridge({
    required String method,
    required String spec,
  }) async {
    final pipeIdx = spec.indexOf('|');
    final rawUrl = (pipeIdx >= 0 ? spec.substring(0, pipeIdx) : spec).trim();
    final body = pipeIdx >= 0 ? spec.substring(pipeIdx + 1).trim() : '';

    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      throw ArgumentError('URL HTTP/HTTPS inválida no Skill Bridge: "$rawUrl"');
    }
    if (ActionGate.isBlockedMetadataHost(uri.host)) {
      throw ArgumentError(
        'Endpoint bloqueado por política anti-SSRF (metadata/link-local): "${uri.host}"',
      );
    }
    if (uri.scheme == 'http' &&
        !DesktopPairingService.isLanOrLocalHost(uri.host)) {
      throw ArgumentError(
        'HTTPS obrigatório para requisições HTTP fora da rede local (LAN): "$rawUrl"',
      );
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client
          .openUrl(method.toUpperCase(), uri)
          .timeout(const Duration(seconds: 6));
      req.headers.set('User-Agent', 'ULTRON-Mobile/1.4');
      req.headers.set('Accept', 'application/json, text/plain;q=0.9');
      if (body.isNotEmpty) {
        req.headers.contentType = ContentType.json;
        req.write(body);
      }
      final resp = await req.close().timeout(const Duration(seconds: 6));
      final respText = (await utf8.decoder
              .bind(resp)
              .join()
              .timeout(const Duration(seconds: 4)))
          .trim();
      final portPart = uri.hasPort ? ':${uri.port}' : '';
      if (resp.statusCode >= 400) {
        throw HttpException(
          'HTTP ${resp.statusCode} em ${uri.host}$portPart${uri.path}',
          uri: uri,
        );
      }
      final snippet = respText.isEmpty
          ? ''
          : ' • ${respText.length > 80 ? '${respText.substring(0, 80)}…' : respText}';
      return '🌐 HTTP $method ${uri.host}$portPart${uri.path} (${resp.statusCode})$snippet';
    } finally {
      client.close(force: true);
    }
  }

  static const Map<String, _MediaActionSpec> _mediaActionSpecs = {
    'MEDIA_PLAY': _MediaActionSpec(
      action: 'play',
      logLabel: '▶️ Reprodução retomada',
      message: '▶️ Reprodução de mídia retomada.',
      speakText: 'Reproduzindo mídia.',
    ),
    'MEDIA_PAUSE': _MediaActionSpec(
      action: 'pause',
      logLabel: '⏸️ Mídia pausada',
      message: '⏸️ Reprodução de mídia pausada.',
      speakText: 'Mídia pausada.',
    ),
    'MEDIA_PLAY_PAUSE': _MediaActionSpec(
      action: 'play_pause',
      logLabel: '⏯️ Play/Pause enviado',
      message: '⏯️ Comando Play/Pause enviado ao player ativo.',
      speakText: 'Alternando reprodução.',
    ),
    'MEDIA_NEXT': _MediaActionSpec(
      action: 'next',
      logLabel: '⏭️ Próxima faixa',
      message: '⏭️ Avançando para a próxima faixa.',
      speakText: 'Próxima faixa.',
    ),
    'MEDIA_PREVIOUS': _MediaActionSpec(
      action: 'previous',
      logLabel: '⏮️ Faixa anterior',
      message: '⏮️ Voltando para a faixa anterior.',
      speakText: 'Faixa anterior.',
    ),
    'MEDIA_STOP': _MediaActionSpec(
      action: 'stop',
      logLabel: '⏹️ Mídia parada',
      message: '⏹️ Reprodução de mídia interrompida.',
      speakText: 'Mídia parada.',
    ),
  };

  static final List<({RegExp pattern, String tag})> _naturalMediaMatchers = [
    (
      pattern: RegExp(
        r'\b(pr[oó]xima|avan[cç]ar|pular)\s+(?:a\s+)?(?:m[uú]sica|faixa|v[ií]deo|m[ií]dia)\b|^(?:pr[oó]xima|pular)$',
      ),
      tag: 'MEDIA_NEXT',
    ),
    (
      pattern: RegExp(
        r'\b(?:m[uú]sica|faixa|v[ií]deo)\s+anterior\b|\bvoltar\s+(?:a\s+)?(?:m[uú]sica|faixa)\b',
      ),
      tag: 'MEDIA_PREVIOUS',
    ),
    (
      pattern: RegExp(
        r'\b(pausar|pausa)\s+(?:a\s+)?(?:m[uú]sica|m[ií]dia|reprodu[cç][aã]o|v[ií]deo|spotify|player)\b|^(?:pausar|pausa)$',
      ),
      tag: 'MEDIA_PAUSE',
    ),
    (
      pattern: RegExp(
        r'\b(tocar|reproduzir|continuar|retomar|dar\s+play|play\s+na)\s+(?:a\s+)?(?:m[uú]sica|m[ií]dia|reprodu[cç][aã]o|v[ií]deo|spotify|player)\b|^(?:dar\s+)?play$|^(?:retomar|continuar)\s+m[uú]sica$',
      ),
      tag: 'MEDIA_PLAY',
    ),
    (
      pattern: RegExp(r'\bplay\s*/?\s*pause\b|^alternar\s+m[ií]dia$'),
      tag: 'MEDIA_PLAY_PAUSE',
    ),
    (
      pattern: RegExp(
        r'\b(parar|interromper|encerrar)\s+(?:a\s+)?(?:m[uú]sica|m[ií]dia|reprodu[cç][aã]o|spotify|player)\b',
      ),
      tag: 'MEDIA_STOP',
    ),
  ];

  Future<DeviceActionResult?> _tryHandleCalendarNaturalCommand(
    String text,
    String lower, {
    ActionGateConfirmCallback? confirmAction,
  }) async {
    if (RegExp(
      r'^(?:ver|ler|abrir|mostrar|quais(?:\s+s[aã]o)?(?:\s+os)?)?\s*(?:minha\s+|meus\s+)?(?:agenda|compromissos?|eventos?)(?:\s+de\s+hoje|\s+para\s+hoje|\s+de\s+amanh[aã]|\s+da\s+semana)?$',
      caseSensitive: false,
    ).hasMatch(lower)) {
      final isTomorrow = lower.contains('amanhã') || lower.contains('amanha');
      final isWeek = lower.contains('semana');
      final now = DateTime.now();
      final base = DateTime(now.year, now.month, now.day);
      final from = isTomorrow ? base.add(const Duration(days: 1)) : base;
      final daysAhead = isWeek ? 7 : 1;
      final events = await getCalendarEvents(from: from, daysAhead: daysAhead);
      if (events.isEmpty) {
        final period = isWeek
            ? 'para os próximos 7 dias'
            : isTomorrow
                ? 'para amanhã'
                : 'para hoje';
        return DeviceActionResult(
          handled: true,
          message: '📅 Agenda livre $period — nenhum compromisso encontrado.',
          speakText: 'Sua agenda está livre $period.',
        );
      }
      final lines =
          events.map((e) => e.formatLine(includeDate: isWeek)).join('\n');
      final first = events.first;
      return DeviceActionResult(
        handled: true,
        message: '📅 COMPROMISSOS (${events.length}):\n$lines',
        speakText:
            'Você tem ${events.length} compromissos. O primeiro é ${first.title}, às ${first.timeRangeLabel}.',
      );
    }

    if (RegExp(
      r'^(?:agendar|marcar|criar\s+(?:evento|compromisso)|adicionar\s+(?:evento|compromisso))\b',
      caseSensitive: false,
    ).hasMatch(lower)) {
      final draft = parseNaturalCalendarEvent(text);
      if (draft == null) {
        return const DeviceActionResult(
          handled: true,
          message:
              '📅 Informe o título e horário. Ex.: "agendar reunião com Carlos amanhã às 15:00".',
        );
      }
      final formattedWhen =
          '${CalendarEvent._two(draft.startTime.day)}/${CalendarEvent._two(draft.startTime.month)} ${CalendarEvent._two(draft.startTime.hour)}:${CalendarEvent._two(draft.startTime.minute)}';
      final sim = actionGate.simulate(
        'CREATE_EVENT:${draft.title}:$formattedWhen',
      );
      final allowed = await authorizeAction(
        sim,
        confirmAction: confirmAction ?? (_) async => true,
      );
      if (!allowed) {
        return const DeviceActionResult(
          handled: true,
          message: '🚫 Criação de evento cancelada ou bloqueada pelo nível de acesso.',
          speakText: 'Agendamento bloqueado.',
        );
      }
      final res = await createCalendarEvent(
        title: draft.title,
        startTime: draft.startTime,
        endTime: draft.endTime,
      );
      final calName = (res['calendarName'] as String?) ?? 'Agenda';
      return DeviceActionResult(
        handled: true,
        message:
            '📅 Evento agendado em $calName:\n• ${draft.title} ($formattedWhen)',
        speakText: 'Evento ${draft.title} agendado para $formattedWhen.',
      );
    }

    final cancelEventMatch = RegExp(
      r'^(?:cancelar|remover|excluir|apagar)\s+(?:o\s+|a\s+)?(?:evento|compromisso)(?:\s+da\s+agenda)?\s*[:\s]+(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (cancelEventMatch != null) {
      final rawTarget = cancelEventMatch.group(1)!.trim().replaceFirst(RegExp(r'^#'), '');
      if (rawTarget.isNotEmpty) {
        final sim = actionGate.simulate('CANCEL_EVENT:$rawTarget');
        final allowed = await authorizeAction(
          sim,
          confirmAction: confirmAction ?? (_) async => true,
        );
        if (!allowed) {
          return const DeviceActionResult(
            handled: true,
            message:
                '🚫 Remoção de evento cancelada ou bloqueada pelo nível de acesso.',
            speakText: 'Cancelamento de evento bloqueado.',
          );
        }
        final isNumeric = RegExp(r'^\d+$').hasMatch(rawTarget);
        final res = await cancelCalendarEvent(
          eventId: isNumeric ? rawTarget : '',
          title: isNumeric ? '' : rawTarget,
        );
        final deleted = res['deleted'] == true;
        final label = (res['title'] as String?)?.trim().isNotEmpty == true
            ? res['title'] as String
            : rawTarget;
        await recordAudit(
          actor: 'OPERATOR',
          action: 'CANCEL_EVENT',
          target: rawTarget,
          status: deleted ? 'EXECUTED' : 'NOT_FOUND',
          detail: deleted ? 'Evento removido: $label' : 'Não encontrado',
        );
        return DeviceActionResult(
          handled: true,
          message: deleted
              ? '🗑️ Evento removido da agenda: "$label".'
              : '⚠️ Nenhum evento encontrado na agenda para "$rawTarget".',
          speakText: deleted
              ? 'Evento $label removido da agenda.'
              : 'Não encontrei o evento $rawTarget na agenda.',
        );
      }
    }

    return null;
  }

  Future<DeviceActionResult?> _tryHandleObsidianCrudNaturalCommand(
    String text,
    String lower, {
    ActionGateConfirmCallback? confirmAction,
  }) async {
    // 1. UNDO ("desfazer", "desfazer nota", "desfazer última alteração no obsidian")
    if (RegExp(
      r'^(?:desfazer|reverter)(?:\s+(?:[uú]ltima\s+)?(?:a[cç][aã]o|altera[cç][aã]o|nota|edi[cç][aã]o|no\s+obsidian|no\s+cofre))?$',
      caseSensitive: false,
    ).hasMatch(lower)) {
      final res = await undoLastObsidianMutation();
      if (res.undone) {
        await recordAudit(
          actor: 'OPERATOR',
          action: 'UNDO',
          target: res.relativePath,
          status: 'EXECUTED',
          detail: res.message,
        );
      }
      return DeviceActionResult(
        handled: true,
        message: res.message,
        speakText: res.undone
            ? 'Última alteração no cofre desfeita.'
            : 'Não há alterações recentes para desfazer.',
      );
    }

    // 2. OBSIDIAN_STATUS ("status do obsidian", "status do cofre", "estatísticas do cofre")
    if (RegExp(
      r'^(?:status|estat[ií]sticas)\s+do\s+(?:obsidian|cofre|segundo\s+c[eé]rebro)$|^obsidian\s+status$',
      caseSensitive: false,
    ).hasMatch(lower)) {
      final status = await getObsidianStatus();
      return DeviceActionResult(
        handled: true,
        message: status.formatSummary(),
        speakText:
            'O cofre ${status.vaultName} possui ${status.totalNotes} notas, totalizando ${status.sizeLabel}.',
      );
    }

    // 3. OBSIDIAN_LIST ("listar notas", "listar notas em Memoria", "notas do obsidian")
    final listMatch = RegExp(
      r'^(?:listar\s+notas|notas\s+do\s+(?:obsidian|cofre)|obsidian\s+notas)(?:\s+(?:em|da\s+pasta|de)\s+([a-zA-Z0-9_\-/]+)|\s+([a-zA-Z0-9_\-/]+))?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (listMatch != null) {
      final rawFolder = (listMatch.group(1) ?? listMatch.group(2) ?? '').trim();
      final notes = await listObsidianNotes(
        folder: rawFolder.isEmpty ? null : rawFolder,
      );
      if (notes.isEmpty) {
        return DeviceActionResult(
          handled: true,
          message:
              '📓 Nenhuma nota encontrada${rawFolder.isEmpty ? ' no cofre.' : ' na pasta "$rawFolder".'}',
          speakText: 'Nenhuma nota encontrada.',
        );
      }
      final lines = notes
          .take(25)
          .map((n) => '• ${n.relativePath} (${n.title})')
          .join('\n');
      return DeviceActionResult(
        handled: true,
        message:
            '📓 NOTAS DO COFRE${rawFolder.isEmpty ? '' : ' [$rawFolder]'} (${notes.length}):\n$lines',
        speakText: '${notes.length} notas encontradas no cofre.',
      );
    }

    // 4. OBSIDIAN_READ ("ler nota Memoria/Operador.md", "abrir nota Operador")
    final readMatch = RegExp(
      r'^(?:ler\s+nota|mostrar\s+nota|ver\s+nota|obsidian\s+ler)\s*[:\s]+(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (readMatch != null) {
      final targetPath = readMatch.group(1)!.trim();
      final content = await readObsidianNote(targetPath);
      return DeviceActionResult(
        handled: true,
        message: '📖 NOTA ($targetPath):\n${content.trim()}',
        speakText: 'Nota $targetPath carregada.',
      );
    }

    // 5. OBSIDIAN_APPEND ("anexar na nota Memoria/Operador.md: texto", "adicionar à nota X: texto")
    final appendMatch = RegExp(
      r'^(?:anexar\s+(?:na\s+nota|em)|adicionar\s+(?:na\s+nota|[àa]\s+nota)|obsidian\s+anexar)\s+([^:]+?)\s*:\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (appendMatch != null) {
      final targetPath = appendMatch.group(1)!.trim();
      final appendBody = appendMatch.group(2)!.trim();
      final file = await appendObsidianNote(targetPath, appendBody);
      final name = file.uri.pathSegments.last;
      return DeviceActionResult(
        handled: true,
        message: '✍️ Texto anexado em $name:\n"$appendBody"',
        speakText: 'Texto anexado na nota $name.',
      );
    }

    // 6. OBSIDIAN_TASKS ("listar tarefas do obsidian", "marcar tarefa 1", "desmarcar tarefa 1")
    if (RegExp(
      r'^(?:listar\s+tarefas(?:\s+do\s+(?:obsidian|cofre))?|tarefas\s+do\s+(?:obsidian|cofre)|obsidian\s+tarefas)$',
      caseSensitive: false,
    ).hasMatch(lower)) {
      final tasks = await listObsidianTasks();
      if (tasks.isEmpty) {
        return const DeviceActionResult(
          handled: true,
          message: '☑️ Nenhuma tarefa Markdown (- [ ] / - [x]) encontrada no cofre.',
          speakText: 'Nenhuma tarefa encontrada no cofre.',
        );
      }
      final lines = tasks.take(25).map((t) => t.formatLine()).join('\n');
      final pendingCount = tasks.where((t) => !t.completed).length;
      return DeviceActionResult(
        handled: true,
        message:
            '☑️ TAREFAS DO COFRE (${tasks.length} total • $pendingCount pendente(s)):\n$lines',
        speakText:
            'Você tem ${tasks.length} tarefas no cofre, sendo $pendingCount pendentes.',
      );
    }

    final toggleTaskMatch = RegExp(
      r'^(?:(marcar|concluir|desmarcar|reabrir|alternar)\s+tarefa(?:\s+do\s+obsidian)?)\s+#?(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (toggleTaskMatch != null) {
      final verb = toggleTaskMatch.group(1)!.toLowerCase();
      final selector = toggleTaskMatch.group(2)!.trim();
      final completed = (verb == 'marcar' || verb == 'concluir')
          ? true
          : (verb == 'desmarcar' || verb == 'reabrir')
              ? false
              : null;
      final asIdx = int.tryParse(selector);
      final updated = await toggleObsidianTask(
        taskIndex: asIdx,
        queryText: asIdx == null ? selector : null,
        completed: completed,
      );
      return DeviceActionResult(
        handled: true,
        message: '☑️ Tarefa atualizada: ${updated.formatLine()}',
        speakText: updated.completed
            ? 'Tarefa ${updated.text} marcada como concluída.'
            : 'Tarefa ${updated.text} reaberta.',
      );
    }

    return null;
  }

  Future<DeviceActionResult?> _tryHandleReminderNaturalCommand(
    String text,
    String lower, {
    ActionGateConfirmCallback? confirmAction,
  }) async {
    // 1. REMINDER_LIST ("meus lembretes", "listar lembretes", "quais são meus lembretes")
    if (RegExp(
      r'^(?:ver|listar|mostrar|quais(?:\s+s[aã]o)?(?:\s+os)?)?\s*(?:meus\s+)?lembretes(?:\s+pendentes|\s+ativos)?$',
      caseSensitive: false,
    ).hasMatch(lower)) {
      final reminders = await listReminders(onlyPending: true);
      if (reminders.isEmpty) {
        return const DeviceActionResult(
          handled: true,
          message: '⏰ Nenhum lembrete pendente agendado.',
          speakText: 'Você não tem lembretes pendentes.',
        );
      }
      final lines = reminders.map((r) => r.formatLine()).join('\n');
      return DeviceActionResult(
        handled: true,
        message: '⏰ LEMBRETES PENDENTES (${reminders.length}):\n$lines',
        speakText:
            'Você tem ${reminders.length} lembretes pendentes. O próximo é ${reminders.first.title}.',
      );
    }

    // 2. REMINDER_CANCEL ("cancelar lembrete 1", "remover lembrete Tomar água")
    final cancelRemMatch = RegExp(
      r'^(?:cancelar|remover|excluir|apagar)\s+(?:o\s+)?lembrete\s*[:\s]+#?(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (cancelRemMatch != null) {
      final target = cancelRemMatch.group(1)!.trim();
      final cancelled = await cancelReminder(target);
      if (cancelled == null) {
        return DeviceActionResult(
          handled: true,
          message: '⚠️ Lembrete "$target" não encontrado.',
          speakText: 'Não encontrei o lembrete $target.',
        );
      }
      return DeviceActionResult(
        handled: true,
        message:
            '🗑️ Lembrete #${cancelled.id} cancelado: "${cancelled.title}" (${cancelled.formattedSchedule}).',
        speakText: 'Lembrete ${cancelled.title} cancelado.',
      );
    }

    // 3. REMINDER_CREATE ("me lembre de tomar água daqui 15 minutos", "criar lembrete 18:00 Ligar para João")
    if (RegExp(
      r'^(?:criar\s+lembrete|novo\s+lembrete|agendar\s+lembrete|me\s+lembre(?:\s+de)?|lembrar(?:-me)?\s+de)\b',
      caseSensitive: false,
    ).hasMatch(lower)) {
      final draft = ReminderService.parseReminderSpec(text);
      if (draft == null) {
        return const DeviceActionResult(
          handled: true,
          message:
              '⏰ Informe o texto e horário do lembrete. Ex.: "me lembre de tomar água daqui 20 minutos".',
        );
      }
      final item = await createReminder(
        title: draft.title,
        scheduledAt: draft.scheduledAt,
      );
      return DeviceActionResult(
        handled: true,
        message:
            '⏰ Lembrete #${item.id} agendado para ${item.formattedSchedule}:\n• "${item.title}"',
        speakText:
            'Lembrete ${item.title} agendado para ${item.formattedSchedule}.',
      );
    }

    return null;
  }

  Future<DeviceActionResult?> _tryHandleWebInfoNaturalCommand(
    String text,
    String lower,
  ) async {
    // 1. WEATHER ("clima", "clima em São Paulo", "previsão do tempo em Curitiba", "qual a temperatura em ...")
    final weatherMatch = RegExp(
      r'^(?:qual\s+(?:[eé]\s+)?(?:o\s+|a\s+)?)?(?:clima|previs[aã]o\s+do\s+tempo|temperatura)(?:\s+(?:em|de|para|no|na)\s+(.+)|\s+(.+))?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (weatherMatch != null) {
      final rawCity =
          (weatherMatch.group(1) ?? weatherMatch.group(2) ?? '').trim();
      final city = rawCity.toLowerCase() == 'hoje' ||
              rawCity.toLowerCase() == 'agora'
          ? ''
          : rawCity;
      final snap = await fetchWeather(city: city.isEmpty ? null : city);
      if (snap == null) {
        return DeviceActionResult(
          handled: true,
          message:
              '🌤️ Previsão meteorológica indisponível no momento${city.isEmpty ? '.' : ' para "$city".'}',
          speakText: 'Não consegui consultar o clima agora.',
        );
      }
      return DeviceActionResult(
        handled: true,
        message: '🌤️ CLIMA ATUAL:\n• ${snap.summaryLine}',
        speakText: snap.spokenLine,
      );
    }

    // 2. NEWS ("notícias", "notícias sobre tecnologia", "manchetes do dia")
    final newsMatch = RegExp(
      r'^(?:ver\s+|ler\s+|mostrar\s+|quais(?:\s+s[aã]o)?(?:\s+as)?\s+)?(?:[uú]ltimas\s+|principais\s+)?(?:not[ií]cias|manchetes)(?:\s+(?:sobre|de|do|da)\s+(.+)|\s+(.+))?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (newsMatch != null) {
      final rawTopic =
          (newsMatch.group(1) ?? newsMatch.group(2) ?? '').trim();
      final topic = (rawTopic.toLowerCase() == 'hoje' ||
              rawTopic.toLowerCase() == 'dia' ||
              rawTopic.toLowerCase() == 'do dia' ||
              rawTopic.toLowerCase() == 'principais')
          ? ''
          : rawTopic;
      final articles = await fetchNews(topic: topic, limit: 5);
      if (articles.isEmpty) {
        return DeviceActionResult(
          handled: true,
          message:
              '📰 Nenhuma notícia encontrada${topic.isEmpty ? ' no feed RSS.' : ' para "$topic".'}',
          speakText: 'Não encontrei notícias no momento.',
        );
      }
      final lines = articles.map((a) => a.formatLine()).join('\n');
      final header = topic.isEmpty
          ? '📰 PRINCIPAIS NOTÍCIAS (${articles.length}):'
          : '📰 NOTÍCIAS SOBRE "${topic.toUpperCase()}" (${articles.length}):';
      return DeviceActionResult(
        handled: true,
        message: '$header\n$lines',
        speakText:
            'Encontrei ${articles.length} notícias. A principal é: ${articles.first.title}.',
      );
    }

    // 3. WEB_SEARCH ("pesquisar_web ...", "resumo web ...", "consulta web: ...")
    final webSearchMatch = RegExp(
      r'^(?:pesquisar_web|pesquisa\s+web|resumo\s+web|consultar?\s+na\s+web)\s*[:\s]+(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (webSearchMatch != null) {
      final query = webSearchMatch.group(1)!.trim();
      final summary = await searchWebSummary(query, limit: 4);
      return DeviceActionResult(
        handled: true,
        message: summary.formatReport(),
        speakText: summary.speakText,
      );
    }

    return null;
  }

  Future<DeviceActionResult?> _tryHandleSkillAndWorkflowNaturalCommand(
    String text,
    String lower, {
    ActionGateConfirmCallback? confirmAction,
  }) async {
    // 1. SKILL_CREATE ("criar skill modo_foco | [ACTION:VOLUME_SET:20]")
    final createSkillMatch = RegExp(
      r'^(?:criar|salvar|nova)\s+skill\s+([^|:]+?)\s*[|:]\s*([\s\S]+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (createSkillMatch != null) {
      final name = createSkillMatch.group(1)!.trim();
      final body = createSkillMatch.group(2)!.trim();
      final sim = actionGate.simulate('[ACTION:SKILL_CREATE:$name|$body]');
      final allowed = await authorizeAction(
        sim,
        confirmAction: confirmAction ?? (_) async => true,
      );
      if (!allowed) {
        return const DeviceActionResult(
          handled: true,
          message:
              '🚫 Criação de Skill cancelada ou bloqueada pelo Action Gate.',
          speakText: 'Criação de skill bloqueada.',
        );
      }
      final created = await createObsidianSkill(name, body);
      await recordAudit(
        actor: 'OPERATOR',
        action: 'SKILL_CREATE',
        target: 'Skills/${created.id}.md',
        status: 'EXECUTED',
        detail: created.title,
      );
      return DeviceActionResult(
        handled: true,
        message:
            '⚡ Skill criada com sucesso em Skills/${created.id}.md (${created.title}).',
        speakText: 'Skill ${created.title} criada no cofre.',
      );
    }

    // 2. SKILL_DELETE ("excluir skill modo_foco", "remover skill modo_foco")
    final deleteSkillMatch = RegExp(
      r'^(?:excluir|remover|apagar|deletar)\s+skill\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (deleteSkillMatch != null) {
      final name = deleteSkillMatch.group(1)!.trim();
      final sim = actionGate.simulate('[ACTION:SKILL_DELETE:$name]');
      final allowed = await authorizeAction(
        sim,
        confirmAction: confirmAction ?? (_) async => true,
      );
      if (!allowed) {
        return const DeviceActionResult(
          handled: true,
          message:
              '🚫 Exclusão de Skill cancelada ou bloqueada pelo Action Gate.',
          speakText: 'Exclusão de skill bloqueada.',
        );
      }
      final deleted = await deleteObsidianSkill(name);
      await recordAudit(
        actor: 'OPERATOR',
        action: 'SKILL_DELETE',
        target: 'Skills/$name.md',
        status: deleted ? 'EXECUTED' : 'NOT_FOUND',
        detail: deleted ? 'Removida' : 'Não encontrada',
      );
      return DeviceActionResult(
        handled: true,
        message: deleted
            ? '🗑️ Skill "$name" removida de Skills/ (use /desfazer para restaurar).'
            : '⚠️ Skill "$name" não encontrada em Skills/.',
        speakText:
            deleted ? 'Skill $name removida.' : 'Skill $name não encontrada.',
      );
    }

    // 3. FLOW_LIST ("listar fluxos", "meus fluxos", "fluxos agendados")
    if (RegExp(
      r'^(?:listar|ver|mostrar|meus)\s+fluxos(?:\s+agendados)?$|^fluxos$',
      caseSensitive: false,
    ).hasMatch(lower)) {
      final flows = await listWorkflows();
      if (flows.isEmpty) {
        return const DeviceActionResult(
          handled: true,
          message: '⚙️ Nenhum fluxo dinâmico cadastrado.',
          speakText: 'Você não tem fluxos cadastrados.',
        );
      }
      final lines = flows.map((f) => f.formatLine()).join('\n');
      return DeviceActionResult(
        handled: true,
        message: '⚙️ FLUXOS DINÂMICOS (${flows.length}):\n$lines',
        speakText: 'Você tem ${flows.length} fluxos cadastrados.',
      );
    }

    // 4. FLOW_CREATE ("criar fluxo rotina_manha | TORCH_OFF -> VOLUME_SET:40 | diario 07:00")
    final createFlowMatch = RegExp(
      r'^(?:criar|novo)\s+fluxo\s+([^|]+?)\s*\|\s*([^|]+?)(?:\s*\|\s*(.+))?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (createFlowMatch != null) {
      final name = createFlowMatch.group(1)!.trim();
      final steps = createFlowMatch.group(2)!.trim();
      final sched = (createFlowMatch.group(3) ?? '').trim();
      final sim = actionGate.simulate('[ACTION:FLOW_CREATE:$name|$steps|$sched]');
      final allowed = await authorizeAction(
        sim,
        confirmAction: confirmAction ?? (_) async => true,
      );
      if (!allowed) {
        return const DeviceActionResult(
          handled: true,
          message: '🚫 Criação de fluxo cancelada ou bloqueada pelo Action Gate.',
          speakText: 'Criação de fluxo bloqueada.',
        );
      }
      final flow = await createWorkflow(
        name: name,
        stepsPayload: steps,
        scheduleSpec: sched,
      );
      await recordAudit(
        actor: 'OPERATOR',
        action: 'FLOW_CREATE',
        target: flow.name,
        status: 'EXECUTED',
        detail: '${flow.stepsPayload} [${flow.formattedNextRun}]',
      );
      return DeviceActionResult(
        handled: true,
        message: '⚙️ Fluxo criado:\n${flow.formatLine()}',
        speakText: 'Fluxo ${flow.name} criado.',
      );
    }

    // 5. FLOW_SCHEDULE ("agendar fluxo rotina_manha: a cada 60m" or "agendar fluxo rotina_manha | 07:30")
    final schedFlowMatch = RegExp(
      r'^agendar\s+fluxo\s+([^|:]+?)\s*[|:]\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (schedFlowMatch != null) {
      final nameOrId = schedFlowMatch.group(1)!.trim();
      final spec = schedFlowMatch.group(2)!.trim();
      final sim = actionGate.simulate('[ACTION:FLOW_SCHEDULE:$nameOrId:$spec]');
      final allowed = await authorizeAction(
        sim,
        confirmAction: confirmAction ?? (_) async => true,
      );
      if (!allowed) {
        return const DeviceActionResult(
          handled: true,
          message:
              '🚫 Agendamento de fluxo cancelado ou bloqueado pelo Action Gate.',
          speakText: 'Agendamento bloqueado.',
        );
      }
      final updated = await scheduleWorkflow(
        nameOrId: nameOrId,
        scheduleSpec: spec,
      );
      await recordAudit(
        actor: 'OPERATOR',
        action: 'FLOW_SCHEDULE',
        target: updated.name,
        status: 'EXECUTED',
        detail: updated.formattedNextRun,
      );
      return DeviceActionResult(
        handled: true,
        message:
            '⏰ Fluxo "${updated.name}" agendado para ${updated.formattedNextRun}.',
        speakText: 'Fluxo ${updated.name} agendado.',
      );
    }

    // 6. FLOW_RUN ("executar fluxo rotina_manha", "rodar fluxo 1")
    final runFlowMatch = RegExp(
      r'^(?:executar|rodar|acionar|iniciar)\s+fluxo\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (runFlowMatch != null) {
      final nameOrId = runFlowMatch.group(1)!.trim();
      final res = await runWorkflow(
        nameOrId,
        confirmAction: confirmAction,
        isBackgroundTrigger: false,
      );
      return DeviceActionResult(
        handled: true,
        message: res.message,
        speakText: res.executed
            ? 'Fluxo ${res.flowName} executado.'
            : 'Fluxo ${res.flowName} bloqueado.',
      );
    }

    // 7. FLOW_DELETE ("excluir fluxo rotina_manha", "remover fluxo 1")
    final delFlowMatch = RegExp(
      r'^(?:excluir|remover|apagar|deletar|cancelar)\s+fluxo\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (delFlowMatch != null) {
      final nameOrId = delFlowMatch.group(1)!.trim();
      final sim = actionGate.simulate('[ACTION:FLOW_DELETE:$nameOrId]');
      final allowed = await authorizeAction(
        sim,
        confirmAction: confirmAction ?? (_) async => true,
      );
      if (!allowed) {
        return const DeviceActionResult(
          handled: true,
          message:
              '🚫 Exclusão de fluxo cancelada ou bloqueada pelo Action Gate.',
          speakText: 'Exclusão de fluxo bloqueada.',
        );
      }
      final deleted = await deleteWorkflow(nameOrId);
      await recordAudit(
        actor: 'OPERATOR',
        action: 'FLOW_DELETE',
        target: nameOrId,
        status: deleted != null ? 'EXECUTED' : 'NOT_FOUND',
        detail: deleted?.name ?? 'Não encontrado',
      );
      return DeviceActionResult(
        handled: true,
        message: deleted != null
            ? '🗑️ Fluxo "${deleted.name}" removido e alarme cancelado.'
            : '⚠️ Fluxo "$nameOrId" não encontrado.',
        speakText: deleted != null
            ? 'Fluxo ${deleted.name} removido.'
            : 'Fluxo não encontrado.',
      );
    }

    return null;
  }

  Future<DeviceActionResult?> _tryHandleSpotifyNaturalCommand(
    String text,
    String lower,
  ) async {
    Future<DeviceActionResult> degradedNotConnected() async {
      final sp = getSpotifyService();
      var paired = false;
      try {
        paired = (await _getDesktopPairing().loadPairing()) != null;
      } catch (_) {}
      return DeviceActionResult(
        handled: true,
        message: sp.buildNotConfiguredMessage(hasDesktopPaired: paired),
        speakText:
            'O Spotify Web API ainda não está conectado. Configure seu Client ID em Config IA.',
      );
    }

    // 1. SPOTIFY_STATE ("o que está tocando no spotify", "estado do spotify", "spotify status", "spotify estado")
    if (RegExp(
      r'^(?:o\s+que\s+est[aá]\s+tocando(?:\s+no\s+spotify)?|qual\s+m[uú]sica\s+est[aá]\s+tocando(?:\s+no\s+spotify)?|(?:estado|status)\s+do\s+spotify|spotify\s+(?:estado|status|state))$',
      caseSensitive: false,
    ).hasMatch(lower)) {
      final sp = getSpotifyService();
      if (!await sp.isConnected()) return degradedNotConnected();
      final state = await sp.getPlaybackState();
      return DeviceActionResult(
        handled: true,
        message: state.formatSummary(),
        speakText: state.speakText,
      );
    }

    // 2. SPOTIFY_PLAYLISTS ("listar playlists do spotify", "minhas playlists no spotify", "spotify playlists")
    if (RegExp(
      r'^(?:(?:listar|ver|mostrar|minhas)\s+playlists(?:\s+(?:do|no)\s+spotify)?|spotify\s+playlists)$',
      caseSensitive: false,
    ).hasMatch(lower)) {
      final sp = getSpotifyService();
      if (!await sp.isConnected()) return degradedNotConnected();
      final pls = await sp.listUserPlaylists(limit: 15);
      if (pls.isEmpty) {
        return const DeviceActionResult(
          handled: true,
          message: '🎵 Nenhuma playlist encontrada na sua conta Spotify.',
          speakText: 'Nenhuma playlist encontrada no Spotify.',
        );
      }
      final lines = pls.map((p) => p.formatLine()).join('\n');
      return DeviceActionResult(
        handled: true,
        message: '🎵 PLAYLISTS DO SPOTIFY (${pls.length}):\n$lines',
        speakText:
            'Você tem ${pls.length} playlists no Spotify. A primeira é ${pls.first.name}.',
      );
    }

    // 3. SPOTIFY_ADD_PLAYLIST ("adicionar à playlist Treino", "adicionar na playlist Foco | Starboy", "spotify adicionar playlist ...")
    final addPlMatch = RegExp(
      r'^(?:adicionar\s+(?:(?:essa\s+m[uú]sica|a\s+m[uú]sica\s+atual)\s+)?(?:[àa]|na)\s+playlist(?:\s+do\s+spotify)?|spotify\s+adicionar(?:\s+playlist)?)\s+([^|]+?)(?:\s*\|\s*(.+))?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (addPlMatch != null) {
      final sp = getSpotifyService();
      if (!await sp.isConnected()) return degradedNotConnected();
      final plName = addPlMatch.group(1)!.trim();
      final trackSpec = (addPlMatch.group(2) ?? '').trim();
      final msg = await sp.addTrackToPlaylist(
        playlistIdOrName: plName,
        trackUriOrQuery: trackSpec,
      );
      return DeviceActionResult(
        handled: true,
        message: msg,
        speakText: 'Faixa adicionada à playlist $plName.',
      );
    }

    // 4. SPOTIFY_SEARCH ("buscar no spotify: Daft Punk", "spotify buscar ...")
    final searchSpMatch = RegExp(
      r'^(?:(?:buscar|procurar|pesquisar)\s+no\s+spotify|spotify\s+(?:buscar|search))\s*[:\s]+(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (searchSpMatch != null) {
      final sp = getSpotifyService();
      if (!await sp.isConnected()) return degradedNotConnected();
      final query = searchSpMatch.group(1)!.trim();
      final tracks = await sp.searchTracks(query, limit: 5);
      if (tracks.isEmpty) {
        return DeviceActionResult(
          handled: true,
          message: '🎵 Nenhuma faixa encontrada no Spotify para "$query".',
          speakText: 'Não encontrei $query no Spotify.',
        );
      }
      final lines = tracks.map((t) => t.formatLine()).join('\n');
      return DeviceActionResult(
        handled: true,
        message: '🎵 RESULTADOS NO SPOTIFY ("$query"):\n$lines',
        speakText:
            'Encontrei ${tracks.length} faixas no Spotify. A principal é ${tracks.first.name}, de ${tracks.first.artist}.',
      );
    }

    // 5. SPOTIFY_PLAY ("tocar Starboy no spotify", "tocar no spotify: Starboy", "spotify tocar ...")
    final playSpMatchA = RegExp(
      r'^(?:tocar|reproduzir|colocar|bota)\s+(.+?)\s+no\s+spotify$',
      caseSensitive: false,
    ).firstMatch(text);
    final playSpMatchB = RegExp(
      r'^(?:(?:tocar|reproduzir)\s+no\s+spotify|spotify\s+(?:tocar|play))\s*[:\s]+(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    final playQuery =
        (playSpMatchA?.group(1) ?? playSpMatchB?.group(1) ?? '').trim();
    if (playQuery.isNotEmpty) {
      final sp = getSpotifyService();
      if (!await sp.isConnected()) return degradedNotConnected();
      final msg = await sp.play(playQuery);
      return DeviceActionResult(
        handled: true,
        message: msg,
        speakText: msg.replaceAll('🎵 ', ''),
      );
    }

    return null;
  }

  FileUtilitiesService? _cachedFileUtilities;

  FileUtilitiesService getFileUtilitiesService() {
    if (fileUtilitiesProvider != null) {
      return fileUtilitiesProvider!();
    }
    return _cachedFileUtilities ??= FileUtilitiesService(channel: _channel);
  }

  /// Despacha a criação de um Mini-App sandboxed no U.L.T.R.O.N. Desktop via
  /// `PC_EXEC_TOOL` (`create_mini_app`), passando obrigatoriamente pelo `ActionGate`
  /// crítico (confirmação explícita), validando a URL LAN/Tailscale + token retornados
  /// e abrindo opcionalmente no navegador do smartphone.
  Future<
      ({
        DesktopCommandResult bridgeResult,
        MiniAppLaunchResponse? miniApp,
        bool openedInBrowser,
      })> launchDesktopMiniApp(
    MiniAppLaunchRequest request, {
    Future<bool> Function(ActionSimulation)? confirmAction,
    bool autoOpenBrowser = true,
  }) async {
    final sim = actionGate.simulate(
      '[ACTION:PC_EXEC_TOOL:create_mini_app|${jsonEncode(request.toToolArgs()['params'])}]',
    );
    final allowed = await authorizeAction(
      sim,
      confirmAction: confirmAction ?? (_) async => false,
    );
    if (!allowed) {
      return (
        bridgeResult: const DesktopCommandResult(
          sent: false,
          deniedByUser: true,
          error: 'Criação de Mini-App bloqueada ou negada no Action Gate.',
        ),
        miniApp: null,
        openedInBrowser: false,
      );
    }

    final res = await sendDesktopBridgeCommand(
      command: 'PC_EXEC_TOOL',
      args: request.toToolArgs(),
      actor: 'OPERATOR',
      skipLocalConfirm: true,
    );
    if (!res.sent) {
      return (
        bridgeResult: res,
        miniApp: null,
        openedInBrowser: false,
      );
    }

    final parsed = MiniAppLaunchResponse.tryParse(res.responseBody);
    var opened = false;
    if (parsed != null && autoOpenBrowser) {
      try {
        opened = await openUrl(parsed.url);
      } catch (_) {}
    }
    return (
      bridgeResult: res,
      miniApp: parsed,
      openedInBrowser: opened,
    );
  }

  /// Marco 5 (v2.0.0): Executa o Projetista Elétrico offline (`/eletrica`),
  /// dimensiona pela NBR 5410, audita o circuito, salva em `Memoria/Engenharia/`
  /// no Obsidian e opcionalmente envia a Netlist ao Desktop (`PC_CLIPBOARD_PUSH`).
  Future<DeviceActionResult> executeEletricaCommand(
    String rawInput, {
    Future<bool> Function(ActionSimulation)? confirmAction,
  }) async {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      return const DeviceActionResult(
        handled: true,
        message: '⚡ **Projetista Elétrico Industrial (NBR 5410 / IEC)**\n'
            'Exemplos:\n'
            '• `/eletrica partida direta 5 cv 380v`\n'
            '• `/eletrica reversao 3 cv 220v cfw500`\n'
            '• `/eletrica estrela triangulo 10 cv 380v pc`\n'
            '• `/eletrica sequencia 5 cv 10s ad600m`',
        speakText:
            'Informe a topologia, potência em CV e tensão para o projetista elétrico.',
      );
    }

    const engine = EletricaEngine();
    final project = engine.designFromNaturalPrompt(trimmed);
    final netlist = project.exportNetlist();
    final svg = project.exportIecSvg();

    String? savedPath;
    try {
      final vault = await _getObsidian();
      final cvTag = project.sizing.powerCv.toStringAsFixed(1).replaceAll('.', '_');
      final notePath =
          'Memoria/Engenharia/Projeto_${project.topology.name}_${cvTag}CV_${project.sizing.voltageV}V.md';
      final markdown = '${project.formatTechnicalSummary()}\n\n'
          '## Netlist (Apoio CADe_SIMU)\n```text\n$netlist\n```\n\n'
          '## Diagrama Esquemático IEC (SVG)\n```svg\n$svg\n```\n';
      await vault.appendToNote(notePath, markdown, createIfMissing: true);
      _cachedVaultSearch?.invalidateSyncCache();
      savedPath = notePath;
    } catch (_) {}

    final lower = trimmed.toLowerCase();
    final wantsDesktop = lower.contains('pc') ||
        lower.contains('cadesimu') ||
        lower.contains('desktop') ||
        lower.contains('enviar');
    var desktopNote = '';
    if (wantsDesktop) {
      final paired = await _hasDesktopPairedSafe();
      if (paired) {
        final pcRes = await sendDesktopBridgeCommand(
          command: 'PC_CLIPBOARD_PUSH',
          args: <String, dynamic>{'text': netlist},
          actor: 'OPERATOR',
          confirmAction: confirmAction,
        );
        desktopNote = pcRes.sent
            ? '\n💻 Netlist enviada ao Clipboard do Desktop via Ponte LAN para montagem no CADe_SIMU.'
            : '\n⚠️ Ponte Desktop: ${pcRes.error ?? 'não enviada'}';
      } else {
        desktopNote =
            '\nℹ️ Desktop LAN não pareado: pareie em `/desktop` para enviar a Netlist automaticamente.';
      }
    }

    final savedNote = savedPath != null
        ? '\n📝 Ficha + Netlist + SVG salvos em `$savedPath` no Obsidian.'
        : '';

    return DeviceActionResult(
      handled: true,
      message: '${project.formatTechnicalSummary()}$savedNote$desktopNote',
      speakText:
          '${project.title} dimensionado. Corrente nominal ${project.sizing.nominalCurrentA.toStringAsFixed(1)} ampères, cabo ${project.sizing.cableSectionMm2} milímetros quadrados e disjuntor de ${project.sizing.breakerA} ampères.',
    );
  }

  Future<DeviceActionResult> executeFileUtilityCommand(
    String rawInput, {
    Future<bool> Function(ActionSimulation)? confirmAction,
  }) async {
    final trimmed = rawInput.trim();
    final res = await _tryHandleFileUtilitiesNaturalCommand(
      trimmed,
      trimmed.toLowerCase(),
      confirmAction: confirmAction,
    );
    if (res != null) return res;
    return const DeviceActionResult(
      handled: true,
      message: '🗂️ **Utilitários de Arquivos (SAF / Downloads)**:\n'
          '• `/limpar_duplicados [pasta]` — verifica SHA-256 e remove cópias com confirmação\n'
          '• `/converter_imagens [jpg|png] [pasta]` — converte `.webp`/`.heic` para `.jpg`/`.png` sem sobrescrever\n'
          '• `/organizar_pdf_downloads [pasta]` — renomeia PDFs para `AAAA-MM-DD - Assunto.pdf`\n'
          '• `/etl [saf|pasta]` — processa documentos em lote (offline + PDFs via Desktop LAN) e salva tabela em `Inbox/` no Obsidian',
      speakText:
          'Use limpar duplicados, converter imagens, organizar PDFs ou ETL em lote.',
    );
  }

  Future<DeviceActionResult?> _tryHandleFileUtilitiesNaturalCommand(
    String text,
    String lower, {
    Future<bool> Function(ActionSimulation)? confirmAction,
  }) async {
    // 1. CLEAN_DUPLICATES ("limpar duplicados", "limpar arquivos duplicados", "duplicados <pasta>")
    final dupMatch = RegExp(
      r'^(?:(?:limpar|apagar|remover|excluir|verificar)\s+(?:os\s+)?(?:arquivos\s+)?duplicados(?:\s+(?:em|na\s+pasta|de))?|duplicados)(?:\s*[:\s]\s*(.+))?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (dupMatch != null) {
      final rawDir = (dupMatch.group(1) ?? '').trim();
      final svc = getFileUtilitiesService();
      final preview = await svc.cleanDuplicates(
        directoryPath: rawDir.isEmpty ? null : rawDir,
        dryRun: true,
      );
      if (preview.duplicates.isEmpty) {
        return DeviceActionResult(
          handled: true,
          message: preview.formatSummary(),
          speakText: 'Nenhum arquivo duplicado encontrado.',
        );
      }
      final sim =
          actionGate.simulate('[ACTION:CLEAN_DUPLICATES:${preview.directoryPath}]');
      final allowed = await authorizeAction(
        sim,
        confirmAction: confirmAction ?? (_) async => true,
      );
      if (!allowed) {
        return DeviceActionResult(
          handled: true,
          message:
              '🚫 Limpeza de ${preview.duplicates.length} duplicado(s) cancelada ou bloqueada pelo Action Gate.\n\n${preview.formatSummary()}',
          speakText: 'Limpeza de duplicados cancelada.',
        );
      }
      final deletedReport = await svc.cleanDuplicates(
        directoryPath: preview.directoryPath,
        dryRun: false,
      );
      await recordAudit(
        actor: 'OPERATOR',
        action: 'CLEAN_DUPLICATES',
        target: deletedReport.directoryPath,
        status: 'EXECUTED',
        detail:
            '${deletedReport.deletedCount} duplicado(s) (${deletedReport.reclaimedBytes} bytes)',
      );
      return DeviceActionResult(
        handled: true,
        message: deletedReport.formatSummary(),
        speakText:
            '${deletedReport.deletedCount} arquivos duplicados foram removidos.',
      );
    }

    // 2. CONVERT_IMAGES ("converter imagens", "converter imagens para png", "converter webp para jpg", "converter png <pasta>")
    final convMatch = RegExp(
      r'^(?:converter\s+(?:as\s+)?(?:imagens|fotos|webp|heic)(?:\s+para\s+(jpg|jpeg|png))?(?:\s+(?:em|na\s+pasta))?|converter(?:\s+(jpg|jpeg|png))?)(?:\s*[:\s]\s*(.+))?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (convMatch != null) {
      final fmtRaw =
          (convMatch.group(1) ?? convMatch.group(2) ?? 'jpg').toLowerCase();
      final fmt = fmtRaw.contains('png') ? 'png' : 'jpg';
      final rawDir = (convMatch.group(3) ?? '').trim();
      final report = await getFileUtilitiesService().convertImages(
        directoryPath: rawDir.isEmpty ? null : rawDir,
        targetFormat: fmt,
      );
      await recordAudit(
        actor: 'OPERATOR',
        action: 'CONVERT_IMAGES',
        target: report.directoryPath,
        status: 'EXECUTED',
        detail: '${report.convertedFiles.length} convertida(s) para .$fmt',
      );
      return DeviceActionResult(
        handled: true,
        message: report.formatSummary(),
        speakText:
            '${report.convertedFiles.length} imagens convertidas para $fmt.',
      );
    }

    // 3. ORGANIZE_PDFS ("organizar pdfs", "organizar pdf downloads", "pdfs <pasta>")
    final pdfMatch = RegExp(
      r'^(?:(?:organizar|renomear|padronizar)\s+(?:os\s+)?pdfs?(?:\s+(?:de\s+)?downloads?)?(?:\s+(?:em|na\s+pasta))?|pdfs?)(?:\s*[:\s]\s*(.+))?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (pdfMatch != null) {
      final rawDir = (pdfMatch.group(1) ?? '').trim();
      final sim = actionGate.simulate(
        '[ACTION:ORGANIZE_PDFS:${rawDir.isEmpty ? 'Downloads' : rawDir}]',
      );
      final allowed = await authorizeAction(
        sim,
        confirmAction: confirmAction ?? (_) async => true,
      );
      if (!allowed) {
        return const DeviceActionResult(
          handled: true,
          message:
              '🚫 Organização de PDFs cancelada ou bloqueada pelo Action Gate.',
          speakText: 'Organização de PDFs cancelada.',
        );
      }
      final report = await getFileUtilitiesService().organizePdfDownloads(
        directoryPath: rawDir.isEmpty ? null : rawDir,
      );
      await recordAudit(
        actor: 'OPERATOR',
        action: 'ORGANIZE_PDFS',
        target: report.directoryPath,
        status: 'EXECUTED',
        detail: '${report.renamedFiles.length} PDF(s) renomeado(s)',
      );
      return DeviceActionResult(
        handled: true,
        message: report.formatSummary(),
        speakText: '${report.renamedFiles.length} PDFs organizados.',
      );
    }

    // 4. BATCH_ETL ("lote [saf|pasta]", "etl [saf|pasta]", "processar lote ...")
    final etlMatch = RegExp(
      r'^(?:(?:processar\s+)?lote(?:\s+de\s+(?:documentos|arquivos|pdfs?))?|etl(?:\s+documentos?)?)(?:\s+(?:em|na\s+pasta|de))?(?:\s*[:\s]\s*(.+))?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (etlMatch != null) {
      final rawArg = (etlMatch.group(1) ?? '').trim();
      final useSafPicker = rawArg.isEmpty || rawArg.toLowerCase() == 'saf';
      final paired = await _hasDesktopPairedSafe();
      Future<String?> Function(List<File>)? desktopExtractor;
      if (paired) {
        desktopExtractor = (pdfFiles) async {
          const maxPdfBytesPerFile = 4 * 1024 * 1024;
          final payloadFiles = <Map<String, Object>>[];
          for (final pdf in pdfFiles.take(10)) {
            final bytes = await pdf.readAsBytes();
            if (bytes.length > maxPdfBytesPerFile) continue;
            payloadFiles.add({
              'name': pdf.uri.pathSegments.isNotEmpty
                  ? pdf.uri.pathSegments.last
                  : pdf.path,
              'size_bytes': bytes.length,
              'content_base64': base64Encode(bytes),
            });
          }
          if (payloadFiles.isEmpty) return null;
          final res = await sendDesktopBridgeCommand(
            command: 'PC_EXEC_TOOL',
            args: <String, dynamic>{
              'tool': 'batch_pdf_etl',
              'params': <String, dynamic>{'files': payloadFiles},
            },
            actor: 'OPERATOR',
            confirmAction: confirmAction,
          );
          if (!res.sent) return null;
          return res.responseBody;
        };
      }

      var report = await getFileUtilitiesService().processBatchDocuments(
        directoryPath: useSafPicker ? null : rawArg,
        pickViaSaf: useSafPicker,
        desktopPdfExtractor: desktopExtractor,
      );

      if (report.items.isNotEmpty) {
        final now = DateTime.now();
        final stamp =
            '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
            '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
        final notePath = 'Inbox/ETL_$stamp.md';
        final vault = await _getObsidian();
        await vault.appendToNote(
          notePath,
          report.markdownNote,
          createIfMissing: true,
        );
        _cachedVaultSearch?.invalidateSyncCache();
        report = report.withSavedNotePath(notePath);
        await recordAudit(
          actor: 'OPERATOR',
          action: 'BATCH_ETL',
          target: notePath,
          status: 'EXECUTED',
          detail:
              '${report.items.length} doc(s), modo=${report.mode}, pdfs_pc=${report.delegatedPdfCount}',
        );
      }

      return DeviceActionResult(
        handled: true,
        message: report.formatSummary(),
        speakText: report.items.isEmpty
            ? 'Nenhum documento selecionado para o lote.'
            : 'Lote consolidado com ${report.items.length} documentos na pasta Inbox do Obsidian.',
      );
    }

    return null;
  }

  static _MediaActionSpec? _matchMediaNaturalCommand(String lower) {
    for (final entry in _naturalMediaMatchers) {
      if (entry.pattern.hasMatch(lower)) {
        return _mediaActionSpecs[entry.tag];
      }
    }
    return null;
  }
}

class _MediaActionSpec {
  const _MediaActionSpec({
    required this.action,
    required this.logLabel,
    required this.message,
    required this.speakText,
  });

  final String action;
  final String logLabel;
  final String message;
  final String speakText;
}

enum MediaControlStatus {
  confirmed,
  openedNeedsPlay,
  noActiveSession,
  uncertain,
  failed,
}

class MediaControlResult {
  const MediaControlResult({
    required this.status,
    required this.confirmed,
    this.activePackage = '',
    this.launchedApp = '',
    this.detail = '',
  });

  factory MediaControlResult.fromMap(Map<Object?, Object?> map) {
    final rawStatus = (map['status'] as String? ?? '').trim().toLowerCase();
    final status = switch (rawStatus) {
      'confirmed' => MediaControlStatus.confirmed,
      'opened_needs_play' => MediaControlStatus.openedNeedsPlay,
      'no_active_session' => MediaControlStatus.noActiveSession,
      'uncertain' => MediaControlStatus.uncertain,
      _ => (map['confirmed'] as bool? ?? false)
          ? MediaControlStatus.confirmed
          : MediaControlStatus.failed,
    };
    return MediaControlResult(
      status: status,
      confirmed:
          (map['confirmed'] as bool?) ?? (status == MediaControlStatus.confirmed),
      activePackage: (map['activePackage'] as String? ?? '').trim(),
      launchedApp: (map['launchedApp'] as String? ?? '').trim(),
      detail: (map['detail'] as String? ?? '').trim(),
    );
  }

  final MediaControlStatus status;
  final bool confirmed;
  final String activePackage;
  final String launchedApp;
  final String detail;
}
