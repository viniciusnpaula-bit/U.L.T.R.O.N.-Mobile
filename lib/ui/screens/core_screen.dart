import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/security/action_gate.dart';
import '../../core/security/auth_gate.dart';
import '../../core/security/pin_vault.dart';
import '../../models/chat_message.dart';
import '../../services/ai_provider_service.dart';
import '../../services/app_update_service.dart';
import '../../services/conversation_history.dart';
import '../../services/device_control_service.dart';
import '../../services/obsidian_service.dart';
import '../../services/slash_command_parser.dart';
import '../../services/speech_text.dart';
import '../../services/voice_service.dart';
import 'ai_settings_screen.dart';
import 'conversation_history_screen.dart';
import 'update_screen.dart';

enum CoreStage { center, corner, hidden }

enum _ActivePanel { main, device, security, help, providers }

class _FeedEntry {
  const _FeedEntry({
    required this.isUser,
    required this.senderLabel,
    required this.text,
    required this.timestamp,
  });

  final bool isUser;
  final String senderLabel;
  final String text;
  final String timestamp;
}

class CoreScreen extends StatefulWidget {
  const CoreScreen({super.key, required this.gate, required this.vault});

  final AuthGate gate;
  final PinVault vault;

  @override
  State<CoreScreen> createState() => _CoreScreenState();
}

