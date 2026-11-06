import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Voz personalizada do U.L.T.R.O.N. via Fish Audio (fish.audio).
///
/// A chave e o ID do modelo ficam no armazenamento seguro do aparelho; também
/// podem vir de `--dart-define=FISH_AUDIO_API_KEY=...` /
/// `--dart-define=FISH_AUDIO_VOICE_ID=...` no build.
class FishAudioConfig {
  const FishAudioConfig({
    required this.apiKey,
    required this.voiceId,
    this.model = FishAudioTts.defaultModel,
  });

  final String apiKey;
  final String voiceId;
  final String model;

  bool get isConfigured => apiKey.isNotEmpty && voiceId.isNotEmpty;
}

class FishAudioTts {
  FishAudioTts({
    FlutterSecureStorage? storage,
    AudioPlayer? player,
    HttpClient Function()? httpFactory,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _providedPlayer = player,
        _httpFactory = httpFactory ?? HttpClient.new;

  static const apiKeyStorageKey = 'ultron.fish.api_key';
  static const voiceIdStorageKey = 'ultron.fish.voice_id';

  /// Tier gratuito do Fish Audio. Trocar para `s2.1-pro` exige crédito.
  static const defaultModel = 's2.1-pro-free';

  static const _envApiKey = String.fromEnvironment('FISH_AUDIO_API_KEY');
  static const _envVoiceId = String.fromEnvironment('FISH_AUDIO_VOICE_ID');

  final FlutterSecureStorage _storage;
  final AudioPlayer? _providedPlayer;
  final HttpClient Function() _httpFactory;

  AudioPlayer? _playerInstance;
  AudioPlayer get _player => _playerInstance ??= _providedPlayer ?? AudioPlayer();

  Completer<void>? _playbackDone;

  Future<FishAudioConfig> loadConfig() async {
    var apiKey = _envApiKey.trim();
    var voiceId = _envVoiceId.trim();
    try {
      final storedKey = await _storage.read(key: apiKeyStorageKey);
      final storedVoice = await _storage.read(key: voiceIdStorageKey);
      if (storedKey != null && storedKey.trim().isNotEmpty) {
        apiKey = storedKey.trim();
      }
      if (storedVoice != null && storedVoice.trim().isNotEmpty) {
        voiceId = storedVoice.trim();
      }
    } catch (_) {}
    return FishAudioConfig(apiKey: apiKey, voiceId: voiceId);
  }

  Future<void> saveConfig({
    required String apiKey,
    required String voiceId,
  }) async {
    await _storage.write(key: apiKeyStorageKey, value: apiKey.trim());
    await _storage.write(key: voiceIdStorageKey, value: voiceId.trim());
  }

  /// Corpo da requisição; separado para poder ser testado sem rede.
  static Map<String, dynamic> buildPayload(
    String text, {
    required String voiceId,
  }) =>
      {
        'text': text,
        'reference_id': voiceId,
        'format': 'mp3',
        'mp3_bitrate': 128,
        'normalize': true,
        'latency': 'normal',
        'prosody': {'speed': 1.0, 'normalize_loudness': true},
      };

  /// Sintetiza [text] e devolve o MP3, ou `null` em qualquer falha.
  Future<Uint8List?> synthesize(FishAudioConfig config, String text) async {
    if (!config.isConfigured || text.trim().isEmpty) return null;
    final client = _httpFactory()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.postUrl(
        Uri.parse('https://api.fish.audio/v1/tts'),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${config.apiKey}',
      );
      request.headers.set('model', config.model);
      request.add(
        utf8.encode(jsonEncode(buildPayload(text, voiceId: config.voiceId))),
      );
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }
      final bytes = <int>[];
      await for (final part in response) {
        bytes.addAll(part);
      }
      return bytes.isEmpty ? null : Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Toca e só retorna quando o áudio termina (ou é interrompido por [stop]).
  Future<void> play(Uint8List audio) async {
    _finishPlayback();
    final done = Completer<void>();
    _playbackDone = done;
    final subscription = _player.onPlayerComplete.listen((_) {
      _finishPlayback();
    });
    try {
      await _player.play(BytesSource(audio));
      await done.future.timeout(const Duration(minutes: 2));
    } finally {
      await subscription.cancel();
      _playbackDone = null;
    }
  }

  Future<void> stop() async {
    _finishPlayback();
    await _player.stop();
  }

  void _finishPlayback() {
    final done = _playbackDone;
    if (done != null && !done.isCompleted) done.complete();
  }

  Future<void> dispose() async {
    _finishPlayback();
    await _playerInstance?.dispose();
    _playerInstance = null;
  }
}
