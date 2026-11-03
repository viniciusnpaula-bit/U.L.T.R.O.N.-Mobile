import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/security/auth_gate.dart';
import '../../core/security/pin_vault.dart';
import '../../models/chat_message.dart';
import '../../services/ai_provider_service.dart';
import '../../services/app_update_service.dart';
import '../../services/conversation_history.dart';
import '../../services/slash_command_parser.dart';
import '../../services/voice_service.dart';
import 'ai_settings_screen.dart';
import 'conversation_history_screen.dart';
import 'update_screen.dart';

enum CoreStage { center, corner, hidden }

enum _ActivePanel { main, security, help }

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
  static const _crimson = Color(0xFFFF1A24);
  static const _rose = Color(0xFFFF8088);
  static const _border = Color(0xFF2E0306);

  late final Ticker ticker;
  final commandController = TextEditingController();
  final scrollController = ScrollController();
  final coreTime = ValueNotifier<double>(0);
  final voiceService = VoiceService();
  final updateService = AppUpdateService();
  final providerStore = AiProviderStore();

  CoreStage stage = CoreStage.center;
  _ActivePanel panel = _ActivePanel.main;
  bool active = false;
  bool sending = false;
  bool hasUpdate = false;
  bool isAudioOn = true;
  String activeProviderUsed = 'Failover Pronto';
  String installedVersion = 'v0.4.0';
  int authFailures = 0;
  bool? hasPinConfigured;

  static const _defaultFeed = <_FeedEntry>[
    _FeedEntry(
      isUser: false,
      senderLabel: 'Kernel Local',
      text:
          'U.L.T.R.O.N. Mobile online. Failover de provedores ativo. Digite comandos ou /help.',
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
    _loadInitialState();
    _checkUpdate();
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
      if (!mounted) return;
      setState(() {
        authFailures = failures;
        hasPinConfigured = pinSet;
        activeProviderUsed = enabledProviders.isNotEmpty
            ? enabledProviders.first.name
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
      _scrollToBottom();
    } catch (_) {}
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
    }
    _syncTickerWithState(lifecycle: state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ticker.dispose();
    coreTime.dispose();
    voiceService.stop();
    commandController.dispose();
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
              'Comando desconhecido: "$text". Use /help para ver os comandos rápidos disponíveis.',
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

    // 3. AI Conversation + Failover
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
      final reply = await AiFailover(store: providerStore).ask(
        text,
        history: aiHistory,
      );
      final replyNow = DateTime.now();
      await ConversationHistory.instance.save(
        ChatMessage(
          id: null,
          conversationId: 'default',
          role: ChatRole.assistant,
          content: reply.text,
          createdAt: replyNow,
        ),
      );
      if (!mounted) return;
      setState(() => activeProviderUsed = reply.provider);
      _appendFeed(
        _FeedEntry(
          isUser: false,
          senderLabel: reply.provider,
          text: reply.text,
          timestamp: _formatTime(replyNow),
        ),
      );
      await voiceService.speak(reply.text);
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

  Future<void> _runCommand(
    UltronCommand command, [
    String argument = '',
  ]) async {
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
        if (!mounted) return;
        setState(() {
          authFailures = failures;
          hasPinConfigured = pinSet;
        });
        _setPanel(_ActivePanel.security);
        break;
      case UltronCommand.history:
        await _openHistory();
        break;
      case UltronCommand.settings:
        await _openSettings();
        break;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
                    color: const Color(0xCC0C0003),
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
                            label: 'CONFIG',
                            selected: false,
                            onTap: _openSettings,
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
                                    : const Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Main Screen Content (Main / Security / Help)
                Expanded(
                  child: switch (panel) {
                    _ActivePanel.main => _buildMainPanel(),
                    _ActivePanel.security => _buildSecurityPanel(),
                    _ActivePanel.help => _buildHelpPanel(),
                  },
                ),
              ],
            ),
          ),
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
                          color: const Color(0xFF200004),
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
                          color: Color(0xFF94A3B8),
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
                      tooltip: 'Comandos Rápidos (/help)',
                      onPressed: () => _setPanel(_ActivePanel.help),
                      icon: const Icon(
                        Icons.help_outline,
                        size: 16,
                        color: Color(0xFF94A3B8),
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
                        color: Color(0xFF94A3B8),
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
                          color: Color(0xFF94A3B8),
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
                        color: Color(0xFFF43F5E),
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
              color: const Color(0xFF120003),
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
                      color: Color(0xFFE2E8F0),
                      fontSize: 12,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: sending
                          ? 'Consultando provedor ativo…'
                          : 'Digite /help, /settings, palco ou fale...',
                      hintStyle: const TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 11,
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
                      color: const Color(0xFF200004),
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
                        intensity: sending ? 2.2 : 1.0,
                      ),
                    ),
                  ),
                ),
              ),
              const Text(
                'U.L.T.R.O.N. CORE',
                style: TextStyle(
                  color: _rose,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.5,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Voz Nativa TTS • Pitch: 0.55 • Failover Pronto',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 9,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _StageChip(
                    label: 'MODO PALCO',
                    icon: Icons.picture_in_picture_alt_outlined,
                    onTap: () => _setStage(CoreStage.corner),
                  ),
                  const SizedBox(width: 8),
                  _StageChip(
                    label: 'TELA CHEIA',
                    icon: Icons.open_in_full,
                    onTap: () => _setStage(CoreStage.hidden),
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
                            ? const Color(0xFF180004)
                            : const Color(0xFF0F0003),
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
                                  color: Color(0xFF64748B),
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
                                  ? const Color(0xFFE2E8F0)
                                  : const Color(0xFFCBD5E1),
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
                color: const Color(0xFF0F0003),
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
                                  color: Color(0xFF94A3B8),
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
                                  color: Color(0xFF94A3B8),
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
                      color: Color(0xFFE2E8F0),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'O Palco isola documentos e saídas sem abrir novas janelas. Toque nos comandos rápidos abaixo para executar localmente:',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
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
                        color: const Color(0xFF180004),
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
                              color: Color(0xFFE2E8F0),
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
                  color: Color(0xFF64748B),
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
          color: const Color(0xFF0E0002),
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
                          color: Color(0xFF94A3B8),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'REDUZIR',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
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
                  titleColor: const Color(0xFF34D399),
                  body:
                      'Ativo: $activeProviderUsed • Chave protegida no Keystore Android',
                ),
                const SizedBox(height: 10),
                _TelemetryBox(
                  title: 'ATUALIZAÇÃO GITHUB:',
                  titleColor: const Color(0xFF94A3B8),
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
                  foregroundColor: Colors.black,
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
                  color: const Color(0xFF0F0003),
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
                      valueColor: const Color(0xFF34D399),
                    ),
                    const SizedBox(height: 6),
                    const _SecurityRow(
                      label: 'Nível de Restrição:',
                      value: 'Nível 02 (-2 Níveis Ativo)',
                      valueColor: _rose,
                    ),
                    const SizedBox(height: 6),
                    _SecurityRow(
                      label: 'Cofre de PIN:',
                      value: pinLabel,
                      valueColor: const Color(0xFFCBD5E1),
                    ),
                    const SizedBox(height: 6),
                    _SecurityRow(
                      label: 'Tentativas Falhas:',
                      value: '$authFailures',
                      valueColor: const Color(0xFFCBD5E1),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0E0002),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'POLÍTICAS LOCAIS FAIL-CLOSED',
                      style: TextStyle(
                        color: Color(0xFFE2E8F0),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Nenhuma ordem da IA sobrepõe a validação do dispositivo. O comando /security audita e bloqueia privilégios a qualquer momento.',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10,
                        height: 1.4,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '✓ Cifragem PBKDF2-HMAC-SHA256 (120k iter): Ativa',
                      style: TextStyle(
                        color: Color(0xFF34D399),
                        fontSize: 10,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '✓ Isolação de Chaves de API no Keystore: Ativa',
                      style: TextStyle(
                        color: Color(0xFF34D399),
                        fontSize: 10,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '✓ Exclusão de Backup em Nuvem (allowBackup=false): Ativa',
                      style: TextStyle(
                        color: Color(0xFF34D399),
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
              foregroundColor: Colors.black,
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
                  'Comandos rápidos executados localmente sem gastar tokens:',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 10,
                  ),
                ),
                SizedBox(height: 8),
                _HelpSyntaxItem(
                  cmd: '/help',
                  desc: 'Abre este manual rápido com a lista de comandos.',
                  highlight: true,
                ),
                _HelpSyntaxItem(
                  cmd: '/security | /security lock',
                  desc:
                      'Exibe a auditoria do AuthGate ou trava a sessão imediatamente.',
                  highlight: true,
                ),
                _HelpSyntaxItem(
                  cmd: '/history',
                  desc:
                      'Abre a lista de conversas salvas localmente no dispositivo.',
                  highlight: true,
                ),
                _HelpSyntaxItem(
                  cmd: '/settings',
                  desc:
                      'Configuração de IA, chaves, failover e releases do GitHub.',
                  highlight: true,
                ),
                _HelpSyntaxItem(
                  cmd: 'palco | mostrar documento',
                  desc:
                      'Transiciona para o Modo Palco, encolhendo o núcleo para o canto.',
                  highlight: false,
                ),
                _HelpSyntaxItem(
                  cmd: 'tela cheia | expandir',
                  desc:
                      'Oculta o núcleo e libera visualização total com economia de GPU.',
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
                backgroundColor: const Color(0xFF1E0004),
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
            color: selected ? const Color(0xFFFF1A24) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : const Color(0xFF94A3B8),
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
            color: const Color(0xFF140003),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2E0306)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: const Color(0xFFFF8088)),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFCBD5E1),
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
            color: const Color(0xFF180004),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2E0306)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                command,
                style: const TextStyle(
                  color: Color(0xFFFF1A24),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
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
          color: const Color(0x99000000),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2E0306)),
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
                color: Color(0xFFCBD5E1),
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
              color: Color(0xFF94A3B8),
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
          color: const Color(0xFF0E0002),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2E0306)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cmd,
              style: TextStyle(
                color: highlight
                    ? const Color(0xFFFF1A24)
                    : const Color(0xFFE2E8F0),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              desc,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
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
      Color(0xE6FF1A24),
      Color(0x73AA0812),
      Color(0x40320205),
      Color(0x000A0002),
    ],
    stops: [0.0, 0.35, 0.70, 1.0],
  );

  static const _hotspotGradient = RadialGradient(
    colors: [
      Color(0xFFFFFFFF),
      Color(0xFFFF9098),
      Color(0xFFFF1A24),
      Color(0x00FF1A24),
    ],
    stops: [0.0, 0.28, 0.70, 1.0],
  );

  static final _ring1Paint = Paint()
    ..color = const Color(0xBFFF1A24)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.8;

  static final _nodePaint = Paint()..color = const Color(0xFFFF2B37);

  static final _ring2Paint = Paint()
    ..color = const Color(0x80FF3C46)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.3;

  static final _majorTickPaint = Paint()..color = const Color(0xFFFF1A24);
  static final _minorTickPaint = Paint()..color = const Color(0x59FF5050);

  static final _hexPaint = Paint()
    ..color = const Color(0xBFFF6E78)
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