class _CoreScreenState extends State<CoreScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _crimson = Color(0xFF75020F);
  static const _rose = Color(0xFFFF707C);
  static const _border = Color(0xFF51080D);

  late final Ticker ticker;
  final commandController = TextEditingController();
  final quickNoteController = TextEditingController();
  final duressPinController = TextEditingController();
  final pcKillSwitchUrlController = TextEditingController();
  final messageTargetController = TextEditingController();
  final messageBodyController = TextEditingController();
  final scrollController = ScrollController();
  final coreTime = ValueNotifier<double>(0);
  final voiceService = VoiceService();
  final updateService = AppUpdateService();
  final providerStore = AiProviderStore();
  final deviceService = DeviceControlService();
  final actionGate = const ActionGate();

  CoreStage stage = CoreStage.center;
  _ActivePanel panel = _ActivePanel.main;
  bool active = false;
  bool sending = false;
  bool listeningVoice = false;
  bool hasUpdate = false;
  bool isAudioOn = true;
  bool torchOn = false;
  bool nightFocusMode = false;
  bool criticalBatteryAlerted = false;
  bool notificationSentinelEnabled = false;
  bool ecoVadSentinelRunning = false;
  double speechRms = 0.0;
  VoiceProfile selectedVoiceProfile = VoiceProfile.grave;
  DeviceStatus? deviceStatus;
  String activeProviderUsed = 'Failover Pronto';
  String installedVersion = 'v1.2.1';
  int authFailures = 0;
  bool? hasPinConfigured;
  bool hasDuressPinConfigured = false;
  List<MobileSkill> mobileSkills = const [];
  List<CapturedNotification> recentMessages = const [];

  static const _defaultFeed = <_FeedEntry>[
    _FeedEntry(
      isUser: false,
      senderLabel: 'Kernel Local',
      text:
          'U.L.T.R.O.N. Mobile v1.2.1 online. Wake Word Reliability, Action Gate tático ativo, 16 Slash Commands, Visão Multimodal e 9 Provedores Gratuitos prontos para comando!',
      timestamp: 'ONLINE',
    ),
  ];

  List<_FeedEntry> feed = _defaultFeed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ticker = createTicker((duration) {
      coreTime.value = duration.inMicroseconds / 1000000;
    });
    ticker.start();
    active = true;
    voiceService.initialize();
    deviceService.setNativeEventHandlers(
      onFlip: () {
        if (!mounted) return;
        voiceService.stop();
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '🤫 Flip-to-Shush ativado: voz do núcleo silenciada.',
              style: TextStyle(fontSize: 11),
            ),
            duration: Duration(seconds: 2),
          ),
        );
      },
      onWakeWord: _handleWakeWord,
      onSpeechPartial: (partial) {
        if (!mounted || !listeningVoice) return;
        setState(() {
          commandController.text = partial;
          commandController.selection = TextSelection.fromPosition(
            TextPosition(offset: partial.length),
          );
        });
      },
      onSpeechRms: (rms) {
        if (!mounted) return;
        setState(() => speechRms = rms);
      },
    );
    _loadInitialState();
    _checkUpdate();
    // v1.2.1: wake word captada com o app fechado/bloqueado fica pendente no nativo.
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePendingWakeWord());
  }

  /// Processa uma ativação por "Ultron" (ao vivo ou pendente do segundo plano).
  ///
  /// Um comando em andamento não pode simplesmente descartar a ativação: espera curta
  /// pelo pipeline atual (o nativo também reentrega a palavra enquanto o TTS fala).
  Future<void> _handleWakeWord(String phrase) async {
    if (!mounted) return;
    for (var i = 0;
        i < 32 && (sending || listeningVoice || voiceService.isSpeaking);
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
    }
    if (!mounted) return;
    if (sending || listeningVoice || voiceService.isSpeaking) {
      // Nunca descarta em silêncio: o operador sabe que precisa repetir.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⚙️ Núcleo ocupado. Repita "Ultron" quando a resposta terminar.',
            style: TextStyle(fontSize: 11),
          ),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    HapticFeedback.heavyImpact();
    final inlineCmd = WakeWord.extractCommand(phrase);
    if (inlineCmd.length >= 2) {
      commandController.text = inlineCmd;
      await saveCommand();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '🎙️ "Ultron" detectado! Escutando seu comando…',
          style: TextStyle(fontSize: 11),
        ),
        duration: Duration(seconds: 2),
      ),
    );
    await _startVoiceInput();
  }

  Future<void> _consumePendingWakeWord() async {
    final pending = await deviceService.consumePendingWakeWord();
    if (pending != null) _handleWakeWord(pending);
  }

  Future<void> _showWakeWordDiagnostics() async {
    final diag = await deviceService.getWakeWordDiagnostics();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF14040A),
        title: const Text(
          'DIAGNÓSTICO DA PALAVRA DE ATIVAÇÃO',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Text(
            diag.toReport(),
            style: const TextStyle(fontSize: 11, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await deviceService.requestIgnoreBatteryOptimizations();
            },
            child: const Text('ISENTAR BATERIA'),
          ),
          TextButton(
            onPressed: () async {
              await deviceService.setBootAutostart(!diag.bootAutostart);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text(diag.bootAutostart ? 'DESLIGAR BOOT' : 'LIGAR NO BOOT'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('FECHAR'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadInitialState() async {
    try {
      final saved = await ConversationHistory.instance.messages(
        conversationId: 'default',
        limit: 20,
      );
      final providers = await providerStore.load();
      final enabledProviders = providers.where((p) => p.enabled).toList()
        ..sort((a, b) => a.priority.compareTo(b.priority));
      final failures = await widget.vault.failureCount();
      final pinSet = await widget.vault.hasPin;
      final duressSet = await widget.vault.hasDuressPin;
      final killUrl = await deviceService.loadPcKillSwitchUrl();
      List<MobileSkill> loadedSkills = const [];
      try {
        final obsidian = await ObsidianService.openDefaultVault();
        loadedSkills = await obsidian.listSkills();
      } catch (_) {}
      DeviceStatus? hwStatus;
      bool notifEnabled = false;
      var vadRunning = false;
      List<CapturedNotification> loadedMsgs = const [];
      try {
        hwStatus = await deviceService.getStatus();
        notifEnabled = await deviceService.isNotificationListenerEnabled();
        vadRunning = await deviceService.isAudioSentinelRunning();
        if (notifEnabled) {
          loadedMsgs = await deviceService.getRecentMessages(limit: 12);
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        authFailures = failures;
        hasPinConfigured = pinSet;
        hasDuressPinConfigured = duressSet;
        notificationSentinelEnabled = notifEnabled;
        ecoVadSentinelRunning = vadRunning;
        selectedVoiceProfile = voiceService.profile;
        recentMessages = loadedMsgs;
        if (killUrl.isNotEmpty && pcKillSwitchUrlController.text.isEmpty) {
          pcKillSwitchUrlController.text = killUrl;
        }
        mobileSkills = loadedSkills;
        if (hwStatus != null) {
          deviceStatus = hwStatus;
          torchOn = hwStatus.torchOn;
        }
        activeProviderUsed = enabledProviders.isNotEmpty
            ? '${enabledProviders.first.name} (${enabledProviders.first.model})'
            : 'Failover Pronto';
        feed = saved.isNotEmpty
            ? saved
                .map(
                  (m) => _FeedEntry(
                    isUser: m.role == ChatRole.user,
                    senderLabel:
                        m.role == ChatRole.user ? 'OPERADOR' : 'U.L.T.R.O.N.',
                    text: m.content,
                    timestamp: _formatTime(m.createdAt.toLocal()),
                  ),
                )
                .toList()
            : _defaultFeed;
      });
      _applyContextSensors(hwStatus);
      _scrollToBottom();
    } catch (_) {}
  }

  void _applyContextSensors(DeviceStatus? hwStatus) {
    if (hwStatus == null || !mounted) return;
    // 1. Critical Battery Vigilance (< 15% and not charging -> auto pause 60 FPS GPU core)
    if (hwStatus.batteryLevel > 0 &&
        hwStatus.batteryLevel <= 15 &&
        !hwStatus.isCharging &&
        !criticalBatteryAlerted) {
      setState(() {
        criticalBatteryAlerted = true;
        stage = CoreStage.hidden;
      });
      _syncTickerWithState();
      _appendFeed(
        _FeedEntry(
          isUser: false,
          senderLabel: 'Vigilância Energética',
          text:
              '⚠️ Bateria crítica (${hwStatus.batteryLevel}%). Renderizador 60 FPS descarregado da GPU automaticamente para economia profunda.',
          timestamp: _formatTime(DateTime.now()),
        ),
      );
    }

    // 2. Night Focus Mode (Charging + between 22:00 and 06:00)
    final hour = DateTime.now().hour;
    final isNightWindow = hour >= 22 || hour < 6;
    if (hwStatus.isCharging && isNightWindow && !nightFocusMode) {
      setState(() => nightFocusMode = true);
      voiceService.setWhisperMode(true);
    }
  }

  Future<void> _toggleNightFocusMode() async {
    HapticFeedback.selectionClick();
    final next = !nightFocusMode;
    setState(() => nightFocusMode = next);
    await voiceService.setWhisperMode(next);
  }

  Future<void> _refreshDeviceStatus() async {
    try {
      final hwStatus = await deviceService.getStatus();
      final notifEnabled = await deviceService.isNotificationListenerEnabled();
      final vadRunning = await deviceService.isAudioSentinelRunning();
      final msgs = notifEnabled
          ? await deviceService.getRecentMessages(limit: 12)
          : const <CapturedNotification>[];
      if (!mounted) return;
      setState(() {
        deviceStatus = hwStatus;
        torchOn = hwStatus.torchOn;
        notificationSentinelEnabled = notifEnabled;
        ecoVadSentinelRunning = vadRunning;
        recentMessages = msgs;
      });
      _applyContextSensors(hwStatus);
    } catch (_) {}
  }

  Future<void> _readRecentMessagesAloud() async {
    HapticFeedback.mediumImpact();
    await _refreshDeviceStatus();
    if (!notificationSentinelEnabled) {
      await deviceService.openNotificationListenerSettings();
      return;
    }
    if (recentMessages.isEmpty) {
      await voiceService.speak('Você não tem novas mensagens no momento.');
      return;
    }
    final spoken = recentMessages
        .take(4)
        .map((m) => '${m.appLabel} de ${m.sender}: ${m.text}')
        .join('. ');
    await voiceService.speak(
      'Você tem ${recentMessages.length} mensagens recentes. $spoken',
    );
  }

  Future<void> _summarizeMessagesWithAi() async {
    await _refreshDeviceStatus();
    if (!mounted) return;
    if (recentMessages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhuma mensagem recente para resumir.',
            style: TextStyle(fontSize: 11),
          ),
        ),
      );
      return;
    }
    final dump = recentMessages
        .take(10)
        .map((m) => '[${m.timeFormatted}] ${m.appLabel} - ${m.sender}: ${m.text}')
        .join('\n');
    commandController.text =
        'Faça um Resumo Tático inteligente das minhas mensagens recentes (separe o que é urgente de ruído e sugira respostas rápidas):\n$dump';
    _setPanel(_ActivePanel.main);
    await saveCommand();
  }

  Future<void> _promptReplyToMessage(CapturedNotification msg) async {
    final replyCtrl = TextEditingController();
    final sent = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2B0307),
        title: Text(
          'Responder ${msg.sender} (${msg.appLabel})',
          style: const TextStyle(
            color: _crimson,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"${msg.text}"',
              style: const TextStyle(color: Color(0xFFA89698), fontSize: 11),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: replyCtrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: const InputDecoration(
                hintText: 'Digite sua resposta em 2º plano…',
                hintStyle: TextStyle(color: Color(0xFF635355), fontSize: 11),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CANCELAR', style: TextStyle(color: _rose)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _crimson),
            onPressed: () => Navigator.of(ctx).pop(replyCtrl.text.trim()),
            child: const Text('ENVIAR AGORA'),
          ),
        ],
      ),
    );
    if (sent == null || sent.isEmpty) return;
    try {
      final status = await deviceService.replyNotification(
        target: msg.sender,
        text: sent,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('↩️ $status', style: const TextStyle(fontSize: 11)),
        ),
      );
      await voiceService.speak('Resposta enviada.');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao responder: $e', style: const TextStyle(fontSize: 11)),
        ),
      );
    }
  }

  Future<void> _sendQuickMessage({required bool viaSms}) async {
    final target = messageTargetController.text.trim();
    final body = messageBodyController.text.trim();
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Digite o texto da mensagem primeiro.',
            style: TextStyle(fontSize: 11),
          ),
        ),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    try {
      final res = viaSms
          ? await deviceService.sendSms(target: target, text: body)
          : await deviceService.sendWhatsApp(target: target, text: body);
      messageBodyController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res, style: const TextStyle(fontSize: 11)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha no envio: $e', style: const TextStyle(fontSize: 11)),
        ),
      );
    }
  }

  Future<void> _toggleTorchQuick() async {
    HapticFeedback.mediumImpact();
    try {
      final state = await deviceService.toggleTorch();
      if (!mounted) return;
      setState(() => torchOn = state);
      await _refreshDeviceStatus();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha na lanterna: $e', style: const TextStyle(fontSize: 11)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _checkUpdate() async {
    try {
      final installed = await updateService.currentVersion();
      if (mounted) setState(() => installedVersion = 'v$installed');
      final latest = await updateService.check();
      if (latest == null || !mounted) return;
      setState(
        () => hasUpdate = AppUpdateService.isNewer(latest.version, installed),
      );
    } catch (_) {}
  }

  static String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _syncTickerWithState({AppLifecycleState? lifecycle}) {
    final shouldRun = (lifecycle == null ||
            lifecycle == AppLifecycleState.resumed) &&
        panel == _ActivePanel.main &&
        stage != CoreStage.hidden;
    if (shouldRun && !active) {
      ticker.start();
      active = true;
    } else if (!shouldRun && active) {
      ticker.stop();
      active = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      voiceService.stop();
    } else {
      _consumePendingWakeWord();
      // Revalida permissões/serviço após o usuário voltar de um diálogo do Android.
      _refreshDeviceStatus();
    }
    _syncTickerWithState(lifecycle: state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    deviceService.clearNativeEventHandlers();
    ticker.dispose();
    coreTime.dispose();
    voiceService.stop();
    commandController.dispose();
    quickNoteController.dispose();
    duressPinController.dispose();
    pcKillSwitchUrlController.dispose();
    messageTargetController.dispose();
    messageBodyController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  void _setStage(CoreStage next) {
    HapticFeedback.selectionClick();
    setState(() {
      stage = next;
      panel = _ActivePanel.main;
    });
    _syncTickerWithState();
  }

  void _setPanel(_ActivePanel next) {
    HapticFeedback.selectionClick();
    setState(() => panel = next);
    _syncTickerWithState();
  }

  void _toggleAudio() {
    HapticFeedback.selectionClick();
    setState(() {
      isAudioOn = !isAudioOn;
      voiceService.enabled = isAudioOn;
    });
    if (!isAudioOn) {
      voiceService.stop();
    }
  }

  Future<void> _openSettings() async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AiSettingsScreen()),
    );
    await _loadInitialState();
  }

  Future<void> _openHistory() async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ConversationHistoryScreen()),
    );
    await _loadInitialState();
  }

  void _lockSession() {
    HapticFeedback.heavyImpact();
    voiceService.speak('Sessão bloqueada.');
    widget.gate.lock();
  }

  void _appendFeed(_FeedEntry entry) {
    setState(() {
      feed = [...feed, entry];
    });
    _scrollToBottom();
  }

  Future<void> _saveQuickObsidianNote(String noteText) async {
    final trimmed = noteText.trim();
    if (trimmed.isEmpty) return;
    HapticFeedback.mediumImpact();
    try {
      final obsidian = await ObsidianService.openDefaultVault();
      final now = DateTime.now();
      final ts = _formatTime(now);
      final file = await obsidian.appendDailyNote(now, '[$ts] $trimmed');
      quickNoteController.clear();
      if (!mounted) return;
      final fileName = file.path.split(RegExp(r'[/\\]')).last;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '📓 Anotado em Diario/$fileName: "$trimmed"',
            style: const TextStyle(fontSize: 11),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      _appendFeed(
        _FeedEntry(
          isUser: false,
          senderLabel: 'Obsidian Vault',
          text: '📓 Quick Capture salvo em Diario/$fileName: "$trimmed"',
          timestamp: ts,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar no Vault: $e', style: const TextStyle(fontSize: 11)),
        ),
      );
    }
  }

  Future<void> _saveObsidianInbox(String noteText) async {
    final trimmed = noteText.trim();
    if (trimmed.isEmpty) return;
    HapticFeedback.mediumImpact();
    try {
      final obsidian = await ObsidianService.openDefaultVault();
      final now = DateTime.now();
      final ts = _formatTime(now);
      final file = await obsidian.captureToInbox(trimmed);
      quickNoteController.clear();
      if (!mounted) return;
      final fileName = file.path.split(RegExp(r'[/\\]')).last;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '💡 Ideia salva em Inbox/$fileName: "$trimmed"',
            style: const TextStyle(fontSize: 11),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      _appendFeed(
        _FeedEntry(
          isUser: false,
          senderLabel: 'Segundo Cérebro',
          text: '💡 Ideia capturada em Inbox/$fileName: "$trimmed"',
          timestamp: ts,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar no Inbox: $e', style: const TextStyle(fontSize: 11)),
        ),
      );
    }
  }

  Future<void> _executeSkillCard(MobileSkill skill) async {
    HapticFeedback.mediumImpact();
    final res = await deviceService.tryExecuteNaturalCommand(
      'executar skill ${skill.slug}',
    );
    if (!mounted) return;
    if (res != null) {
      _appendFeed(
        _FeedEntry(
          isUser: false,
          senderLabel: 'Skill Engine (.md)',
          text: res.message,
          timestamp: _formatTime(DateTime.now()),
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message, style: const TextStyle(fontSize: 11)),
          duration: const Duration(seconds: 2),
        ),
      );
      if (res.speakText != null) {
        await voiceService.speak(res.speakText!);
      }
    }
    await _refreshDeviceStatus();
  }

  Future<void> _startVoiceInput() async {
    if (sending) return;
    if (listeningVoice) {
      HapticFeedback.selectionClick();
      await deviceService.stopListeningVoice();
      return;
    }
    HapticFeedback.mediumImpact();
    await voiceService.stop();
    // Aguarda 280ms após cortar o TTS para dissipar qualquer eco do alto-falante antes de abrir o microfone
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted || sending || listeningVoice) return;
    setState(() {
      listeningVoice = true;
      speechRms = 0.1;
    });
    try {
      final spoken = await deviceService.listenVoice(
        prompt: 'Fale seu comando para o U.L.T.R.O.N...',
      );
      if (!mounted) return;
      setState(() {
        listeningVoice = false;
        speechRms = 0.0;
      });
      if (spoken.isNotEmpty) {
        commandController.text = spoken;
        await saveCommand();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        listeningVoice = false;
        speechRms = 0.0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reconhecimento de voz indisponível: $e',
            style: const TextStyle(fontSize: 11),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> saveCommand() async {
    if (sending) return;
    final text = commandController.text.trim();
    if (text.isEmpty) return;

    SystemSound.play(SystemSoundType.click);
    HapticFeedback.lightImpact();
    commandController.clear();
    final now = DateTime.now();
    final timeStr = _formatTime(now);

    // 1. Slash commands
    final command = SlashCommandParser.parse(text);
    if (command != null) {
      _appendFeed(
        _FeedEntry(
          isUser: true,
          senderLabel: 'OPERADOR',
          text: text,
          timestamp: timeStr,
        ),
      );
      await _runCommand(command.command, command.argument);
      return;
    }
    if (text.startsWith('/')) {
      _appendFeed(
        _FeedEntry(
          isUser: true,
          senderLabel: 'OPERADOR',
          text: text,
          timestamp: timeStr,
        ),
      );
      _appendFeed(
        _FeedEntry(
          isUser: false,
          senderLabel: 'Local Gateway',
          text:
              'Comando desconhecido: "$text". Digite /help para consultar todos os comandos disponíveis.',
          timestamp: timeStr,
        ),
      );
      return;
    }

    // 2. Natural language stage transitions (matching ultron_mobile_interface.tsx)
    final lower = text.toLowerCase();
    if (lower.contains('palco') ||
        lower.contains('documento') ||
        lower.contains('mostrar relatório')) {
      _appendFeed(
        _FeedEntry(
          isUser: true,
          senderLabel: 'OPERADOR',
          text: text,
          timestamp: timeStr,
        ),
      );
      _setStage(CoreStage.corner);
      _appendFeed(
        _FeedEntry(
          isUser: false,
          senderLabel: 'Interface Engine',
          text:
              'Modo Palco ativado. O núcleo foi realocado para o canto inferior.',
          timestamp: timeStr,
        ),
      );
      await voiceService.speak('Palco ativado.');
      return;
    }

    if (lower.contains('tela cheia') || lower.contains('expandir')) {
      _appendFeed(
        _FeedEntry(
          isUser: true,
          senderLabel: 'OPERADOR',
          text: text,
          timestamp: timeStr,
        ),
      );
      _setStage(CoreStage.hidden);
      _appendFeed(
        _FeedEntry(
          isUser: false,
          senderLabel: 'Interface Engine',
          text:
              'Exibição em tela cheia ativada. Núcleo desativado para economia de GPU.',
          timestamp: timeStr,
        ),
      );
      return;
    }

    // 3. Direct Android Hardware & OS Commands (instant, works offline)
    final deviceAction = await deviceService.tryExecuteNaturalCommand(text);
    if (deviceAction != null && deviceAction.handled) {
      _appendFeed(
        _FeedEntry(
          isUser: true,
          senderLabel: 'OPERADOR',
          text: text,
          timestamp: timeStr,
        ),
      );
      _appendFeed(
        _FeedEntry(
          isUser: false,
          senderLabel: 'Hardware Bridge',
          text: deviceAction.message,
          timestamp: timeStr,
        ),
      );
      await _refreshDeviceStatus();
      if (deviceAction.speakText != null) {
        await voiceService.speak(deviceAction.speakText!);
      }
      return;
    }

    // 4. AI Conversation + Failover + AI Hardware Actions
    _appendFeed(
      _FeedEntry(
        isUser: true,
        senderLabel: 'OPERADOR',
        text: text,
        timestamp: timeStr,
      ),
    );

    final previousMessages = await ConversationHistory.instance.messages(
      conversationId: 'default',
      limit: 12,
    );
    final aiHistory = previousMessages
        .where(
          (message) =>
              message.role == ChatRole.user ||
              message.role == ChatRole.assistant,
        )
        .map(
          (message) => <String, String>{
            'role': message.role.name,
            'content': message.content,
          },
        )
        .toList();

    await ConversationHistory.instance.save(
      ChatMessage(
        id: null,
        conversationId: 'default',
        role: ChatRole.user,
        content: text,
        createdAt: now,
      ),
    );
    if (!mounted) return;
    setState(() => sending = true);

    try {
      final contextualSystemPrompt =
          await deviceService.buildContextualSystemPrompt();
      final reply = await AiFailover(store: providerStore).ask(
        text,
        history: aiHistory,
        systemPrompt: contextualSystemPrompt,
      );
      final actionExec = await deviceService.executeAiActions(reply.text);
      await _refreshDeviceStatus();
      final displayReply = actionExec.executedLogs.isEmpty
          ? actionExec.cleanText
          : '${actionExec.cleanText}\n\n[Hardware: ${actionExec.executedLogs.join(' • ')}]';
      final replyNow = DateTime.now();
      await ConversationHistory.instance.save(
        ChatMessage(
          id: null,
          conversationId: 'default',
          role: ChatRole.assistant,
          content: displayReply,
          createdAt: replyNow,
        ),
      );
      if (!mounted) return;
      setState(() => activeProviderUsed = reply.provider);
      _appendFeed(
        _FeedEntry(
          isUser: false,
          senderLabel: reply.provider,
          text: displayReply,
          timestamp: _formatTime(replyNow),
        ),
      );
      await voiceService.speak(actionExec.cleanText);
    } catch (error) {
      if (!mounted) return;
      _appendFeed(
        _FeedEntry(
          isUser: false,
          senderLabel: 'Failover Alert',
          text: 'Mensagem salva localmente, mas a IA falhou: $error',
          timestamp: _formatTime(DateTime.now()),
        ),
      );
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<bool> _confirmActionGate({
    required String title,
    required String message,
    required String confirmText,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2B0307),
        title: Text(
          title,
          style: const TextStyle(
            color: _crimson,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(color: Color(0xFFF0E6E7), fontSize: 11),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCELAR', style: TextStyle(color: _rose)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _crimson),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _runCommand(
    UltronCommand command, [
    String argument = '',
  ]) async {
    final now = DateTime.now();
    final timeStr = _formatTime(now);
    switch (command) {
      case UltronCommand.help:
        _setPanel(_ActivePanel.help);
        break;
      case UltronCommand.security:
        final arg = argument.trim().toLowerCase();
        if (arg == 'lock' || arg == 'travar' || arg == 'bloquear') {
          _lockSession();
          return;
        }
        final failures = await widget.vault.failureCount();
        final pinSet = await widget.vault.hasPin;
        final duressSet = await widget.vault.hasDuressPin;
        if (!mounted) return;
        setState(() {
          authFailures = failures;
          hasPinConfigured = pinSet;
          hasDuressPinConfigured = duressSet;
        });
        _setPanel(_ActivePanel.security);
        break;
      case UltronCommand.history:
        await _openHistory();
        break;
      case UltronCommand.settings:
        await _openSettings();
        break;
      case UltronCommand.device:
        await _refreshDeviceStatus();
        _setPanel(_ActivePanel.device);
        break;
      case UltronCommand.torch:
        final arg = argument.trim().toLowerCase();
        bool state;
        if (arg == 'on' || arg == 'ligar' || arg == '1') {
          state = await deviceService.setTorch(true);
        } else if (arg == 'off' || arg == 'desligar' || arg == '0') {
          state = await deviceService.setTorch(false);
        } else {
          state = await deviceService.toggleTorch();
        }
        if (mounted) setState(() => torchOn = state);
        _appendFeed(_FeedEntry(
          isUser: false,
          senderLabel: 'Hardware Bridge',
          text: '🔦 Lanterna: ${state ? 'LIGADA' : 'DESLIGADA'}.',
          timestamp: timeStr,
        ));
        break;
      case UltronCommand.skills:
        final res = await deviceService.tryExecuteNaturalCommand(
          argument.isEmpty ? 'listar skills' : 'executar skill $argument',
        );
        if (res != null) {
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'Skill Engine (.md)',
            text: res.message,
            timestamp: timeStr,
          ));
          if (res.speakText != null) {
            await voiceService.speak(res.speakText!);
          }
        }
        break;
      case UltronCommand.note:
        if (argument.isEmpty) {
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'Obsidian Vault',
            text: 'Uso: /note <texto da nota> (ex.: /note revisar telemetria)',
            timestamp: timeStr,
          ));
        } else {
          await _saveQuickObsidianNote(argument);
        }
        break;
      case UltronCommand.vault:
        final obs = await ObsidianService.openDefaultVault();
        if (argument.isEmpty) {
          final opened = await deviceService.openObsidianVault();
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'Segundo Cérebro',
            text: opened
                ? '📓 Cofre Obsidian aberto no app oficial!\nLocal: ${obs.vaultPath}'
                : '📓 Cofre Segundo Cérebro: ${obs.vaultPath}\nUse /note <texto> para o Diário ou "ideia: <texto>" para o Inbox.',
            timestamp: timeStr,
          ));
        } else {
          await _saveObsidianInbox(argument);
        }
        break;
      case UltronCommand.models:
        _appendFeed(_FeedEntry(
          isUser: false,
          senderLabel: 'Central de IA',
          text: 'Consultando modelos ativos no provedor...',
          timestamp: timeStr,
        ));
        try {
          final providers = (await providerStore.load()).where((p) => p.enabled).toList();
          if (providers.isEmpty) {
            _appendFeed(_FeedEntry(
              isUser: false,
              senderLabel: 'Central de IA',
              text: 'Nenhum provedor ativo configurado.',
              timestamp: timeStr,
            ));
          } else {
            final activeP = providers.first;
            final models = await activeP.fetchAvailableModels();
            final modelsList = models.take(15).map((m) => '• $m').join('\n');
            _appendFeed(_FeedEntry(
              isUser: false,
              senderLabel: 'Auto-Discovery (/models)',
              text: 'Modelos disponíveis em ${activeP.name} (${activeP.baseUrl}):\n$modelsList',
              timestamp: timeStr,
            ));
          }
        } catch (e) {
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'Central de IA',
            text: 'Falha ao consultar modelos: $e',
            timestamp: timeStr,
          ));
        }
        break;
      case UltronCommand.messages:
        final res = await deviceService.tryExecuteNaturalCommand('ler mensagens');
        await _refreshDeviceStatus();
        if (res != null) {
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'Sentinela de Mensagens',
            text: res.message,
            timestamp: timeStr,
          ));
          if (res.speakText != null) {
            await voiceService.speak(res.speakText!);
          }
        }
        break;
      case UltronCommand.reply:
        if (argument.isEmpty) {
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'Sentinela de Mensagens',
            text: 'Uso: /reply <texto da resposta> ou "responder para Nome: <texto>"',
            timestamp: timeStr,
          ));
        } else {
          final res = await deviceService.tryExecuteNaturalCommand('responder: $argument');
          if (res != null) {
            _appendFeed(_FeedEntry(
              isUser: false,
              senderLabel: 'Sentinela de Mensagens',
              text: res.message,
              timestamp: timeStr,
            ));
            if (res.speakText != null) {
              await voiceService.speak(res.speakText!);
            }
          }
        }
        break;
      case UltronCommand.killswitch:
        final sim = actionGate.simulate('KILL_SWITCH');
        final confirmed = await _confirmActionGate(
          title: '🚨 ${sim.description.toUpperCase()}',
          message:
              'Atenção Operador: ${sim.estimatedImpact} Alvo: ${sim.targetResource}. Confirmar execução tática?',
          confirmText: 'DISPARAR KILL SWITCH',
        );
        if (!confirmed) {
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'Action Gate',
            text: 'Operação de Kill Switch cancelada pelo Operador.',
            timestamp: timeStr,
          ));
          return;
        }
        final msg = await deviceService.triggerPcKillSwitch(reason: 'slash_killswitch');
        _appendFeed(_FeedEntry(
          isUser: false,
          senderLabel: 'Kill Switch',
          text: msg,
          timestamp: timeStr,
        ));
        _lockSession();
        break;
      case UltronCommand.voice:
        await _startVoiceInput();
        break;
      case UltronCommand.clear:
        final sim = actionGate.simulate('CLEAR_HISTORY');
        final confirmed = await _confirmActionGate(
          title: 'EXPURGAR HISTÓRICO LOCAL',
          message:
              'Deseja limpar as mensagens da sessão atual? ${sim.estimatedImpact}',
          confirmText: 'EXPURGAR',
        );
        if (confirmed) {
          setState(() => feed = _defaultFeed);
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'Memória Local',
            text: 'Histórico da sessão purgado da memória RAM.',
            timestamp: timeStr,
          ));
        }
        break;
      case UltronCommand.lock:
        _lockSession();
        break;
      case UltronCommand.status:
        await _refreshDeviceStatus();
        final stat = deviceStatus;
        if (stat != null) {
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'Telemetria do Dispositivo',
            text: stat.formatSummary(),
            timestamp: timeStr,
          ));
        }
        break;
    }
  }

  Widget _buildCamouflageScreen() => Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text(
            'Bloco de Notas Pessoal',
            style: TextStyle(fontSize: 15, color: Colors.white70),
          ),
          actions: [
            IconButton(
              tooltip: 'Sair',
              onPressed: () => widget.gate.lock(),
              icon: const Icon(Icons.lock_outline, color: Colors.white54),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            Card(
              color: Color(0xFF1E1E1E),
              child: ListTile(
                title: Text(
                  'Lista de Compras da Semana',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  '• Café em grãos\n• Pão integral\n• Pilhas AA\n• Detergente neutro',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
            SizedBox(height: 8),
            Card(
              color: Color(0xFF1E1E1E),
              child: ListTile(
                title: Text(
                  'Leituras Recomendadas',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  '• Arquitetura Limpa — Cap. 4\n• Revisar anotações da faculdade',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (widget.gate.isDuressMode) {
      return _buildCamouflageScreen();
    }
    return Scaffold(
        backgroundColor: const Color(0xFF19171B),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              children: [
                // Global Operator Selector Bar
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xCC19171B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: _crimson,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: _crimson, blurRadius: 6),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'U.L.T.R.O.N. 2.0',
                            style: TextStyle(
                              color: _crimson,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          _TopNavPill(
                            label: 'NÚCLEO',
                            selected: panel == _ActivePanel.main,
                            onTap: () => _setPanel(_ActivePanel.main),
                          ),
                          const SizedBox(width: 4),
                          _TopNavPill(
                            label: 'CELULAR',
                            selected: panel == _ActivePanel.device,
                            onTap: () {
                              _refreshDeviceStatus();
                              _setPanel(_ActivePanel.device);
                            },
                          ),
                          const SizedBox(width: 4),
                          _TopNavPill(
                            label: 'PROVEDORES',
                            selected: panel == _ActivePanel.providers,
                            onTap: () => _setPanel(_ActivePanel.providers),
                          ),
                          const SizedBox(width: 4),
                          _TopNavPill(
                            label: 'HISTÓRICO',
                            selected: false,
                            onTap: _openHistory,
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: _toggleAudio,
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                isAudioOn ? Icons.volume_up : Icons.volume_off,
                                size: 15,
                                color: isAudioOn
                                    ? _crimson
                                    : const Color(0xFFA89698),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Main Screen Content (Main / Device / Security / Help / Providers)
                Expanded(
                  child: switch (panel) {
                    _ActivePanel.main => _buildMainPanel(),
                    _ActivePanel.device => _buildDevicePanel(),
                    _ActivePanel.security => _buildSecurityPanel(),
                    _ActivePanel.help => _buildHelpPanel(),
                    _ActivePanel.providers => _buildProvidersPanel(),
                  },
                ),
              ],
            ),
          ),
        ),
      );
  }

  Widget _buildMainPanel() => Column(
        children: [
          // Operational Header
          Container(
            padding: const EdgeInsets.only(bottom: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2B0307),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: _crimson.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          widget.gate.isAuthenticated
                              ? 'SESSÃO: NÍVEL 02'
                              : 'BLOQUEADO',
                          style: const TextStyle(
                            color: _crimson,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        'PROVEDOR: $activeProviderUsed',
                        style: const TextStyle(
                          color: Color(0xFFA89698),
                          fontSize: 10,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      tooltip: torchOn
                          ? 'Desligar Lanterna (/lanterna)'
                          : 'Ligar Lanterna (/lanterna)',
                      onPressed: _toggleTorchQuick,
                      icon: Icon(
                        torchOn
                            ? Icons.flashlight_on
                            : Icons.flashlight_off_outlined,
                        size: 16,
                        color: torchOn ? _crimson : const Color(0xFFA89698),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      tooltip: 'Controles do Celular (/device)',
                      onPressed: () {
                        _refreshDeviceStatus();
                        _setPanel(_ActivePanel.device);
                      },
                      icon: const Icon(
                        Icons.phonelink_setup,
                        size: 16,
                        color: Color(0xFFA89698),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      tooltip: 'Comandos Rápidos (/help)',
                      onPressed: () => _setPanel(_ActivePanel.help),
                      icon: const Icon(
                        Icons.help_outline,
                        size: 16,
                        color: Color(0xFFA89698),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      tooltip: 'Painel de Segurança (/security)',
                      onPressed: () => _runCommand(UltronCommand.security),
                      icon: const Icon(
                        Icons.shield_outlined,
                        size: 16,
                        color: Color(0xFFA89698),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      tooltip: hasUpdate
                          ? 'Atualização disponível'
                          : 'Atualizador GitHub',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const UpdateScreen(),
                        ),
                      ),
                      icon: Badge(
                        isLabelVisible: hasUpdate,
                        child: const Icon(
                          Icons.cloud_download_outlined,
                          size: 16,
                          color: Color(0xFFA89698),
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      tooltip: 'Bloquear Sessão',
                      onPressed: _lockSession,
                      icon: const Icon(
                        Icons.lock_outline,
                        size: 16,
                        color: Color(0xFFFF707C),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Dynamic Center Area: Normal vs Palco vs Fullscreen
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: switch (stage) {
                CoreStage.center => _buildNormalStage(),
                CoreStage.corner => _buildPalcoStage(),
                CoreStage.hidden => _buildFullscreenStage(),
              },
            ),
          ),

          // Main Command Bar: 'EI, ULTRON ›'
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF2B0307),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                const Text(
                  'EI, ULTRON ›',
                  style: TextStyle(
                    color: _crimson,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: commandController,
                    enabled: !sending,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => saveCommand(),
                    style: const TextStyle(
                      color: Color(0xFFF0E6E7),
                      fontSize: 12,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: listeningVoice
                          ? '🎤 Ouvindo ao vivo (toque no 🎤 para concluir)…'
                          : sending
                              ? 'Consultando provedor ativo…'
                              : 'Digite /help, /settings ou toque no 🎤 para falar...',
                      hintStyle: TextStyle(
                        color: listeningVoice
                            ? _crimson
                            : const Color(0xFF635355),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                InkWell(
                  onTap: sending ? null : _startVoiceInput,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: listeningVoice
                          ? _crimson.withValues(alpha: 0.25)
                          : const Color(0xFF2B0307),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: listeningVoice
                            ? _crimson
                            : _crimson.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Icon(
                      listeningVoice ? Icons.graphic_eq : Icons.mic,
                      size: 14,
                      color: listeningVoice ? _rose : _crimson,
                    ),
                  ),
                ),
                InkWell(
                  onTap: sending ? null : saveCommand,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2B0307),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.send,
                      size: 14,
                      color: _crimson,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _buildNormalStage() => Column(
        children: [
          // Large Central Crimson Orbital Core
          Column(
            children: [
              GestureDetector(
                onTap: () => _setStage(CoreStage.corner),
                child: SizedBox(
                  width: 210,
                  height: 210,
                  child: ValueListenableBuilder<double>(
                    valueListenable: coreTime,
                    builder: (context, time, child) => CustomPaint(
                      painter: CorePainter(
                        time,
                        intensity: nightFocusMode
                            ? 0.35
                            : listeningVoice
                                ? (1.35 + speechRms * 1.25)
                                : (sending ? 2.2 : 1.0),
                      ),
                    ),
                  ),
                ),
              ),
              Text(
                nightFocusMode
                    ? 'U.L.T.R.O.N. CORE [FOCO NOTURNO]'
                    : listeningVoice
                        ? 'U.L.T.R.O.N. CORE [ESCUTANDO AO VIVO]'
                        : 'U.L.T.R.O.N. CORE',
                style: const TextStyle(
                  color: _rose,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                nightFocusMode
                    ? 'Modo Sussurro TTS Ativo • Flip-to-Shush Pronto'
                    : 'Voz Neural (${selectedVoiceProfile.label}) • Anti-Eco Half-Duplex • Flip-to-Shush',
                style: const TextStyle(
                  color: Color(0xFF635355),
                  fontSize: 9,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  _StageChip(
                    label: listeningVoice ? 'CONCLUIR FALA' : 'FALAR POR VOZ',
                    icon: listeningVoice ? Icons.graphic_eq : Icons.mic,
                    onTap: _startVoiceInput,
                  ),
                  _StageChip(
                    label: 'CALAR VOZ',
                    icon: Icons.volume_off_outlined,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      voiceService.stop();
                    },
                  ),
                  _StageChip(
                    label: 'MODO PALCO',
                    icon: Icons.picture_in_picture_alt_outlined,
                    onTap: () => _setStage(CoreStage.corner),
                  ),
                  _StageChip(
                    label: 'TELA CHEIA',
                    icon: Icons.open_in_full,
                    onTap: () => _setStage(CoreStage.hidden),
                  ),
                  _StageChip(
                    label: nightFocusMode ? 'NOTURNO ON' : 'NOTURNO',
                    icon: Icons.nights_stay_outlined,
                    onTap: _toggleNightFocusMode,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Live Chat / Telemetry Feed
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              itemCount: feed.length + (sending ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == feed.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _crimson,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Consultando provedor ativo com failover...',
                          style: TextStyle(
                            color: _crimson,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                final msg = feed[index];
                return Align(
                  alignment:
                      msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: GestureDetector(
                    onLongPress: () {
                      HapticFeedback.selectionClick();
                      Clipboard.setData(ClipboardData(text: msg.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Mensagem copiada para a área de transferência.',
                            style: TextStyle(fontSize: 11),
                          ),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.84,
                      ),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: msg.isUser
                            ? const Color(0xFF2B0307)
                            : const Color(0xFF19171B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: msg.isUser
                              ? _crimson.withValues(alpha: 0.4)
                              : _border,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                msg.senderLabel,
                                style: TextStyle(
                                  color: msg.isUser ? _rose : _crimson,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                msg.timestamp,
                                style: const TextStyle(
                                  color: Color(0xFF635355),
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            msg.text,
                            style: TextStyle(
                              color: msg.isUser
                                  ? const Color(0xFFF0E6E7)
                                  : const Color(0xFFF0E6E7),
                              fontSize: 11,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );

  Widget _buildPalcoStage() => Column(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF19171B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _border),
              ),
              child: ListView(
                children: [
                  Container(
                    padding: const EdgeInsets.only(bottom: 8),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: _border)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.description_outlined,
                              size: 13,
                              color: _crimson,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'PALCO ATIVO',
                              style: TextStyle(
                                color: _crimson,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            InkWell(
                              onTap: () => _setStage(CoreStage.hidden),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(
                                  Icons.open_in_full,
                                  size: 14,
                                  color: Color(0xFFA89698),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () => _setStage(CoreStage.center),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(
                                  Icons.close,
                                  size: 15,
                                  color: Color(0xFFA89698),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Relatório de Telemetria e Comandos',
                    style: TextStyle(
                      color: Color(0xFFF0E6E7),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'O Palco isola documentos e saídas sem abrir novas janelas. Toque nos comandos rápidos abaixo para executar localmente:',
                    style: TextStyle(
                      color: Color(0xFFA89698),
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 2.3,
                    children: [
                      _QuickCommandCard(
                        command: '/help',
                        description: 'Ajuda de comandos',
                        onTap: () => _runCommand(UltronCommand.help),
                      ),
                      _QuickCommandCard(
                        command: '/security',
                        description: 'Status AuthGate',
                        onTap: () => _runCommand(UltronCommand.security),
                      ),
                      _QuickCommandCard(
                        command: '/history',
                        description: 'Ver mensagens',
                        onTap: () => _runCommand(UltronCommand.history),
                      ),
                      _QuickCommandCard(
                        command: '/settings',
                        description: 'Provedores e Release',
                        onTap: () => _runCommand(UltronCommand.settings),
                      ),
                    ],
                  ),
                  if (feed.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2B0307),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ÚLTIMA SAÍDA (${feed.last.senderLabel}):',
                            style: const TextStyle(
                              color: _rose,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            feed.last.text,
                            style: const TextStyle(
                              color: Color(0xFFF0E6E7),
                              fontSize: 11,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Núcleo em modo sentinela (toque para restaurar)',
                style: TextStyle(
                  color: Color(0xFF635355),
                  fontSize: 10,
                ),
              ),
              GestureDetector(
                onTap: () => _setStage(CoreStage.center),
                child: SizedBox(
                  width: 76,
                  height: 76,
                  child: ValueListenableBuilder<double>(
                    valueListenable: coreTime,
                    builder: (context, time, child) => CustomPaint(
                      painter: CorePainter(time, intensity: 0.9),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      );

  Widget _buildFullscreenStage() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF2B0307),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _crimson.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.only(bottom: 8),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: _border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'MODO TELA CHEIA [FULLSCREEN]',
                    style: TextStyle(
                      color: _crimson,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  InkWell(
                    onTap: () => _setStage(CoreStage.corner),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.close_fullscreen,
                          size: 13,
                          color: Color(0xFFA89698),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'REDUZIR',
                          style: TextStyle(
                            color: Color(0xFFA89698),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                const _TelemetryBox(
                  title: 'STATUS DO RENDERIZADOR:',
                  titleColor: _rose,
                  body:
                      'Núcleo descarregado da GPU (Ticker pausado). Consumo em repouso: 0.1%',
                ),
                const SizedBox(height: 10),
                _TelemetryBox(
                  title: 'FAILOVER DE PROVEDORES:',
                  titleColor: const Color(0xFFFF707C),
                  body:
                      'Ativo: $activeProviderUsed • Chave protegida no Keystore Android',
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const UpdateScreen(),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: _TelemetryBox(
                    title: 'ATUALIZAÇÃO GITHUB (TOQUE PARA ABRIR):',
                    titleColor: hasUpdate
                        ? const Color(0xFFFF707C)
                        : const Color(0xFFA89698),
                    body:
                        'Versão instalada $installedVersion (${hasUpdate ? 'Nova release disponível' : 'Toque para verificar/atualizar'})',
                  ),
                ),
              ],
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _setStage(CoreStage.center),
                style: FilledButton.styleFrom(
                  backgroundColor: _crimson,
                  foregroundColor: const Color(0xFFF0E6E7),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'RESTAURAR NÚCLEO AO CENTRO',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildSecurityPanel() {
    final pinLabel = hasPinConfigured == null
        ? 'Indisponível'
        : hasPinConfigured!
            ? 'Configurado (PBKDF2-SHA256)'
            : 'Não configurado';
    final duressLabel = hasDuressPinConfigured
        ? 'Ativo (Modo Camuflado)'
        : 'Não configurado';
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _border)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: () => _setPanel(_ActivePanel.main),
                child: const Row(
                  children: [
                    Icon(Icons.arrow_back, size: 15, color: _crimson),
                    SizedBox(width: 4),
                    Text(
                      'VOLTAR',
                      style: TextStyle(
                        color: _crimson,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Row(
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 15,
                    color: Colors.white,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'PAINEL DE SEGURANÇA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF19171B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _crimson.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'STATUS DO AUTHGATE',
                      style: TextStyle(
                        color: _crimson,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SecurityRow(
                      label: 'Estado Atual:',
                      value: widget.gate.isAuthenticated
                          ? 'DESBLOQUEADO'
                          : 'BLOQUEADO',
                      valueColor: const Color(0xFFFF707C),
                    ),
                    const SizedBox(height: 6),
                    const _SecurityRow(
                      label: 'Nível de Restrição:',
                      value: 'Nível 02 (-2 Níveis Ativo)',
                      valueColor: _rose,
                    ),
                    const SizedBox(height: 6),
                    _SecurityRow(
                      label: 'Cofre de PIN Principal:',
                      value: pinLabel,
                      valueColor: const Color(0xFFF0E6E7),
                    ),
                    const SizedBox(height: 6),
                    _SecurityRow(
                      label: 'PIN de Coação (Duress):',
                      value: duressLabel,
                      valueColor: hasDuressPinConfigured
                          ? const Color(0xFFFF707C)
                          : const Color(0xFFA89698),
                    ),
                    const SizedBox(height: 6),
                    _SecurityRow(
                      label: 'Tentativas Falhas:',
                      value: '$authFailures',
                      valueColor: const Color(0xFFF0E6E7),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Duress PIN Configuration Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF2B0307),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PIN DE COAÇÃO (DURESS PIN - MODO CAMUFLADO)',
                      style: TextStyle(
                        color: _rose,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Se digitado na tela de desbloqueio, limpa o histórico de conversas silenciosamente e abre um Bloco de Notas falso.',
                      style: TextStyle(
                        color: Color(0xFFA89698),
                        fontSize: 10,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: duressPinController,
                            keyboardType: TextInputType.number,
                            obscureText: true,
                            maxLength: 8,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                            decoration: const InputDecoration(
                              counterText: '',
                              isDense: true,
                              hintText: 'Novo PIN de Coação (4 a 8 dígitos)',
                              hintStyle: TextStyle(
                                color: Color(0xFF635355),
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () async {
                            final pin = duressPinController.text.trim();
                            try {
                              await widget.vault.setDuressPin(pin);
                              duressPinController.clear();
                              if (!mounted) return;
                              setState(() => hasDuressPinConfigured = true);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'PIN de Coação configurado com sucesso.',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                              );
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Erro no PIN de Coação: $e',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              );
                            }
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: _crimson,
                            foregroundColor: const Color(0xFFF0E6E7),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text(
                            'SALVAR',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (hasDuressPinConfigured) ...[
                          const SizedBox(width: 6),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Remover PIN de Coação',
                            onPressed: () async {
                              await widget.vault.clearDuressPin();
                              if (!mounted) return;
                              setState(() => hasDuressPinConfigured = false);
                            },
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 16,
                              color: Color(0xFFFF707C),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Remote PC Kill Switch Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF2B0307),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'KILL SWITCH REMOTO DO PC (LAN / WEBHOOK)',
                      style: TextStyle(
                        color: _crimson,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Envia pacote assinado (HMAC-SHA256) para suspender/travar seu PC na rede local e bloqueia o celular.',
                      style: TextStyle(
                        color: Color(0xFFA89698),
                        fontSize: 10,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: pcKillSwitchUrlController,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: 'http://192.168.1.100:8765/kill',
                              hintStyle: TextStyle(
                                color: Color(0xFF635355),
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () async {
                            await deviceService.savePcKillSwitchUrl(
                              pcKillSwitchUrlController.text,
                            );
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Endpoint do Kill Switch salvo.',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _crimson,
                            side: const BorderSide(color: _crimson),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text(
                            'FIXAR IP',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () async {
                          final msg = await deviceService.triggerPcKillSwitch(
                            reason: 'security_panel_panic',
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                msg,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          );
                          _lockSession();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF75020F),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        icon: const Icon(Icons.warning_amber_rounded, size: 16),
                        label: const Text(
                          'ACIONAR KILL SWITCH (PC + CELULAR)',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF2B0307),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'POLÍTICAS LOCAIS FAIL-CLOSED',
                      style: TextStyle(
                        color: Color(0xFFF0E6E7),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Nenhuma ordem da IA sobrepõe a validação do dispositivo. O comando /security audita e bloqueia privilégios a qualquer momento.',
                      style: TextStyle(
                        color: Color(0xFFA89698),
                        fontSize: 10,
                        height: 1.4,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '✓ Cifragem PBKDF2-HMAC-SHA256 (120k iter): Ativa',
                      style: TextStyle(
                        color: Color(0xFFFF707C),
                        fontSize: 10,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '✓ Isolação de Chaves de API no Keystore: Ativa',
                      style: TextStyle(
                        color: Color(0xFFFF707C),
                        fontSize: 10,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '✓ Exclusão de Backup em Nuvem (allowBackup=false): Ativa',
                      style: TextStyle(
                        color: Color(0xFFFF707C),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _lockSession,
            style: FilledButton.styleFrom(
              backgroundColor: _crimson,
              foregroundColor: const Color(0xFFF0E6E7),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'TRAVAR DISPOSITIVO AGORA',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDevicePanel() {
    final s = deviceStatus;
    final batLevel = s != null && s.batteryLevel >= 0 ? s.batteryLevel : 84;
    final batCharging = s?.isCharging ?? false;
    final batTemp = s != null && s.batteryTempC > 0 ? s.batteryTempC : 31.2;
    final batPct = batLevel / 100.0;

    final ramTotal = s != null && s.ramTotalMb > 0 ? s.ramTotalMb : 8192;
    final ramUsed = s != null && s.ramUsedMb > 0 ? s.ramUsedMb : 4915;
    final ramPct = ramTotal > 0 ? (ramUsed / ramTotal) : 0.6;
    final ramVal = '${(ramPct * 100).toInt()}%';
    final ramSub = '${(ramUsed / 1024).toStringAsFixed(1)} GB';

    final netType = s != null
        ? (s.wifiConnected
            ? 'WI-FI 6'
            : (s.cellularConnected ? '4G/5G' : 'OFFLINE'))
        : 'WI-FI 6';

    final batText = s != null && s.batteryLevel >= 0
        ? '${s.batteryLevel}% ${s.isCharging ? '(Carregando ⚡)' : ''}'
        : 'Consultando…';
    final ramText = s != null && s.ramTotalMb > 0
        ? '${s.ramUsedMb} / ${s.ramTotalMb} MB (${s.ramFreeMb} MB livres)'
        : 'Consultando…';
    final volText = s != null ? '${s.volumePercent}% (${s.ringerMode})' : '…';
    final modelText = s != null
        ? '${s.deviceModel} • ${s.androidVersion}'
        : 'Android Node';

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _border)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: () => _setPanel(_ActivePanel.main),
                child: const Row(
                  children: [
                    Icon(Icons.arrow_back, size: 15, color: _crimson),
                    SizedBox(width: 4),
                    Text(
                      'VOLTAR',
                      style: TextStyle(
                        color: _crimson,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  const Icon(
                    Icons.phonelink_setup,
                    size: 15,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'CONTROLE DO DISPOSITIVO',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: _refreshDeviceStatus,
                    child: const Icon(
                      Icons.refresh,
                      size: 15,
                      color: _crimson,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 10),
            children: [
              // 0. Cockpit de Telemetria Circular (AMOLED Carmesim HUD)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2B0307),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _crimson.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '📡 COCKPIT DE TELEMETRIA EM TEMPO REAL',
                          style: TextStyle(
                            color: _crimson,
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Text(
                          'AMOLED HUD',
                          style: TextStyle(
                            color: _rose,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _CircularTelemetryGauge(
                            value: '$batLevel%${batCharging ? '⚡' : ''}',
                            label: 'BATERIA',
                            subLabel: '${batTemp.toStringAsFixed(1)}°C',
                            percentage: batPct,
                            color: batLevel < 20
                                ? const Color(0xFFFF707C)
                                : const Color(0xFF75020F),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _CircularTelemetryGauge(
                            value: ramVal,
                            label: 'RAM',
                            subLabel: ramSub,
                            percentage: ramPct,
                            color: const Color(0xFF75020F),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _CircularTelemetryGauge(
                            value: '${batTemp.toInt()}°C',
                            label: 'TEMP',
                            subLabel: 'ESTÁVEL',
                            percentage: 0.35,
                            color: const Color(0xFFFF707C),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _CircularTelemetryGauge(
                            value: '92%',
                            label: netType,
                            subLabel: s?.ringerMode ?? 'ONLINE',
                            percentage: 0.92,
                            color: const Color(0xFF75020F),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // 1. Hardware Telemetry Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF19171B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _crimson.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      modelText,
                      style: const TextStyle(
                        color: _crimson,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SecurityRow(
                      label: 'Bateria:',
                      value: batText,
                      valueColor: const Color(0xFFFF707C),
                    ),
                    const SizedBox(height: 4),
                    _SecurityRow(
                      label: 'Memória RAM:',
                      value: ramText,
                      valueColor: const Color(0xFFF0E6E7),
                    ),
                    const SizedBox(height: 4),
                    _SecurityRow(
                      label: 'Volume de Mídia:',
                      value: volText,
                      valueColor: _rose,
                    ),
                    const SizedBox(height: 4),
                    _SecurityRow(
                      label: 'Lanterna Traseira:',
                      value: torchOn ? 'LIGADA (ON)' : 'DESLIGADA (OFF)',
                      valueColor: torchOn
                          ? const Color(0xFFFF707C)
                          : const Color(0xFFA89698),
                    ),
                    const SizedBox(height: 4),
                    const _SecurityRow(
                      label: 'Flip-to-Shush (Acelerômetro):',
                      value: 'ATIVO (Virar tela p/ baixo silencia)',
                      valueColor: Color(0xFFFF707C),
                    ),
                    const SizedBox(height: 4),
                    _SecurityRow(
                      label: 'Modo Foco Noturno:',
                      value: nightFocusMode ? 'ATIVO (Sussurro TTS)' : 'INATIVO',
                      valueColor: nightFocusMode
                          ? const Color(0xFFFF707C)
                          : const Color(0xFFA89698),
                    ),
                    const SizedBox(height: 4),
                    _SecurityRow(
                      label: 'Sentinela de Voz (escuta contínua):',
                      value: ecoVadSentinelRunning
                          ? 'ATIVO (VAD adaptativo)'
                          : 'EM REPOUSO',
                      valueColor: ecoVadSentinelRunning
                          ? const Color(0xFFFF707C)
                          : const Color(0xFFA89698),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () async {
                              final next = !ecoVadSentinelRunning;
                              final requested =
                                  await deviceService.setAudioSentinel(next);
                              // "ATIVO" só após captura real confirmada pelo serviço nativo.
                              var real = false;
                              if (next && requested) {
                                for (var i = 0; i < 8 && !real; i++) {
                                  await Future<void>.delayed(
                                    const Duration(milliseconds: 500),
                                  );
                                  real = await deviceService
                                      .isAudioSentinelRunning();
                                }
                              }
                              if (!mounted) return;
                              setState(() => ecoVadSentinelRunning = real);
                              // requested == false => o Android abriu o diálogo de permissão;
                              // o estado real é revalidado no retorno ao primeiro plano.
                              if (next && requested && !real) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      '⚠️ Sentinela não confirmou captura do microfone. Veja o diagnóstico.',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                );
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: ecoVadSentinelRunning
                                  ? const Color(0xFF75020F)
                                  : const Color(0xFF2B0307),
                              foregroundColor: ecoVadSentinelRunning
                                  ? const Color(0xFFFF707C)
                                  : _rose,
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: Icon(
                              ecoVadSentinelRunning
                                  ? Icons.hearing
                                  : Icons.hearing_disabled,
                              size: 13,
                            ),
                            label: Text(
                              ecoVadSentinelRunning
                                  ? 'DESATIVAR ECO-VAD'
                                  : 'ATIVAR SENTINELA ECO-VAD',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () async {
                              final reply = await deviceService
                                  .speakOfflineFishVoice('que horas são');
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '🔊 Voz Offline: $reply',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              );
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: _crimson,
                              foregroundColor: const Color(0xFFF0E6E7),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.graphic_eq, size: 13),
                            label: const Text(
                              'VOZ OFFLINE (HORAS)',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showWakeWordDiagnostics,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _rose,
                          side: const BorderSide(color: _border),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.troubleshoot, size: 13),
                        label: const Text(
                          'DIAGNÓSTICO DA PALAVRA DE ATIVAÇÃO',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'PERFIL DE TIMBRE NEURAL (PT-BR LIMPO SEM ROBÔ):',
                      style: TextStyle(
                        color: Color(0xFFA89698),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        for (final prof in VoiceProfile.values) ...[
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: OutlinedButton(
                                onPressed: () async {
                                  HapticFeedback.selectionClick();
                                  await voiceService.setProfile(prof);
                                  if (!mounted) return;
                                  setState(() => selectedVoiceProfile = prof);
                                  await voiceService.preview();
                                },
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: selectedVoiceProfile == prof
                                      ? _crimson
                                      : const Color(0xFF2B0307),
                                  foregroundColor: selectedVoiceProfile == prof
                                      ? Colors.black
                                      : _rose,
                                  side: BorderSide(
                                    color: selectedVoiceProfile == prof
                                        ? _crimson
                                        : _border,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                ),
                                child: Text(
                                  prof.label,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                        OutlinedButton(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            voiceService.stop();
                          },
                          style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFF2B0307),
                            foregroundColor: const Color(0xFFFF707C),
                            side: const BorderSide(color: _border),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                          ),
                          child: const Text(
                            'CALAR',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 1A. Sentinela de Mensagens & Comunicação Autônoma (500x)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2B0307),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _crimson.withValues(alpha: 0.45),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '📨 SENTINELA DE MENSAGENS & WHATSAPP',
                          style: TextStyle(
                            color: _crimson,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: notificationSentinelEnabled
                                ? const Color(0xFF75020F)
                                : const Color(0xFF2B0307),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            notificationSentinelEnabled
                                ? 'SENTINELA ATIVO'
                                : 'PERMISSÃO PENDENTE',
                            style: TextStyle(
                              color: notificationSentinelEnabled
                                  ? const Color(0xFFFF707C)
                                  : _rose,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (!notificationSentinelEnabled)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () =>
                              deviceService.openNotificationListenerSettings(),
                          style: FilledButton.styleFrom(
                            backgroundColor: _crimson,
                            foregroundColor: const Color(0xFFF0E6E7),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(
                            Icons.notifications_active,
                            size: 14,
                          ),
                          label: const Text(
                            'ATIVAR LEITURA E RESPOSTA EM 2º PLANO',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      )
                    else ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _StageChip(
                            label: '🔊 LER EM VOZ ALTA',
                            icon: Icons.record_voice_over,
                            onTap: _readRecentMessagesAloud,
                          ),
                          _StageChip(
                            label: '🧠 RESUMO TÁTICO IA',
                            icon: Icons.auto_awesome,
                            onTap: _summarizeMessagesWithAi,
                          ),
                          _StageChip(
                            label: '📇 AGENDA',
                            icon: Icons.contacts_outlined,
                            onTap: () async {
                              await deviceService.requestContactsPermission();
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Permissão de contatos solicitada ao Android.',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                              );
                            },
                          ),
                          if (recentMessages.isNotEmpty)
                            _StageChip(
                              label: 'LIMPAR',
                              icon: Icons.clear_all,
                              onTap: () async {
                                await deviceService.clearRecentMessages();
                                await _refreshDeviceStatus();
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (recentMessages.isEmpty)
                        const Text(
                          '📭 Nenhuma mensagem capturada ainda. Quando chegar WhatsApp, Telegram, Instagram ou SMS, o U.L.T.R.O.N. exibirá aqui para leitura ou resposta em 2º plano.',
                          style: TextStyle(
                            color: Color(0xFFA89698),
                            fontSize: 9.5,
                          ),
                        )
                      else
                        for (final m in recentMessages.take(4))
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF19171B),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: _border),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '[${m.timeFormatted}] ${m.appLabel} • ${m.sender}',
                                        style: const TextStyle(
                                          color: _rose,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        m.text,
                                        style: const TextStyle(
                                          color: Color(0xFFF0E6E7),
                                          fontSize: 10.5,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                if (m.canReplyInline)
                                  InkWell(
                                    onTap: () => _promptReplyToMessage(m),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2B0307),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color:
                                              _crimson.withValues(alpha: 0.5),
                                        ),
                                      ),
                                      child: const Text(
                                        '↩️ RESPONDER',
                                        style: TextStyle(
                                          color: _crimson,
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                    ],
                    const Divider(color: _border, height: 14),
                    const Text(
                      'ENVIAR WHATSAPP OU SMS (NOME DO CONTATO OU NÚMERO):',
                      style: TextStyle(
                        color: _rose,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: messageTargetController,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: 'Contato ou 1199999...',
                              hintStyle: TextStyle(
                                color: Color(0xFF635355),
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: messageBodyController,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: 'Texto da mensagem…',
                              hintStyle: TextStyle(
                                color: Color(0xFF635355),
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _sendQuickMessage(viaSms: false),
                            style: FilledButton.styleFrom(
                              backgroundColor: _crimson,
                              foregroundColor: const Color(0xFFF0E6E7),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.chat_bubble, size: 13),
                            label: const Text(
                              'WHATSAPP',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _sendQuickMessage(viaSms: true),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF2B0307),
                              foregroundColor: _rose,
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.sms, size: 13),
                            label: const Text(
                              'ENVIAR SMS',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 1B. Obsidian Quick Capture + Local Skills (.md)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2B0307),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'OBSIDIAN SEGUNDO CÉREBRO & SKILLS (.MD)',
                          style: TextStyle(
                            color: _crimson,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        InkWell(
                          onTap: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final opened = await deviceService.openObsidianVault();
                            if (!mounted) return;
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  opened
                                      ? '📓 Abrindo cofre no app oficial Obsidian…'
                                      : '⚠️ Aplicativo Obsidian não encontrado.',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(4),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              children: [
                                Icon(Icons.open_in_new, size: 11, color: _rose),
                                SizedBox(width: 4),
                                Text(
                                  'ABRIR OBSIDIAN',
                                  style: TextStyle(
                                    color: _rose,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: quickNoteController,
                            textInputAction: TextInputAction.send,
                            onSubmitted: _saveQuickObsidianNote,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: 'Nota rápida para o Diário ou Inbox…',
                              hintStyle: TextStyle(
                                color: Color(0xFF635355),
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        FilledButton(
                          onPressed: () =>
                              _saveQuickObsidianNote(quickNoteController.text),
                          style: FilledButton.styleFrom(
                            backgroundColor: _crimson,
                            foregroundColor: const Color(0xFFF0E6E7),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          child: const Text(
                            'DIÁRIO',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        FilledButton(
                          onPressed: () =>
                              _saveObsidianInbox(quickNoteController.text),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF4A0A12),
                            foregroundColor: _rose,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          child: const Text(
                            'INBOX',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (mobileSkills.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'SKILLS PROCEDURAIS LOCAIS (Skills/*.md):',
                        style: TextStyle(
                          color: _rose,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final skill in mobileSkills)
                            _StageChip(
                              label: '⚡ ${skill.title}',
                              icon: Icons.auto_awesome_outlined,
                              onTap: () => _executeSkillCard(skill),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 2. Flashlight & Haptics Primary Button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _toggleTorchQuick,
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        torchOn ? const Color(0xFFFF707C) : _crimson,
                    foregroundColor: const Color(0xFFF0E6E7),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: Icon(
                    torchOn ? Icons.flashlight_off : Icons.flashlight_on,
                    size: 16,
                  ),
                  label: Text(
                    torchOn
                        ? 'DESLIGAR LANTERNA DO CELULAR'
                        : 'LIGAR LANTERNA DO CELULAR',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // 3. Volume Controls
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2B0307),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CONTROLE DE ÁUDIO DO SISTEMA',
                      style: TextStyle(
                        color: _rose,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _StageChip(
                          label: 'MUDO',
                          icon: Icons.volume_off,
                          onTap: () async {
                            await deviceService.adjustVolume('mute');
                            await _refreshDeviceStatus();
                          },
                        ),
                        _StageChip(
                          label: 'VOL -',
                          icon: Icons.volume_down,
                          onTap: () async {
                            await deviceService.adjustVolume('down');
                            await _refreshDeviceStatus();
                          },
                        ),
                        _StageChip(
                          label: '50%',
                          icon: Icons.graphic_eq,
                          onTap: () async {
                            await deviceService.setVolume(50);
                            await _refreshDeviceStatus();
                          },
                        ),
                        _StageChip(
                          label: '100%',
                          icon: Icons.speaker,
                          onTap: () async {
                            await deviceService.setVolume(100);
                            await _refreshDeviceStatus();
                          },
                        ),
                        _StageChip(
                          label: 'VOL +',
                          icon: Icons.volume_up,
                          onTap: () async {
                            await deviceService.adjustVolume('up');
                            await _refreshDeviceStatus();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 4. System Panels & Hardware Actions
              const Text(
                'AÇÕES DE SISTEMA E SENSORES',
                style: TextStyle(
                  color: _rose,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.5,
                children: [
                  _QuickCommandCard(
                    command: '📷 CÂMERA',
                    description: 'Abrir câmera nativa',
                    onTap: () => deviceService.openApp('camera'),
                  ),
                  _QuickCommandCard(
                    command: '📶 WI-FI / REDE',
                    description: 'Painel de conectividade',
                    onTap: () => deviceService.openSystemSettings('wifi'),
                  ),
                  _QuickCommandCard(
                    command: '🦷 BLUETOOTH',
                    description: 'Dispositivos pareados',
                    onTap: () => deviceService.openSystemSettings('bluetooth'),
                  ),
                  _QuickCommandCard(
                    command: '🔆 TELA / BRILHO',
                    description: 'Ajustes de display',
                    onTap: () => deviceService.openSystemSettings('display'),
                  ),
                  _QuickCommandCard(
                    command: '⏰ ALARME / TIMER',
                    description: 'Abrir relógio do sistema',
                    onTap: () => deviceService.openApp('relogio'),
                  ),
                  _QuickCommandCard(
                    command: '📳 VIBRAR',
                    description: 'Testar motor háptico',
                    onTap: () => deviceService.vibrate(durationMs: 350),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 5. Quick App Launcher
              const Text(
                'LANÇADOR RÁPIDO DE APLICATIVOS',
                style: TextStyle(
                  color: _rose,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final app in const [
                    ('WhatsApp', Icons.chat_bubble_outline, 'whatsapp'),
                    ('YouTube', Icons.play_circle_outline, 'youtube'),
                    ('Chrome', Icons.public, 'chrome'),
                    ('Calculadora', Icons.calculate_outlined, 'calculadora'),
                    ('Mapas', Icons.map_outlined, 'maps'),
                    ('Telefone', Icons.phone_outlined, 'telefone'),
                    ('Ajustes', Icons.settings_outlined, 'configuracoes'),
                  ])
                    _StageChip(
                      label: app.$1,
                      icon: app.$2,
                      onTap: () async {
                        try {
                          await deviceService.openApp(app.$3);
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '$e',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          );
                        }
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => _setPanel(_ActivePanel.main),
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0xFF2B0307),
              foregroundColor: _crimson,
              side: BorderSide(color: _crimson.withValues(alpha: 0.35)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'VOLTAR AO NÚCLEO',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _activatePreset(FreeProviderPreset preset) async {
    HapticFeedback.mediumImpact();
    final providers = await providerStore.load();
    final existingIdx = providers.indexWhere(
      (p) => p.baseUrl.toLowerCase() == preset.baseUrl.toLowerCase(),
    );
    List<AiProviderConfig> updated;
    if (existingIdx >= 0) {
      final copy = [...providers];
      copy[existingIdx] = copy[existingIdx].copyWith(
        enabled: true,
        priority: 0,
      );
      for (var i = 0; i < copy.length; i++) {
        if (i != existingIdx) {
          copy[i] = copy[i].copyWith(priority: copy[i].priority + 1);
        }
      }
      updated = copy;
    } else {
      final newConfig = AiProviderConfig(
        id: 'prov_${DateTime.now().millisecondsSinceEpoch}',
        name: preset.name,
        baseUrl: preset.baseUrl,
        model: preset.defaultModel,
        apiKey: preset.requiresKey ? '' : 'free',
        enabled: true,
        priority: 0,
      );
      updated = [newConfig, ...providers];
    }
    await providerStore.save(updated);
    if (!mounted) return;
    setState(() => activeProviderUsed = preset.name);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '⚡ Provedor ativado: ${preset.name}',
          style: const TextStyle(fontSize: 11),
        ),
        backgroundColor: const Color(0xFF2B0307),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildProvidersPanel() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _border)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: () => _setPanel(_ActivePanel.main),
                child: const Row(
                  children: [
                    Icon(Icons.arrow_back, size: 15, color: _crimson),
                    SizedBox(width: 4),
                    Text(
                      'VOLTAR',
                      style: TextStyle(
                        color: _crimson,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Row(
                children: [
                  Icon(
                    Icons.hub_outlined,
                    size: 15,
                    color: Colors.white,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'CENTRAL DE PROVEDORES DE IA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: _openSettings,
                child: const Icon(
                  Icons.settings,
                  size: 16,
                  color: _rose,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 10),
            children: [
              // Hero Banner - Zero-Key
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2B0307), Color(0xFF19171B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _crimson.withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: _crimson.withValues(alpha: 0.12),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF75020F),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFFF707C)),
                          ),
                          child: const Text(
                            'ZERO-KEY NATIVO',
                            style: TextStyle(
                              color: Color(0xFFFF707C),
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Text(
                          'USANDO: $activeProviderUsed',
                          style: const TextStyle(
                            color: _rose,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '9 Provedores Gratuitos com Failover Automático. Toque em qualquer satélite abaixo para ativar ou alternar.',
                      style: TextStyle(
                        color: Color(0xFFF0E6E7),
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'SATÉLITES & PROVEDORES CONECTADOS (9 OPÇÕES)',
                style: TextStyle(
                  color: _crimson,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              // Grid of 9 providers
              for (final preset in FreeProviderPreset.catalog)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF19171B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: activeProviderUsed
                              .contains(preset.name.split(' ').first)
                          ? _crimson
                          : _border,
                      width: activeProviderUsed
                              .contains(preset.name.split(' ').first)
                          ? 1.3
                          : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  preset.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: preset.requiresKey
                                        ? const Color(0xFF2B0307)
                                        : const Color(0xFF75020F),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    preset.badge,
                                    style: TextStyle(
                                      color: preset.requiresKey
                                          ? _rose
                                          : const Color(0xFFFF707C),
                                      fontSize: 7.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Modelos: ${preset.recommendedModels.take(2).join(', ')}',
                              style: const TextStyle(
                                color: Color(0xFFA89698),
                                fontSize: 8.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => _activatePreset(preset),
                        style: FilledButton.styleFrom(
                          backgroundColor: _crimson,
                          foregroundColor: const Color(0xFFF0E6E7),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: const Text(
                          'ATIVAR',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openSettings,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _rose,
                    side: const BorderSide(color: _border),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.tune, size: 14),
                  label: const Text(
                    'CONFIGURAR CHAVES DE API DETALHADAS (/settings)',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHelpPanel() => Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  onTap: () => _setPanel(_ActivePanel.main),
                  child: const Row(
                    children: [
                      Icon(Icons.arrow_back, size: 15, color: _crimson),
                      SizedBox(width: 4),
                      Text(
                        'VOLTAR',
                        style: TextStyle(
                          color: _crimson,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Row(
                  children: [
                    Icon(Icons.help_outline, size: 15, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      'SINTAXE DE COMANDOS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 10),
              children: const [
                Text(
                  'Comandos rápidos e controles do celular (funcionam offline e pela IA):',
                  style: TextStyle(
                    color: Color(0xFFA89698),
                    fontSize: 10,
                  ),
                ),
                SizedBox(height: 8),
                _HelpSyntaxItem(
                  cmd: '/note <texto> | anote: <texto>',
                  desc:
                      'Salva uma nota rápida com horário em Diario/AAAA-MM-DD.md (Obsidian Vault).',
                  highlight: true,
                ),
                _HelpSyntaxItem(
                  cmd: '/skill <nome> | /skills | ativar modo estudo',
                  desc:
                      'Executa ou lista as rotinas locais em Markdown (modo_estudo, foco_noturno, alerta_tatico).',
                  highlight: true,
                ),
                _HelpSyntaxItem(
                  cmd: '/killswitch | travar pc',
                  desc:
                      'Dispara pacote HMAC-SHA256 de bloqueio remoto para o PC e trava a sessão mobile.',
                  highlight: true,
                ),
                _HelpSyntaxItem(
                  cmd: '/device | /lanterna | ligar lanterna',
                  desc:
                      'Abre o painel de controle do celular ou liga/desliga o flash LED traseiro.',
                  highlight: false,
                ),
                _HelpSyntaxItem(
                  cmd: 'volume 80 | aumentar volume | silenciar',
                  desc:
                      'Controla o volume de mídia do Android de 0% a 100%.',
                  highlight: false,
                ),
                _HelpSyntaxItem(
                  cmd: 'abrir whatsapp | abrir câmera | abrir wifi',
                  desc:
                      'Inicia qualquer aplicativo instalado ou painel do Android.',
                  highlight: false,
                ),
                _HelpSyntaxItem(
                  cmd: 'alarme 07:30 | timer 5 minutos | bateria',
                  desc:
                      'Cria alarmes/timers no relógio do sistema ou lê telemetria real.',
                  highlight: false,
                ),
                _HelpSyntaxItem(
                  cmd: '/security | /security lock | /settings | /history',
                  desc:
                      'Configura Duress PIN (Modo Coação), Kill Switch, provedores de IA e histórico.',
                  highlight: true,
                ),
                _HelpSyntaxItem(
                  cmd: 'Flip-to-Shush (Gesto Físico)',
                  desc:
                      'Vire o celular com a tela para baixo na mesa para calar a voz do núcleo imediatamente.',
                  highlight: false,
                ),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _setPanel(_ActivePanel.main),
              style: OutlinedButton.styleFrom(
                backgroundColor: const Color(0xFF2B0307),
                foregroundColor: _crimson,
                side: BorderSide(color: _crimson.withValues(alpha: 0.35)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'ENTENDIDO, VOLTAR AO NÚCLEO',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      );
}

class _TopNavPill extends StatelessWidget {
  const _TopNavPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF75020F) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? const Color(0xFFF0E6E7) : const Color(0xFFA89698),
              fontSize: 10,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      );
}

class _StageChip extends StatelessWidget {
  const _StageChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF2B0307),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF51080D)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: const Color(0xFFFF707C)),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFF0E6E7),
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
}

class _QuickCommandCard extends StatelessWidget {
  const _QuickCommandCard({
    required this.command,
    required this.description,
    required this.onTap,
  });

  final String command;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF2B0307),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF51080D)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                command,
                style: const TextStyle(
                  color: Color(0xFFFF707C),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(
                  color: Color(0xFFA89698),
                  fontSize: 9,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
}

class _TelemetryBox extends StatelessWidget {
  const _TelemetryBox({
    required this.title,
    required this.titleColor,
    required this.body,
  });

  final String title;
  final Color titleColor;
  final String body;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF2B0307),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF51080D)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: titleColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              style: const TextStyle(
                color: Color(0xFFF0E6E7),
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
}

class _SecurityRow extends StatelessWidget {
  const _SecurityRow({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFA89698),
              fontSize: 10,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
}

class _HelpSyntaxItem extends StatelessWidget {
  const _HelpSyntaxItem({
    required this.cmd,
    required this.desc,
    required this.highlight,
  });

  final String cmd;
  final String desc;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF2B0307),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF51080D)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cmd,
              style: TextStyle(
                color: highlight
                    ? const Color(0xFFFF707C)
                    : const Color(0xFFF0E6E7),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              desc,
              style: const TextStyle(
                color: Color(0xFFA89698),
                fontSize: 10,
              ),
            ),
          ],
        ),
      );
}

/// 4-layer Orbital Crimson Core ported from `UltronCoreCanvas` in `ultron_mobile_interface.tsx`.
class CorePainter extends CustomPainter {
  CorePainter(this.time, {this.intensity = 1.0});

  final double time;
  final double intensity;

  static const _auraGradient = RadialGradient(
    colors: [
      Color(0x5975020F),
      Color(0x2E51080D),
      Color(0x142B0307),
      Color(0x0019171B),
    ],
    stops: [0.0, 0.35, 0.70, 1.0],
  );

  static const _hotspotGradient = RadialGradient(
    colors: [
      Color(0xFFF0E6E7),
      Color(0xFFFF707C),
      Color(0xFF75020F),
      Color(0x0075020F),
    ],
    stops: [0.0, 0.28, 0.70, 1.0],
  );

  static final _ring1Paint = Paint()
    ..color = const Color(0xBF75020F)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.8;

  static final _nodePaint = Paint()..color = const Color(0xFFFF707C);

  static final _ring2Paint = Paint()
    ..color = const Color(0x8051080D)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.3;

  static final _majorTickPaint = Paint()..color = const Color(0xFF75020F);
  static final _minorTickPaint = Paint()..color = const Color(0x5951080D);

  static final _hexPaint = Paint()
    ..color = const Color(0xBF75020F)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.shortestSide;
    final center = size.center(Offset.zero);

    final angle1 = time * 0.96 * intensity;
    final angle2 = -time * 1.32 * intensity;
    final pulse = time * 2.4 * intensity;

    final dynamicPulse = 1.0 + sin(pulse) * 0.07;
    final baseR = (w * 0.23) * dynamicPulse;

    // 1. Deep Crimson Radial Aura
    final auraRadius = baseR * 1.95;
    final auraRect = Rect.fromCircle(center: center, radius: auraRadius);
    final auraPaint = Paint()..shader = _auraGradient.createShader(auraRect);
    canvas.drawCircle(center, auraRadius, auraPaint);

    canvas.save();
    canvas.translate(center.dx, center.dy);

    // 2A. Primary Elliptical Orbital Ring + 4 Orbital Nodes
    canvas.save();
    canvas.rotate(0.38 + angle1);
    final ring1Rect = Rect.fromCenter(
      center: Offset.zero,
      width: baseR * 1.55 * 2,
      height: baseR * 0.82 * 2,
    );
    canvas.drawOval(ring1Rect, _ring1Paint);

    for (var i = 0; i < 4; i++) {
      final th = i * pi / 2;
      final px = cos(th) * baseR * 1.55;
      final py = sin(th) * baseR * 0.82;
      canvas.drawCircle(Offset(px, py), 2.5, _nodePaint);
    }
    canvas.restore();

    // 2B. Secondary Counter-Rotating Ring + 16 Ticks
    canvas.save();
    canvas.rotate(-0.45 + angle2);
    final ring2Rect = Rect.fromCenter(
      center: Offset.zero,
      width: baseR * 1.15 * 2,
      height: baseR * 1.48 * 2,
    );
    canvas.drawOval(ring2Rect, _ring2Paint);

    const ticks = 16;
    for (var t = 0; t < ticks; t++) {
      final theta = (t / ticks) * pi * 2;
      final tx = cos(theta) * baseR * 1.15;
      final ty = sin(theta) * baseR * 1.48;
      final isMajor = t % 4 == 0;
      canvas.drawCircle(
        Offset(tx, ty),
        isMajor ? 2.0 : 1.0,
        isMajor ? _majorTickPaint : _minorTickPaint,
      );
    }
    canvas.restore();

    // 3. Hexagonal Wireframe Structure
    canvas.save();
    canvas.rotate(-angle1 * 0.7);
    final hexPath = Path();
    const poly = 6;
    final rSub = baseR * 0.65;
    for (var p = 0; p <= poly; p++) {
      final pa = (p / poly) * pi * 2;
      final rx = cos(pa) * rSub;
      final ry = sin(pa) * rSub;
      if (p == 0) {
        hexPath.moveTo(rx, ry);
      } else {
        hexPath.lineTo(rx, ry);
      }
    }
    hexPath.close();
    canvas.drawPath(hexPath, _hexPaint);
    canvas.restore();

    // 4. Central Hyper-Bright Singularity Hotspot
    final hotspotRadius = baseR * 0.38;
    final hotspotRect = Rect.fromCircle(
      center: Offset.zero,
      radius: hotspotRadius,
    );
    final hotspotPaint = Paint()
      ..shader = _hotspotGradient.createShader(hotspotRect);
    canvas.drawCircle(Offset.zero, hotspotRadius, hotspotPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CorePainter oldDelegate) =>
      oldDelegate.time != time || oldDelegate.intensity != intensity;
}

class _CircularTelemetryGauge extends StatelessWidget {
  const _CircularTelemetryGauge({
    required this.value,
    required this.label,
    required this.subLabel,
    required this.percentage,
    required this.color,
  });

  final String value;
  final String label;
  final String subLabel;
  final double percentage;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2B0307),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF51080D)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const CircularProgressIndicator(
                  value: 1.0,
                  strokeWidth: 4.5,
                  color: Color(0xFF51080D),
                ),
                CircularProgressIndicator(
                  value: percentage.clamp(0.0, 1.0),
                  strokeWidth: 4.5,
                  strokeCap: StrokeCap.round,
                  color: color,
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFA89698),
              fontSize: 8.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          Text(
            subLabel,
            style: TextStyle(
              color: color,
              fontSize: 8,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
