import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  VoiceService({FlutterTts? tts}) : _tts = tts ?? FlutterTts();
  final FlutterTts _tts;
  Future<void>? _initializing;
  bool _ready = false;

  Future<void> initialize() async {
    if (_ready) return;
    _initializing ??= _configure();
    await _initializing;
  }

  Future<void> _configure() async {
    await _tts.setLanguage('pt-BR');
    await _tts.setPitch(0.68);
    await _tts.setSpeechRate(0.42);
    await _tts.setVolume(1);
    await _tts.awaitSpeakCompletion(true);
    _ready = true;
  }

  Future<void> speak(String text) async {
    final message = text.trim();
    if (message.isEmpty) return;
    await initialize();
    await _tts.stop();
    await _tts.speak(message);
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}
