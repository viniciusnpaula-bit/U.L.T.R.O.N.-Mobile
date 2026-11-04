import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  VoiceService({FlutterTts? tts, MethodChannel? deviceChannel})
      : _tts = tts ?? FlutterTts(),
        _deviceChannel = deviceChannel ??
            const MethodChannel('com.viniciusnpaula.ultron_mobile/device');

  final FlutterTts _tts;
  final MethodChannel _deviceChannel;
  Future<void>? _initializing;
  bool _ready = false;
  bool enabled = true;
  bool whisperMode = false;
  bool isSpeaking = false;

  Future<void> _notifyNativeSpeaking(bool speaking) async {
    isSpeaking = speaking;
    try {
      await _deviceChannel.invokeMethod<bool>(
        'setUltronSpeaking',
        {'speaking': speaking},
      );
    } catch (_) {}
  }

  Future<void> initialize() async {
    if (_ready) return;
    _initializing ??= _configure();
    await _initializing;
  }

  Future<void> _configure() async {
    await _tts.setLanguage('pt-BR');
    await _tts.setPitch(0.55);
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1);
    await _tts.awaitSpeakCompletion(true);
    _tts.setStartHandler(() {
      _notifyNativeSpeaking(true);
    });
    _tts.setCompletionHandler(() {
      _notifyNativeSpeaking(false);
    });
    _tts.setCancelHandler(() {
      _notifyNativeSpeaking(false);
    });
    _tts.setErrorHandler((_) {
      _notifyNativeSpeaking(false);
    });
    _ready = true;
  }

  Future<void> setWhisperMode(bool whisper) async {
    whisperMode = whisper;
    await initialize();
    await _tts.setVolume(whisper ? 0.28 : 1.0);
    await _tts.setSpeechRate(whisper ? 0.38 : 0.48);
  }

  Future<void> speak(String text) async {
    if (!enabled) return;
    final message = text.trim();
    if (message.isEmpty) return;
    await initialize();
    await _notifyNativeSpeaking(true);
    try {
      await _tts.stop();
      await _tts.speak(message);
    } finally {
      await _notifyNativeSpeaking(false);
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } finally {
      await _notifyNativeSpeaking(false);
    }
  }
}
