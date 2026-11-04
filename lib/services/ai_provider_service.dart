import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AiProviderConfig {
  const AiProviderConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    this.enabled = true,
    this.priority = 0,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String model;
  final String apiKey;
  final bool enabled;
  final int priority;

  AiProviderConfig copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? model,
    String? apiKey,
    bool? enabled,
    int? priority,
  }) =>
      AiProviderConfig(
        id: id ?? this.id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        apiKey: apiKey ?? this.apiKey,
        enabled: enabled ?? this.enabled,
        priority: priority ?? this.priority,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'model': model,
        'apiKey': apiKey,
        'enabled': enabled,
        'priority': priority,
      };

  factory AiProviderConfig.fromJson(Map<String, dynamic> j) => AiProviderConfig(
        id: j['id'] as String,
        name: j['name'] as String,
        baseUrl: j['baseUrl'] as String,
        model: j['model'] as String,
        apiKey: j['apiKey'] as String,
        enabled: j['enabled'] as bool? ?? true,
        priority: j['priority'] as int? ?? 0,
      );
}

class AiProviderStore {
  AiProviderStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _key = 'ultron.ai.providers.v1';

  /// Models that have been decommissioned or replaced on providers like Groq.
  static const deprecatedModels = <String>{
    'llama3-70b-8192',
    'llama3-8b-8192',
    'llama-3.1-70b-versatile',
    'llama-3.2-90b-vision-preview',
    'llama-3.2-11b-vision-preview',
    'llama-3.3-70b-specdec',
    'mixtral-8x7b-32768',
    'gemma-7b-it',
    'gemma2-9b-it',
  };

  static String normalizeModelForUrl(String baseUrl, String model) {
    final cleanModel = model.trim();
    final isGroq = baseUrl.toLowerCase().contains('api.groq.com');
    if (isGroq &&
        (cleanModel.isEmpty ||
            cleanModel == 'auto' ||
            deprecatedModels.contains(cleanModel) ||
            cleanModel.startsWith('llama'))) {
      return 'openai/gpt-oss-120b';
    }
    return cleanModel;
  }

  Future<List<AiProviderConfig>> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return [];
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => AiProviderConfig.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      var migrated = false;
      final normalized = list.map((p) {
        final nextModel = normalizeModelForUrl(p.baseUrl, p.model);
        if (nextModel != p.model) {
          migrated = true;
          return p.copyWith(model: nextModel);
        }
        return p;
      }).toList();
      if (migrated) {
        await save(normalized);
      }
      return normalized;
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<AiProviderConfig> providers) => _storage.write(
        key: _key,
        value: jsonEncode(providers.map((e) => e.toJson()).toList()),
      );

  Future<void> deleteAll() => _storage.delete(key: _key);
}

class AiReply {
  const AiReply(this.provider, this.text);

  final String provider;
  final String text;
}

class AiFailover {
  AiFailover({AiProviderStore? store}) : _store = store ?? AiProviderStore();

  final AiProviderStore _store;

  static const _groqFallbackChain = <String>[
    'openai/gpt-oss-120b',
    'openai/gpt-oss-20b',
    'qwen/qwen3-32b',
    'moonshotai/kimi-k2-instruct',
    'llama-3.3-70b-versatile',
    'llama-3.1-8b-instant',
  ];

  static const _geminiFallbackChain = <String>[
    'gemini-2.5-flash',
    'gemini-2.0-flash',
    'gemini-2.5-pro',
  ];

  static const _openAiFallbackChain = <String>[
    'gpt-4.1-mini',
    'gpt-4o-mini',
    'gpt-4o',
  ];

