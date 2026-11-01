import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  VoiceService({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  Future<void> initialize() async {
    await _tts.setLanguage('pt-BR');
    await _tts.setPitch(0.68);
    await _tts.setSpeechRate(0.42);
    await _tts.setVolume(1);
    await _tts.awaitSpeakCompletion(true);
  }

  Future<void> speak(String text) async {
    if (text.trim().isNotEmpty) await _tts.speak(text.trim());
  }

  Future<void> stop() => _tts.stop();
}
