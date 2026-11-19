import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/security/action_gate.dart';
import 'audit_log_service.dart';
import 'obsidian_service.dart';
import 'vault_search_service.dart';

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
    this.actionGate = const ActionGate(),
  })  : _channel = channel ??
            const MethodChannel('com.viniciusnpaula.ultron_mobile/device'),
        _storage = storage ?? const FlutterSecureStorage();

  final MethodChannel _channel;
  final FlutterSecureStorage _storage;
  final Future<ObsidianService> Function()? obsidianProvider;
  final Future<VaultSearchService> Function()? vaultSearchProvider;
  final Future<AuditLogService> Function()? auditLogProvider;
  final ActionGate actionGate;
  static const _pcEndpointKey = 'ultron.pc.killswitch.v1';
  static const _pcSecretKey = 'ultron.pc.killswitch.secret.v1';

  void setNativeEventHandlers({
    VoidCallback? onFlip,
    void Function(String phrase)? onWakeWord,
    void Function(String partial)? onSpeechPartial,
    void Function(double rms)? onSpeechRms,
    VoidCallback? onBackgroundTurn,
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
      }
      return null;
    });
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
    return VaultSearchService.open(vaultRoot: Directory(vault.vaultPath));
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
    await search.sync();
    return search.search(query, limit: limit);
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

  /// Constrói o System Prompt contextual injetando a memória de longo prazo
  /// e trechos relevantes do cofre Obsidian (RAG lexical local via FTS5).
  Future<String> buildContextualSystemPrompt({String? userQuery}) async {
    final sections = <String>[aiSystemPrompt];
    try {
      final vault = await _getObsidian();
      final memory = await vault.readLongTermMemory();
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
        await search.sync();
        final rag = await search.buildRagContext(
          query,
          limit: 3,
          maxChars: 1400,
        );
        if (rag.trim().isNotEmpty) {
          sections.add(
            '=== NOTAS RELEVANTES DO COFRE (RAG FTS5) ===\n'
            '$rag\n'
            '=== FIM DO CONTEXTO RAG ===',
          );
        }
      } catch (_) {}
    }

    return sections.join('\n\n');
  }

  Future<String> loadPcKillSwitchUrl() async =>
      (await _storage.read(key: _pcEndpointKey))?.trim() ?? '';

  Future<void> savePcKillSwitchUrl(String url) =>
      _storage.write(key: _pcEndpointKey, value: url.trim());

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
  }) async {
    final target = (overrideUrl ?? await loadPcKillSwitchUrl()).trim();
    if (target.isEmpty) {
      return '⚠️ Kill Switch Local: Endpoint do PC não configurado (sessão mobile bloqueada).';
    }
    final secret = (overrideSecret ?? await loadPcLanSecret()).trim();
    if (secret.isEmpty) {
      return '🚫 Kill Switch bloqueado: configure a chave secreta HMAC LAN na aba Segurança antes de disparar.';
    }
    final normalized =
        target.startsWith('http://') || target.startsWith('https://')
            ? target
            : 'http://$target/killswitch';
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
- Executar Skill Mobile (.md): [ACTION:SKILL:modo_estudo]
- Abrir aplicativo (ex: whatsapp, youtube, instagram, chrome, spotify, calculadora, camera, relogio, maps): [ACTION:OPEN_APP:whatsapp]
- Abrir câmera: [ACTION:OPEN_CAMERA]
- Abrir configurações (wifi, bluetooth, display, sound, battery, location, security, apps, general): [ACTION:OPEN_SETTINGS:wifi]
- Criar alarme (HH:MM:Título): [ACTION:ALARM:07:30:Acordar]
- Criar timer em segundos (segundos:Título): [ACTION:TIMER:300:Timer]
- Vibrar celular: [ACTION:VIBRATE]
- Discar número: [ACTION:DIAL:11999999999]
- Pesquisar na web: [ACTION:SEARCH:termo de busca]
- Ler agenda do celular (dias à frente): [ACTION:READ_CALENDAR:1]
- Criar evento na agenda (YYYY-MM-DD HH:MM:Título): [ACTION:CREATE_EVENT:2026-11-20 15:00:Reunião Tática]
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

  /// Sends an Android hardware media key event (`AudioManager.dispatchMediaKeyEvent`)
  /// to the active media session (Spotify, YouTube, players, podcasts).
  Future<bool> controlMedia(String action) async {
    final normalized = action.trim().toLowerCase();
    if (!supportedMediaActions.contains(normalized)) {
      throw ArgumentError.value(action, 'action', 'Ação de mídia inválida');
    }
    final res = await _channel.invokeMethod<bool>(
      'mediaControl',
      {'action': normalized},
    );
    return res ?? false;
  }

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

      // 2B. Media Playback Control (play, pause, next, previous, stop)
      final mediaMatch = _matchMediaNaturalCommand(lower);
      if (mediaMatch != null) {
        await controlMedia(mediaMatch.action);
        return DeviceActionResult(
          handled: true,
          message: mediaMatch.message,
          speakText: mediaMatch.speakText,
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
        await dialNumber(number);
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
        if (confirmAction != null) {
          final sim = actionGate.simulate('KILL_SWITCH');
          final allowed = await confirmAction(sim);
          if (!allowed) {
            return const DeviceActionResult(
              handled: true,
              message: '🚫 Kill Switch cancelado pelo Operador (Action Gate).',
              speakText: 'Kill switch cancelado.',
            );
          }
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

      // 15. Inline Background Reply ("responder: ...", "responda: ...", "responder para Nome: ...")
      final replyMatch = RegExp(
        r'^(?:ultron[,\s]+)?(?:responder|responda|responde)(?:\s+para\s+([^:]+))?[:\s]+(.+)$',
        caseSensitive: false,
      ).firstMatch(text);
      if (replyMatch != null) {
        final target = (replyMatch.group(1) ?? '').trim();
        final replyBody = replyMatch.group(2)!.trim();
        if (confirmAction != null) {
          final sim = actionGate.simulate(
            'REPLY_MESSAGE:${target.isEmpty ? 'ultimo' : target}:$replyBody',
          );
          final allowed = await confirmAction(sim);
          if (!allowed) {
            return const DeviceActionResult(
              handled: true,
              message: '🚫 Envio de resposta cancelado pelo Operador.',
              speakText: 'Envio cancelado.',
            );
          }
        }
        try {
          final status = await replyNotification(
            target: target,
            text: replyBody,
          );
          return DeviceActionResult(
            handled: true,
            message: '↩️ $status',
            speakText: 'Resposta enviada em segundo plano.',
          );
        } catch (_) {
          if (target.isNotEmpty) {
            final waStatus =
                await sendWhatsApp(target: target, text: replyBody);
            return DeviceActionResult(
              handled: true,
              message: '💬 $waStatus',
              speakText: 'Abrindo WhatsApp para enviar a resposta.',
            );
          }
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
        if (confirmAction != null) {
          final sim = actionGate.simulate('WHATSAPP:$target:$body');
          final allowed = await confirmAction(sim);
          if (!allowed) {
            return const DeviceActionResult(
              handled: true,
              message: '🚫 Envio no WhatsApp cancelado pelo Operador.',
              speakText: 'Envio cancelado.',
            );
          }
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
        if (confirmAction != null) {
          final sim = actionGate.simulate('SMS:$target:$body');
          final allowed = await confirmAction(sim);
          if (!allowed) {
            return const DeviceActionResult(
              handled: true,
              message: '🚫 Envio de SMS cancelado pelo Operador.',
              speakText: 'Envio cancelado.',
            );
          }
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

      // 22b. Calendar read/write ("minha agenda", "agenda de amanhã", "agendar reunião às 15:00")
      final calRes = await _tryHandleCalendarNaturalCommand(
        text,
        lower,
        confirmAction: confirmAction,
      );
      if (calRes != null) return calRes;

      // 23. Open any installed app ("abrir whatsapp", "abra o youtube pra mim", etc.)
      final openMatch = RegExp(
        r'^(?:abrir|iniciar|executar|abre|abra)\s+(?:o\s+|a\s+|app\s+|aplicativo\s+)?(.+)$',
      ).firstMatch(lower);
      if (openMatch != null) {
        final rawTarget = openMatch
            .group(1)!
            .replaceFirst(_trailingCourtesyRegex, '')
            .replaceFirst(
              RegExp(r'^(?:o|a|um|uma|app|aplicativo)\s+'),
              '',
            )
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
      r'\[(?:ACTION:([^\]]+)|HTTP:(GET|POST|PUT|PATCH|DELETE):([^\]]+))\]',
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
      if (sim.requiresConfirmation) {
        final allowed = confirmAction != null && await confirmAction(sim);
        if (!allowed) {
          logs.add('🚫 $cmd bloqueado pelo Action Gate');
          await recordAudit(
            actor: actor,
            action: cmd,
            target: sim.targetResource,
            status: 'DENIED',
            detail: sim.description,
          );
          continue;
        }
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
            await controlMedia(mediaSpec.action);
            logs.add(mediaSpec.logLabel);
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
          case 'KILL_SWITCH':
            await triggerPcKillSwitch();
            logs.add('🚨 Kill Switch PC disparado');
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
      if (confirmAction != null) {
        final sim = actionGate.simulate(
          'CREATE_EVENT:${draft.title}:$formattedWhen',
        );
        final allowed = await confirmAction(sim);
        if (!allowed) {
          return const DeviceActionResult(
            handled: true,
            message: '🚫 Criação de evento cancelada pelo Operador.',
            speakText: 'Agendamento cancelado.',
          );
        }
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
