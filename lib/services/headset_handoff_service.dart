import 'dart:async';

import 'desktop_pairing_service.dart';
import 'spotify_service.dart';

/// Direção da skill **Permutação do Fone** (`permutacao_do_fone`).
enum HandoffDirection {
  auto,
  toMobile,
  toDesktop;

  static HandoffDirection parse(String? raw) {
    final norm = (raw ?? '')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[áàâãä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[óòôõö]'), 'o');
    if (norm.contains('mobile') ||
        norm.contains('celular') ||
        norm.contains('telefone') ||
        norm.contains('bluetooth') ||
        norm == 'bt') {
      return HandoffDirection.toMobile;
    }
    if (norm.contains('desktop') ||
        norm.contains('pc') ||
        norm.contains('computador') ||
        norm.contains('dongle') ||
        norm.contains('windows')) {
      return HandoffDirection.toDesktop;
    }
    return HandoffDirection.auto;
  }
}

/// Estado instantâneo de saída de áudio Bluetooth no Android.
class BluetoothAudioSnapshot {
  const BluetoothAudioSnapshot({
    required this.connected,
    this.devices = const <String>[],
    this.primaryDevice = '',
    this.matchedPreferred = false,
    this.elapsedMs = 0,
  });

  factory BluetoothAudioSnapshot.fromMap(Map<Object?, Object?>? raw) {
    if (raw == null) {
      return const BluetoothAudioSnapshot(connected: false);
    }
    final rawDevices = raw['devices'];
    final devices = rawDevices is List
        ? rawDevices
            .map((e) => '$e'.trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    final primary = (raw['deviceName'] as String? ??
            raw['primaryDevice'] as String? ??
            (devices.isNotEmpty ? devices.first : ''))
        .trim();
    return BluetoothAudioSnapshot(
      connected: raw['connected'] == true || devices.isNotEmpty,
      devices: devices,
      primaryDevice: primary,
      matchedPreferred: raw['matchedPreferred'] == true,
      elapsedMs: (raw['elapsedMs'] as num?)?.toInt() ?? 0,
    );
  }

  final bool connected;
  final List<String> devices;
  final String primaryDevice;
  final bool matchedPreferred;
  final int elapsedMs;
}

class HeadsetHandoffResult {
  const HeadsetHandoffResult({
    required this.ok,
    required this.direction,
    required this.message,
    required this.speakText,
    this.desktopNotified = false,
    this.bluetoothConnected = false,
    this.bluetoothDeviceName = '',
    this.spotifyTransferred = false,
    this.spotifyDeviceName = '',
    this.usedMediaFallback = false,
  });

  final bool ok;
  final HandoffDirection direction;
  final String message;
  final String speakText;
  final bool desktopNotified;
  final bool bluetoothConnected;
  final String bluetoothDeviceName;
  final bool spotifyTransferred;
  final String spotifyDeviceName;
  final bool usedMediaFallback;
}

/// Orquestra a skill **Permutação do Fone** (`permutacao_do_fone`), pensada para
/// headsets dual-mode 2.4GHz Dongle + Bluetooth (como o **Attack Shark L30 Pro**)
/// com continuidade imediata de música via **Spotify Connect**.
class HeadsetHandoffService {
  HeadsetHandoffService({
    required this.getBluetoothSnapshot,
    required this.waitForBluetoothAudio,
    required this.getSpotifyService,
    required this.triggerDesktopSkill,
    required this.hasDesktopPaired,
    required this.openSpotifyApp,
    required this.resumeLocalMedia,
    this.delay = _defaultDelay,
  });

  static const String skillId = 'permutacao_do_fone';
  static const String skillTitle = 'Permutação do Fone';
  static const String defaultHeadsetName = 'Attack Shark L30 Pro';

  final Future<BluetoothAudioSnapshot> Function() getBluetoothSnapshot;
  final Future<BluetoothAudioSnapshot> Function({
    required String preferredName,
    required Duration timeout,
  }) waitForBluetoothAudio;
  final SpotifyService Function() getSpotifyService;
  final Future<DesktopCommandResult> Function({
    required String direction,
    required String headsetName,
  }) triggerDesktopSkill;
  final Future<bool> Function() hasDesktopPaired;
  final Future<void> Function() openSpotifyApp;
  final Future<bool> Function() resumeLocalMedia;
  final Future<void> Function(Duration duration) delay;

  static Future<void> _defaultDelay(Duration d) => Future<void>.delayed(d);

