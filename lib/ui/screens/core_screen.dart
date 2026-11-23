import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/security/action_gate.dart';
import '../../core/security/auth_gate.dart';
import '../../core/security/pin_vault.dart';
import '../../models/chat_message.dart';
import '../../models/tactical_mode.dart';
import '../../services/ai_provider_service.dart';
import '../../services/android_actions_service.dart';
import '../../services/app_update_service.dart';
import '../../services/audio_capture_service.dart';
import '../../services/audio_vad_buffer.dart';
import '../../services/audit_log_service.dart';
import '../../services/briefing_service.dart';
import '../../services/cognicao_service.dart';
import '../../services/conversation_history.dart';
import '../../services/desktop_command_listener.dart';
import '../../services/desktop_pairing_service.dart';
import '../../services/device_control_service.dart';
import '../../services/nfc_auth_service.dart';
import '../../services/obsidian_service.dart';
import '../../services/reminder_service.dart';
import '../../services/slash_command_parser.dart';
import '../../services/speech_text.dart';
import '../../services/stt_service.dart';
import '../../services/voice_corrections_service.dart';
import '../../services/voice_pipeline_controller.dart';
import '../../services/voice_service.dart';
import '../../services/voice_shortcuts_service.dart';
import '../widgets/action_confirmation_dialog.dart';
import '../widgets/core_orb.dart' show CoreOrb, CoreStage;
import '../widgets/voice_selector_sheet.dart';
import 'ai_settings_screen.dart';
import 'conversation_history_screen.dart';
import 'desktop_pairing_screen.dart';
import 'memory_settings_screen.dart';
import 'update_screen.dart';

export '../widgets/core_orb.dart' show CoreStage;

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
  const CoreScreen({
    super.key,
    required this.gate,
    required this.vault,
    this.voiceService,
    this.captureSource,
    this.sttService,
    this.shaderProgram,
    this.announceOnline = false,
    this.onlineAnnouncement = 'Ultron online. Todos os sistemas prontos.',
  });

  final AuthGate gate;
  final PinVault vault;
  final VoiceService? voiceService;
  final AudioCaptureSource? captureSource;
  final GroqWhisperSttService? sttService;
  final FragmentProgram? shaderProgram;
  final bool announceOnline;
  final String onlineAnnouncement;

  @override
  State<CoreScreen> createState() => _CoreScreenState();
}

class _CoreScreenState extends State<CoreScreen> with WidgetsBindingObserver {
  static const _crimson = Color(0xFFE50914);
  static const _rose = Color(0xFFFFA0A0);
  static const _border = Color(0xFF51080D);

  final commandController = TextEditingController();
  final quickNoteController = TextEditingController();
  final duressPinController = TextEditingController();
  final pcKillSwitchUrlController = TextEditingController();
  final pcLanSecretController = TextEditingController();
  final messageTargetController = TextEditingController();
  final messageBodyController = TextEditingController();
  final scrollController = ScrollController();
  late final VoiceService voiceService = widget.voiceService ?? VoiceService();
  final updateService = AppUpdateService();
  final providerStore = AiProviderStore();
  late final DeviceControlService deviceService = DeviceControlService(
    authGate: widget.gate,
    onRequestElevation: _elevateSessionTo,
  );
  late final briefingService = BriefingService(deviceService: deviceService);
  final cognicaoService = const CognicaoService();
  final actionGate = const ActionGate();
  late final VoicePipelineController voicePipeline;
  late final AndroidActionsService androidActions;
  final desktopPairing = DesktopPairingService();
  late final DesktopCommandListener desktopCommandListener;
  late AppLifecycleState _lifecycleState;

  bool get _isForegroundActive =>
      _lifecycleState == AppLifecycleState.resumed &&
      widget.gate.isAuthenticated;

  CoreStage stage = CoreStage.center;
  _ActivePanel panel = _ActivePanel.main;
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
  SessionTelemetry sessionTelemetry = SessionTelemetry.initial();
  TacticalMode activeTacticalMode = TacticalMode.geral;
  bool pcLanConfigured = false;
  String installedVersion = 'v1.5.0';
  int authFailures = 0;
  bool? hasPinConfigured;
  bool hasDuressPinConfigured = false;
  NfcHardwareStatus nfcStatus = const NfcHardwareStatus(
    available: false,
    enabled: false,
  );
  List<NfcTagEntry> nfcTags = const [];
  String? _lastShownPipelineError;
  Future<void>? _pendingBgSync;
  List<MobileSkill> mobileSkills = const [];
  List<CapturedNotification> recentMessages = const [];
  VisionAttachment? pendingVisionImage;
  VisionAttachment? lastSessionVisionImage;
  String? lastSessionVisionSummary;

  static const _defaultFeed = <_FeedEntry>[
    _FeedEntry(
      isUser: false,
      senderLabel: 'Kernel Local',
      text:
          'U.L.T.R.O.N. Mobile v1.5.0 online. Wake Word KWS Multi-Perfil (Ultron/Jarvis/Edith/Visão), Orbe Flutuante Android, Obsidian CRUD + Undo, Fluxos Agendados, Spotify OAuth PKCE, Ponte LAN Desktop v3.0.0 e Utilitários SAF prontos para comando!',
      timestamp: 'ONLINE',
    ),
  ];

  List<_FeedEntry> feed = _defaultFeed;