  Future<AiReply> ask(
    String prompt, {
    List<Map<String, String>> history = const [],
    String? systemPrompt,
  }) async {
    final allProviders = await _store.load();
    final providers = allProviders
        .where(
          (p) =>
              p.enabled &&
              p.apiKey.trim().isNotEmpty &&
              p.model.trim().isNotEmpty,
        )
        .toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
    if (providers.isEmpty) {
      throw StateError('Nenhum provedor de IA ativo e configurado.');
    }
    final errors = <String>[];
    for (final p in providers) {
      try {
        final result = await _requestWithModelFallback(
          p,
          prompt,
          history: history,
          systemPrompt: systemPrompt,
        );
        if (result.modelUsed != p.model) {
          // Persist the working model so future turns don't hit the dead model again.
          final updatedAll = allProviders
              .map(
                (item) => item.id == p.id
                    ? item.copyWith(model: result.modelUsed)
                    : item,
              )
              .toList();
          await _store.save(updatedAll);
        }
        return AiReply('${p.name} (${result.modelUsed})', result.replyText);
      } catch (e) {
        errors.add('${p.name}: $e');
      }
    }
    throw HttpException('Todos os provedores falharam. ${errors.join(' | ')}');
  }

  Future<String> test(AiProviderConfig p) async {
    final res = await _requestWithModelFallback(
      p,
      'Responda somente: conexão OK',
    );
    return '${res.replyText} [Modelo ativo: ${res.modelUsed}]';
  }

  /// Queries `GET $baseUrl/models` and returns active chat completion models.
  Future<List<String>> fetchAvailableModels(AiProviderConfig p) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final base = p.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
      final root = base.endsWith('/chat/completions')
          ? base.substring(0, base.length - '/chat/completions'.length)
          : base;
      final uri = Uri.parse('$root/models');
      final req =
          await client.getUrl(uri).timeout(const Duration(seconds: 15));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${p.apiKey}');
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await req.close().timeout(const Duration(seconds: 15));
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }
      return parseChatModelsList(body);
    } catch (_) {
      return const [];
    } finally {
      client.close(force: true);
    }
  }

  Future<({String replyText, String modelUsed})> _requestWithModelFallback(
    AiProviderConfig p,
    String prompt, {
    List<Map<String, String>> history = const [],
    String? systemPrompt,
  }) async {
    final candidates = <String>[
      p.model.trim(),
      if (p.baseUrl.toLowerCase().contains('api.groq.com'))
        ..._groqFallbackChain
      else if (p.baseUrl.toLowerCase().contains('googleapis.com'))
        ..._geminiFallbackChain
      else if (p.baseUrl.toLowerCase().contains('api.openai.com'))
        ..._openAiFallbackChain,
    ];

    final tried = <String>{};
    Object? lastError;

    for (final candidate in candidates) {
      if (candidate.isEmpty || !tried.add(candidate)) continue;
      try {
        final text = await _requestSingleModel(
          p.copyWith(model: candidate),
          prompt,
          history: history,
          systemPrompt: systemPrompt,
        );
        return (replyText: text, modelUsed: candidate);
      } catch (e) {
        lastError = e;
        if (!_isModelError(e.toString())) {
          // If it's an auth error (401) or network timeout, don't keep trying models on the same key.
          rethrow;
        }
      }
    }

    // Dynamic discovery via GET /models if all static candidates failed with a model error
    final liveModels = await fetchAvailableModels(p);
    for (final liveModel in liveModels.take(4)) {
      if (!tried.add(liveModel)) continue;
      try {
        final text = await _requestSingleModel(
          p.copyWith(model: liveModel),
          prompt,
          history: history,
          systemPrompt: systemPrompt,
        );
        return (replyText: text, modelUsed: liveModel);
      } catch (e) {
        lastError = e;
        if (!_isModelError(e.toString())) rethrow;
      }
    }

    throw lastError ?? const HttpException('Nenhum modelo compatível respondeu.');
  }

  static bool _isModelError(String errorText) {
    final lower = errorText.toLowerCase();
    return lower.contains('http 400') ||
        lower.contains('http 404') ||
        lower.contains('model') ||
        lower.contains('decommissioned') ||
        lower.contains('not_found') ||
        lower.contains('not found') ||
        lower.contains('does not exist') ||
        lower.contains('deprecated') ||
        lower.contains('invalid_request_error');
  }

  Future<String> _requestSingleModel(
    AiProviderConfig p,
    String prompt, {
    List<Map<String, String>> history = const [],
    String? systemPrompt,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final base = p.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse(
        base.endsWith('/chat/completions') ? base : '$base/chat/completions',
      );
      final req =
          await client.postUrl(uri).timeout(const Duration(seconds: 20));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${p.apiKey}');
      req.headers.contentType = ContentType.json;
      final baseMessages = buildAiMessages(prompt, history);
      final messages = <Map<String, String>>[
        if (systemPrompt != null && systemPrompt.trim().isNotEmpty)
          {'role': 'system', 'content': systemPrompt.trim()},
        ...baseMessages,
      ];
      req.write(
        jsonEncode({
          'model': p.model,
          'messages': messages,
          'temperature': 0.4,
        }),
      );
      final response = await req.close().timeout(const Duration(seconds: 25));
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String message = 'Falha HTTP ${response.statusCode}';
        try {
          final error = jsonDecode(body);
          message = (error['error']?['message'] ?? error['message'] ?? message)
              .toString();
        } catch (_) {}
        message = redactSecret(message, p.apiKey);
        if (message.length > 220) message = message.substring(0, 220);
        throw HttpException('HTTP ${response.statusCode}: $message');
      }
      return parseAiReply(body);
    } finally {
      client.close(force: true);
    }
  }
}