  Future<HeadsetHandoffResult> execute({
    HandoffDirection direction = HandoffDirection.auto,
    String headsetName = defaultHeadsetName,
    bool fromDesktop = false,
    Duration bluetoothWaitTimeout = const Duration(seconds: 22),
    Duration spotifyWakeDelay = const Duration(milliseconds: 2200),
    FutureOr<void> Function(String prompt)? onProgressSpeak,
  }) async {
    final cleanHeadset =
        headsetName.trim().isEmpty ? defaultHeadsetName : headsetName.trim();

    // 1. Determina direção automaticamente pelo estado atual do fone Bluetooth no celular.
    final initialBt = await getBluetoothSnapshot();
    final resolvedDirection = direction == HandoffDirection.auto
        ? (initialBt.connected
            ? HandoffDirection.toDesktop
            : HandoffDirection.toMobile)
        : direction;

    if (resolvedDirection == HandoffDirection.toDesktop) {
      return _handoffToDesktop(
        headsetName: cleanHeadset,
        fromDesktop: fromDesktop,
      );
    }
    return _handoffToMobile(
      initialBt: initialBt,
      headsetName: cleanHeadset,
      fromDesktop: fromDesktop,
      bluetoothWaitTimeout: bluetoothWaitTimeout,
      spotifyWakeDelay: spotifyWakeDelay,
      onProgressSpeak: onProgressSpeak,
    );
  }

  Future<HeadsetHandoffResult> _handoffToMobile({
    required BluetoothAudioSnapshot initialBt,
    required String headsetName,
    required bool fromDesktop,
    required Duration bluetoothWaitTimeout,
    required Duration spotifyWakeDelay,
    FutureOr<void> Function(String prompt)? onProgressSpeak,
  }) async {
    final steps = <String>[];
    var desktopNotified = false;

    // Passo 1: Pede ao Desktop para desconectar/desabilitar o dongle 2.4GHz
    // (pulado se o próprio Desktop iniciou o handoff via RUN_SKILL para evitar loop).
    if (!fromDesktop && await hasDesktopPaired()) {
      final pcRes = await triggerDesktopSkill(
        direction: 'to_mobile',
        headsetName: headsetName,
      );
      if (pcRes.sent) {
        desktopNotified = true;
        steps.add('PC: dongle 2.4GHz desconectado');
      } else if (pcRes.deniedByUser) {
        steps.add('PC: etapa do dongle cancelada no Action Gate');
      } else {
        steps.add(
          'PC: não respondeu (${pcRes.error ?? 'HTTP ${pcRes.statusCode ?? '-'}'})',
        );
      }
    } else if (fromDesktop) {
      desktopNotified = true;
      steps.add('PC: dongle já desconectado pelo Desktop');
    }

    // Passo 2: Aguarda conexão Bluetooth A2DP no celular (Attack Shark L30 Pro: 2 cliques no Power).
    var bt = initialBt;
    if (!bt.connected) {
      if (onProgressSpeak != null) {
        await onProgressSpeak(
          desktopNotified
              ? 'Dongle desconectado. Dê dois cliques no botão Power do fone para ativar o Bluetooth.'
              : 'Dê dois cliques no botão Power do fone para conectar no Bluetooth do celular.',
        );
      }
      bt = await waitForBluetoothAudio(
        preferredName: headsetName,
        timeout: bluetoothWaitTimeout,
      );
    }

    if (!bt.connected) {
      final detail = steps.isEmpty ? '' : '${steps.join(' • ')}. ';
      return HeadsetHandoffResult(
        ok: false,
        direction: HandoffDirection.toMobile,
        desktopNotified: desktopNotified,
        bluetoothConnected: false,
        message:
            '🎧 Permutação do Fone (PC → Celular) aguardou ${bluetoothWaitTimeout.inSeconds}s, mas nenhum fone Bluetooth conectou.\n'
            '${detail}Dê 2 cliques rápidos no botão Power do $headsetName (LED azul) e tente novamente.',
        speakText:
            'Não detectei o fone no Bluetooth. Dê dois cliques no botão Power do fone até acender o LED azul e peça novamente.',
      );
    }

    final btLabel =
        bt.primaryDevice.isNotEmpty ? bt.primaryDevice : headsetName;
    steps.add('Bluetooth conectado: $btLabel');

    // Passo 3: Transfere reprodução para o celular via Spotify Connect (mesma conta).
    final spotify = getSpotifyService();
    var spotifyTransferred = false;
    var spotifyDeviceName = '';
    var usedFallback = false;

    if (await spotify.isConnected()) {
      try {
        final target = await _transferToSmartphoneWithWakeRetry(
          spotify: spotify,
          wakeDelay: spotifyWakeDelay,
        );
        spotifyTransferred = true;
        spotifyDeviceName = target.name;
        steps.add('Spotify Connect → ${target.name}');
      } catch (e) {
        final resumed = await resumeLocalMedia();
        usedFallback = resumed;
        steps.add(
          resumed
              ? 'Spotify Connect indisponível ($e); mídia local retomada'
              : 'Spotify Connect indisponível ($e)',
        );
      }
    } else {
      final resumed = await resumeLocalMedia();
      usedFallback = resumed;
      steps.add(
        resumed
            ? 'Mídia local retomada (conecte a Spotify Web API em Config IA para Spotify Connect instantâneo)'
            : 'Spotify Web API não conectado (abra Config IA → Spotify)',
      );
    }

    final audioStatus = spotifyTransferred
        ? 'Spotify transferido para $spotifyDeviceName e retomado'
        : (usedFallback
            ? 'reprodução retomada no celular'
            : 'fone pronto no celular');

    return HeadsetHandoffResult(
      ok: true,
      direction: HandoffDirection.toMobile,
      desktopNotified: desktopNotified,
      bluetoothConnected: true,
      bluetoothDeviceName: btLabel,
      spotifyTransferred: spotifyTransferred,
      spotifyDeviceName: spotifyDeviceName,
      usedMediaFallback: usedFallback,
      message: '🎧 Permutação do Fone concluída (PC → Celular)\n'
          '• ${steps.join('\n• ')}',
      speakText:
          'Permutação concluída. Fone $btLabel conectado e $audioStatus.',
    );
  }

