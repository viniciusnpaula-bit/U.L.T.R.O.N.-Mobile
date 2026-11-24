import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'fish_audio_tts_service.dart';
import 'speech_text.dart';
import 'tts_text_normalizer.dart';

export 'fish_audio_tts_service.dart';

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

  String get displayLabel {
    final mode = offline ? 'Offline' : 'Rede';
    final qual = quality.isEmpty ? 'padrão' : quality;
    return '$name ($locale • $mode • $qual)';
  }
}

class VoiceService {
  VoiceService({
    FlutterTts? tts,
    MethodChannel? deviceChannel,
    FlutterSecureStorage? storage,
    FishAudioTtsService? fishService,
    this.onSpeakComplete,
  })  : _tts = tts ?? FlutterTts(),
        _deviceChannel = deviceChannel ??
            const MethodChannel('com.viniciusnpaula.ultron_mobile/device'),
        _storage = storage ?? const FlutterSecureStorage(),
        _fishService = fishService ??
            FishAudioTtsService(
              storage: storage ?? const FlutterSecureStorage(),
            );

  static const _voiceKey = 'ultron.tts.voice.v1';
  static const _profileKey = 'ultron.tts.profile.v1';
  static const _wakeWordProfileKey = 'ultron.tts.wake_word.v1';

  final FlutterTts _tts;
  final MethodChannel _deviceChannel;
  final FlutterSecureStorage _storage;
  final FishAudioTtsService _fishService;
  VoidCallback? onSpeakComplete;
  void Function(bool speaking)? onSpeakingChanged;
  Future<void>? _initializing;
  bool _ready = false;
  bool _profileExplicitlySet = false;
  bool _wakeWordExplicitlySet = false;
  bool _voiceExplicitlySet = false;
  bool _fishExplicitlySet = false;
  int _generation = 0;

  bool enabled = true;
  bool whisperMode = false;
  bool isSpeaking = false;
  VoiceProfile profile = VoiceProfile.grave;
  WakeWordProfile wakeWordProfile = WakeWordProfile.ultron;
  String? activeVoiceName;
  String? lastFishError;

  FishAudioConfig get fishConfig => _fishService.config;
  bool get isFishAudioActive => _fishService.config.isActive;

  String get activeVoiceLabel => isFishAudioActive
      ? 'Fish Audio (${fishConfig.language} • ${fishConfig.model})'
      : (activeVoiceName ?? 'Padrão do sistema');

  void _syncNativeTtsConfig() {
    try {
      unawaited(
        _deviceChannel.invokeMethod<bool>('configureTts', {
          'voiceName': activeVoiceName ?? '',
          'pitch': profile.pitch,
          'rate': whisperMode ? profile.rate * 0.85 : profile.rate,
        }).then<void>((_) {}, onError: (_) {}),
      );
    } catch (_) {}
  }

