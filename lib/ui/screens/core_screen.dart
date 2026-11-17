import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/chat_message.dart';
import '../../core/security/auth_gate.dart';
import '../../core/security/pin_vault.dart';
import '../../services/conversation_history.dart';
import '../../services/ai_provider_service.dart';
import '../../services/android_actions_service.dart';
import '../../services/app_update_service.dart';
import '../../services/audio_capture_service.dart';
import '../../services/desktop_pairing_service.dart';
import '../../services/slash_command_parser.dart';
import '../../services/stt_service.dart';
import '../../services/voice_corrections_service.dart';
import '../../services/voice_pipeline_controller.dart';
import '../../services/voice_service.dart';
import '../../services/voice_shortcuts_service.dart';
import '../widgets/action_confirmation_dialog.dart';
import '../widgets/core_orb.dart';
import 'ai_settings_screen.dart';
import 'conversation_history_screen.dart';
import 'desktop_pairing_screen.dart';
import 'memory_settings_screen.dart';
import 'update_screen.dart';

export '../widgets/core_orb.dart' show CoreOrb, CorePainter, CoreStage;

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
  final commandController = TextEditingController();
  CoreStage stage = CoreStage.center;
  bool sending = false;
  bool hasUpdate = false;
  late final VoiceService voiceService;
  final updateService = AppUpdateService();
  late final VoicePipelineController voicePipeline;
  late final AndroidActionsService androidActions;
  final desktopPairing = DesktopPairingService();
  late AppLifecycleState _lifecycleState;

  bool get _isForegroundActive =>
      _lifecycleState == AppLifecycleState.resumed &&
      widget.gate.isAuthenticated;

  @override
  void initState() {
    super.initState();
    _lifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    voiceService = widget.voiceService ?? VoiceService();
    androidActions = AndroidActionsService(gate: widget.gate);
    voicePipeline = VoicePipelineController(
      gate: widget.gate,
      capture: widget.captureSource ?? MethodChannelAudioCaptureSource(),
      stt: widget.sttService ?? GroqWhisperSttService(),
      voiceService: voiceService,
      corrections: VoiceCorrectionsService(),
      shortcuts: VoiceShortcutsService(),
      onConfirmShortcut: _confirmShortcut,
      onExecuteShortcut: _executeShortcut,
      onTranscript: _handleVoiceTranscript,
    )..addListener(_onVoicePipelineChanged);
    voicePipeline.handleLifecycleState(_lifecycleState);
    unawaited(voiceService.initialize().catchError((_) {}));
    if (widget.announceOnline && _isForegroundActive) {
      unawaited(
        voiceService.speak(widget.onlineAnnouncement).catchError((_) {}),
      );
    }
    _checkUpdate();
    unawaited(_consumePendingTileAction());
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
      // Desktop VM tests and non-Android hosts have no android_actions channel.
      return false;
    }
  }

  void _onVoicePipelineChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _handleVoiceTranscript(String transcript) async {
    if (!mounted || sending) return;
    await _submitText(transcript);
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
        await _showSecurity();
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

  /// Silent, best effort: only paints a dot on the update button.
  Future<void> _checkUpdate() async {
    try {
      final latest = await updateService.check();
      if (latest == null || !mounted) return;
      final installed = await updateService.currentVersion();
      if (!mounted) return;
      setState(() => hasUpdate = AppUpdateService.isNewer(latest.version, installed));
    } catch (_) {
      // Offline or rate limited: the update screen reports details on demand.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    voicePipeline.handleLifecycleState(state);
    if (state != AppLifecycleState.resumed) {
      voiceService.stop();
    } else {
      unawaited(_consumePendingTileAction());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    voicePipeline.removeListener(_onVoicePipelineChanged);
    voicePipeline.dispose();
    voiceService.stop();
    commandController.dispose();
    super.dispose();
  }

  void nextStage() => setState(() {
        stage = CoreStage.values[(stage.index + 1) % CoreStage.values.length];
      });

  Future<void> saveCommand() async {
    if (sending) return;
    final text = commandController.text.trim();
    if (text.isEmpty) return;
    commandController.clear();
    await _submitText(text);
  }

  Future<void> _submitText(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || sending) return;
    final command = SlashCommandParser.parse(text);
    if (command != null) {
      await _runCommand(command.command);
      return;
    }
    if (text.startsWith('/')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Comando desconhecido. Use /help.')),
      );
      return;
    }

    setState(() => sending = true);

    try {
      final now = DateTime.now();
      final previousMessages = await ConversationHistory.instance.messages(
        conversationId: 'default',
        limit: 12,
      );
      final aiHistory = previousMessages
          .where((message) =>
              message.role == ChatRole.user ||
              message.role == ChatRole.assistant)
          .map((message) => <String, String>{
                'role': message.role.name,
                'content': message.content,
              })
          .toList();

      await ConversationHistory.instance.save(ChatMessage(
        id: null,
        conversationId: 'default',
        role: ChatRole.user,
        content: text,
        createdAt: now,
      ));
      final reply = await AiFailover().ask(text, history: aiHistory);
      await ConversationHistory.instance.save(ChatMessage(
        id: null,
        conversationId: 'default',
        role: ChatRole.assistant,
        content: reply.text,
        createdAt: DateTime.now(),
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Resposta recebida de ${reply.provider}. Consulte o histórico.')),
      );
      if (_isForegroundActive) {
        unawaited(voiceService.speak(reply.text).catchError((_) {}));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível concluir o comando: $error')),
      );
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _runCommand(UltronCommand command) async {
    switch (command) {
      case UltronCommand.help:
        await showDialog<void>(context: context, builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF160509),
          title: const Text('COMANDOS U.L.T.R.O.N.'),
          content: const SingleChildScrollView(child: Text(
            '/help     Exibe esta lista\n'
            '/security  Abre o painel de segurança\n'
            '/history   Abre o histórico local\n'
            '/memory    Abre memória, correções e atalhos\n'
            '/desktop   Pareamento LAN e ações Android\n'
            '/settings  Configurações de IA\n\n'
            'Comandos são interpretados localmente.',
          )),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('FECHAR'))],
        ));
        break;
      case UltronCommand.security:
        await _showSecurity();
        break;
      case UltronCommand.history:
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConversationHistoryScreen()));
        break;
      case UltronCommand.memory:
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MemorySettingsScreen()));
        break;
      case UltronCommand.desktop:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DesktopPairingScreen(
              pairingService: desktopPairing,
              actionsService: androidActions,
            ),
          ),
        );
        break;
      case UltronCommand.settings:
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AiSettingsScreen()));
        break;
    }
  }

  Future<void> _showSecurity() async {
    bool? hasPin;
    try {
      hasPin = await widget.vault.hasPin;
    } catch (_) {
      hasPin = null;
    }
    if (!mounted) return;
    final pinLabel = hasPin == null
        ? 'indisponível'
        : hasPin
            ? 'configurado'
            : 'não configurado';
    final lock = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF160509),
        title: const Text('SEGURANÇA'),
        content: Text(
          'Sessão autenticada: ${widget.gate.isAuthenticated ? 'sim' : 'não'}\n'
          'PIN: $pinLabel\n'
          'Bloqueio: ao iniciar o app e ao tocar em BLOQUEAR\n\n'
          'Conversas e comandos ficam no aparelho. Chaves de IA ficam no armazenamento seguro do Android.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('FECHAR')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('BLOQUEAR')),
        ],
      ),
    );
    if (lock == true) widget.gate.lock();
  }

  Future<void> _toggleContinuousListening() async {
    HapticFeedback.selectionClick();
    if (voicePipeline.isContinuousEnabled) {
      await voicePipeline.stopContinuousListening();
      return;
    }
    final ok = await voicePipeline.startContinuousListening();
    if (!mounted || ok || voicePipeline.lastError == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(voicePipeline.lastError!)),
    );
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

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF0A0002),
        body: SafeArea(
          child: Stack(
            children: [
              if (stage != CoreStage.hidden)
                Align(
                  alignment: stage == CoreStage.center
                      ? Alignment.center
                      : const Alignment(0.88, -0.68),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      if (voiceService.isSpeaking) {
                        voiceService.stop();
                      } else {
                        nextStage();
                      }
                    },
                    child: SizedBox(
                      width: stage == CoreStage.center ? 280 : 90,
                      height: stage == CoreStage.center ? 280 : 90,
                      child: CoreOrb(
                        stage: stage,
                        shaderProgram: widget.shaderProgram,
                        energy: voiceService.isSpeaking
                            ? 0.9
                            : voicePipeline.isCapturing
                                ? 0.7
                                : sending
                                    ? 0.55
                                    : 0.2,
                      ),
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(left: 8, right: 4),
                        child: Text(
                          'U.L.T.R.O.N.',
                          style: TextStyle(
                            color: Color(0xFFE50914),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: hasUpdate
                                      ? 'Atualização disponível'
                                      : 'Atualizar U.L.T.R.O.N.',
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) => const UpdateScreen()),
                                  ),
                                  icon: Badge(
                                    isLabelVisible: hasUpdate,
                                    child: const Icon(Icons.system_update,
                                        color: Color(0xFFE50914)),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Configurações de IA',
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const AiSettingsScreen(),
                                    ),
                                  ),
                                  icon: const Icon(Icons.settings,
                                      color: Color(0xFFE50914)),
                                ),
                                IconButton(
                                  tooltip: 'Histórico',
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const ConversationHistoryScreen(),
                                    ),
                                  ),
                                  icon: const Icon(Icons.history,
                                      color: Color(0xFFE50914)),
                                ),
                                IconButton(
                                  tooltip: 'Memória & Voz',
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const MemorySettingsScreen(),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.psychology_alt_outlined,
                                    color: Color(0xFFE50914),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Desktop LAN & Ações Android',
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => DesktopPairingScreen(
                                        pairingService: desktopPairing,
                                        actionsService: androidActions,
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.devices_other,
                                    color: Color(0xFFE50914),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Alterar posição do núcleo',
                                  onPressed: nextStage,
                                  icon: const Icon(Icons.crop_free,
                                      color: Color(0xFFE50914)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: commandController,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => saveCommand(),
                          decoration: InputDecoration(
                            hintText: sending ? 'U.L.T.R.O.N. processando…' : 'Comando…',
                          ),
                          enabled: !sending,
                        ),
                      ),
                      IconButton(
                        tooltip: voicePipeline.isContinuousEnabled
                            ? 'Desativar escuta contínua'
                            : 'Ativar escuta contínua',
                        onPressed: _toggleContinuousListening,
                        icon: Icon(
                          voicePipeline.isContinuousEnabled
                              ? Icons.hearing
                              : Icons.hearing_disabled,
                          color: voicePipeline.isContinuousEnabled
                              ? const Color(0xFFFF4D57)
                              : const Color(0xFF993036),
                        ),
                      ),
                      GestureDetector(
                        onLongPressStart: (_) async {
                          HapticFeedback.mediumImpact();
                          await voicePipeline.startPushToTalk();
                        },
                        onLongPressEnd: (_) async {
                          await voicePipeline.stopPushToTalk();
                        },
                        onLongPressCancel: () async {
                          await voicePipeline.stopPushToTalk();
                        },
                        child: IconButton(
                          tooltip: voicePipeline.isPushToTalkActive
                              ? 'Solte ou toque para enviar fala'
                              : 'Segure para falar (Push-to-Talk)',
                          onPressed: _togglePushToTalk,
                          icon: Icon(
                            voicePipeline.isPushToTalkActive
                                ? Icons.mic_none
                                : Icons.mic,
                            color: voicePipeline.isPushToTalkActive
                                ? const Color(0xFFFF6B73)
                                : const Color(0xFFE50914),
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
      );
}
