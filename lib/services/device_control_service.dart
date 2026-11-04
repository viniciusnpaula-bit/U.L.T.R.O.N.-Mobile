import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'obsidian_service.dart';

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

class DeviceControlService {
  DeviceControlService({
    MethodChannel? channel,
    FlutterSecureStorage? storage,
    this.obsidianProvider,
  })  : _channel = channel ??
            const MethodChannel('com.viniciusnpaula.ultron_mobile/device'),
        _storage = storage ?? const FlutterSecureStorage();

  final MethodChannel _channel;
  final FlutterSecureStorage _storage;
  final Future<ObsidianService> Function()? obsidianProvider;
  static const _pcEndpointKey = 'ultron.pc.killswitch.v1';

  void setNativeEventHandlers({
    VoidCallback? onFlip,
    void Function(String phrase)? onWakeWord,
    void Function(String partial)? onSpeechPartial,
    void Function(double rms)? onSpeechRms,
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
      }
      return null;
    });
  }

  void setFlipToShushHandler(VoidCallback? onFlip) {
    setNativeEventHandlers(onFlip: onFlip);
  }

  Future<ObsidianService> _getObsidian() =>
      obsidianProvider != null
          ? obsidianProvider!()
          : ObsidianService.openDefaultVault();

  Future<String> loadPcKillSwitchUrl() async =>
      (await _storage.read(key: _pcEndpointKey))?.trim() ?? '';

  Future<void> savePcKillSwitchUrl(String url) =>
      _storage.write(key: _pcEndpointKey, value: url.trim());

  Future<String> triggerPcKillSwitch({
    String? overrideUrl,
    String? reason,
  }) async {
    final target = (overrideUrl ?? await loadPcKillSwitchUrl()).trim();
    if (target.isEmpty) {
      return '⚠️ Kill Switch Local: Endpoint do PC não configurado (sessão mobile bloqueada).';
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
    final signature = Hmac(sha256, utf8.encode('ULTRON_LAN_GUARD'))
        .convert(utf8.encode(payload))
        .toString();

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6);
    try {
      final req =
          await client.postUrl(uri).timeout(const Duration(seconds: 8));
      req.headers.contentType = ContentType.json;
      req.headers.set('X-Ultron-Signature', 'sha256=$signature');
      req.headers.set('X-Ultron-Timestamp', timestamp);
      req.write(payload);
      final resp = await req.close().timeout(const Duration(seconds: 8));
      await resp.drain<void>();
      return '🚨 Pacote Kill Switch enviado para ${uri.host} (HTTP ${resp.statusCode}).';
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
    String secret = 'ULTRON_LAN_GUARD',
  }) {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final body = jsonEncode({
      'command': command,
      'source': 'ULTRON_MOBILE',
      'timestamp': timestamp,
      'payload': data,
    });
    final signature = Hmac(sha256, utf8.encode(secret))
        .convert(utf8.encode(body))
        .toString();
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

  Future<void> openUrl(String url) async {
    await _channel.invokeMethod<bool>('openUrl', {'url': url});
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

  Future<String> speakOfflineFishVoice(String text) async {
    final res = await _channel.invokeMethod<String>('speakOfflineFishVoice', {
      'text': text,
    });
    return res ?? text;
  }

  /// Parses direct natural-language hardware commands so they execute immediately
  /// with zero latency and even without internet/API keys.
  Future<DeviceActionResult?> tryExecuteNaturalCommand(String rawInput) async {
    final text = rawInput.trim();
    final lower = text.toLowerCase();

    try {
      // 1. Flashlight / Torch
      if (RegExp(
        r'\b(ligar|acender|ativar|liga|acende)\b.*\b(lanterna|flash|luz)\b|\b(lanterna|flash)\s+(on|ligar|acesa)\b',
      ).hasMatch(lower)) {
        final on = await setTorch(true);
        return DeviceActionResult(
          handled: true,
          message: '🔦 Lanterna do dispositivo ativada (Estado: ${on ? 'ON' : 'OFF'}).',
          speakText: 'Lanterna ligada.',
        );
      }

      if (RegExp(
        r'\b(desligar|apagar|desativar|desliga|apaga)\b.*\b(lanterna|flash|luz)\b|\b(lanterna|flash)\s+(off|desligar|apagada)\b',
      ).hasMatch(lower)) {
        final on = await setTorch(false);
        return DeviceActionResult(
          handled: true,
          message: '🔦 Lanterna do dispositivo desativada (Estado: ${on ? 'ON' : 'OFF'}).',
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
      if (lower == 'vibrar' || lower == 'testar vibração' || lower == 'vibracao') {
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
          final exec = await executeAiActions(skill.content);
          return DeviceActionResult(
            handled: true,
            message:
                '⚡ Skill Mobile "${skill.title}" (${skill.id}.md) executada!\n'
                '${exec.executedLogs.isEmpty ? exec.cleanText : exec.executedLogs.join(' • ')}',
            speakText: 'Skill ${skill.title} ativada.',
          );
        }
      }

      // 13. PC Remote Kill Switch
      if (RegExp(
        r'^(travar\s+pc|bloquear\s+pc|kill\s*switch)$',
        caseSensitive: false,
      ).hasMatch(lower)) {
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
            final waStatus = await sendWhatsApp(target: target, text: replyBody);
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

      // 20. Open any installed app ("abrir whatsapp", "abrir youtube", etc.)
      final openMatch = RegExp(
        r'^(?:abrir|iniciar|executar)\s+(?:o\s+|a\s+|app\s+|aplicativo\s+)?(.+)$',
      ).firstMatch(lower);
      if (openMatch != null) {
        final appTarget = openMatch.group(1)!.trim();
        if (appTarget.isNotEmpty &&
            appTarget != 'palco' &&
            appTarget != 'documento') {
          final opened = await openApp(appTarget);
          return DeviceActionResult(
            handled: true,
            message: '📱 Aplicativo iniciado: $opened.',
            speakText: 'Abrindo $opened.',
          );
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

  /// Parses `[ACTION:...]` tags emitted by the AI model, executes them on the
  /// Android device, and returns the cleaned reply text + execution logs.
  Future<AiActionExecution> executeAiActions(String rawReply) async {
    final pattern = RegExp(r'\[ACTION:([^\]]+)\]', caseSensitive: false);
    final matches = pattern.allMatches(rawReply).toList();
    if (matches.isEmpty) {
      return AiActionExecution(cleanText: rawReply.trim(), executedLogs: const []);
    }

    final logs = <String>[];
    for (final match in matches) {
      final content = match.group(1)?.trim() ?? '';
      final parts = content.split(':');
      final cmd = parts.first.toUpperCase();
      final arg1 = parts.length > 1 ? parts[1].trim() : '';
      final arg2 = parts.length > 2 ? parts[2].trim() : '';
      final arg3 = parts.length > 3 ? parts.sublist(3).join(':').trim() : '';

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
          case 'SKILL':
            if (arg1.isNotEmpty) {
              final vault = await _getObsidian();
              final skill = await vault.findSkill(arg1);
              if (skill != null) {
                final sub = await executeAiActions(skill.content);
                logs.add('⚡ Skill ${skill.id}: ${sub.executedLogs.join(', ')}');
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
        }
      } catch (e) {
        logs.add('⚠️ Falha em $cmd: $e');
      }
    }

    final clean = rawReply.replaceAll(pattern, '').trim();
    return AiActionExecution(
      cleanText: clean.isEmpty ? 'Comando executado no dispositivo.' : clean,
      executedLogs: logs,
    );
  }
}
