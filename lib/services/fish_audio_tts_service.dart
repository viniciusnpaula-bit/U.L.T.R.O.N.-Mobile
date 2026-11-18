import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class FishAudioLanguageOption {
  const FishAudioLanguageOption(this.code, this.label);

  final String code;
  final String label;
}

class FishAudioConfig {
  const FishAudioConfig({
    this.enabled = false,
    this.apiKey = '',
    this.referenceId = '',
    this.language = defaultLanguage,
    this.model = defaultModel,
  });

  static const String defaultLanguage = 'pt';
  static const String defaultModel = 's2.1-pro';

  static const List<FishAudioLanguageOption> supportedLanguages = [
    FishAudioLanguageOption('pt', 'Português (pt)'),
    FishAudioLanguageOption('auto', 'Automático (auto)'),
    FishAudioLanguageOption('en', 'Inglês (en)'),
    FishAudioLanguageOption('es', 'Espanhol (es)'),
  ];

  static const List<String> supportedModels = [
    's2.1-pro',
    's2.1-pro-free',
    's2-pro',
    'drama-3',
    's1',
  ];

  final bool enabled;
  final String apiKey;
  final String referenceId;
  final String language;
  final String model;

  bool get isConfigured =>
      apiKey.trim().isNotEmpty && referenceId.trim().isNotEmpty;

  bool get isActive => enabled && isConfigured;

  String get shortReferenceId {
    final trimmed = referenceId.trim();
    if (trimmed.length <= 10) return trimmed;
    return '${trimmed.substring(0, 8)}...';
  }

  FishAudioConfig copyWith({
    bool? enabled,
    String? apiKey,
    String? referenceId,
    String? language,
    String? model,
  }) {
    return FishAudioConfig(
      enabled: enabled ?? this.enabled,
      apiKey: apiKey ?? this.apiKey,
      referenceId: referenceId ?? this.referenceId,
      language: language ?? this.language,
      model: model ?? this.model,
    );
  }
}

class FishAudioException implements Exception {
  const FishAudioException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'Fish Audio ($statusCode): $message';
}

