import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'ai_provider_service.dart';
import 'audio_vad_buffer.dart';

export 'ai_provider_service.dart' show SttConfig;

class SttConfidence {
  const SttConfidence({
    required this.level,
    required this.reason,
    this.avgLogprob,
    this.noSpeechProb,
    this.compressionRatio,
  });

  final String level;
  final String reason;
  final double? avgLogprob;
  final double? noSpeechProb;
  final double? compressionRatio;
}

class SttResult {
  const SttResult({
    this.text,
    this.confidence,
    this.error,
    this.reason,
  });

  final String? text;
  final SttConfidence? confidence;
  final String? error;
  final String? reason;

  bool get hasText => text != null && text!.trim().isNotEmpty;
}

class _HttpAttemptException implements Exception {
  _HttpAttemptException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  bool get isRetryable => statusCode == 429 || statusCode >= 500;

  @override
  String toString() => message;
}

/// Groq Whisper / OpenAI-compatible speech-to-text client with RMS gate,
/// confidence hallucination filters, single 429/5xx retry, and circuit breaker.
class GroqWhisperSttService {
  GroqWhisperSttService({
    AiProviderStore? store,
    SttConfig? config,
    Future<SttConfig> Function()? configLoader,
    this.minRmsThreshold = 50.0,
    this.failureThreshold = 2,
    this.circuitCooldown = const Duration(seconds: 45),
    this.requestTimeout = const Duration(seconds: 20),
    this.retryDelay = Duration.zero,
    DateTime Function()? now,
  })  : _store = store ?? AiProviderStore(),
        _config = config,
        _configLoader = configLoader,
        _now = now ?? DateTime.now;

  static const int maxPromptChars = 900;
  static const double maxNoSpeechProb = 0.60;
  static const double maxCompressionRatio = 2.40;
  static const double minAvgLogprob = -1.0;

  final AiProviderStore _store;
  final SttConfig? _config;
  final Future<SttConfig> Function()? _configLoader;
  final double minRmsThreshold;
  final int failureThreshold;
  final Duration circuitCooldown;
  final Duration requestTimeout;
  final Duration retryDelay;
  final DateTime Function() _now;

  int _consecutiveFailures = 0;
  DateTime? _circuitOpenUntil;

  bool get isCircuitOpen {
    final openUntil = _circuitOpenUntil;
    return openUntil != null && _now().isBefore(openUntil);
  }

  Future<SttResult> transcribe(
    Uint8List pcm, {
    int sampleRate = 16000,
    String prompt = '',
  }) async {
    if (pcm.isEmpty) {
      return const SttResult(error: 'sem_audio');
    }
    if (PcmEnergy.rmsInt16(pcm) < minRmsThreshold) {
      return const SttResult(reason: 'sem_fala');
    }

    if (isCircuitOpen) {
      return const SttResult(error: 'disjuntor', reason: 'circuit_open');
    }

    final cfg = _config ??
        await (_configLoader != null
            ? _configLoader()
            : _store.resolveSttConfig());
    final apiKey = cfg.apiKey.trim();
    if (apiKey.isEmpty) {
      return const SttResult(error: 'sem_chave_stt');
    }
    final uri = Uri.tryParse(cfg.endpointUrl.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return const SttResult(error: 'endpoint_stt_invalido');
    }

    final wavBytes = WavEncoder.pcm16MonoToWav(pcm, sampleRate: sampleRate);
    final truncatedPrompt = prompt.length > maxPromptChars
        ? prompt.substring(0, maxPromptChars)
        : prompt;

    try {
      final responseBody = await _postWithSingleRetry(
        uri: uri,
        config: cfg,
        apiKey: apiKey,
        wavBytes: wavBytes,
        prompt: truncatedPrompt,
      );
      _consecutiveFailures = 0;
      _circuitOpenUntil = null;
      return _parseVerboseResponse(responseBody);
    } catch (error) {
      _consecutiveFailures += 1;
      if (_consecutiveFailures >= failureThreshold) {
        _circuitOpenUntil = _now().add(circuitCooldown);
      }
      final safe = redactSecret(error.toString(), apiKey);
      return SttResult(error: safe);
    }
  }