/// Filters `/models` response to usable chat models and ranks modern models first.
List<String> parseChatModelsList(String body) {
  try {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final rawList = decoded['data'] as List? ?? const [];
    final ids = <String>[];
    for (final item in rawList) {
      if (item is Map) {
        final id = (item['id'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        final lower = id.toLowerCase();
        if (lower.contains('whisper') ||
            lower.contains('tts') ||
            lower.contains('orpheus') ||
            lower.contains('guard') ||
            lower.contains('embed') ||
            lower.contains('moderation') ||
            lower.contains('dall-e') ||
            lower.contains('audio')) {
          continue;
        }
        ids.add(id);
      }
    }
    ids.sort((a, b) => _modelRank(a).compareTo(_modelRank(b)));
    return ids;
  } catch (_) {
    return const [];
  }
}

int _modelRank(String id) {
  final l = id.toLowerCase();
  if (l == 'openai/gpt-oss-120b') return 0;
  if (l == 'openai/gpt-oss-20b') return 1;
  if (l.contains('gemini-2.5-flash')) return 2;
  if (l.contains('gpt-4.1') || l.contains('gpt-4o')) return 3;
  if (l.contains('qwen3') || l.contains('qwen-3')) return 4;
  if (l.contains('kimi') || l.contains('deepseek')) return 5;
  if (l.contains('gpt-oss')) return 6;
  return 10;
}

/// Keeps only usable turns, caps the window and appends the new prompt.
List<Map<String, String>> buildAiMessages(
  String prompt,
  List<Map<String, String>> history,
) {
  final messages = <Map<String, String>>[];
  for (final item in history.take(12)) {
    final role = item['role'], content = item['content'];
    if ((role == 'user' || role == 'assistant') &&
        content != null &&
        content.trim().isNotEmpty) {
      messages.add({'role': role!, 'content': content});
    }
  }
  messages.add({'role': 'user', 'content': prompt});
  return messages;
}

String parseAiReply(String body) {
  final data = jsonDecode(body) as Map<String, dynamic>;
  final text = ((data['choices'] as List?)?.first['message']?['content'] ?? '')
      .toString();
  if (text.trim().isEmpty) throw const FormatException('Resposta vazia');
  return text;
}

/// Provider errors echo the request back; never let the key reach the UI.
String redactSecret(String message, String secret) {
  if (secret.trim().isEmpty) return message;
  return message.replaceAll(secret, '[chave ocultada]');
}