  void _notifyNativeSpeaking(bool speaking) {
    isSpeaking = speaking;
    onSpeakingChanged?.call(speaking);
    try {
      unawaited(
        _deviceChannel.invokeMethod<bool>('setUltronSpeaking',
            {'speaking': speaking}).then<void>((_) {}, onError: (_) {}),
      );
    } catch (_) {}
  }

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
    await _tts.awaitSpeakCompletion(true);
    if (!_profileExplicitlySet) {
      try {
        final savedProfile = await _storage.read(key: _profileKey);
        if (!_profileExplicitlySet) {
          profile = VoiceProfile.values.firstWhere(
            (p) => p.name == savedProfile,
            orElse: () => VoiceProfile.grave,
          );
        }
      } catch (_) {}
    }
    if (!_wakeWordExplicitlySet) {
      try {
        final savedWake = await _storage.read(key: _wakeWordProfileKey);
        if (!_wakeWordExplicitlySet && savedWake != null) {
          wakeWordProfile = WakeWordProfile.fromId(savedWake);
          WakeWord.setActiveProfile(wakeWordProfile);
        }
      } catch (_) {}
    }
    _syncNativeWakeWordProfile();
    if (!_fishExplicitlySet && !_fishService.hasInitialConfig) {
      try {
        await _fishService.loadConfig();
      } catch (_) {}
    }
    if (!_voiceExplicitlySet) {
      await _selectVoice();
    }
    await _applyProfile();
    try {
      _tts.setErrorHandler((_) => _notifyNativeSpeaking(false));
    } catch (_) {}
    _ready = true;
    _syncNativeTtsConfig();
  }

  Future<void> _applyProfile() async {
    await _tts.setPitch(profile.pitch);
    await _tts.setSpeechRate(whisperMode ? profile.rate * 0.85 : profile.rate);
    await _tts.setVolume(whisperMode ? 0.28 : 1.0);
  }

  /// Lista as vozes pt-BR (e fallback pt) instaladas, das melhores para as piores.
  Future<List<TtsVoiceOption>> listPortugueseVoices() async {
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return const [];
      final seen = <String>{};
      final voices = <TtsVoiceOption>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final name = (item['name'] ?? '').toString();
        final locale = (item['locale'] ?? '').toString();
        final normalizedLocale = locale.toLowerCase().replaceAll('_', '-');
        if (name.isEmpty ||
            !(normalizedLocale.startsWith('pt-br') ||
                normalizedLocale == 'pt' ||
                normalizedLocale.startsWith('pt-'))) {
          continue;
        }
        final key = '$name|$locale';
        if (!seen.add(key)) continue;
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
    if (v.locale.toLowerCase().replaceAll('_', '-').startsWith('pt-br')) {
      score += 8;
    }
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
    _voiceExplicitlySet = true;
    await initialize();
    await _tts.stop();
    await _tts.setVoice(voice.toEngineMap());
    activeVoiceName = voice.name;
    // Android TextToSpeech.setVoice() can reset pitch/rate back to engine defaults.
    await _applyProfile();
    _syncNativeTtsConfig();
    try {
      await _storage.write(key: _voiceKey, value: voice.name);
    } catch (_) {}
  }

  void _syncNativeWakeWordProfile() {
    try {
      unawaited(
        _deviceChannel
            .invokeMethod<Object?>('setWakeWordProfile', {
              'profile': wakeWordProfile.id,
            })
            .then<void>((_) {}, onError: (_) {}),
      );
    } catch (_) {}
  }

  Future<void> setWakeWordProfile(WakeWordProfile next) async {
    _wakeWordExplicitlySet = true;
    wakeWordProfile = next;
    WakeWord.setActiveProfile(next);
    _syncNativeWakeWordProfile();
    try {
      await _storage.write(key: _wakeWordProfileKey, value: next.id);
    } catch (_) {}
  }

  Future<void> setProfile(VoiceProfile next) async {
    _profileExplicitlySet = true;
    profile = next;
    await initialize();
    await _tts.stop();
    await _applyProfile();
    _syncNativeTtsConfig();
    try {
      await _storage.write(key: _profileKey, value: next.name);
    } catch (_) {}
  }

  Future<void> setFishConfig(FishAudioConfig config) async {
    _fishExplicitlySet = true;
    await _fishService.saveConfig(config);
    lastFishError = null;
    await initialize();
    await stop();
  }

  Future<void> setWhisperMode(bool whisper) async {
    whisperMode = whisper;
    await initialize();
    await _applyProfile();
    _syncNativeTtsConfig();
  }

  /// Fala [text] já higienizado, em blocos curtos e interrompíveis.
  ///
  /// Uma nova chamada a [speak] ou [stop] cancela a fala em andamento.
  Future<void> speak(
    String text, {
    int maxSpokenChars = SpeechText.defaultMaxSpokenChars,
  }) async {
    if (!enabled) return;
    final normalized = TtsTextNormalizer.normalize(text.trim());
    final chunks =
        SpeechText.prepareChunks(normalized, maxSpokenChars: maxSpokenChars);
    if (chunks.isEmpty) return;
    final generation = ++_generation;
    await initialize();
    if (generation != _generation) return;
    await _tts.stop();
    if (generation != _generation) return;
    _notifyNativeSpeaking(true);
    var completedNaturally = false;
    try {
      for (final chunk in chunks) {
        if (generation != _generation) break;
        if (_fishService.config.isActive) {
          final outcome = await _speakChunkWithFishAudio(chunk, generation);
          if (generation != _generation ||
              outcome == _FishPlayOutcome.interrupted) {
            break;
          }
          if (outcome == _FishPlayOutcome.played) {
            continue;
          }
        }
        if (generation != _generation) break;
        await _tts.speak(chunk);
      }
      completedNaturally = generation == _generation;
    } finally {
      if (generation == _generation) {
        _notifyNativeSpeaking(false);
        if (completedNaturally) {
          onSpeakComplete?.call();
        }
      }
    }
  }

  Future<_FishPlayOutcome> _speakChunkWithFishAudio(
    String chunk,
    int generation,
  ) async {
    try {
      final bytes = await _fishService.synthesize(chunk);
      if (generation != _generation) {
        return _FishPlayOutcome.interrupted;
      }
      final played = await _deviceChannel.invokeMethod<bool>(
        'playTtsAudioBytes',
        {
          'bytes': bytes,
          'volume': whisperMode ? 0.28 : 1.0,
        },
      );
      if (generation != _generation || played != true) {
        return _FishPlayOutcome.interrupted;
      }
      lastFishError = null;
      return _FishPlayOutcome.played;
    } on MissingPluginException {
      lastFishError = 'Reprodução nativa indisponível; usando voz offline.';
      return _FishPlayOutcome.fallback;
    } on PlatformException catch (e) {
      lastFishError = e.message ?? e.code;
      return _FishPlayOutcome.fallback;
    } catch (e) {
      lastFishError = e.toString();
      return _FishPlayOutcome.fallback;
    }
  }

  Future<void> preview() => speak(
        'Sistemas online. Eu sou ${wakeWordProfile == WakeWordProfile.edith ? 'a' : 'o'} ${wakeWordProfile.label}, pronto para suas ordens.',
      );

  Future<void> stop() async {
    _generation++;
    try {
      await _tts.stop();
    } finally {
      _notifyNativeSpeaking(false);
    }
  }
}

enum _FishPlayOutcome { played, interrupted, fallback }