  Future<String> _postWithSingleRetry({
    required Uri uri,
    required SttConfig config,
    required String apiKey,
    required Uint8List wavBytes,
    required String prompt,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await _postMultipartOnce(
          uri: uri,
          config: config,
          apiKey: apiKey,
          wavBytes: wavBytes,
          prompt: prompt,
        );
      } on _HttpAttemptException catch (e) {
        if (attempt == 0 && e.isRetryable) {
          if (retryDelay > Duration.zero) {
            await Future<void>.delayed(retryDelay);
          }
          continue;
        }
        rethrow;
      } on SocketException {
        if (attempt == 0) {
          if (retryDelay > Duration.zero) {
            await Future<void>.delayed(retryDelay);
          }
          continue;
        }
        rethrow;
      } on TimeoutException {
        if (attempt == 0) {
          if (retryDelay > Duration.zero) {
            await Future<void>.delayed(retryDelay);
          }
          continue;
        }
        rethrow;
      }
    }
    throw const HttpException('Falha inesperada no envio STT');
  }

  Future<String> _postMultipartOnce({
    required Uri uri,
    required SttConfig config,
    required String apiKey,
    required Uint8List wavBytes,
    required String prompt,
  }) async {
    final boundary =
        '----ultronSttBoundary${_now().microsecondsSinceEpoch}';
    final body = _buildMultipartBody(
      boundary: boundary,
      wavBytes: wavBytes,
      model: config.model,
      language: config.language,
      prompt: prompt,
    );

    final client = HttpClient()..connectionTimeout = requestTimeout;
    try {
      final req = await client.postUrl(uri).timeout(requestTimeout);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      req.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );
      req.contentLength = body.length;
      req.add(body);

      final response = await req.close().timeout(requestTimeout);
      final responseText = await response
          .transform(utf8.decoder)
          .join()
          .timeout(requestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        var message = 'Falha HTTP ${response.statusCode}';
        try {
          final decoded = jsonDecode(responseText);
          if (decoded is Map<String, dynamic>) {
            message = (decoded['error']?['message'] ??
                    decoded['message'] ??
                    message)
                .toString();
          }
        } catch (_) {}
        message = redactSecret(message, apiKey);
        if (message.length > 220) message = message.substring(0, 220);
        throw _HttpAttemptException(
          response.statusCode,
          'HTTP ${response.statusCode}: $message',
        );
      }

      return responseText;
    } finally {
      client.close(force: true);
    }
  }

  Uint8List _buildMultipartBody({
    required String boundary,
    required Uint8List wavBytes,
    required String model,
    required String language,
    required String prompt,
  }) {
    final builder = BytesBuilder(copy: false);

    void addField(String name, String value) {
      builder.add(utf8.encode('--$boundary\r\n'));
      builder.add(
        utf8.encode('Content-Disposition: form-data; name="$name"\r\n\r\n'),
      );
      builder.add(utf8.encode('$value\r\n'));
    }

    builder.add(utf8.encode('--$boundary\r\n'));
    builder.add(
      utf8.encode(
        'Content-Disposition: form-data; name="file"; filename="fala.wav"\r\n',
      ),
    );
    builder.add(utf8.encode('Content-Type: audio/wav\r\n\r\n'));
    builder.add(wavBytes);
    builder.add(utf8.encode('\r\n'));

    addField('model', model);
    addField('language', language);
    addField('response_format', 'verbose_json');
    addField('temperature', '0');
    addField('prompt', prompt);

    builder.add(utf8.encode('--$boundary--\r\n'));
    return builder.takeBytes();
  }

  SttResult _parseVerboseResponse(String rawJson) {
    final data = jsonDecode(rawJson);
    if (data is! Map<String, dynamic>) {
      return const SttResult(error: 'resposta_stt_invalida');
    }

    final text = (data['text'] as String? ?? '').trim();
    double? worstNoSpeech = _asDouble(data['no_speech_prob']);
    double? worstCompression = _asDouble(data['compression_ratio']);
    double? worstAvgLogprob = _asDouble(data['avg_logprob']);

    final segments = data['segments'];
    if (segments is List) {
      for (final item in segments) {
        if (item is! Map) continue;
        final noSpeech = _asDouble(item['no_speech_prob']);
        final compression = _asDouble(item['compression_ratio']);
        final avgLogprob = _asDouble(item['avg_logprob']);
        if (noSpeech != null &&
            (worstNoSpeech == null || noSpeech > worstNoSpeech)) {
          worstNoSpeech = noSpeech;
        }
        if (compression != null &&
            (worstCompression == null || compression > worstCompression)) {
          worstCompression = compression;
        }
        if (avgLogprob != null &&
            (worstAvgLogprob == null || avgLogprob < worstAvgLogprob)) {
          worstAvgLogprob = avgLogprob;
        }
      }
    }

    if (worstNoSpeech != null && worstNoSpeech >= maxNoSpeechProb) {
      return SttResult(
        confidence: SttConfidence(
          level: 'rejected',
          reason: 'no_speech_prob',
          avgLogprob: worstAvgLogprob,
          noSpeechProb: worstNoSpeech,
          compressionRatio: worstCompression,
        ),
        reason: 'baixa_confianca',
      );
    }

    if (worstCompression != null &&
        worstCompression >= maxCompressionRatio) {
      return SttResult(
        confidence: SttConfidence(
          level: 'rejected',
          reason: 'compression_ratio',
          avgLogprob: worstAvgLogprob,
          noSpeechProb: worstNoSpeech,
          compressionRatio: worstCompression,
        ),
        reason: 'baixa_confianca',
      );
    }

    if (worstAvgLogprob != null && worstAvgLogprob <= minAvgLogprob) {
      return SttResult(
        confidence: SttConfidence(
          level: 'rejected',
          reason: 'avg_logprob',
          avgLogprob: worstAvgLogprob,
          noSpeechProb: worstNoSpeech,
          compressionRatio: worstCompression,
        ),
        reason: 'baixa_confianca',
      );
    }

    final confidence = SttConfidence(
      level: 'ok',
      reason: 'accepted',
      avgLogprob: worstAvgLogprob,
      noSpeechProb: worstNoSpeech,
      compressionRatio: worstCompression,
    );

    if (text.isEmpty) {
      return SttResult(confidence: confidence, reason: 'vazio');
    }

    return SttResult(text: text, confidence: confidence);
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
