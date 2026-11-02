import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../models/chat_message.dart';
import '../../services/conversation_history.dart';
import 'ai_settings_screen.dart';
import 'conversation_history_screen.dart';

enum CoreStage { center, corner, hidden }

class CoreScreen extends StatefulWidget {
  const CoreScreen({super.key});

  @override
  State<CoreScreen> createState() => _CoreScreenState();
}

class _CoreScreenState extends State<CoreScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker ticker;
  final commandController = TextEditingController();
  Duration elapsed = Duration.zero;
  CoreStage stage = CoreStage.center;
  bool active = false;


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ticker = createTicker((duration) {
      elapsed = duration;
      if (mounted) setState(() {});
    });
    ticker.start();
    active = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!active) {
        ticker.start();
        active = true;
      }
    } else if (active) {
      ticker.stop();
      active = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ticker.dispose();
    commandController.dispose();
    super.dispose();
  }

  void nextStage() => setState(() {
        stage = CoreStage.values[(stage.index + 1) % CoreStage.values.length];
      });

  Future<void> saveCommand() async {
    final text = commandController.text.trim();
    if (text.isEmpty) return;
    await ConversationHistory.instance.save(ChatMessage(
      id: null,
      conversationId: 'default',
      role: ChatRole.user,
      content: text,
      createdAt: DateTime.now(),
    ));
    if (!mounted) return;
    commandController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mensagem salva no histórico local.')),
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
                      : const Alignment(0.82, -0.82),
                  child: SizedBox(
                    width: stage == CoreStage.center ? 280 : 90,
                    height: stage == CoreStage.center ? 280 : 90,
                    child: CustomPaint(
                      painter: CorePainter(elapsed.inMilliseconds / 1000),
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
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
                            builder: (_) => const ConversationHistoryScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.history, color: Color(0xFFE50914)),
                      ),
                      Expanded(
                        child: TextField(
                          controller: commandController,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => saveCommand(),
                          decoration: const InputDecoration(hintText: 'Comando…'),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Alterar posição do núcleo',
                        onPressed: nextStage,
                        icon: const Icon(Icons.crop_free,
                            color: Color(0xFFE50914)),
                      ),
                      IconButton(
                        tooltip: 'Microfone (em breve)',
                        onPressed: () => HapticFeedback.lightImpact(),
                        icon: const Icon(Icons.mic, color: Color(0xFFE50914)),
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

class CorePainter extends CustomPainter {
  CorePainter(this.time);
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE50914)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final center = size.center(Offset.zero);
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(center, size.shortestSide * (0.22 + i * 0.12), paint);
    }
    canvas.drawCircle(
      center,
      size.shortestSide * 0.07,
      Paint()..color = const Color(0xFFFF1A24),
    );
  }

  @override
  bool shouldRepaint(covariant CorePainter oldDelegate) =>
      oldDelegate.time != time;
}
