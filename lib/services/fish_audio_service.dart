import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class FishAudioSettings {
  const FishAudioSettings({
    required this.apiKey,
    required this.model,
    required this.referenceId,
    required this.enabled,
  });

  final String apiKey;
  final String model;
  final String referenceId;
  final bool enabled;

  FishAudioSettings copyWith({
    String? apiKey,
    String? model,
    String? referenceId,
    bool? enabled,
  }) =>
      FishAudioSettings(
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        referenceId: referenceId ?? this.referenceId,
        enabled: enabled ?? this.enabled,
      );
}

/// Integração REST oficial do Fish Audio para síntese de fala no Android.
class FishAudioService {
  FishAudioService({
    FlutterSecureStorage? storage,
    AudioPlayer? player,
    HttpClient Function()? httpFactory,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _player = player ?? AudioPlayer(),
        _httpFactory = httpFactory ?? HttpClient.new;

  static const _apiKeyKey = 'ultron.fish_audio.api_key.v1';
  static const _modelKey = 'ultron.fish_audio.model.v1';
  static const _referenceKey = 'ultron.fish_audio.reference_id.v1';
  static const _enabledKey = 'ultron.fish_audio.enabled.v1';
  static const defaultModel = 's2.1-pro-free';

  final FlutterSecureStorage _storage;
  final AudioPlayer _player;
  final HttpClient Function() _httpFactory;
  int _generation = 0;

  Future<FishAudioSettings> loadSettings() async {
    final values = await Future.wait([
      _storage.read(key: _apiKeyKey),
      _storage.read(key: _modelKey),
      _storage.read(key: _referenceKey),
      _storage.read(key: _enabledKey),
    ]);
    return FishAudioSettings(
      apiKey: values[0] ?? '',
      model: values[1]?.trim().isNotEmpty == true
          ? values[1]!.trim()
          : defaultModel,
      referenceId: values[2] ?? '',
      enabled: values[3] == 'true',
    );
  }

  Future<void> saveSettings(FishAudioSettings settings) async {
    final key = settings.apiKey.trim();
    final model = settings.model.trim();
    final referenceId = settings.referenceId.trim();
    if (model.isEmpty) {
      throw ArgumentError('Selecione um modelo do Fish Audio.');
    }
    await _storage.write(key: _apiKeyKey, value: key);
    await _storage.write(key: _modelKey, value: model);
    await _storage.write(key: _referenceKey, value: referenceId);
    await _storage.write(
      key: _enabledKey,
      value: settings.enabled ? 'true' : 'false',
    );
  }

  /// Retorna false quando o Fish Audio está desativado; erros são propagados
  /// para que o VoiceService possa recorrer ao TTS local.
  Future<bool> speakIfEnabled(String text) async {
    final settings = await loadSettings();
    if (!settings.enabled) return false;
    await _synthesizeAndPlay(text, settings);
    return true;
  }

  /// Teste real: envia texto à API e reproduz o áudio recebido.
  Future<void> testAndPlay() async {
    final settings = await loadSettings();
    await _synthesizeAndPlay(
      'Sistemas online. Eu sou o Ultron. Teste de voz do Fish Audio concluído.',
      settings,
    );
  }

  Future<void> _synthesizeAndPlay(
    String text,
    FishAudioSettings settings,
  ) async {
    final apiKey = settings.apiKey.trim();
    if (apiKey.isEmpty) {
      throw StateError('Informe a API Key do Fish Audio nas configurações.');
    }
    if (text.trim().isEmpty) return;

    final generation = ++_generation;
    final bytes = await _requestAudio(text.trim(), settings);
    if (generation != _generation) return;

    await _player.stop();
    final completed = _player.onPlayerComplete.first.timeout(
      const Duration(minutes: 2),
      onTimeout: () => throw TimeoutException(
        'A reprodução do Fish Audio excedeu o tempo limite.',
      ),
    );
    await _player.play(BytesSource(Uint8List.fromList(bytes), mimeType: 'audio/mpeg'));
    await completed;
  }

  Future<List<int>> _requestAudio(
    String text,
    FishAudioSettings settings,
  ) async {
    final client = _httpFactory()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client
          .postUrl(Uri.https('api.fish.audio', '/v1/tts'))
          .timeout(const Duration(seconds: 20));
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer ${settings.apiKey.trim()}')
        ..contentType = ContentType.json
        ..set('model', settings.model.trim())
        ..set(HttpHeaders.acceptHeader, 'audio/mpeg');
      final payload = <String, Object>{
        'text': text,
        'format': 'mp3',
      };
      if (settings.referenceId.trim().isNotEmpty) {
        payload['reference_id'] = settings.referenceId.trim();
      }
      request.add(utf8.encode(jsonEncode(payload)));

      final response = await request.close().timeout(
            const Duration(seconds: 45),
          );
      final bytes = await response.fold<List<int>>(
        <int>[],
        (buffer, chunk) {
          if (buffer.length + chunk.length > 15 * 1024 * 1024) {
            throw const HttpException(
              'O áudio retornado excedeu o limite de 15 MB.',
            );
          }
          return buffer..addAll(chunk);
        },
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = utf8.decode(bytes, allowMalformed: true);
        throw HttpException(
          'Fish Audio HTTP ${response.statusCode}: ${_redact(body, settings.apiKey)}',
        );
      }
      if (bytes.isEmpty) {
        throw const HttpException('Fish Audio retornou um áudio vazio.');
      }
      final contentType = response.headers.contentType?.mimeType ?? '';
      if (contentType.contains('json') || contentType.startsWith('text/')) {
        final body = utf8.decode(bytes, allowMalformed: true);
        throw HttpException(
          'Resposta inesperada do Fish Audio: ${_redact(body, settings.apiKey)}',
        );
      }
      return bytes;
    } on TimeoutException {
      rethrow;
    } catch (error) {
      if (error is HttpException || error is StateError) rethrow;
      throw HttpException(
        'Falha ao acessar Fish Audio: ${_redact(error.toString(), settings.apiKey)}',
      );
    } finally {
      client.close(force: true);
    }
  }

  static String _redact(String value, String secret) {
    if (secret.isEmpty) return value;
    return value.replaceAll(secret, '[API KEY OCULTA]');
  }

  Future<void> stop() async {
    _generation++;
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (_) {}
  }
}