  @override
  void initState() {
    super.initState();
    _lifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    androidActions = AndroidActionsService(gate: widget.gate);
    voicePipeline = VoicePipelineController(
      gate: widget.gate,
      capture: widget.captureSource ?? MethodChannelAudioCaptureSource(),
      stt: widget.sttService ?? GroqWhisperSttService(),
      voiceService: voiceService,
      vadSegmenter: VadSegmenter(
        sampleRate: 16000,
        silenceHangover: const Duration(milliseconds: 500),
      ),
      corrections: VoiceCorrectionsService(),
      shortcuts: VoiceShortcutsService(),
      onConfirmShortcut: _confirmShortcut,
      onExecuteShortcut: _executeShortcut,
      onTranscript: _handleVoiceTranscript,
      onRmsChanged: (rms) {
        if (!mounted) return;
        setState(() => speechRms = rms);
      },
    )..addListener(_onVoicePipelineChanged);
    voicePipeline.handleLifecycleState(_lifecycleState);
    unawaited(voiceService.initialize().catchError((_) {}));
    unawaited(
      ReminderService.instance()
          .then((s) => s.reschedulePendingAlarms())
          .catchError((_) => 0),
    );
    if (widget.announceOnline && _isForegroundActive) {
      unawaited(
        voiceService.speak(widget.onlineAnnouncement).catchError((_) {}),
      );
    }
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
      onBackgroundTurn: () => unawaited(_syncPendingBackgroundTurns()),
      onPairingUriReceived: (uri) =>
          unawaited(_handleIncomingPairingUri(uri)),
      onWorkflowTriggered: (_) => unawaited(_consumePendingWorkflows()),
      onSpotifyCallbackReceived: (uri) =>
          unawaited(_handleIncomingSpotifyCallbackUri(uri)),
      onFloatingOrbTapped: (requiresUnlock) =>
          unawaited(_handleFloatingOrbTap(requiresUnlock)),
    );
    desktopCommandListener = DesktopCommandListener(
      pairingService: desktopPairing,
      deviceService: deviceService,
      authGate: widget.gate,
      actionGate: actionGate,
      confirmAction: (sim) {
        if (!mounted || !_isForegroundActive) return Future.value(false);
        return _confirmActionSimulation(sim);
      },
      onCommandHandled: (res) {
        if (!mounted) return;
        final now = DateTime.now();
        final timeStr =
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
        _appendFeed(_FeedEntry(
          isUser: false,
          senderLabel: 'Desktop → Celular (${res.command})',
          text: res.message,
          timestamp: timeStr,
        ));
      },
    );
    widget.gate.addListener(_onAuthGateChanged);
    _syncDesktopListenerState();
    _syncFloatingOrbAuthState();
    _loadInitialState();
    _checkUpdate();
    // v1.2.1: wake word captada com o app fechado/bloqueado fica pendente no nativo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumePendingWakeWord();
      unawaited(_consumePendingFloatingOrbTap());
      unawaited(_consumePendingTileAction());
      unawaited(_consumePendingPairingUri());
      unawaited(_consumePendingNfcUnlock());
      unawaited(_consumePendingWorkflows());
      unawaited(_consumePendingSpotifyCallbackUri());
    });
  }

  void _syncFloatingOrbAuthState() {
    unawaited(
      deviceService.syncFloatingOrbAuthState(
        locked: !widget.gate.isAuthenticated,
        accessLevel: widget.gate.level.name,
      ),
    );
  }

  Future<void> _consumePendingFloatingOrbTap() async {
    try {
      final pending = await deviceService.consumePendingFloatingOrbTap();
      if (pending != null && pending.triggered) {
        await _handleFloatingOrbTap(pending.requiresUnlock);
      }
    } catch (_) {}
  }

  Future<void> _handleFloatingOrbTap(bool requiresUnlock) async {
    if (!mounted) return;
    if (requiresUnlock || !widget.gate.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '🔒 Sessão bloqueada no AuthGate. Desbloqueie ou eleve a sessão para executar comandos pelo Orbe Flutuante.',
            style: TextStyle(fontSize: 11),
          ),
          duration: Duration(seconds: 3),
        ),
      );
      if (widget.gate.isAuthenticated &&
          !widget.gate.satisfies(AccessLevel.elevated)) {
        final elevated = await _elevateSessionTo(
          AccessLevel.elevated,
          'O Orbe Flutuante solicitou elevação de sessão para ações sensíveis.',
        );
        if (!elevated || !mounted) return;
      } else if (!widget.gate.isAuthenticated) {
        return;
      }
    }
    if (sending) return;
    if (voiceService.isSpeaking) {
      await voiceService.stop();
      return;
    }
    await _startVoiceInput();
  }

  Future<void> _consumePendingSpotifyCallbackUri() async {
    try {
      final uri = await deviceService.consumePendingSpotifyCallbackUri();
      if (uri != null && uri.isNotEmpty) {
        await _handleIncomingSpotifyCallbackUri(uri);
      }
    } catch (_) {}
  }

  Future<void> _handleIncomingSpotifyCallbackUri(String rawUri) async {
    if (!mounted) return;
    try {
      await deviceService
          .getSpotifyService()
          .handleAuthorizationCallbackUri(rawUri);
      if (!mounted) return;
      final now = DateTime.now();
      _appendFeed(_FeedEntry(
        isUser: false,
        senderLabel: 'Spotify OAuth 2.0 PKCE',
        text:
            '✅ Conta Spotify conectada com sucesso via OAuth 2.0 PKCE! Use `/spotify estado` ou `"tocar <música> no spotify"`.',
        timestamp: _formatTime(now),
      ));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎵 Spotify conectado com sucesso via PKCE!'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _appendFeed(_FeedEntry(
        isUser: false,
        senderLabel: 'Spotify OAuth 2.0 PKCE',
        text: '⚠️ Falha no callback OAuth do Spotify: $e',
        timestamp: _formatTime(DateTime.now()),
      ));
    }
  }

  Future<void> _consumePendingWorkflows() async {
    try {
      final ids = await deviceService.consumePendingWorkflowIds();
      for (final id in ids) {
        final res = await deviceService.runWorkflow(
          '$id',
          isBackgroundTrigger: true,
        );
        if (!mounted) return;
        _appendFeed(_FeedEntry(
          isUser: false,
          senderLabel: 'Workflow Scheduler',
          text: res.message,
          timestamp: _formatTime(DateTime.now()),
        ));
      }
    } catch (_) {}
  }

  Future<void> _consumePendingNfcUnlock() async {
    try {
      final uid = await NfcAuthService.instance.consumePendingUnlockUid();
      if (uid == null || uid.isEmpty || !mounted) return;
      final ok = await widget.gate.authenticateNfc(
        uid,
        widget.vault.verifyNfcTag,
      );
      if (ok && mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🔑 Sessão elevada por NFC (${widget.gate.levelBadge})!'),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _consumePendingPairingUri() async {
    try {
      final uri = await deviceService.consumePendingPairingUri();
      if (uri != null && uri.isNotEmpty) {
        await _handleIncomingPairingUri(uri);
      }
    } catch (_) {}
  }

  Future<void> _handleIncomingPairingUri(String rawUri) async {
    if (!mounted) return;
    try {
      final parsed = DesktopPairingService.parsePairingUri(rawUri);
      final allowed = await showActionConfirmationDialog(
        context,
        ActionConfirmationRequest(
          title: 'Parear com U.L.T.R.O.N. Desktop?',
          description:
              'URL LAN: ${parsed.config.baseUrl}\nDispositivo: ${parsed.config.deviceId}\n'
              '${parsed.syncKillSwitch ? 'Também sincronizará o Kill Switch LAN.' : ''}',
          actionLabel: 'Parear agora',
          danger: false,
        ),
      );
      if (!allowed || !mounted) return;
      final config = await desktopPairing.pairFromUri(
        rawUri,
        onConfigureKillSwitch: (baseUrl, secret,
            {bool allowNonPrivateHost = false}) async {
          await deviceService.savePcKillSwitchUrl(
            baseUrl,
            allowNonPrivateHost: allowNonPrivateHost,
          );
          await deviceService.savePcLanSecret(secret);
        },
      );
      if (!mounted) return;
      desktopCommandListener.wakeUp();
      final now = DateTime.now();
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      _appendFeed(_FeedEntry(
        isUser: false,
        senderLabel: 'Bridge Desktop LAN',
        text: '✅ Desktop pareado com sucesso!\n'
            '• URL: ${config.baseUrl}\n'
            '• Dispositivo: ${config.deviceId}\n'
            'Use `/pc status` para testar a conexão.',
        timestamp: timeStr,
      ));
    } catch (e) {
      if (!mounted) return;
      final now = DateTime.now();
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      _appendFeed(_FeedEntry(
        isUser: false,
        senderLabel: 'Bridge Desktop LAN',
        text: '⚠️ Link de pareamento inválido: $e',
        timestamp: timeStr,
      ));
    }
  }

  Future<bool> _consumePendingTileAction() async {
    try {
      final action = await androidActions.consumeTileActionIfAuthenticated();
      if (!mounted || !_isForegroundActive) return false;
      if (action == TileLaunchAction.listenVoice) {
        await voiceService.stop();
        await voicePipeline.startPushToTalk();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void _onVoicePipelineChanged() {
    if (!mounted) return;
    final capturing =
        voicePipeline.isSingleTurnActive || voicePipeline.isPushToTalkActive;
    final err = voicePipeline.lastError;
    if (err != null && err != _lastShownPipelineError) {
      _lastShownPipelineError = err;
      final friendly = err == 'sem_chave_stt'
          ? 'Configure uma chave STT (Groq gratuito ou Whisper compatível) em Config IA para transcrever o microfone do celular.'
          : err;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendly, style: const TextStyle(fontSize: 11)),
          duration: const Duration(seconds: 3),
        ),
      );
    } else if (err == null) {
      _lastShownPipelineError = null;
    }
    setState(() {
      listeningVoice = capturing;
      if (!capturing) {
        speechRms = 0.0;
      }
    });
    final orbState = capturing
        ? 'ouvindo'
        : (voicePipeline.isTranscribing || sending)
            ? 'processando'
            : voiceService.isSpeaking
                ? 'falando'
                : 'ocioso';
    unawaited(deviceService.updateFloatingOrbState(orbState));
  }

  Future<void> _handleVoiceTranscript(String transcript) async {
    if (!mounted || sending) return;
    commandController.text = transcript;
    await saveCommand();
  }

  Future<bool> _confirmShortcut(VoiceShortcut shortcut) async {
    if (!mounted) return false;
    return showActionConfirmationDialog(
      context,
      ActionConfirmationRequest(
        title: 'Confirmar atalho de voz',
        description:
            'Executar "${shortcut.triggerPhrase}" (${shortcut.actionType})?',
        actionLabel: 'Confirmar',
      ),
    );
  }

  Future<void> _executeShortcut(VoiceShortcut shortcut) async {
    if (!mounted) return;
    switch (shortcut.actionType) {
      case 'open_security':
        await _runCommand(UltronCommand.security);
        break;
      case 'open_history':
        await _runCommand(UltronCommand.history);
        break;
      case 'open_memory':
        await _runCommand(UltronCommand.memory);
        break;
      case 'open_settings':
        await _runCommand(UltronCommand.settings);
        break;
      case 'lock_app':
        widget.gate.lock();
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Atalho acionado: ${shortcut.triggerPhrase}')),
        );
    }
  }

  /// Processa uma ativação por "Ultron" (ao vivo ou pendente do segundo plano).
  Future<void> _handleWakeWord(String phrase) async {
    if (!mounted || sending || listeningVoice || !_isForegroundActive) {
      return;
    }
    if (voiceService.isSpeaking) {
      await voiceService.stop();
    }
    HapticFeedback.heavyImpact();
    final inlineCmd = WakeWord.extractCommand(phrase);
    if (inlineCmd.length >= 2) {
      commandController.text = inlineCmd;
      await saveCommand();
      return;
    }
    if (!mounted) return;
    final detectedProfile =
        WakeWord.detectProfile(phrase) ?? voiceService.wakeWordProfile;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '🎙️ "${detectedProfile.label}" detectado! Escutando seu comando…',
          style: const TextStyle(fontSize: 11),
        ),
        duration: const Duration(seconds: 2),
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
          if (!diag.overlayPermission)
            TextButton(
              onPressed: () async {
                await deviceService.requestOverlayPermission();
              },
              child: const Text('SOBREPOR APPS'),
            ),
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

  Future<void> _syncPendingBackgroundTurns({bool persistOnly = false}) {
    final prev = _pendingBgSync;
    final current = () async {
      if (prev != null) {
        try {
          await prev;
        } catch (_) {}
      }
      await _performBackgroundTurnSync(persistOnly: persistOnly);
    }();
    _pendingBgSync = current;
    return current;
  }

  Future<void> _performBackgroundTurnSync({required bool persistOnly}) async {
    try {
      final turns = await deviceService.consumePendingBackgroundTurns();
      if (turns.isEmpty) return;

      final entries = <_FeedEntry>[];
      for (final turn in turns) {
        await ConversationHistory.instance.save(
          ChatMessage(
            id: null,
            conversationId: 'default',
            role: ChatRole.user,
            content: turn.userText,
            createdAt: turn.userTimestamp,
          ),
        );
        await ConversationHistory.instance.save(
          ChatMessage(
            id: null,
            conversationId: 'default',
            role: ChatRole.assistant,
            content: turn.assistantText,
            createdAt: turn.replyTimestamp,
          ),
        );
        entries.add(
          _FeedEntry(
            isUser: true,
            senderLabel: 'OPERADOR',
            text: turn.userText,
            timestamp: _formatTime(turn.userTimestamp.toLocal()),
          ),
        );
        entries.add(
          _FeedEntry(
            isUser: false,
            senderLabel: turn.senderLabel,
            text: turn.assistantText,
            timestamp: _formatTime(turn.replyTimestamp.toLocal()),
          ),
        );
      }

      if (!persistOnly && mounted && entries.isNotEmpty) {
        setState(() {
          feed = [...feed, ...entries];
        });
        _scrollToBottom();
        unawaited(_refreshDeviceStatus());
      }
    } catch (_) {}
  }

  Future<void> _loadInitialState() async {
    try {
      await _syncPendingBackgroundTurns(persistOnly: true);
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
      final storedNfcTags = await widget.vault.listNfcTags();
      final hwNfc = await NfcAuthService.instance.getStatus();
      final killUrl = await deviceService.loadPcKillSwitchUrl();
      final lanSecret = await deviceService.loadPcLanSecret();
      final desktopCfg = await desktopPairing.loadPairing();
      List<MobileSkill> loadedSkills = const [];
      try {
        final obsidian = await ObsidianService.openDefaultVault();
        loadedSkills = await obsidian.listSkills();
      } catch (_) {}
      DeviceStatus? hwStatus;
      bool notifEnabled = false;
      List<CapturedNotification> loadedMsgs = const [];
      try {
        hwStatus = await deviceService.getStatus();
        notifEnabled = await deviceService.isNotificationListenerEnabled();
        if (notifEnabled) {
          loadedMsgs = await deviceService.getRecentMessages(limit: 12);
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        authFailures = failures;
        hasPinConfigured = pinSet;
        hasDuressPinConfigured = duressSet;
        nfcTags = storedNfcTags;
        nfcStatus = hwNfc;
        notificationSentinelEnabled = notifEnabled;
        selectedVoiceProfile = voiceService.profile;
        recentMessages = loadedMsgs;
        if (killUrl.isNotEmpty && pcKillSwitchUrlController.text.isEmpty) {
          pcKillSwitchUrlController.text = killUrl;
        }
        if (lanSecret.isNotEmpty && pcLanSecretController.text.isEmpty) {
          pcLanSecretController.text = lanSecret;
        }
        pcLanConfigured = desktopCfg != null || lanSecret.isNotEmpty;
        mobileSkills = loadedSkills;
        if (hwStatus != null) {
          deviceStatus = hwStatus;
          torchOn = hwStatus.torchOn;
        }
        activeProviderUsed = enabledProviders.isNotEmpty
            ? '${enabledProviders.first.name} (${enabledProviders.first.model})'
            : 'Failover Pronto';
        sessionTelemetry = sessionTelemetry.withActiveProvider(
          enabledProviders.isNotEmpty
              ? enabledProviders.first.name
              : 'Failover Pronto',
        );
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
      unawaited(_syncBackgroundVoiceConfig(enabledProviders: enabledProviders));
    } catch (_) {}
  }

  Future<void> _syncBackgroundVoiceConfig({
    List<AiProviderConfig>? enabledProviders,
  }) async {
    try {
      await voiceService.initialize();
      final providers = enabledProviders ??
          ((await providerStore.load()).where((p) => p.enabled).toList()
            ..sort((a, b) => a.priority.compareTo(b.priority)));
      final sttCfg = await providerStore.resolveSttConfig();
      final primaryAi = providers.isNotEmpty
          ? providers.first
          : const AiProviderConfig(
              id: 'pollinations_free',
              name: 'Pollinations',
              baseUrl: 'https://text.pollinations.ai/openai',
              model: 'openai',
              apiKey: '',
              enabled: true,
              priority: 0,
            );
      final fish = voiceService.fishConfig;
      final recentPairs = <Map<String, String>>[];
      for (var i = 0; i + 1 < feed.length; i++) {
        if (feed[i].isUser && !feed[i + 1].isUser) {
          recentPairs.add(<String, String>{
            'userText': feed[i].text,
            'assistantText': feed[i + 1].text,
          });
        }
      }
      final trimmedPairs = recentPairs.length > 6
          ? recentPairs.sublist(recentPairs.length - 6)
          : recentPairs;
      await deviceService.syncBackgroundVoiceConfig(
        sttUrl: sttCfg.endpointUrl,
        sttKey: sttCfg.apiKey,
        sttModel: sttCfg.model,
        sttLanguage: sttCfg.language,
        aiBaseUrl: primaryAi.baseUrl,
        aiKey: primaryAi.apiKey,
        aiModel: primaryAi.model,
        fishEnabled: fish.enabled,
        fishKey: fish.apiKey,
        fishRefId: fish.referenceId,
        fishLanguage: fish.language,
        fishModel: fish.model,
        whisperMode: nightFocusMode,
        wakeWordProfile: voiceService.wakeWordProfile.id,
        recentHistory: trimmedPairs.isEmpty ? null : trimmedPairs,
      );
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
    unawaited(_syncBackgroundVoiceConfig());
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
        .map((m) =>
            '[${m.timeFormatted}] ${m.appLabel} - ${m.sender}: ${m.text}')
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
        backgroundColor: const Color(0xFF2E0305),
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
          content: Text('Erro ao responder: $e',
              style: const TextStyle(fontSize: 11)),
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
    final actionCode = viaSms ? 'SMS' : 'WHATSAPP';
    final sim = actionGate.simulate(
      '$actionCode:${target.isEmpty ? 'contato' : target}:$body',
    );
    final approved = await _confirmActionSimulation(sim);
    if (!approved) {
      await deviceService.recordAudit(
        actor: 'OPERATOR',
        action: actionCode,
        target: sim.targetResource,
        status: 'DENIED',
        detail: 'Cancelado pelo Operador no Action Gate (painel Celular)',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '🚫 Envio cancelado pelo Operador.',
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
      await deviceService.recordAudit(
        actor: 'OPERATOR',
        action: actionCode,
        target: sim.targetResource,
        status: 'EXECUTED',
        detail: res,
      );
      messageBodyController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res, style: const TextStyle(fontSize: 11)),
        ),
      );
    } catch (e) {
      await deviceService.recordAudit(
        actor: 'OPERATOR',
        action: actionCode,
        target: sim.targetResource,
        status: 'FAILED',
        detail: '$e',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Falha no envio: $e', style: const TextStyle(fontSize: 11)),
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
          content: Text('Falha na lanterna: $e',
              style: const TextStyle(fontSize: 11)),
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

  void _onAuthGateChanged() {
    _syncDesktopListenerState();
    _syncFloatingOrbAuthState();
    if (mounted) {
      setState(() {});
    }
  }

  void _syncDesktopListenerState() {
    if (widget.gate.hasBiometricAccess) {
      desktopCommandListener.start();
    } else {
      desktopCommandListener.stop();
    }
  }

  Future<bool> _elevateSessionTo(
    AccessLevel requiredLevel,
    String reason,
  ) async {
    if (widget.gate.satisfies(requiredLevel)) return true;
    if (!mounted) return false;
    final hasNfcTags = await widget.vault.hasNfcKey;
    final hwNfc = await NfcAuthService.instance.getStatus();
    if (!mounted) return false;

    final allowNfc = requiredLevel == AccessLevel.elevated &&
        hasNfcTags &&
        hwNfc.available &&
        hwNfc.enabled;

    final upgraded = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        var readingStarted = false;
        var errorMsg = '';
        var checking = false;
        StreamSubscription<String>? sub;

        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            if (allowNfc && !readingStarted) {
              readingStarted = true;
              NfcAuthService.instance.startReader();
              sub = NfcAuthService.instance.tagStream.listen((uidHex) async {
                if (checking) return;
                setDialogState(() {
                  checking = true;
                  errorMsg = '';
                });
                final ok = await widget.gate.authenticateNfc(
                  uidHex,
                  widget.vault.verifyNfcTag,
                );
                if (ok && ctx.mounted) {
                  Navigator.of(ctx).pop(true);
                } else if (ctx.mounted) {
                  setDialogState(() {
                    checking = false;
                    errorMsg = 'Chave NFC não reconhecida.';
                  });
                }
              });
            }

            final targetLabel = requiredLevel == AccessLevel.sovereign
                ? 'NÍVEL 3 • BIOMETRIA'
                : 'NÍVEL 2 • NFC OU BIOMETRIA';

            return AlertDialog(
              backgroundColor: const Color(0xFF140204),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: _crimson.withValues(alpha: 0.5)),
              ),
              title: const Text(
                'Elevar Nível de Acesso',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sessão atual: ${widget.gate.levelBadge}\nExigido: $targetLabel',
                    style: const TextStyle(
                      color: _rose,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (reason.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      reason,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (allowNfc) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E0305),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _crimson.withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.nfc, color: _rose, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Encoste sua chave NFC nas costas do celular para liberar Nível 2.',
                              style: TextStyle(color: Colors.white, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (errorMsg.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorMsg,
                      style: const TextStyle(color: _crimson, fontSize: 11),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    sub?.cancel();
                    if (readingStarted) {
                      NfcAuthService.instance.stopReader();
                    }
                    Navigator.of(ctx).pop(false);
                  },
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: checking
                      ? null
                      : () async {
                          setDialogState(() {
                            checking = true;
                            errorMsg = '';
                          });
                          final ok =
                              await widget.gate.authenticateBiometric();
                          if (ok && ctx.mounted) {
                            sub?.cancel();
                            if (readingStarted) {
                              await NfcAuthService.instance.stopReader();
                            }
                            if (ctx.mounted) Navigator.of(ctx).pop(true);
                          } else if (ctx.mounted) {
                            setDialogState(() {
                              checking = false;
                              errorMsg = 'Biometria recusada ou indisponível.';
                            });
                          }
                        },
                  style: FilledButton.styleFrom(backgroundColor: _crimson),
                  icon: const Icon(Icons.fingerprint, size: 16),
                  label: const Text('Liberar c/ Biometria'),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      if (allowNfc) {
        unawaited(NfcAuthService.instance.stopReader());
      }
    });

    if (mounted) {
      setState(() {});
    }
    return upgraded == true && widget.gate.satisfies(requiredLevel);
  }

  Future<void> _openNfcEnrollmentWizard() async {
    final bioOk = await _elevateSessionTo(
      AccessLevel.sovereign,
      'Cadastrar uma chave física NFC exige Biometria do Dono (Nível 3).',
    );
    if (!bioOk || !mounted) return;

    final st = await NfcAuthService.instance.getStatus();
    if (!mounted) return;
    setState(() => nfcStatus = st);
    if (!st.available) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este aparelho não possui hardware NFC disponível.'),
        ),
      );
      return;
    }
    if (!st.enabled) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF140204),
          title: const Text('Ative o NFC no Android'),
          content: const Text(
            'O NFC do celular está desligado. Toque em "Abrir Ajustes NFC", ative a chave NFC e depois volte para cadastrar sua tag.',
            style: TextStyle(fontSize: 12),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Fechar'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await NfcAuthService.instance.openNfcSettings();
              },
              child: const Text('Abrir Ajustes NFC'),
            ),
          ],
        ),
      );
      return;
    }

    final labelCtrl = TextEditingController(text: 'Chave NFC');
    StreamSubscription<String>? sub;
    StreamSubscription<NfcWriteResult>? writeSub;
    var capturedUid = '';
    var writeShortcut = true;
    String? ndefStatus;
    var readerOn = false;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            if (!readerOn) {
              readerOn = true;
              NfcAuthService.instance.startReader(
                writeUnlockNdef: writeShortcut,
              );
              writeSub =
                  NfcAuthService.instance.writeResultStream.listen((res) {
                if (!ctx.mounted) return;
                setDialogState(() {
                  ndefStatus = res.written
                      ? 'Atalho ultron://unlock gravado na tag!'
                      : 'Tag cadastrada (sem gravação NDEF: ${res.error ?? 'somente leitura'}).';
                });
              });
              sub = NfcAuthService.instance.tagStream.listen((uidHex) {
                if (ctx.mounted && capturedUid.isEmpty) {
                  HapticFeedback.mediumImpact();
                  setDialogState(() => capturedUid = uidHex);
                }
              });
            }
            return AlertDialog(
              backgroundColor: const Color(0xFF140204),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: _crimson.withValues(alpha: 0.5)),
              ),
              title: const Text(
                'Cadastrar Chave NFC (Nível 2)',
                style: TextStyle(fontSize: 15),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: labelCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'Apelido da tag (ex: Chaveiro, Cartão)',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: writeShortcut,
                    onChanged: capturedUid.isNotEmpty
                        ? null
                        : (v) {
                            setDialogState(() => writeShortcut = v);
                            unawaited(
                              NfcAuthService.instance.stopReader().then(
                                    (_) => NfcAuthService.instance.startReader(
                                      writeUnlockNdef: v,
                                    ),
                                  ),
                            );
                          },
                    title: const Text(
                      'Gravar abertura direta (ultron://unlock)',
                      style: TextStyle(fontSize: 11.5),
                    ),
                    subtitle: const Text(
                      'Abre e desbloqueia o app direto ao encostar.',
                      style: TextStyle(fontSize: 10, color: Colors.white60),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E0305),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: capturedUid.isEmpty
                            ? Colors.white24
                            : const Color(0xFF5CE69C),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          capturedUid.isEmpty ? Icons.nfc : Icons.check_circle,
                          color: capturedUid.isEmpty
                              ? _rose
                              : const Color(0xFF5CE69C),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            capturedUid.isEmpty
                                ? 'Encoste sua tag, cartão ou adesivo NFC atrás do celular agora...'
                                : 'Tag lida! Final ****${capturedUid.length >= 4 ? capturedUid.substring(capturedUid.length - 4) : capturedUid}.${ndefStatus == null ? '' : '\n$ndefStatus'}',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: capturedUid.isEmpty
                      ? null
                      : () async {
                          await widget.vault.addNfcTag(
                            capturedUid,
                            label: labelCtrl.text,
                          );
                          if (ctx.mounted) Navigator.of(ctx).pop(true);
                        },
                  style: FilledButton.styleFrom(backgroundColor: _crimson),
                  child: const Text('Salvar Chave NFC'),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() async {
      await writeSub?.cancel();
      await sub?.cancel();
      if (readerOn) {
        await NfcAuthService.instance.stopReader();
      }
      labelCtrl.dispose();
    });

    if (saved == true && mounted) {
      final list = await widget.vault.listNfcTags();
      if (!mounted) return;
      setState(() => nfcTags = list);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Chave NFC cadastrada com hash criptográfico!'),
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    voicePipeline.handleLifecycleState(state);
    if (state != AppLifecycleState.resumed) {
      voiceService.stop();
    } else {
      unawaited(_syncPendingBackgroundTurns());
      _consumePendingWakeWord();
      unawaited(_consumePendingFloatingOrbTap());
      unawaited(_consumePendingTileAction());
      unawaited(_consumePendingNfcUnlock());
      unawaited(_consumePendingWorkflows());
      unawaited(_consumePendingSpotifyCallbackUri());
      desktopCommandListener.wakeUp();
    }
  }

  @override
  void dispose() {
    widget.gate.removeListener(_onAuthGateChanged);
    desktopCommandListener.stop();
    WidgetsBinding.instance.removeObserver(this);
    voicePipeline.removeListener(_onVoicePipelineChanged);
    voicePipeline.dispose();
    deviceService.setNativeEventHandlers(
      onFlip: null,
      onWakeWord: null,
      onBackgroundTurn: null,
      onPairingUriReceived: null,
    );
    voiceService.stop();
    commandController.dispose();
    quickNoteController.dispose();
    duressPinController.dispose();
    pcKillSwitchUrlController.dispose();
    pcLanSecretController.dispose();
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
  }

  void _setPanel(_ActivePanel next) {
    HapticFeedback.selectionClick();
    setState(() => panel = next);
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
      deviceService.invalidateVaultSearchCache();
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
          content: Text('Erro ao salvar no Vault: $e',
              style: const TextStyle(fontSize: 11)),
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
      deviceService.invalidateVaultSearchCache();
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
          content: Text('Erro ao salvar no Inbox: $e',
              style: const TextStyle(fontSize: 11)),
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
    if (voicePipeline.isSingleTurnActive) {
      HapticFeedback.selectionClick();
      await voicePipeline.stopSingleTurnListening();
      return;
    }
    if (voicePipeline.isPushToTalkActive) {
      HapticFeedback.selectionClick();
      await voicePipeline.stopPushToTalk();
      return;
    }
    HapticFeedback.mediumImpact();
    final wasSpeaking = voiceService.isSpeaking;
    await voiceService.stop();
    if (wasSpeaking) {
      // Aguarda dissipar eco do alto-falante somente se o TTS estava falando.
      await Future<void>.delayed(const Duration(milliseconds: 220));
    }
    if (!mounted || sending || voicePipeline.isCapturing) return;

    final sttCfg = widget.sttService == null
        ? await providerStore.resolveSttConfig()
        : null;
    if (!mounted) return;
    if (sttCfg != null && sttCfg.apiKey.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Microfone nativo pronto, mas falta chave STT (Groq gratuito ou Whisper em Config IA). Google Voz desativado.',
            style: TextStyle(fontSize: 11),
          ),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    final ok = await voicePipeline.startSingleTurnListening();
    if (!mounted) return;
    if (!ok && voicePipeline.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Microfone nativo indisponível: ${voicePipeline.lastError}',
            style: const TextStyle(fontSize: 11),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> saveCommand() async {
    if (sending) return;
    final attachedVision = pendingVisionImage;
    var text = commandController.text.trim();
    if (text.isEmpty && attachedVision == null) return;
    if (text.isEmpty && attachedVision != null) {
      text =
          'Analise esta imagem em detalhes (texto/OCR, objetos, códigos QR e contexto tático).';
    }

    SystemSound.play(SystemSoundType.click);
    HapticFeedback.lightImpact();
    commandController.clear();
    if (attachedVision != null && mounted) {
      setState(() => pendingVisionImage = null);
    }
    final now = DateTime.now();
    final timeStr = _formatTime(now);

    // 1. Slash commands
    final command =
        attachedVision == null ? SlashCommandParser.parse(text) : null;
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
    if (attachedVision == null && text.startsWith('/')) {
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

    // 2b. Unified Morning Briefing natural trigger ("bom dia", "briefing matinal", "resumo do dia")
    if (attachedVision == null &&
        RegExp(
          r'^(?:(?:ei|oi|ol[aá]|ok)\s+ultron[,\s]+)?(?:bom\s+dia(?:\s+ultron)?|briefing(?:\s+matinal|\s+do\s+dia)?|resumo\s+(?:matinal|do\s+dia)|meu\s+briefing)[!?.]*$',
          caseSensitive: false,
        ).hasMatch(text.trim())) {
      _appendFeed(
        _FeedEntry(
          isUser: true,
          senderLabel: 'OPERADOR',
          text: text,
          timestamp: timeStr,
        ),
      );
      await _runMorningBriefing();
      return;
    }

    // 3. Direct Android Hardware & OS Commands (instant, works offline)
    final deviceAction = attachedVision == null
        ? await deviceService.tryExecuteNaturalCommand(
            text,
            confirmAction: _confirmActionSimulation,
          )
        : null;
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
    final userFeedText = attachedVision == null
        ? text
        : '📷 [Imagem ${attachedVision.width}x${attachedVision.height} · ${attachedVision.sizeKbLabel}]\n$text';
    _appendFeed(
      _FeedEntry(
        isUser: true,
        senderLabel: 'OPERADOR',
        text: userFeedText,
        timestamp: timeStr,
      ),
    );

    final preAnalysis = cognicaoService.analyzePrompt(text);
    final activeConvId = activeTacticalMode.conversationId;
    final previousMessages = await ConversationHistory.instance.messages(
      conversationId: activeConvId,
      limit: preAnalysis.recommendedMaxHistory,
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
        conversationId: activeConvId,
        role: ChatRole.user,
        content: text,
        createdAt: now,
      ),
    );
    if (!mounted) return;
    setState(() => sending = true);

    final totalSw = Stopwatch()..start();
    try {
      final ragSw = Stopwatch()..start();
      final baseSystemPrompt = await deviceService.buildContextualSystemPrompt(
        userQuery: text,
        mode: activeTacticalMode,
      );
      final reusingSessionVision = attachedVision == null &&
          lastSessionVisionImage != null &&
          cognicaoService.looksLikeVisualFollowUp(text);
      final effectiveVision =
          attachedVision ?? (reusingSessionVision ? lastSessionVisionImage : null);
      final visualMemorySection = reusingSessionVision &&
              (lastSessionVisionSummary?.trim().isNotEmpty ?? false)
          ? '\n\n${cognicaoService.wrapUntrustedVisualData(lastSessionVisionSummary!, sourceLabel: 'SESSAO_VISUAL_ANTERIOR')}'
          : '';
      final contextualSystemPrompt =
          '$baseSystemPrompt$visualMemorySection\n\n=== DIRETRIZ COGNITIVA DO TURNO ===\n${preAnalysis.directivePrompt}';
      ragSw.stop();
      final ragMs = ragSw.elapsedMilliseconds;

      final llmSw = Stopwatch()..start();
      final reply = await AiFailover(store: providerStore).ask(
        text,
        history: aiHistory,
        systemPrompt: contextualSystemPrompt,
        imageBase64: effectiveVision?.base64,
      );
      llmSw.stop();
      final llmMs = llmSw.elapsedMilliseconds;

      final actSw = Stopwatch()..start();
      final actionExec = await deviceService.executeAiActions(
        reply.text,
        confirmAction: _confirmActionSimulation,
      );
      await _refreshDeviceStatus();
      actSw.stop();
      final actMs = actSw.elapsedMilliseconds;

      final postAudit = cognicaoService.auditResponse(
        cleanReplyText: actionExec.cleanText,
        executedTools: actionExec.executedLogs,
        isUrgent: preAnalysis.isUrgent,
      );
      final displayReply = actionExec.executedLogs.isEmpty
          ? postAudit.text
          : '${postAudit.text}\n\n[Hardware: ${actionExec.executedLogs.join(' • ')}]';
      final replyNow = DateTime.now();
      await ConversationHistory.instance.save(
        ChatMessage(
          id: null,
          conversationId: activeConvId,
          role: ChatRole.assistant,
          content: displayReply,
          createdAt: replyNow,
        ),
      );
      if (!mounted) return;
      setState(() {
        activeProviderUsed = reply.provider;
        sessionTelemetry = sessionTelemetry.recordReply(reply);
        if (attachedVision != null) {
          lastSessionVisionImage = attachedVision;
          lastSessionVisionSummary = postAudit.text;
        }
      });
      _appendFeed(
        _FeedEntry(
          isUser: false,
          senderLabel: reply.provider,
          text: displayReply,
          timestamp: _formatTime(replyNow),
        ),
      );
      unawaited(_syncBackgroundVoiceConfig());
      var ttsMs = 0;
      if (_isForegroundActive) {
        final ttsSw = Stopwatch()..start();
        await voiceService.speak(postAudit.speakText);
        ttsSw.stop();
        ttsMs = ttsSw.elapsedMilliseconds;
      }
      totalSw.stop();
      debugPrint(
        '[ULTRON][LATENCY] RAG=${ragMs}ms LLM=${llmMs}ms'
        '(provider=${reply.provider},fails=${reply.failedAttempts}) '
        'ACT=${actMs}ms TTS=${ttsMs}ms TOTAL=${totalSw.elapsedMilliseconds}ms',
      );
    } catch (error) {
      totalSw.stop();
      debugPrint(
        '[ULTRON][LATENCY] ERROR after ${totalSw.elapsedMilliseconds}ms: $error',
      );
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

  Future<void> _runMorningBriefing({String? cityOverride}) async {
    if (!mounted) return;
    setState(() => sending = true);
    try {
      final briefing = await briefingService.generateBriefing(
        cityOverride: cityOverride,
      );
      if (!mounted) return;
      _appendFeed(
        _FeedEntry(
          isUser: false,
          senderLabel: 'Briefing Executivo (P4)',
          text: briefing.formattedReport,
          timestamp: _formatTime(DateTime.now()),
        ),
      );
      if (_isForegroundActive) {
        await voiceService.speak(briefing.speakText);
      }
    } catch (e) {
      if (!mounted) return;
      _appendFeed(
        _FeedEntry(
          isUser: false,
          senderLabel: 'Briefing Executivo (P4)',
          text: '⚠️ Falha ao consolidar briefing: $e',
          timestamp: _formatTime(DateTime.now()),
        ),
      );
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<bool> _confirmActionSimulation(ActionSimulation sim) async {
    if (!mounted) return false;
    return _confirmActionGate(
      title: '⚠️ ACTION GATE — ${sim.actionCode}',
      message:
          '${sim.description}\n\nImpacto: ${sim.estimatedImpact}\nAlvo: ${sim.targetResource}',
      confirmText: 'APROVAR',
    );
  }

  Future<void> _captureVisionImage(String source) async {
    try {
      final attachment = await deviceService.captureVisionImage(source: source);
      if (!mounted) return;
      if (attachment == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Captura de imagem cancelada.',
              style: TextStyle(fontSize: 11),
            ),
          ),
        );
        return;
      }
      setState(() => pendingVisionImage = attachment);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '📷 Imagem anexada (${attachment.width}x${attachment.height} · ${attachment.sizeKbLabel}). Digite sua pergunta ou toque em enviar.',
            style: const TextStyle(fontSize: 11),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _appendFeed(_FeedEntry(
        isUser: false,
        senderLabel: 'Visão Multimodal',
        text: '⚠️ Falha ao capturar imagem: $e',
        timestamp: _formatTime(DateTime.now()),
      ));
    }
  }

  Future<void> _openVisionPicker() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A0204),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'VISÃO MULTIMODAL (CÂMERA / GALERIA)',
                style: TextStyle(
                  color: _crimson,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.photo_camera, color: _rose),
                title: const Text(
                  'Capturar com a Câmera',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
                subtitle: const Text(
                  'OCR, QR Code, placas ou diagnóstico visual',
                  style: TextStyle(color: Color(0xFFA89698), fontSize: 11),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  unawaited(_captureVisionImage('camera'));
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: _rose),
                title: const Text(
                  'Escolher da Galeria',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
                subtitle: const Text(
                  'Prints de tela ou fotos salvas',
                  style: TextStyle(color: Color(0xFFA89698), fontSize: 11),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  unawaited(_captureVisionImage('gallery'));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmActionGate({
    required String title,
    required String message,
    required String confirmText,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2E0305),
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

  Future<void> _openVoiceSelector() async {
    await showVoiceSelectorSheet(
      context,
      voiceService: voiceService,
      onChanged: () {
        if (mounted) {
          setState(() => selectedVoiceProfile = voiceService.profile);
        }
        unawaited(_syncBackgroundVoiceConfig());
      },
    );
  }

  Future<bool> _setOfflineSentinelEnabled(bool next) async {
    if (next && voicePipeline.isContinuousEnabled) {
      await voicePipeline.stopContinuousListening();
    }
    if (next) {
      unawaited(_syncBackgroundVoiceConfig());
    }
    final requested = await deviceService.setAudioSentinel(next);
    var real = false;
    if (next) {
      final attempts = requested ? 16 : 12;
      final step = Duration(milliseconds: requested ? 250 : 500);
      for (var i = 0; i < attempts && !real; i++) {
        real = await deviceService.isAudioSentinelRunning();
        if (real) break;
        await Future<void>.delayed(step);
      }
      if (real) {
        real = await deviceService.isAudioSentinelRunning();
      }
    }
    if (!mounted) return real;
    setState(() => ecoVadSentinelRunning = real);
    if (next && !real) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⚠️ Sentinela não confirmou captura do microfone. Conceda permissão e veja o diagnóstico em CELULAR.',
            style: TextStyle(fontSize: 11),
          ),
        ),
      );
    } else if (next && real) {
      final canOverlay = await deviceService.canDrawOverlays();
      if (!mounted) return real;
      if (!canOverlay) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              '🎙️ Sentinela ativa. Ative "Aparecer sobre outros apps" para abrir WhatsApp/apps em 2º plano.',
              style: TextStyle(fontSize: 11),
            ),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'ATIVAR',
              onPressed: () =>
                  unawaited(deviceService.requestOverlayPermission()),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '🎙️ Palavra de ativação "Ultron" ativa (1º e 2º plano).',
              style: TextStyle(fontSize: 11),
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
    return real;
  }

  Future<void> _toggleContinuousListening() async {
    HapticFeedback.selectionClick();
    if (ecoVadSentinelRunning) {
      await _setOfflineSentinelEnabled(false);
      return;
    }
    if (voicePipeline.isContinuousEnabled) {
      await voicePipeline.stopContinuousListening();
      return;
    }
    await _setOfflineSentinelEnabled(true);
  }

  Future<void> _togglePushToTalk() async {
    HapticFeedback.lightImpact();
    if (voicePipeline.isPushToTalkActive) {
      await voicePipeline.stopPushToTalk();
      return;
    }
    final ok = await voicePipeline.startPushToTalk();
    if (!mounted || ok || voicePipeline.lastError == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(voicePipeline.lastError!)),
    );
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
        final storedNfc = await widget.vault.listNfcTags();
        final hwNfc = await NfcAuthService.instance.getStatus();
        if (!mounted) return;
        setState(() {
          authFailures = failures;
          hasPinConfigured = pinSet;
          hasDuressPinConfigured = duressSet;
          nfcTags = storedNfc;
          nfcStatus = hwNfc;
        });
        _setPanel(_ActivePanel.security);
        break;
      case UltronCommand.history:
        await _openHistory();
        break;
      case UltronCommand.memory:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MemorySettingsScreen(voiceService: voiceService),
          ),
        );
        if (mounted) {
          setState(() => selectedVoiceProfile = voiceService.profile);
        }
        unawaited(_syncBackgroundVoiceConfig());
        break;
      case UltronCommand.desktop:
        final desktopAllowed = await _elevateSessionTo(
          AccessLevel.sovereign,
          'Acesso à aba Desktop e pareamento PC exige Biometria (Nível 3).',
        );
        if (!desktopAllowed || !mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DesktopPairingScreen(
              pairingService: desktopPairing,
              actionsService: androidActions,
              deviceService: deviceService,
              onPairingChanged: () => desktopCommandListener.wakeUp(),
            ),
          ),
        );
        desktopCommandListener.wakeUp();
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
          confirmAction: _confirmActionSimulation,
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
        } else {
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'Skill Engine (.md)',
            text:
                '⚠️ Skill "$argument" não encontrada em Skills/. Use /skills para listar as disponíveis.',
            timestamp: timeStr,
          ));
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
        final trimmedArg = argument.trim();
        final lowerArg = trimmedArg.toLowerCase();
        if (trimmedArg.isEmpty) {
          final opened = await deviceService.openObsidianVault();
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'Segundo Cérebro',
            text: opened
                ? '📓 Cofre Obsidian aberto no app oficial!\nLocal: ${obs.vaultPath}'
                : '📓 Cofre Segundo Cérebro: ${obs.vaultPath}\nUse /note <texto> para o Diário ou "ideia: <texto>" para o Inbox.',
            timestamp: timeStr,
          ));
        } else if (lowerArg == 'status') {
          final status = await deviceService.getObsidianStatus();
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'Segundo Cérebro',
            text: status.formatSummary(),
            timestamp: timeStr,
          ));
        } else if (lowerArg == 'notas' || lowerArg.startsWith('notas ')) {
          final folder = trimmedArg.length > 5
              ? trimmedArg.substring(5).trim()
              : '';
          final res = await deviceService.tryExecuteNaturalCommand(
            folder.isEmpty ? 'listar notas' : 'listar notas $folder',
            confirmAction: _confirmActionSimulation,
          );
          if (res != null) {
            _appendFeed(_FeedEntry(
              isUser: false,
              senderLabel: 'Segundo Cérebro',
              text: res.message,
              timestamp: timeStr,
            ));
          }
        } else if (lowerArg.startsWith('ler ')) {
          final noteTarget = trimmedArg.substring(4).trim();
          final res = await deviceService.tryExecuteNaturalCommand(
            'ler nota $noteTarget',
            confirmAction: _confirmActionSimulation,
          );
          if (res != null) {
            _appendFeed(_FeedEntry(
              isUser: false,
              senderLabel: 'Segundo Cérebro',
              text: res.message,
              timestamp: timeStr,
            ));
          }
        } else if (lowerArg.startsWith('anexar ')) {
          final spec = trimmedArg.substring(7).trim();
          final res = await deviceService.tryExecuteNaturalCommand(
            'anexar na nota $spec',
            confirmAction: _confirmActionSimulation,
          );
          if (res != null) {
            _appendFeed(_FeedEntry(
              isUser: false,
              senderLabel: 'Segundo Cérebro',
              text: res.message,
              timestamp: timeStr,
            ));
          }
        } else if (lowerArg == 'tarefas' || lowerArg.startsWith('tarefas ')) {
          final sub = trimmedArg.length > 7
              ? trimmedArg.substring(7).trim()
              : '';
          final phrase = sub.isEmpty
              ? 'listar tarefas do obsidian'
              : (sub.toLowerCase().startsWith('marcar ') ||
                      sub.toLowerCase().startsWith('desmarcar '))
                  ? '${sub.split(' ').first} tarefa ${sub.split(' ').skip(1).join(' ')}'
                  : 'alternar tarefa $sub';
          final res = await deviceService.tryExecuteNaturalCommand(
            phrase,
            confirmAction: _confirmActionSimulation,
          );
          if (res != null) {
            _appendFeed(_FeedEntry(
              isUser: false,
              senderLabel: 'Segundo Cérebro',
              text: res.message,
              timestamp: timeStr,
            ));
          }
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
          final providers =
              (await providerStore.load()).where((p) => p.enabled).toList();
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
              text:
                  'Modelos disponíveis em ${activeP.name} (${activeP.baseUrl}):\n$modelsList',
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
        final res =
            await deviceService.tryExecuteNaturalCommand('ler mensagens');
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
            text:
                'Uso: /reply <texto da resposta> ou "responder para Nome: <texto>"',
            timestamp: timeStr,
          ));
        } else {
          final res = await deviceService.tryExecuteNaturalCommand(
            'responder: $argument',
            confirmAction: _confirmActionSimulation,
          );
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
        final ksElevated = await _elevateSessionTo(
          AccessLevel.sovereign,
          'Kill Switch remoto no PC exige Biometria (Nível 3) + confirmação.',
        );
        if (!ksElevated || !mounted) return;
        final sim = actionGate.simulate('KILL_SWITCH');
        final confirmed = await _confirmActionGate(
          title: '🚨 ${sim.description.toUpperCase()}',
          message:
              'Atenção Operador: ${sim.estimatedImpact} Alvo: ${sim.targetResource}. Confirmar execução tática?',
          confirmText: 'DISPARAR KILL SWITCH',
        );
        if (!confirmed) {
          await deviceService.recordAudit(
            actor: 'OPERATOR',
            action: 'KILL_SWITCH',
            target: sim.targetResource,
            status: 'DENIED',
            detail: 'Operador cancelou /killswitch no Action Gate',
          );
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'Action Gate',
            text: 'Operação de Kill Switch cancelada pelo Operador.',
            timestamp: timeStr,
          ));
          return;
        }
        final msg =
            await deviceService.triggerPcKillSwitch(reason: 'slash_killswitch');
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
        final clearElevated = await _elevateSessionTo(
          AccessLevel.sovereign,
          'Expurgo irreversível do histórico exige Biometria (Nível 3) + confirmação.',
        );
        if (!clearElevated || !mounted) return;
        final sim = actionGate.simulate('CLEAR_HISTORY');
        final confirmed = await _confirmActionGate(
          title: 'EXPURGAR HISTÓRICO LOCAL',
          message:
              'Deseja limpar as mensagens da sessão atual? ${sim.estimatedImpact}',
          confirmText: 'EXPURGAR',
        );
        if (confirmed) {
          await ConversationHistory.instance.clear();
          await deviceService.recordAudit(
            actor: 'OPERATOR',
            action: 'CLEAR_HISTORY',
            target: 'SQLCipher',
            status: 'EXECUTED',
            detail: 'Histórico local expurgado via /clear',
          );
          if (!mounted) return;
          setState(() => feed = _defaultFeed);
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'Memória Local',
            text:
                'Histórico da sessão expurgado (RAM + Banco Criptografado SQLCipher).',
            timestamp: timeStr,
          ));
        } else {
          await deviceService.recordAudit(
            actor: 'OPERATOR',
            action: 'CLEAR_HISTORY',
            target: 'SQLCipher',
            status: 'DENIED',
            detail: 'Operador cancelou /clear no Action Gate',
          );
        }
        break;
      case UltronCommand.search:
        if (argument.isEmpty) {
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'RAG Obsidian (FTS5)',
            text: 'Uso: /buscar <termo ou tópico> (ex.: /buscar sensores)',
            timestamp: timeStr,
          ));
        } else {
          final hits = await deviceService.searchObsidianVault(
            argument,
            limit: 5,
          );
          if (hits.isEmpty) {
            _appendFeed(_FeedEntry(
              isUser: false,
              senderLabel: 'RAG Obsidian (FTS5)',
              text: '🔍 Nenhuma nota encontrada para "$argument".',
              timestamp: timeStr,
            ));
          } else {
            final summary = hits
                .map((h) => '• ${h.title} (${h.path})\n  ${h.snippet}')
                .join('\n\n');
            _appendFeed(_FeedEntry(
              isUser: false,
              senderLabel: 'RAG Obsidian (FTS5)',
              text:
                  '🔍 ${hits.length} resultado(s) para "$argument":\n\n$summary',
              timestamp: timeStr,
            ));
          }
        }
        break;
      case UltronCommand.vision:
        final argLower = argument.trim().toLowerCase();
        final source = argLower == 'galeria' ||
                argLower == 'gallery' ||
                argLower.startsWith('galeria ') ||
                argLower.startsWith('gallery ')
            ? 'gallery'
            : 'camera';
        if (argument.isEmpty ||
            argLower == 'camera' ||
            argLower == 'galeria' ||
            argLower == 'gallery') {
          await _captureVisionImage(source);
        } else {
          final prompt = source == 'gallery'
              ? argument.trim().replaceFirst(
                    RegExp(r'^(?:galeria|gallery)\s*', caseSensitive: false),
                    '',
                  )
              : argument.trim();
          await _captureVisionImage(source);
          if (pendingVisionImage != null && prompt.isNotEmpty) {
            commandController.text = prompt;
            await saveCommand();
          }
        }
        break;
      case UltronCommand.pc:
        final trimmedArg = argument.trim();
        if (trimmedArg.isEmpty) {
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'Bridge Desktop LAN',
            text: 'Uso de /pc (Requer Biometria • Nível 3):\n'
                '• /pc status — ping HMAC assinado no Desktop\n'
                '• /pc abrir <app> — solicita abertura de app no PC\n'
                '• /pc midia <play_pause|next|previous|mute> — controle de mídia\n'
                '• /pc copiar <texto> | /pc colar — área de transferência LAN\n'
                '• /pc skill <nome> — executa skill no Desktop\n'
                '• /pc termico — proteção térmica e telemetria CPU/GPU/RAM\n'
                '• /pc energia <high_performance|balanced|power_saver> — plano de energia\n'
                '• /pc volume_app [listar|<app> <0-100>] — mixer de volume por app\n'
                '• /pc travados — encerrar aplicativos travados\n'
                '• /pc backup — executar backup incremental\n'
                '• /pc limpar_disco — limpeza de temporários e cache\n'
                '• /pc ejetar_usb — ejetar unidade USB ociosa\n'
                '• /pc tool <nome_ferramenta>|[ALTO/CRITICO]|{json} — despachante genérico v3.0.0\n'
                '• Use /desktop para parear ou testar o endpoint LAN.',
            timestamp: timeStr,
          ));
          break;
        }
        final parsedPc = DesktopPairingService.parsePcCommandInput(trimmedArg);
        if (parsedPc == null) {
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'Bridge Desktop LAN',
            text: '⚠️ Subcomando /pc não reconhecido: "$trimmedArg".\n'
                'Use: /pc status | abrir | midia | copiar | colar | skill | termico | energia | volume_app | travados | backup | limpar_disco | ejetar_usb | tool',
            timestamp: timeStr,
          ));
          break;
        }
        final pcCmd = parsedPc.command;
        final pcArgs = parsedPc.args;
        try {
          final res = await deviceService.sendDesktopBridgeCommand(
            command: pcCmd,
            args: pcArgs,
            confirmAction: _confirmActionSimulation,
            actor: 'OPERATOR',
          );
          final statusMsg = res.deniedByUser
              ? '🚫 Comando /pc ($pcCmd) cancelado ou requer Biometria (Nível 3).'
              : res.sent
                  ? '✅ PC ($pcCmd) -> HTTP ${res.statusCode ?? 200}'
                      '${res.verifiedSignature ? ' [HMAC resposta verificado]' : ''}'
                      '${(res.responseBody ?? '').trim().isNotEmpty ? '\n${res.responseBody}' : ''}'
                  : '⚠️ Falha no /pc ($pcCmd): ${res.error ?? 'HTTP ${res.statusCode}'}';
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'Bridge Desktop LAN',
            text: statusMsg,
            timestamp: timeStr,
          ));
        } catch (e) {
          await deviceService.recordAudit(
            actor: 'OPERATOR',
            action: pcCmd,
            target: 'Desktop LAN',
            status: 'FAILED',
            detail: '$e',
          );
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'Bridge Desktop LAN',
            text: '⚠️ Falha no comando /pc ($pcCmd): $e',
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
      case UltronCommand.calendar:
        final argLower = argument.trim().toLowerCase();
        if (argLower.isEmpty ||
            argLower == 'hoje' ||
            argLower == 'amanha' ||
            argLower == 'amanhã' ||
            argLower == 'semana') {
          final queryPhrase = argLower.isEmpty
              ? 'agenda de hoje'
              : argLower == 'semana'
                  ? 'agenda da semana'
                  : 'agenda de $argLower';
          final res = await deviceService.tryExecuteNaturalCommand(
            queryPhrase,
            confirmAction: _confirmActionSimulation,
          );
          if (res != null) {
            _appendFeed(_FeedEntry(
              isUser: false,
              senderLabel: 'Agenda Android (CalendarContract)',
              text: res.message,
              timestamp: timeStr,
            ));
            if (res.speakText != null && _isForegroundActive) {
              await voiceService.speak(res.speakText!);
            }
          }
        } else if (argLower.startsWith('cancelar ') ||
            argLower.startsWith('remover ')) {
          final target = argument
              .trim()
              .replaceFirst(
                RegExp(r'^(?:cancelar|remover)\s+', caseSensitive: false),
                '',
              )
              .trim();
          final res = await deviceService.tryExecuteNaturalCommand(
            'cancelar evento $target',
            confirmAction: _confirmActionSimulation,
          );
          if (res != null) {
            _appendFeed(_FeedEntry(
              isUser: false,
              senderLabel: 'Agenda Android (CalendarContract)',
              text: res.message,
              timestamp: timeStr,
            ));
            if (res.speakText != null && _isForegroundActive) {
              await voiceService.speak(res.speakText!);
            }
          }
        } else {
          final createSpec = argument.trim().replaceFirst(
                RegExp(r'^criar\s+', caseSensitive: false),
                '',
              );
          final res = await deviceService.tryExecuteNaturalCommand(
            'agendar $createSpec',
            confirmAction: _confirmActionSimulation,
          );
          if (res != null) {
            _appendFeed(_FeedEntry(
              isUser: false,
              senderLabel: 'Agenda Android (CalendarContract)',
              text: res.message,
              timestamp: timeStr,
            ));
            if (res.speakText != null && _isForegroundActive) {
              await voiceService.speak(res.speakText!);
            }
          }
        }
        break;
      case UltronCommand.briefing:
        final argTrim = argument.trim();
        final cityMatch = RegExp(
          r'^(?:cidade|local|city)\s+(.+)$',
          caseSensitive: false,
        ).firstMatch(argTrim);
        if (cityMatch != null) {
          final city = cityMatch.group(1)!.trim();
          await briefingService.savePreferredCity(city);
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'Briefing Executivo (P4)',
            text: '🌤️ Cidade padrão do Briefing salva: $city.',
            timestamp: timeStr,
          ));
        } else {
          await _runMorningBriefing(
            cityOverride: argTrim.isEmpty ? null : argTrim,
          );
        }
        break;
      case UltronCommand.audit:
        try {
          final audit = await AuditLogService.instance();
          final report = await audit.formatReport(limit: 18);
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'Auditoria SHA-256 (P5)',
            text: report,
            timestamp: timeStr,
          ));
        } catch (e) {
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'Auditoria SHA-256 (P5)',
            text: '⚠️ Falha ao carregar trilha de auditoria: $e',
            timestamp: timeStr,
          ));
        }
        break;
      case UltronCommand.undo:
        final undoRes = await deviceService.undoLastObsidianMutation();
        _appendFeed(_FeedEntry(
          isUser: false,
          senderLabel: 'Segundo Cérebro (UNDO)',
          text: undoRes.message,
          timestamp: timeStr,
        ));
        if (_isForegroundActive) {
          await voiceService.speak(
            undoRes.undone
                ? 'Última alteração no cofre desfeita.'
                : 'Não há alterações recentes para desfazer.',
          );
        }
        break;
      case UltronCommand.reminder:
        final argTrim = argument.trim();
        final argLower = argTrim.toLowerCase();
        final String naturalPhrase;
        if (argTrim.isEmpty ||
            argLower == 'listar' ||
            argLower == 'list' ||
            argLower == 'pendentes') {
          naturalPhrase = 'listar lembretes';
        } else if (argLower.startsWith('cancelar ') ||
            argLower.startsWith('remover ')) {
          final target = argTrim.replaceFirst(
            RegExp(r'^(?:cancelar|remover)\s+', caseSensitive: false),
            '',
          );
          naturalPhrase = 'cancelar lembrete $target';
        } else {
          naturalPhrase = 'criar lembrete $argTrim';
        }
        final remRes = await deviceService.tryExecuteNaturalCommand(
          naturalPhrase,
          confirmAction: _confirmActionSimulation,
        );
        if (remRes != null) {
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'Lembretes (AlarmManager)',
            text: remRes.message,
            timestamp: timeStr,
          ));
          if (remRes.speakText != null && _isForegroundActive) {
            await voiceService.speak(remRes.speakText!);
          }
        }
        break;
      case UltronCommand.weather:
        final city = argument.trim();
        final wRes = await deviceService.tryExecuteNaturalCommand(
          city.isEmpty ? 'clima' : 'clima em $city',
          confirmAction: _confirmActionSimulation,
        );
        if (wRes != null) {
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'Meteorologia (wttr.in)',
            text: wRes.message,
            timestamp: timeStr,
          ));
          if (wRes.speakText != null && _isForegroundActive) {
            await voiceService.speak(wRes.speakText!);
          }
        }
        break;
      case UltronCommand.news:
        final topic = argument.trim();
        final nRes = await deviceService.tryExecuteNaturalCommand(
          topic.isEmpty ? 'notícias' : 'notícias sobre $topic',
          confirmAction: _confirmActionSimulation,
        );
        if (nRes != null) {
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'Notícias RSS',
            text: nRes.message,
            timestamp: timeStr,
          ));
          if (nRes.speakText != null && _isForegroundActive) {
            await voiceService.speak(nRes.speakText!);
          }
        }
        break;
      case UltronCommand.websearch:
        final q = argument.trim();
        if (q.isEmpty) {
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'WebInfoService',
            text: 'Uso: /pesquisar_web <consulta> (ex.: /pesquisar_web computação quântica)',
            timestamp: timeStr,
          ));
        } else {
          final wsRes = await deviceService.tryExecuteNaturalCommand(
            'pesquisar_web $q',
            confirmAction: _confirmActionSimulation,
          );
          if (wsRes != null) {
            _appendFeed(_FeedEntry(
              isUser: false,
              senderLabel: 'WebInfoService',
              text: wsRes.message,
              timestamp: timeStr,
            ));
            if (wsRes.speakText != null && _isForegroundActive) {
              await voiceService.speak(wsRes.speakText!);
            }
          }
        }
        break;
      case UltronCommand.flow:
        final argTrim = argument.trim();
        final argLower = argTrim.toLowerCase();
        String flowPhrase;
        if (argTrim.isEmpty || argLower == 'listar' || argLower == 'list') {
          flowPhrase = 'listar fluxos';
        } else if (argLower.startsWith('criar ')) {
          flowPhrase = 'criar fluxo ${argTrim.substring(6).trim()}';
        } else if (argLower.startsWith('rodar ') ||
            argLower.startsWith('executar ')) {
          final rest = argTrim.replaceFirst(
            RegExp(r'^(?:rodar|executar)\s+', caseSensitive: false),
            '',
          );
          flowPhrase = 'executar fluxo $rest';
        } else if (argLower.startsWith('agendar ')) {
          flowPhrase = 'agendar fluxo ${argTrim.substring(8).trim()}';
        } else if (argLower.startsWith('excluir ') ||
            argLower.startsWith('remover ')) {
          final rest = argTrim.replaceFirst(
            RegExp(r'^(?:excluir|remover)\s+', caseSensitive: false),
            '',
          );
          flowPhrase = 'excluir fluxo $rest';
        } else {
          flowPhrase = 'executar fluxo $argTrim';
        }
        final fRes = await deviceService.tryExecuteNaturalCommand(
          flowPhrase,
          confirmAction: _confirmActionSimulation,
        );
        if (fRes != null) {
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'Workflow Scheduler',
            text: fRes.message,
            timestamp: timeStr,
          ));
          if (fRes.speakText != null && _isForegroundActive) {
            await voiceService.speak(fRes.speakText!);
          }
        }
        break;
      case UltronCommand.spotify:
        final argTrim = argument.trim();
        final argLower = argTrim.toLowerCase();
        String spPhrase;
        if (argTrim.isEmpty ||
            argLower == 'estado' ||
            argLower == 'status' ||
            argLower == 'state') {
          spPhrase = 'spotify estado';
        } else if (argLower == 'playlists' || argLower == 'listar playlists') {
          spPhrase = 'spotify playlists';
        } else if (argLower.startsWith('buscar ') ||
            argLower.startsWith('search ')) {
          final q = argTrim.replaceFirst(
            RegExp(r'^(?:buscar|search)\s+', caseSensitive: false),
            '',
          );
          spPhrase = 'spotify buscar $q';
        } else if (argLower.startsWith('tocar ') ||
            argLower.startsWith('play ')) {
          final q = argTrim.replaceFirst(
            RegExp(r'^(?:tocar|play)\s+', caseSensitive: false),
            '',
          );
          spPhrase = 'spotify tocar $q';
        } else if (argLower.startsWith('adicionar ')) {
          final spec = argTrim.substring('adicionar '.length).trim();
          spPhrase = 'spotify adicionar playlist $spec';
        } else {
          spPhrase = 'spotify tocar $argTrim';
        }
        final spRes = await deviceService.tryExecuteNaturalCommand(
          spPhrase,
          confirmAction: _confirmActionSimulation,
        );
        if (spRes != null) {
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'Spotify Web API',
            text: spRes.message,
            timestamp: timeStr,
          ));
          if (spRes.speakText != null && _isForegroundActive) {
            await voiceService.speak(spRes.speakText!);
          }
        }
        break;
      case UltronCommand.files:
        final fileRes = await deviceService.executeFileUtilityCommand(
          argument,
          confirmAction: _confirmActionSimulation,
        );
        _appendFeed(_FeedEntry(
          isUser: false,
          senderLabel: 'Utilitários de Arquivos (SAF)',
          text: fileRes.message,
          timestamp: timeStr,
        ));
        if (fileRes.speakText != null && _isForegroundActive) {
          await voiceService.speak(fileRes.speakText!);
        }
        break;
      case UltronCommand.mode:
        final arg = argument.trim();
        if (arg.isEmpty || arg.toLowerCase() == 'listar' || arg.toLowerCase() == 'list') {
          final list = TacticalMode.presets
              .map(
                (m) =>
                    '• **${m.id}** (${m.label})${m.id == activeTacticalMode.id ? ' ← ATIVO' : ''}'
                    '${m.vaultPathPrefix != null ? ' · Cofre `${m.vaultPathPrefix}/`' : ' · Cofre global'}',
              )
              .join('\n');
          _appendFeed(_FeedEntry(
            isUser: false,
            senderLabel: 'Modos Táticos',
            text: '🎯 **Modos Táticos Isolados:**\n$list\n\nUse `/modo <nome>` ou toque no badge `MODO` na barra de telemetria.',
            timestamp: timeStr,
          ));
        } else {
          final parsed = TacticalMode.parse(arg);
          if (parsed == null) {
            _appendFeed(_FeedEntry(
              isUser: false,
              senderLabel: 'Modos Táticos',
              text:
                  '⚠️ Modo "$arg" não reconhecido. Opções: `geral`, `engenharia`, `estudos`, `treino`, `dev`.',
              timestamp: timeStr,
            ));
          } else {
            await _switchTacticalMode(parsed);
          }
        }
        break;
      case UltronCommand.eletrica:
        final elRes = await deviceService.executeEletricaCommand(
          argument,
          confirmAction: _confirmActionSimulation,
        );
        _appendFeed(_FeedEntry(
          isUser: false,
          senderLabel: 'Projetista Elétrico (NBR 5410)',
          text: elRes.message,
          timestamp: timeStr,
        ));
        if (elRes.speakText != null && _isForegroundActive) {
          await voiceService.speak(elRes.speakText!);
        }
        break;
    }
  }

  Future<void> _switchTacticalMode(TacticalMode mode) async {
    List<ChatMessage> saved = const [];
    try {
      saved = await ConversationHistory.instance.messages(
        conversationId: mode.conversationId,
        limit: 40,
      );
    } catch (_) {}
    if (!mounted) return;
    final scopeMsg = mode.vaultPathPrefix != null
        ? 'Memória filtrada em `${mode.vaultPathPrefix}/` e histórico isolado.'
        : 'Acesso global ao cofre Obsidian e todas as ferramentas.';
    final entry = _FeedEntry(
      isUser: false,
      senderLabel: 'Modo ${mode.label}',
      text: '🎯 Modo Tático **${mode.label}** ativado. $scopeMsg',
      timestamp: _formatTime(DateTime.now()),
    );
    setState(() {
      activeTacticalMode = mode;
      feed = saved.isNotEmpty
          ? [
              ...saved.map(
                (m) => _FeedEntry(
                  isUser: m.role == ChatRole.user,
                  senderLabel:
                      m.role == ChatRole.user ? 'OPERADOR' : 'U.L.T.R.O.N.',
                  text: m.content,
                  timestamp: _formatTime(m.createdAt.toLocal()),
                ),
              ),
              entry,
            ]
          : [entry];
    });
    _scrollToBottom();
  }

  Future<void> _showTacticalModePicker() async {
    final chosen = await showModalBottomSheet<TacticalMode>(
      context: context,
      backgroundColor: const Color(0xFF140204),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SELECIONAR MODO TÁTICO (HELPER ISOLADO)',
                style: TextStyle(
                  color: _crimson,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              ...TacticalMode.presets.map((m) {
                final selected = m.id == activeTacticalMode.id;
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                  leading: Icon(
                    selected ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: selected ? _crimson : const Color(0xFFA89698),
                    size: 18,
                  ),
                  title: Text(
                    m.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${m.description}${m.vaultPathPrefix != null ? ' (${m.vaultPathPrefix}/)' : ''}',
                    style: const TextStyle(
                      color: Color(0xFFA89698),
                      fontSize: 10,
                    ),
                  ),
                  onTap: () => Navigator.of(ctx).pop(m),
                );
              }),
            ],
          ),
        ),
      ),
    );
    if (chosen != null && chosen.id != activeTacticalMode.id) {
      await _switchTacticalMode(chosen);
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
      backgroundColor: const Color(0xFF0A0002),
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
                  color: const Color(0xCC0A0002),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
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
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _TopNavPill(
                              label: 'NÚCLEO',
                              selected: panel == _ActivePanel.main,
                              onTap: () => _setPanel(_ActivePanel.main),
                            ),
                            const SizedBox(width: 4),
                            _TopNavPill(
                              label: 'VOZ',
                              selected: false,
                              onTap: _openVoiceSelector,
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
                              label: 'MEMÓRIA',
                              selected: false,
                              onTap: () => _runCommand(UltronCommand.memory),
                            ),
                            const SizedBox(width: 4),
                            _TopNavPill(
                              label: 'DESKTOP',
                              selected: false,
                              onTap: () => _runCommand(UltronCommand.desktop),
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
                                  isAudioOn
                                      ? Icons.volume_up
                                      : Icons.volume_off,
                                  size: 15,
                                  color: isAudioOn
                                      ? _crimson
                                      : const Color(0xFFA89698),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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

  Widget _buildTelemetryBar() {
    final t = sessionTelemetry;
    final tokPrefix = t.hasEstimatedTokens ? '~' : '';
    final promptStr = SessionTelemetry.formatCompactTokens(t.promptTokens);
    final compStr = SessionTelemetry.formatCompactTokens(t.completionTokens);
    final latStr = t.lastLatencyMs > 0 ? '${t.lastLatencyMs}ms' : '--ms';
    final btOn = deviceStatus?.bluetoothEnabled ?? false;
    final lanActive = pcLanConfigured || desktopCommandListener.isRunning;
    final voiceLabel = isAudioOn
        ? selectedVoiceProfile.name.toUpperCase()
        : 'MUDO';

    return Container(
      key: const Key('cockpit_telemetry_bar'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF140204),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              key: const Key('cockpit_mode_chip'),
              onTap: _showTacticalModePicker,
              child: _telemetryChip(
                label: 'MODO',
                value: activeTacticalMode.shortLabel,
                accent: activeTacticalMode.isGeneral
                    ? _rose
                    : const Color(0xFF64B5F6),
              ),
            ),
            const SizedBox(width: 6),
            _telemetryChip(
              label: 'BRAIN',
              value: t.lastProvider,
              accent: t.lastUsedFailover
                  ? const Color(0xFFFFB74D)
                  : _crimson,
              badge: t.lastUsedFailover ? 'FAILOVER' : null,
            ),
            const SizedBox(width: 6),
            _telemetryChip(
              label: 'LAT',
              value: latStr,
              accent: t.lastLatencyMs > 4000
                  ? const Color(0xFFFFB74D)
                  : const Color(0xFF5CE69C),
            ),
            const SizedBox(width: 6),
            _telemetryChip(
              label: 'TOK',
              value: '$tokPrefix↑$promptStr ↓$compStr · T${t.turns}',
              accent: _rose,
            ),
            const SizedBox(width: 6),
            _telemetryChip(
              label: 'LAN',
              value: lanActive ? 'ON' : 'OFF',
              accent: lanActive
                  ? const Color(0xFF5CE69C)
                  : const Color(0xFF8A7A7C),
            ),
            const SizedBox(width: 6),
            _telemetryChip(
              label: 'BT',
              value: btOn ? 'ON' : 'OFF',
              accent: btOn
                  ? const Color(0xFF64B5F6)
                  : const Color(0xFF8A7A7C),
            ),
            const SizedBox(width: 6),
            _telemetryChip(
              label: 'VOZ',
              value: voiceLabel,
              accent: isAudioOn ? _rose : const Color(0xFF8A7A7C),
            ),
          ],
        ),
      ),
    );
  }

  Widget _telemetryChip({
    required String label,
    required String value,
    required Color accent,
    String? badge,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF210407),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label ',
              style: TextStyle(
                color: accent,
                fontSize: 8.5,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFFEADCDD),
                fontSize: 8.5,
                fontFamily: 'monospace',
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB74D).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: Color(0xFFFFB74D),
                    fontSize: 7.5,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ],
        ),
      );

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: widget.gate.hasBiometricAccess
                            ? null
                            : () => _elevateSessionTo(
                                  AccessLevel.sovereign,
                                  'Eleve seu acesso usando NFC (Nível 2) ou Biometria (Nível 3).',
                                ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2E0305),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: widget.gate.hasBiometricAccess
                                  ? const Color(0xFF5CE69C).withValues(alpha: 0.6)
                                  : _crimson.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            widget.gate.levelBadge,
                            style: TextStyle(
                              color: widget.gate.hasBiometricAccess
                                  ? const Color(0xFF5CE69C)
                                  : _crimson,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'PROVEDOR: $activeProviderUsed',
                        style: const TextStyle(
                          color: Color(0xFFA89698),
                          fontSize: 10,
                        ),
                        maxLines: 1,
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
                        color: Color(0xFFFFA0A0),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Tactical Telemetry Bar (Cockpit AMOLED Carmesim)
          _buildTelemetryBar(),

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
              color: const Color(0xFF2E0305),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pendingVisionImage != null)
                  Container(
                    margin: const EdgeInsets.only(top: 4, bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A0204),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _crimson.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(
                            base64Decode(pendingVisionImage!.base64),
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'VISÃO MULTIMODAL ANEXADA',
                                style: TextStyle(
                                  color: _rose,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${pendingVisionImage!.width}x${pendingVisionImage!.height} · ${pendingVisionImage!.sizeKbLabel} · JPEG VLM',
                                style: const TextStyle(
                                  color: Color(0xFFA89698),
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remover imagem anexada',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          onPressed: () =>
                              setState(() => pendingVisionImage = null),
                          icon: const Icon(
                            Icons.close,
                            size: 16,
                            color: _rose,
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    const Text(
                      '›',
                      style: TextStyle(
                        color: _crimson,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
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
                          hintText: voicePipeline.isPushToTalkActive
                              ? '🎤 Gravando Push-to-Talk…'
                              : listeningVoice
                                  ? '🎤 Ouvindo ao vivo (toque no 🎤 para concluir)…'
                                  : sending
                                      ? 'Consultando provedor ativo…'
                                      : pendingVisionImage != null
                                          ? 'Pergunte sobre a imagem anexada…'
                                          : 'Comando ou toque/segure 🎤...',
                          hintStyle: TextStyle(
                            color: (listeningVoice ||
                                    voicePipeline.isPushToTalkActive)
                                ? _crimson
                                : const Color(0xFF635355),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    Tooltip(
                      message: 'Visão Multimodal (Câmera / Galeria)',
                      child: InkWell(
                        onTap: sending ? null : _openVisionPicker,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          margin: const EdgeInsets.only(right: 5),
                          decoration: BoxDecoration(
                            color: pendingVisionImage != null
                                ? _crimson.withValues(alpha: 0.25)
                                : const Color(0xFF2E0305),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: pendingVisionImage != null
                                  ? _crimson
                                  : _crimson.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Icon(
                            Icons.photo_camera_outlined,
                            size: 14,
                            color: pendingVisionImage != null
                                ? _rose
                                : const Color(0xFF993036),
                          ),
                        ),
                      ),
                    ),
                    Builder(
                      builder: (context) {
                        final continuousActive =
                            voicePipeline.isContinuousEnabled ||
                                ecoVadSentinelRunning;
                        return Tooltip(
                          message: continuousActive
                              ? 'Desativar escuta contínua ("Ultron")'
                              : 'Ativar escuta contínua ("Ultron")',
                          child: InkWell(
                            onTap: sending ? null : _toggleContinuousListening,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              margin: const EdgeInsets.only(right: 5),
                              decoration: BoxDecoration(
                                color: continuousActive
                                    ? _crimson.withValues(alpha: 0.25)
                                    : const Color(0xFF2E0305),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: continuousActive
                                      ? _crimson
                                      : _crimson.withValues(alpha: 0.25),
                                ),
                              ),
                              child: Icon(
                                continuousActive
                                    ? Icons.hearing
                                    : Icons.hearing_disabled,
                                size: 14,
                                color: continuousActive
                                    ? _rose
                                    : const Color(0xFF993036),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    GestureDetector(
                      onLongPressStart: sending
                          ? null
                          : (_) async {
                              HapticFeedback.mediumImpact();
                              await voicePipeline.startPushToTalk();
                            },
                      onLongPressEnd: (_) async {
                        await voicePipeline.stopPushToTalk();
                      },
                      onLongPressCancel: () async {
                        await voicePipeline.stopPushToTalk();
                      },
                      child: InkWell(
                        onTap: sending
                            ? null
                            : () => voicePipeline.isPushToTalkActive
                                ? _togglePushToTalk()
                                : _startVoiceInput(),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          margin: const EdgeInsets.only(right: 5),
                          decoration: BoxDecoration(
                            color: (listeningVoice ||
                                    voicePipeline.isPushToTalkActive)
                                ? _crimson.withValues(alpha: 0.25)
                                : const Color(0xFF2E0305),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: (listeningVoice ||
                                      voicePipeline.isPushToTalkActive)
                                  ? _crimson
                                  : _crimson.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Icon(
                            (listeningVoice || voicePipeline.isPushToTalkActive)
                                ? Icons.graphic_eq
                                : Icons.mic,
                            size: 14,
                            color: (listeningVoice ||
                                    voicePipeline.isPushToTalkActive)
                                ? _rose
                                : _crimson,
                          ),
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: sending ? null : saveCommand,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E0305),
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
                  child: CoreOrb(
                    stage: stage,
                    shaderProgram: widget.shaderProgram,
                    energy: nightFocusMode
                        ? 0.12
                        : voiceService.isSpeaking
                            ? 0.95
                            : (listeningVoice || voicePipeline.isCapturing)
                                ? (0.55 + speechRms * 0.65).clamp(0.4, 1.2)
                                : sending
                                    ? 0.65
                                    : 0.22,
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
                            ? const Color(0xFF2E0305)
                            : const Color(0xFF0A0002),
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
                color: const Color(0xFF0A0002),
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
                        color: const Color(0xFF2E0305),
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
                  child: CoreOrb(
                    stage: stage,
                    shaderProgram: widget.shaderProgram,
                    energy: voiceService.isSpeaking ? 0.85 : 0.28,
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
          color: const Color(0xFF2E0305),
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
                  titleColor: const Color(0xFFFFA0A0),
                  body:
                      'Ativo: $activeProviderUsed • Chave protegida no Keystore Android',
                ),
                const SizedBox(height: 10),
                _TelemetryBox(
                  title: 'ATUALIZAÇÃO GITHUB:',
                  titleColor: const Color(0xFFA89698),
                  body:
                      'Versão instalada $installedVersion (${hasUpdate ? 'Nova release disponível' : 'Release verificado'})',
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
    final duressLabel =
        hasDuressPinConfigured ? 'Ativo (Modo Camuflado)' : 'Não configurado';
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
                  color: const Color(0xFF0A0002),
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
                      valueColor: const Color(0xFFFFA0A0),
                    ),
                    const SizedBox(height: 6),
                    _SecurityRow(
                      label: 'Estágio de Acesso:',
                      value: widget.gate.levelBadge,
                      valueColor: widget.gate.hasBiometricAccess
                          ? const Color(0xFF5CE69C)
                          : _rose,
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
                          ? const Color(0xFFFFA0A0)
                          : const Color(0xFFA89698),
                    ),
                    const SizedBox(height: 6),
                    _SecurityRow(
                      label: 'Chaves NFC (Nível 2):',
                      value: nfcTags.isEmpty
                          ? 'Nenhuma cadastrada'
                          : '${nfcTags.length} tag(s) ativa(s)',
                      valueColor: nfcTags.isNotEmpty
                          ? const Color(0xFF5CE69C)
                          : const Color(0xFFA89698),
                    ),
                    const SizedBox(height: 6),
                    _SecurityRow(
                      label: 'Tentativas Falhas:',
                      value: '$authFailures',
                      valueColor: const Color(0xFFF0E6E7),
                    ),
                    if (!widget.gate.hasBiometricAccess) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _elevateSessionTo(
                            AccessLevel.sovereign,
                            'Eleve para Nível 2 (NFC) ou Nível 3 (Biometria).',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _rose,
                            side: const BorderSide(color: _crimson),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.upgrade, size: 15),
                          label: const Text(
                            'ELEVAR ESTÁGIO DE SESSÃO',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // NFC Key Configuration Card (Estágio 2)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E0305),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.nfc, size: 15, color: _rose),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'CHAVE FÍSICA NFC (NÍVEL 2) & REGRAS DOS 3 ESTÁGIOS',
                            style: TextStyle(
                              color: _rose,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '• Nível 1 (PIN): Ultron Base (chat, notas, hardware local).\n'
                      '• Nível 2 (NFC): libera WhatsApp/SMS/agenda/HTTP no celular (sem /pc e críticos).\n'
                      '• Nível 3 (Biometria): acesso total sem popup, só confirma críticos/autodestrutivos.',
                      style: TextStyle(
                        color: Color(0xFFA89698),
                        fontSize: 10,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SecurityRow(
                      label: 'Chip NFC Android:',
                      value: !nfcStatus.available
                          ? 'Indisponível neste aparelho'
                          : (nfcStatus.enabled
                              ? 'Ativo e pronto'
                              : 'Desativado nas configurações'),
                      valueColor: nfcStatus.enabled
                          ? const Color(0xFF5CE69C)
                          : const Color(0xFFFFA0A0),
                    ),
                    if (nfcStatus.available && !nfcStatus.enabled) ...[
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await NfcAuthService.instance.openNfcSettings();
                        },
                        icon: const Icon(Icons.settings, size: 14),
                        label: const Text(
                          'ATIVAR NFC NO ANDROID',
                          style: TextStyle(fontSize: 10),
                        ),
                      ),
                    ],
                    if (nfcTags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      for (final tag in nfcTags)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.vpn_key_outlined,
                                size: 14,
                                color: _rose,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${tag.label} (****${tag.uidSuffix})',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Remover tag NFC',
                                onPressed: () async {
                                  final ok = await _elevateSessionTo(
                                    AccessLevel.sovereign,
                                    'Remover chave NFC exige Biometria (Nível 3).',
                                  );
                                  if (!ok) return;
                                  await widget.vault.removeNfcTag(tag.id);
                                  final updated =
                                      await widget.vault.listNfcTags();
                                  if (!mounted) return;
                                  setState(() => nfcTags = updated);
                                },
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 16,
                                  color: _rose,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _openNfcEnrollmentWizard,
                        style: FilledButton.styleFrom(
                          backgroundColor: _crimson,
                          foregroundColor: Colors.white,
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.nfc, size: 15),
                        label: const Text(
                          'CADASTRAR NOVA CHAVE NFC',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Duress PIN Configuration Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E0305),
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
                            final bioOk = await _elevateSessionTo(
                              AccessLevel.sovereign,
                              'Alterar o PIN de Coação exige Biometria (Nível 3).',
                            );
                            if (!bioOk || !mounted) return;
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
                              final errMsg =
                                  e is ArgumentError ? '${e.message}' : '$e';
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Erro no PIN de Coação: $errMsg',
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
                              final bioOk = await _elevateSessionTo(
                                AccessLevel.sovereign,
                                'Remover o PIN de Coação exige Biometria (Nível 3).',
                              );
                              if (!bioOk || !mounted) return;
                              await widget.vault.clearDuressPin();
                              if (!mounted) return;
                              setState(() => hasDuressPinConfigured = false);
                            },
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 16,
                              color: Color(0xFFFFA0A0),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Immutable Audit Log Card (P5)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E0305),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'LOG IMUTÁVEL DE AUDITORIA (SHA-256 • P5)',
                      style: TextStyle(
                        color: _crimson,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Cadeia criptográfica append-only de todas as ações sensíveis, Kill Switches, /pc e webhooks HTTP em Skills/*.md.',
                      style: TextStyle(
                        color: Color(0xFFA89698),
                        fontSize: 10,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          _setPanel(_ActivePanel.main);
                          unawaited(_runCommand(UltronCommand.audit, ''));
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _rose,
                          side: const BorderSide(color: _crimson),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon:
                            const Icon(Icons.verified_user_outlined, size: 15),
                        label: const Text(
                          'VERIFICAR CADEIA & LOGS (/audit)',
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

              // Remote PC Kill Switch Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E0305),
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
                            final bioOk = await _elevateSessionTo(
                              AccessLevel.sovereign,
                              'Alterar o endpoint do Kill Switch exige Biometria (Nível 3).',
                            );
                            if (!bioOk || !mounted) return;
                            try {
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
                            } catch (e) {
                              if (!mounted) return;
                              final msg =
                                  e is ArgumentError ? '${e.message}' : '$e';
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Endpoint inválido: $msg',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              );
                            }
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
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: pcLanSecretController,
                            obscureText: true,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: 'Chave secreta HMAC LAN (obrigatória)',
                              hintStyle: TextStyle(
                                color: Color(0xFF635355),
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        OutlinedButton(
                          onPressed: () async {
                            final bioOk = await _elevateSessionTo(
                              AccessLevel.sovereign,
                              'Salvar a chave HMAC LAN exige Biometria (Nível 3).',
                            );
                            if (!bioOk || !mounted) return;
                            await deviceService.savePcLanSecret(
                              pcLanSecretController.text,
                            );
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Chave HMAC LAN salva com segurança.',
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
                            'CHAVE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        OutlinedButton(
                          onPressed: () async {
                            final bioOk = await _elevateSessionTo(
                              AccessLevel.sovereign,
                              'Gerar nova chave HMAC LAN exige Biometria (Nível 3).',
                            );
                            if (!bioOk || !mounted) return;
                            final gen =
                                await deviceService.generatePcLanSecret();
                            pcLanSecretController.text = gen;
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Nova chave HMAC LAN gerada e salva.',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _rose,
                            side: const BorderSide(color: _border),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text(
                            'GERAR',
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
                          final ksBio = await _elevateSessionTo(
                            AccessLevel.sovereign,
                            'Disparar o Kill Switch exige Biometria (Nível 3) + confirmação.',
                          );
                          if (!ksBio || !mounted) return;
                          final sim = actionGate.simulate('KILL_SWITCH');
                          final confirmed = await _confirmActionGate(
                            title: '🚨 ${sim.description.toUpperCase()}',
                            message:
                                'Atenção Operador: ${sim.estimatedImpact} Alvo: ${sim.targetResource}. Confirmar execução tática?',
                            confirmText: 'DISPARAR KILL SWITCH',
                          );
                          if (!confirmed) {
                            await deviceService.recordAudit(
                              actor: 'OPERATOR',
                              action: 'KILL_SWITCH',
                              target: sim.targetResource,
                              status: 'DENIED',
                              detail:
                                  'Operador cancelou Kill Switch no painel Segurança',
                            );
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  '🚫 Kill Switch cancelado pelo Operador.',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            );
                            return;
                          }
                          String msg;
                          try {
                            msg = await deviceService.triggerPcKillSwitch(
                              reason: 'security_panel_panic',
                            );
                          } catch (e) {
                            msg = '⚠️ Erro no Kill Switch remoto: $e';
                          }
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
                          backgroundColor: const Color(0xFFE50914),
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
                  color: const Color(0xFF2E0305),
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
                        color: Color(0xFFFFA0A0),
                        fontSize: 10,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '✓ Isolação de Chaves de API no Keystore: Ativa',
                      style: TextStyle(
                        color: Color(0xFFFFA0A0),
                        fontSize: 10,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '✓ Exclusão de Backup em Nuvem (allowBackup=false): Ativa',
                      style: TextStyle(
                        color: Color(0xFFFFA0A0),
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
    final modelText =
        s != null ? '${s.deviceModel} • ${s.androidVersion}' : 'Android Node';

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
                  color: const Color(0xFF2E0305),
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
                                ? const Color(0xFFFFA0A0)
                                : const Color(0xFFE50914),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _CircularTelemetryGauge(
                            value: ramVal,
                            label: 'RAM',
                            subLabel: ramSub,
                            percentage: ramPct,
                            color: const Color(0xFFE50914),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _CircularTelemetryGauge(
                            value: '${batTemp.toInt()}°C',
                            label: 'TEMP',
                            subLabel: 'ESTÁVEL',
                            percentage: 0.35,
                            color: const Color(0xFFFFA0A0),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _CircularTelemetryGauge(
                            value: '92%',
                            label: netType,
                            subLabel: s?.ringerMode ?? 'ONLINE',
                            percentage: 0.92,
                            color: const Color(0xFFE50914),
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
                  color: const Color(0xFF0A0002),
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
                      valueColor: const Color(0xFFFFA0A0),
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
                          ? const Color(0xFFFFA0A0)
                          : const Color(0xFFA89698),
                    ),
                    const SizedBox(height: 4),
                    const _SecurityRow(
                      label: 'Flip-to-Shush (Acelerômetro):',
                      value: 'ATIVO (Virar tela p/ baixo silencia)',
                      valueColor: Color(0xFFFFA0A0),
                    ),
                    const SizedBox(height: 4),
                    _SecurityRow(
                      label: 'Modo Foco Noturno:',
                      value:
                          nightFocusMode ? 'ATIVO (Sussurro TTS)' : 'INATIVO',
                      valueColor: nightFocusMode
                          ? const Color(0xFFFFA0A0)
                          : const Color(0xFFA89698),
                    ),
                    const SizedBox(height: 4),
                    _SecurityRow(
                      label: 'Sentinela de Voz (escuta contínua):',
                      value: ecoVadSentinelRunning
                          ? 'ATIVO (VAD adaptativo)'
                          : 'EM REPOUSO',
                      valueColor: ecoVadSentinelRunning
                          ? const Color(0xFFFFA0A0)
                          : const Color(0xFFA89698),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _setOfflineSentinelEnabled(
                              !ecoVadSentinelRunning,
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: ecoVadSentinelRunning
                                  ? const Color(0xFFE50914)
                                  : const Color(0xFF2E0305),
                              foregroundColor: ecoVadSentinelRunning
                                  ? const Color(0xFFFFA0A0)
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
                                      : const Color(0xFF2E0305),
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
                            backgroundColor: const Color(0xFF2E0305),
                            foregroundColor: const Color(0xFFFFA0A0),
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
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _openVoiceSelector,
                        style: OutlinedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E0305),
                          foregroundColor: _rose,
                          side: const BorderSide(color: _crimson),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.record_voice_over, size: 14),
                        label: Text(
                          'TROCAR VOZ NO APARELHO (${voiceService.activeVoiceLabel})',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 1. Agenda & Briefing Matinal (P4)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E0305),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _crimson.withValues(alpha: 0.45),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '📅 AGENDA ANDROID & BRIEFING MATINAL (P4)',
                      style: TextStyle(
                        color: _crimson,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              _setPanel(_ActivePanel.main);
                              unawaited(
                                  _runCommand(UltronCommand.calendar, 'hoje'));
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _rose,
                              side: BorderSide(
                                color: _crimson.withValues(alpha: 0.5),
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.calendar_today, size: 13),
                            label: const Text(
                              'AGENDA HOJE',
                              style: TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () {
                              _setPanel(_ActivePanel.main);
                              unawaited(_runMorningBriefing());
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: _crimson,
                              foregroundColor: const Color(0xFFF0E6E7),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.wb_sunny_outlined, size: 14),
                            label: const Text(
                              'BRIEFING',
                              style: TextStyle(
                                fontSize: 10,
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

              // 1A. Sentinela de Mensagens & Comunicação Autônoma (500x)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E0305),
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
                                ? const Color(0xFFE50914)
                                : const Color(0xFF2E0305),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            notificationSentinelEnabled
                                ? 'SENTINELA ATIVO'
                                : 'PERMISSÃO PENDENTE',
                            style: TextStyle(
                              color: notificationSentinelEnabled
                                  ? const Color(0xFFFFA0A0)
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
                              color: const Color(0xFF0A0002),
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
                                        color: const Color(0xFF2E0305),
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
                              backgroundColor: const Color(0xFF2E0305),
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
                  color: const Color(0xFF2E0305),
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
                            final opened =
                                await deviceService.openObsidianVault();
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
                            padding: EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
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
                        torchOn ? const Color(0xFFFFA0A0) : _crimson,
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
                  color: const Color(0xFF2E0305),
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
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _StageChip(
                          label: 'ANTERIOR',
                          icon: Icons.skip_previous,
                          onTap: () => deviceService.controlMedia('previous'),
                        ),
                        _StageChip(
                          label: 'PLAY/PAUSE',
                          icon: Icons.play_arrow,
                          onTap: () => deviceService.controlMedia('play_pause'),
                        ),
                        _StageChip(
                          label: 'PARAR',
                          icon: Icons.stop,
                          onTap: () => deviceService.controlMedia('stop'),
                        ),
                        _StageChip(
                          label: 'PRÓXIMA',
                          icon: Icons.skip_next,
                          onTap: () => deviceService.controlMedia('next'),
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
              backgroundColor: const Color(0xFF2E0305),
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
        backgroundColor: const Color(0xFF2E0305),
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
                    colors: [Color(0xFF2E0305), Color(0xFF0A0002)],
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
                            color: const Color(0xFFE50914),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFFFA0A0)),
                          ),
                          child: const Text(
                            'ZERO-KEY NATIVO',
                            style: TextStyle(
                              color: Color(0xFFFFA0A0),
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
                    color: const Color(0xFF0A0002),
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
                                        ? const Color(0xFF2E0305)
                                        : const Color(0xFFE50914),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    preset.badge,
                                    style: TextStyle(
                                      color: preset.requiresKey
                                          ? _rose
                                          : const Color(0xFFFFA0A0),
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
                  desc: 'Controla o volume de mídia do Android de 0% a 100%.',
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
                backgroundColor: const Color(0xFF2E0305),
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
            color: selected ? const Color(0xFFE50914) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              color:
                  selected ? const Color(0xFFF0E6E7) : const Color(0xFFA89698),
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
            color: const Color(0xFF2E0305),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF51080D)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: const Color(0xFFFFA0A0)),
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
            color: const Color(0xFF2E0305),
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
                  color: Color(0xFFFFA0A0),
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
          color: const Color(0xFF2E0305),
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
          color: const Color(0xFF2E0305),
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
                    ? const Color(0xFFFFA0A0)
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
        color: const Color(0xFF2E0305),
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
