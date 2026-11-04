import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'speech_text.dart';

/// Perfis de timbre da voz do U.L.T.R.O.N.
enum VoiceProfile {
  /// Timbre grave, tático e militar característico do U.L.T.R.O.N. (pitch 0.55).
  grave('GRAVE', 0.55, 0.45),

  /// Timbre padrão do motor nativo, ritmo normal.
  natural('NATURAL', 1.0, 0.50),

  /// Respostas mais rápidas para quem tem pressa.
  agil('ÁGIL', 0.70, 0.58);

  const VoiceProfile(this.label, this.pitch, this.rate);
  final String label;
  final double pitch;
  final double rate;
}

class TtsVoiceOption {
  const TtsVoiceOption({
    required this.name,
    required this.locale,
    required this.offline,
    required this.quality,
  });

  final String name;
  final String locale;
  final bool offline;
  final String quality;

  Map<String, String> toEngineMap() => {'name': name, 'locale': locale};
}

class VoiceService {
  VoiceService({
    FlutterTts? tts,
    MethodChannel? deviceChannel,
    FlutterSecureStorage? storage,
  })  : _tts = tts ?? FlutterTts(),
        _deviceChannel = deviceChannel ??
            const MethodChannel('com.viniciusnpaula.ultron_mobile/device'),
        _storage = storage ?? const FlutterSecureStorage();

  static const _voiceKey = 'ultron.tts.voice.v1';
  static const _profileKey = 'ultron.tts.profile.v1';

  final FlutterTts _tts;
  final MethodChannel _deviceChannel;
  final FlutterSecureStorage _storage;
  Future<void>? _initializing;
  bool _ready = false;
  int _generation = 0;

  bool enabled = true;
  bool whisperMode = false;
  bool isSpeaking = false;
  VoiceProfile profile = VoiceProfile.grave;
  String? activeVoiceName;

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
    await _tts.awaitSpeakCompletion(true);
    try {
      final savedProfile = await _storage.read(key: _profileKey);
      profile = VoiceProfile.values.firstWhere(
        (p) => p.name == savedProfile,
        orElse: () => VoiceProfile.grave,
      );
    } catch (_) {}
    await _applyProfile();
    await _selectVoice();
    _tts.setErrorHandler((_) => _notifyNativeSpeaking(false));
    _ready = true;
  }

  Future<void> _applyProfile() async {
    await _tts.setPitch(profile.pitch);
    await _tts.setSpeechRate(whisperMode ? profile.rate * 0.85 : profile.rate);
    await _tts.setVolume(whisperMode ? 0.28 : 1.0);
  }

  /// Lista as vozes pt-BR instaladas, das melhores para as piores.
  Future<List<TtsVoiceOption>> listPortugueseVoices() async {
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return const [];
      final voices = <TtsVoiceOption>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final name = (item['name'] ?? '').toString();
        final locale = (item['locale'] ?? '').toString();
        final normalizedLocale = locale.toLowerCase().replaceAll('_', '-');
        if (name.isEmpty || !normalizedLocale.startsWith('pt-br')) continue;
        final network = (item['network_required'] ?? '').toString();
        final offline = network == '0' ||
            (network.isEmpty && !name.toLowerCase().contains('network'));
        voices.add(
          TtsVoiceOption(
            name: name,
            locale: locale,
            offline: offline,
            quality: (item['quality'] ?? '').toString().toLowerCase(),
          ),
        );
      }
      voices.sort((a, b) => _score(b).compareTo(_score(a)));
      return voices;
    } catch (_) {
      return const [];
    }
  }

  static int _score(TtsVoiceOption v) {
    var score = 0;
    if (v.offline) score += 4;
    if (v.quality.contains('very')) {
      score += 3;
    } else if (v.quality.contains('high')) {
      score += 2;
    }
    if (v.name.toLowerCase().contains('local')) score += 1;
    return score;
  }

  Future<void> _selectVoice() async {
    final voices = await listPortugueseVoices();
    if (voices.isEmpty) return;
    String? saved;
    try {
      saved = await _storage.read(key: _voiceKey);
    } catch (_) {}
    final chosen = voices.firstWhere(
      (v) => v.name == saved,
      orElse: () => voices.first,
    );
    try {
      await _tts.setVoice(chosen.toEngineMap());
      activeVoiceName = chosen.name;
    } catch (_) {}
  }

  Future<void> setPreferredVoice(TtsVoiceOption voice) async {
    await initialize();
    await _tts.setVoice(voice.toEngineMap());
    activeVoiceName = voice.name;
    try {
      await _storage.write(key: _voiceKey, value: voice.name);
    } catch (_) {}
  }

  Future<void> setProfile(VoiceProfile next) async {
    profile = next;
    await initialize();
    await _applyProfile();
    try {
      await _storage.write(key: _profileKey, value: next.name);
    } catch (_) {}
  }

  Future<void> setWhisperMode(bool whisper) async {
    whisperMode = whisper;
    await initialize();
    await _applyProfile();
  }

  /// Fala [text] já higienizado, em blocos curtos e interrompíveis.
  ///
  /// Uma nova chamada a [speak] ou [stop] cancela a fala em andamento.
  Future<void> speak(
    String text, {
    int maxSpokenChars = SpeechText.defaultMaxSpokenChars,
  }) async {
    if (!enabled) return;
    final chunks =
        SpeechText.prepareChunks(text, maxSpokenChars: maxSpokenChars);
    if (chunks.isEmpty) return;
    await initialize();
    final generation = ++_generation;
    await _tts.stop();
    await _notifyNativeSpeaking(true);
    try {
      for (final chunk in chunks) {
        if (generation != _generation) break;
        await _tts.speak(chunk);
      }
    } finally {
      if (generation == _generation) {
        await _notifyNativeSpeaking(false);
      }
    }
  }

  Future<void> preview() =>
      speak('Sistemas online. Eu sou o Ultron, pronto para suas ordens.');

  Future<void> stop() async {
    _generation++;
    try {
      await _tts.stop();
    } finally {
      await _notifyNativeSpeaking(false);
    }
  }
}
