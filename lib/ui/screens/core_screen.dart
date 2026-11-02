import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../services/ai_service.dart';
import '../../services/command_router.dart';
import '../../services/voice_service.dart';
import 'ai_settings_screen.dart';

enum CoreStage { center, corner, hidden }

class CoreScreen extends StatefulWidget {
  const CoreScreen({super.key});

  @override
  State<CoreScreen> createState() => _CoreScreenState();
}

class _CoreScreenState extends State<CoreScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker ticker;
  final command = TextEditingController();
  final scroll = ScrollController();
  final ai = AiService();
  const router = CommandRouter();
  final voice = VoiceService();
  final speech = stt.SpeechToText();
  Duration elapsed = Duration.zero;
  CoreStage stage = CoreStage.center;
  bool active = false;
  bool listening = false;
  bool busy = false;
  bool speechReady = false;
  String status = 'Aguardando comando';
  final List<String> messages = [];

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
    voice.initialize().catchError((_) {});
    speech
        .initialize(
      onStatus: (value) {
        if (mounted) {
          setState(() {
            listening = value == 'listening';
            status = listening
                ? 'Ouvindo…'
                : (busy ? 'Processando…' : 'Aguardando comando');
          });
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            listening = false;
            status = 'Erro de voz: ${error.errorMsg}';
          });
        }
      },
    )
        .then((ready) {
      if (mounted) {
        setState(() => speechReady = ready);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!active) {
        ticker.start();
        active = true;
      }
    } else {
      if (active) {
        ticker.stop();
        active = false;
      }
      if (listening) speech.stop();
      voice.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ticker.dispose();
    command.dispose();
    scroll.dispose();
    speech.stop();
    voice.stop();
    super.dispose();
  }

  static const updateChannel = MethodChannel('ultron.mobile/update');

  Future<void> openUpdates() async {
    try {
      await updateChannel.invokeMethod<bool>('openReleases');
      if (mounted) {
        setState(() => status = 'Página de atualizações aberta.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => status = 'Não foi possível abrir atualizações: $e');
      }
    }
  }

  Future<void> send() async {
    final text = command.text.trim();
    if (text.isEmpty || busy) return;
    command.clear();
    setState(() {
      busy = true;
      status = 'Processando…';
      messages.add('VOCÊ: $text');
    });
    try {
      final result = await router.route(
        text,
        askAi: ai.ask,
        openAiSettings: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => AiSettingsScreen(service: ai)),
          );
        },
        statusSummary: 'Diagnóstico básico disponível em /status.',
        clearHistory: () => messages.clear(),
      );
      if (!mounted) return;
      setState(() {
        messages.add('U.L.T.R.O.N.: ${result.message}');
        status = result.handled ? 'Aguardando comando' : 'Erro';
      });
      if (result.intent == CommandIntent.ai && result.handled) {
        await voice.speak(result.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          messages.add('ERRO: $e');
          status = 'Erro';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
      if (mounted && scroll.hasClients) {
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    }
  }

  Future<void> toggleVoice() async {
    if (listening) {
      await speech.stop();
      if (mounted) {
        setState(() {
          listening = false;
          status = 'Aguardando comando';
        });
      }
      return;
    }
    if (!speechReady) {
      setState(() => status = 'Reconhecimento de voz indisponível neste dispositivo.');
      return;
    }
    try {
      setState(() => status = 'Ouvindo…');
      await speech.listen(
        listenOptions: stt.SpeechListenOptions(localeId: 'pt_BR'),
        onResult: (result) {
          if (!mounted) return;
          setState(() => command.text = result.recognizedWords);
          if (result.finalResult) {
            setState(() {
              listening = false;
              status = 'Texto reconhecido';
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => status = 'Microfone indisponível: $e');
      }
    }
  }

  void nextStage() => setState(
        () => stage =
            CoreStage.values[(stage.index + 1) % CoreStage.values.length],
      );

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFE50914);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0002),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E0305),
        title: const Text('U.L.T.R.O.N.'),
        actions: [
          IconButton(
            tooltip: 'Configurações de IA',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AiSettingsScreen(service: ai),
              ),
            ),
            icon: const Icon(Icons.settings, color: red),
          ),
          IconButton(
            tooltip: 'Atualizar U.L.T.R.O.N.',
            onPressed: openUpdates,
            icon: const Icon(Icons.system_update, color: red),
          ),
          IconButton(
            tooltip: 'Posição do núcleo',
            onPressed: nextStage,
            icon: const Icon(Icons.crop_free, color: red),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (stage != CoreStage.hidden)
              SizedBox(
                height: stage == CoreStage.center ? 230 : 100,
                child: Align(
                  alignment: stage == CoreStage.center
                      ? Alignment.center
                      : Alignment.topRight,
                  child: SizedBox(
                    width: stage == CoreStage.center ? 220 : 90,
                    height: stage == CoreStage.center ? 220 : 90,
                    child: CustomPaint(
                      painter: CorePainter(elapsed.inMilliseconds / 1000),
                    ),
                  ),
                ),
              ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '● $status',
                style: TextStyle(
                  color: status == 'Erro'
                      ? Colors.orangeAccent
                      : const Color(0xFFFFA0A0),
                ),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.all(16),
                children: messages
                    .map(
                      (m) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SelectableText(
                          m,
                          style: TextStyle(
                            color: m.startsWith('ERRO')
                                ? Colors.orangeAccent
                                : Colors.white,
                            height: 1.4,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: command,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => send(),
                      decoration: const InputDecoration(
                        hintText: 'Comando…',
                        filled: true,
                        fillColor: Color(0xFF2E0305),
                        border: OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: red),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: listening ? 'Parar microfone' : 'Reconhecimento de voz',
                    onPressed: toggleVoice,
                    icon: Icon(
                      listening ? Icons.mic : Icons.mic_none,
                      color: listening ? const Color(0xFFFF1A24) : red,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Enviar comando',
                    onPressed: busy ? null : send,
                    icon: Icon(Icons.send, color: busy ? Colors.white38 : red),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CorePainter extends CustomPainter {
  CorePainter(this.time);

  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = const Color(0xFFE50914)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
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