  Future<SpotifyDevice> _transferToSmartphoneWithWakeRetry({
    required SpotifyService spotify,
    required Duration wakeDelay,
  }) async {
    try {
      return await spotify.transferPlayback(
        targetType: 'Smartphone',
        play: true,
      );
    } catch (_) {
      // Quando o app Spotify está dormindo no Android, ele só aparece em /v1/me/player/devices
      // depois de ser acordado. Abre o app e tenta novamente uma vez.
      await openSpotifyApp();
      if (wakeDelay > Duration.zero) {
        await delay(wakeDelay);
      }
      return spotify.transferPlayback(
        targetType: 'Smartphone',
        play: true,
      );
    }
  }

  Future<HeadsetHandoffResult> _handoffToDesktop({
    required String headsetName,
    required bool fromDesktop,
  }) async {
    final steps = <String>[];
    var desktopNotified = false;

    if (!fromDesktop && await hasDesktopPaired()) {
      final pcRes = await triggerDesktopSkill(
        direction: 'to_desktop',
        headsetName: headsetName,
      );
      if (pcRes.sent) {
        desktopNotified = true;
        steps.add('PC: dongle 2.4GHz reativado como saída de áudio');
      } else if (pcRes.deniedByUser) {
        steps.add('PC: reativação do dongle cancelada no Action Gate');
      } else {
        steps.add(
          'PC: não respondeu (${pcRes.error ?? 'HTTP ${pcRes.statusCode ?? '-'}'})',
        );
      }
    } else if (fromDesktop) {
      desktopNotified = true;
      steps.add('PC: dongle já reativado pelo Desktop');
    } else {
      steps.add('PC não pareado via LAN (/desktop)');
    }

    final spotify = getSpotifyService();
    var spotifyTransferred = false;
    var spotifyDeviceName = '';
    if (await spotify.isConnected()) {
      try {
        final pcDevice = await spotify.transferPlayback(
          targetType: 'Computer',
          play: true,
        );
        spotifyTransferred = true;
        spotifyDeviceName = pcDevice.name;
        steps.add('Spotify Connect → ${pcDevice.name}');
      } catch (e) {
        steps.add('Spotify Connect PC indisponível ($e)');
      }
    }

    final ok = desktopNotified || spotifyTransferred;
    return HeadsetHandoffResult(
      ok: ok,
      direction: HandoffDirection.toDesktop,
      desktopNotified: desktopNotified,
      bluetoothConnected: false,
      spotifyTransferred: spotifyTransferred,
      spotifyDeviceName: spotifyDeviceName,
      message: '🖥️ Permutação do Fone (Celular → PC)\n'
          '• ${steps.join('\n• ')}\n'
          '💡 Dê 2 cliques no botão Power do $headsetName para voltar ao modo Dongle 2.4GHz (LED branco).',
      speakText: spotifyTransferred
          ? 'Spotify transferido para o computador $spotifyDeviceName. Dê dois cliques no botão Power do fone para voltar ao dongle.'
          : 'Dongle solicitado no computador. Dê dois cliques no botão Power do fone para voltar ao modo 2.4 giga-hertz.',
    );
  }
}
