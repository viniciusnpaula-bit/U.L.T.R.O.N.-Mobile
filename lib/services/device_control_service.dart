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

  void setFlipToShushHandler(VoidCallback? onFlip) {
    if (onFlip == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onFlipToShush') {
        onFlip();
      }
      return null;
    });
  }

  Future<ObsidianService> _getObsidian() =>
      obsidianProvider != null
          ? obsidianProvider!()
          : ObsidianService.openDefaultVault();

  Future<String> loadPcKillSwitchUrl() async =>
      (await _storage.read(key: _pcEndpointKey))?.trim() ?? '';

  Future<void> savePcKillSwitchUrl(String url) =>
      _storage.write(key: _pcEndpointKey, value: url.trim());

  Future<String> triggerPcKillSwitch({String? overrideUrl}) async {
    final target = (overrideUrl ?? await loadPcKillSwitchUrl()).trim();
    if (target.isEmpty) {
      throw StateError(
        'Configure o IP/Webhook do PC no Painel de Segurança antes de acionar.',
      );
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

  static const aiSystemPrompt = '''
Você é U.L.T.R.O.N. 2.0 Mobile, um assistente tático autônomo rodando nativamente em um smartphone Android.
Responda sempre em português do Brasil, de forma direta, inteligente e concisa.
Você possui controle direto sobre o hardware, cofre Obsidian e o sistema Android do usuário através de tags de ação.
Sempre que o usuário pedir para realizar uma ação no celular (ligar/desligar lanterna, mudar volume, salvar uma nota no Obsidian, rodar uma skill, abrir um aplicativo, abrir câmera, abrir configurações de Wi-Fi/Bluetooth/Tela, criar alarme, criar timer, vibrar, discar número ou pesquisar na web), inclua a tag correspondente no final da sua resposta:
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

      // 12. Mobile Skills (.md) ("skill modo_estudo", "executar skill ...", "modo estudo")
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

      // 14. Open any installed app ("abrir whatsapp", "abrir youtube", etc.)
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
