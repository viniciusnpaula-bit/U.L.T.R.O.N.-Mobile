import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'tts_text_normalizer.dart';

class VoiceService {
  VoiceService({FlutterTts? tts, this.onSpeakComplete})
      : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  VoidCallback? onSpeakComplete;
  Future<void>? _initializing;
  bool _ready = false;
  bool _isSpeaking = false;
  int _speakToken = 0;

  bool get isSpeaking => _isSpeaking;

  Future<void> initialize() async {
    if (_ready) return;
    final pending = _initializing ??= _configure();
    try {
      await pending;
    } catch (_) {
      if (identical(_initializing, pending)) {
        _initializing = null;
      }
      rethrow;
    }
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
    final normalized = TtsTextNormalizer.normalize(text.trim());
    if (normalized.isEmpty) return;
    final token = ++_speakToken;
    await initialize();
    if (token != _speakToken) return;
    _isSpeaking = true;
    try {
      await _tts.stop();
      if (token != _speakToken) return;
      await _tts.speak(normalized);
      if (token == _speakToken) {
        _isSpeaking = false;
        onSpeakComplete?.call();
      }
    } finally {
      if (token == _speakToken) {
        _isSpeaking = false;
      }
    }
  }

  Future<void> stop() async {
    _speakToken += 1;
    _isSpeaking = false;
    await _tts.stop();
  }
}