/// Cliente HTTP e cofre de credenciais para síntese de voz via API Fish Audio / Fish Studio.
class FishAudioTtsService {
  FishAudioTtsService({
    FlutterSecureStorage? storage,
    FishAudioConfig? initialConfig,
    Uri? endpoint,
    this.requestTimeout = const Duration(seconds: 20),
    HttpClient Function()? httpClientFactory,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        hasInitialConfig = initialConfig != null,
        _config = initialConfig ?? const FishAudioConfig(),
        _endpoint = endpoint ?? Uri.parse(defaultEndpointUrl),
        _httpClientFactory = httpClientFactory ?? HttpClient.new;

  static const String defaultEndpointUrl = 'https://api.fish.audio/v1/tts';

  static const _enabledKey = 'ultron.tts.fish.enabled.v1';
  static const _apiKeyStorageKey = 'ultron.tts.fish.api_key.v1';
  static const _referenceIdKey = 'ultron.tts.fish.reference_id.v1';
  static const _languageKey = 'ultron.tts.fish.language.v1';
  static const _modelKey = 'ultron.tts.fish.model.v1';

  final FlutterSecureStorage _storage;
  final Uri _endpoint;
  final Duration requestTimeout;
  final HttpClient Function() _httpClientFactory;
  final bool hasInitialConfig;

  FishAudioConfig _config;
  FishAudioConfig get config => _config;

  Future<FishAudioConfig> loadConfig() async {
    final enabledRaw = await _storage.read(key: _enabledKey);
    final apiKey = await _storage.read(key: _apiKeyStorageKey) ?? '';
    final referenceId = await _storage.read(key: _referenceIdKey) ?? '';
    final languageRaw = await _storage.read(key: _languageKey);
    final modelRaw = await _storage.read(key: _modelKey);

    _config = FishAudioConfig(
      enabled: enabledRaw == 'true',
      apiKey: apiKey.trim(),
      referenceId: referenceId.trim(),
      language: (languageRaw ?? '').trim().isEmpty
          ? FishAudioConfig.defaultLanguage
          : languageRaw!.trim(),
      model: (modelRaw ?? '').trim().isEmpty
          ? FishAudioConfig.defaultModel
          : modelRaw!.trim(),
    );
    return _config;
  }

  Future<void> saveConfig(FishAudioConfig next) async {
    final normalized = FishAudioConfig(
      enabled: next.enabled,
      apiKey: next.apiKey.trim(),
      referenceId: next.referenceId.trim(),
      language: next.language.trim().isEmpty
          ? FishAudioConfig.defaultLanguage
          : next.language.trim(),
      model: next.model.trim().isEmpty
          ? FishAudioConfig.defaultModel
          : next.model.trim(),
    );
    _config = normalized;
    await _storage.write(
      key: _enabledKey,
      value: normalized.enabled ? 'true' : 'false',
    );
    await _storage.write(key: _apiKeyStorageKey, value: normalized.apiKey);
    await _storage.write(key: _referenceIdKey, value: normalized.referenceId);
    await _storage.write(key: _languageKey, value: normalized.language);
    await _storage.write(key: _modelKey, value: normalized.model);
  }

  static Map<String, Object?> buildPayload(
    String text,
    FishAudioConfig cfg,
  ) {
    final payload = <String, Object?>{
      'text': text,
      'reference_id': cfg.referenceId.trim(),
      'format': 'mp3',
    };
    final lang = cfg.language.trim();
    if (lang.isNotEmpty && lang.toLowerCase() != 'auto') {
      payload['language'] = lang;
    }
    return payload;
  }

  Future<Uint8List> synthesize(
    String text, {
    FishAudioConfig? overrideConfig,
  }) async {
    final cfg = overrideConfig ?? _config;
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      throw const FishAudioException(400, 'Texto vazio para síntese.');
    }
    final apiKey = cfg.apiKey.trim();
    if (apiKey.isEmpty) {
      throw const FishAudioException(
          400, 'API Key do Fish Audio não definida.');
    }
    final referenceId = cfg.referenceId.trim();
    if (referenceId.isEmpty) {
      throw const FishAudioException(
        400,
        'Reference ID da voz não definido.',
      );
    }

    final client = _httpClientFactory()..connectionTimeout = requestTimeout;
    try {
      final req = await client.postUrl(_endpoint).timeout(requestTimeout);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      req.headers.contentType = ContentType.json;
      req.headers.set(
          'model',
          cfg.model.trim().isEmpty
              ? FishAudioConfig.defaultModel
              : cfg.model.trim());
      req.add(utf8.encode(jsonEncode(buildPayload(cleanText, cfg))));

      final res = await req.close().timeout(requestTimeout);
      final chunks = <int>[];
      await for (final part in res.timeout(requestTimeout)) {
        chunks.addAll(part);
      }
      final bytes = Uint8List.fromList(chunks);
      if (res.statusCode != HttpStatus.ok) {
        throw FishAudioException(
          res.statusCode,
          _extractErrorMessage(bytes, res.reasonPhrase),
        );
      }
      if (bytes.isEmpty) {
        throw const FishAudioException(
          502,
          'Resposta de áudio vazia do Fish Audio.',
        );
      }
      return bytes;
    } on FishAudioException {
      rethrow;
    } on TimeoutException {
      throw const FishAudioException(
        408,
        'Tempo esgotado ao conectar no Fish Audio.',
      );
    } catch (e) {
      throw FishAudioException(0, 'Falha de rede no Fish Audio: $e');
    } finally {
      client.close(force: true);
    }
  }

  static String _extractErrorMessage(Uint8List bytes, String fallbackReason) {
    if (bytes.isEmpty) {
      return fallbackReason.isEmpty ? 'Erro na API Fish Audio' : fallbackReason;
    }
    final raw = utf8.decode(bytes, allowMalformed: true).trim();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final msg = decoded['message'] ?? decoded['detail'] ?? decoded['error'];
        if (msg != null && msg.toString().trim().isNotEmpty) {
          return msg.toString().trim();
        }
      }
    } catch (_) {}
    if (raw.length > 180) return raw.substring(0, 180);
    return raw.isEmpty ? fallbackReason : raw;
  }
}
