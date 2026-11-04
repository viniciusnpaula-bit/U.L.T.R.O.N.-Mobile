import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class FreeProviderPreset {
  const FreeProviderPreset({
    required this.id,
    required this.name,
    required this.badge,
    required this.description,
    required this.baseUrl,
    required this.defaultModel,
    required this.recommendedModels,
    required this.getKeyUrl,
    this.requiresKey = true,
  });

  final String id;
  final String name;
  final String badge;
  final String description;
  final String baseUrl;
  final String defaultModel;
  final List<String> recommendedModels;
  final String getKeyUrl;
  final bool requiresKey;

  static const catalog = <FreeProviderPreset>[
    FreeProviderPreset(
      id: 'pollinations_free',
      name: 'Pollinations AI (Zero-Key)',
      badge: '100% GRÁTIS • SEM CHAVE',
      description:
          'Funciona instantaneamente sem precisar de cadastro ou chave de API. Ideal para uso imediato ou fallback automático.',
      baseUrl: 'https://text.pollinations.ai/openai',
      defaultModel: 'openai',
      recommendedModels: [
        'openai',
        'mistral',
        'qwen-coder',
        'deepseek-reasoning',
      ],
      getKeyUrl: 'https://pollinations.ai',
      requiresKey: false,
    ),
    FreeProviderPreset(
      id: 'groq_free',
      name: 'Groq Cloud (LPU)',
      badge: 'GRÁTIS • ULTRA RÁPIDO',
      description:
          'Inferência em milissegundos no plano gratuito (Free Tier). Crie uma chave gsk_... grátis em 10 segundos.',
      baseUrl: 'https://api.groq.com/openai/v1',
      defaultModel: 'openai/gpt-oss-120b',
      recommendedModels: [
        'openai/gpt-oss-120b',
        'openai/gpt-oss-20b',
        'qwen/qwen3-32b',
        'moonshotai/kimi-k2-instruct',
        'llama-3.3-70b-versatile',
      ],
      getKeyUrl: 'https://console.groq.com/keys',
    ),
    FreeProviderPreset(
      id: 'gemini_free',
      name: 'Google Gemini Studio',
      badge: 'GRÁTIS • GOOGLE AI',
      description:
          'Plano gratuito oficial do Google AI Studio com suporte a Gemini 2.5 Flash e Pro (15 RPM grátis).',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      defaultModel: 'gemini-2.5-flash',
      recommendedModels: [
        'gemini-2.5-flash',
        'gemini-2.5-pro',
        'gemini-2.0-flash',
      ],
      getKeyUrl: 'https://aistudio.google.com/app/apikey',
    ),
    FreeProviderPreset(
      id: 'openrouter_free',
      name: 'OpenRouter (:free)',
      badge: 'GRÁTIS • +30 MODELOS',
      description:
          'Acesso unificado a dezenas de modelos com sufixo :free (DeepSeek R1, Qwen 3, Gemini, Llama 3.3) sem cartão.',
      baseUrl: 'https://openrouter.ai/api/v1',
      defaultModel: 'deepseek/deepseek-r1:free',
      recommendedModels: [
        'deepseek/deepseek-r1:free',
        'deepseek/deepseek-chat-v3-0324:free',
        'qwen/qwen3-235b-a22b:free',
        'google/gemini-2.0-flash-exp:free',
        'meta-llama/llama-3.3-70b-instruct:free',
      ],
      getKeyUrl: 'https://openrouter.ai/settings/keys',
    ),
    FreeProviderPreset(
      id: 'cerebras_free',
      name: 'Cerebras Inference',
      badge: 'GRÁTIS • 2000+ TOK/S',
      description:
          'Wafer-Scale Engine com 1 milhão de tokens gratuitos por dia e velocidade recorde.',
      baseUrl: 'https://api.cerebras.ai/v1',
      defaultModel: 'llama-3.3-70b',
      recommendedModels: [
        'llama-3.3-70b',
        'qwen-3-32b',
        'llama3.1-8b',
      ],
      getKeyUrl: 'https://cloud.cerebras.ai/',
    ),
    FreeProviderPreset(
      id: 'github_models_free',
      name: 'GitHub Models',
      badge: 'GRÁTIS • CONTA GITHUB',
      description:
          'Use seu Personal Access Token (PAT) gratuito do GitHub para rodar GPT-4o-mini, GPT-4o e DeepSeek R1.',
      baseUrl: 'https://models.inference.ai.azure.com',
      defaultModel: 'gpt-4o-mini',
      recommendedModels: [
        'gpt-4o-mini',
        'gpt-4o',
        'DeepSeek-R1',
        'Llama-3.3-70B-Instruct',
      ],
      getKeyUrl: 'https://github.com/settings/tokens',
    ),
    FreeProviderPreset(
      id: 'mistral_free',
      name: 'Mistral La Plateforme',
      badge: 'GRÁTIS • EXPERIMENT PLAN',
      description:
          'Plano Experiment 100% gratuito da Mistral AI para chat tático e geração de código (Codestral).',
      baseUrl: 'https://api.mistral.ai/v1',
      defaultModel: 'mistral-small-latest',
      recommendedModels: [
        'mistral-small-latest',
        'codestral-latest',
        'open-mistral-nemo',
      ],
      getKeyUrl: 'https://console.mistral.ai/api-keys',
    ),
    FreeProviderPreset(
      id: 'sambanova_free',
      name: 'SambaNova Cloud',
      badge: 'GRÁTIS • RDU CLOUD',
      description:
          'Acesso gratuito de alta velocidade aos modelos DeepSeek-R1, Llama 3.3 70B e Qwen 2.5 72B.',
      baseUrl: 'https://api.sambanova.ai/v1',
      defaultModel: 'Meta-Llama-3.3-70B-Instruct',
      recommendedModels: [
        'Meta-Llama-3.3-70B-Instruct',
        'DeepSeek-R1',
        'Qwen2.5-72B-Instruct',
      ],
      getKeyUrl: 'https://cloud.sambanova.ai/apis',
    ),
    FreeProviderPreset(
      id: 'huggingface_free',
      name: 'HuggingFace Router',
      badge: 'GRÁTIS • OPEN SOURCE',
      description:
          'Inference Router gratuito usando seu token de leitura/inferência do Hugging Face Hub.',
      baseUrl: 'https://router.huggingface.co/v1',
      defaultModel: 'Qwen/Qwen2.5-72B-Instruct',
      recommendedModels: [
        'Qwen/Qwen2.5-72B-Instruct',
        'deepseek-ai/DeepSeek-R1',
        'meta-llama/Llama-3.3-70B-Instruct',
      ],
      getKeyUrl: 'https://huggingface.co/settings/tokens',
    ),
  ];
}

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

  bool get isKeylessProvider =>
      baseUrl.toLowerCase().contains('pollinations.ai') ||
      apiKey.trim().toLowerCase() == 'free';

  bool get hasUsableCredentials =>
      isKeylessProvider || apiKey.trim().isNotEmpty;

  String get effectiveToken =>
      apiKey.trim().isEmpty ? 'free' : apiKey.trim();

  AiProviderConfig copyWith({
    String? name,
    String? baseUrl,
    String? model,
    String? apiKey,
    bool? enabled,
    int? priority,
  }) =>
      AiProviderConfig(
        id: id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        apiKey: apiKey ?? this.apiKey,
        enabled: enabled ?? this.enabled,
        priority: priority ?? this.priority,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'model': model,
        'apiKey': apiKey,
        'enabled': enabled,
        'priority': priority,
      };

  factory AiProviderConfig.fromJson(Map<String, Object?> json) {
    final baseUrl = json['baseUrl'] as String? ?? '';
    final rawModel = json['model'] as String? ?? '';
    return AiProviderConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      baseUrl: baseUrl,
      model: AiProviderStore.normalizeModelForUrl(baseUrl, rawModel),
      apiKey: json['apiKey'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
    );
  }

  /// Queries `<baseUrl>/models` to fetch active, non-deprecated chat models
  /// directly from the provider.
  Future<List<String>> fetchAvailableModels({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final cleanUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (cleanUrl.toLowerCase().contains('pollinations.ai')) {
      return const ['openai', 'mistral', 'qwen-coder', 'deepseek-reasoning'];
    }
    if (!hasUsableCredentials) {
      throw StateError('Informe a chave da API para listar os modelos.');
    }
    final uri = AiFailover._requireHttps('$cleanUrl/models');
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $effectiveToken',
      );
      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'HTTP ${response.statusCode}: ${redactSecret(body, apiKey)}',
        );
      }
      return parseChatModelsList(body);
    } finally {
      client.close(force: true);
    }
  }

  /// Tests whether this provider is reachable and returns the active model used.
  Future<String> testConnection({
    Duration timeout = const Duration(seconds: 14),
  }) async {
    if (!hasUsableCredentials) {
      throw StateError('Chave de API vazia.');
    }
    final failover = AiFailover(store: _SingleProviderStore(this));
    final reply = await failover.ask(
      'Responda apenas: OK',
      timeout: timeout,
    );
    return '${reply.provider}: ${reply.text}';
  }
}

class _SingleProviderStore extends AiProviderStore {
  _SingleProviderStore(this._provider) : super(storage: null);
  final AiProviderConfig _provider;

  @override
  Future<List<AiProviderConfig>> load() async => [_provider];

  @override
  Future<void> save(List<AiProviderConfig> providers) async {}
}

class AiProviderStore {
  AiProviderStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'ultron.ai.providers.v1';
  final FlutterSecureStorage _storage;

  /// Legacy Llama models that were deprecated/decommissioned or replaced by
  /// newer default flagship models.
  static const _deprecatedGroqModels = <String>{
    'llama-3.3-70b-versatile',
    'llama-3.1-70b-versatile',
    'llama-3.1-8b-instant',
    'llama3-70b-8192',
    'llama3-8b-8192',
    'mixtral-8x7b-32768',
    'gemma2-9b-it',
  };

  /// Automatically upgrades legacy/deprecated models when loading from storage.
  static String normalizeModelForUrl(String baseUrl, String model) {
    final cleanModel = model.trim();
    final lowerUrl = baseUrl.toLowerCase();
    if (lowerUrl.contains('pollinations.ai')) {
      return cleanModel.isEmpty ? 'openai' : cleanModel;
    }
    if (lowerUrl.contains('groq.com')) {
      if (cleanModel.isEmpty || _deprecatedGroqModels.contains(cleanModel)) {
        return 'openai/gpt-oss-120b';
      }
    } else if (lowerUrl.contains('openai.com')) {
      if (cleanModel.isEmpty || cleanModel == 'gpt-4o-mini') {
        return 'gpt-4.1-mini';
      }
    } else if (lowerUrl.contains('googleapis.com')) {
      if (cleanModel.isEmpty || cleanModel.startsWith('gemini-1.5')) {
        return 'gemini-2.5-flash';
      }
    } else if (lowerUrl.contains('openrouter.ai')) {
      if (cleanModel.isEmpty) {
        return 'deepseek/deepseek-r1:free';
      }
    } else if (lowerUrl.contains('cerebras.ai')) {
      if (cleanModel.isEmpty) {
        return 'llama-3.3-70b';
      }
    }
    return cleanModel.isEmpty ? 'openai/gpt-oss-120b' : cleanModel;
  }

  /// Fallback models tried automatically if the primary model on a provider
  /// is unavailable, rate-limited, or decommissioned.
  static List<String> fallbackModelsFor(String baseUrl, String primaryModel) {
    final lowerUrl = baseUrl.toLowerCase();
    final candidates = <String>[primaryModel];
    if (lowerUrl.contains('pollinations.ai')) {
      for (final m in const [
        'openai',
        'mistral',
        'qwen-coder',
      ]) {
        if (!candidates.contains(m)) candidates.add(m);
      }
    } else if (lowerUrl.contains('groq.com')) {
      for (final m in const [
        'openai/gpt-oss-120b',
        'openai/gpt-oss-20b',
        'qwen/qwen3-32b',
        'moonshotai/kimi-k2-instruct',
        'llama-3.3-70b-versatile',
      ]) {
        if (!candidates.contains(m)) candidates.add(m);
      }
    } else if (lowerUrl.contains('openai.com')) {
      for (final m in const ['gpt-4.1-mini', 'gpt-4o-mini']) {
        if (!candidates.contains(m)) candidates.add(m);
      }
    } else if (lowerUrl.contains('googleapis.com')) {
      for (final m in const [
        'gemini-2.5-flash',
        'gemini-2.0-flash',
      ]) {
        if (!candidates.contains(m)) candidates.add(m);
      }
    } else if (lowerUrl.contains('openrouter.ai')) {
      for (final m in const [
        'deepseek/deepseek-r1:free',
        'deepseek/deepseek-chat-v3-0324:free',
        'qwen/qwen3-235b-a22b:free',
        'google/gemini-2.0-flash-exp:free',
        'meta-llama/llama-3.3-70b-instruct:free',
      ]) {
        if (!candidates.contains(m)) candidates.add(m);
      }
    } else if (lowerUrl.contains('cerebras.ai')) {
      for (final m in const ['llama-3.3-70b', 'qwen-3-32b', 'llama3.1-8b']) {
        if (!candidates.contains(m)) candidates.add(m);
      }
    } else if (lowerUrl.contains('mistral.ai')) {
      for (final m in const [
        'mistral-small-latest',
        'open-mistral-nemo',
      ]) {
        if (!candidates.contains(m)) candidates.add(m);
      }
    }
    return candidates;
  }

  Future<List<AiProviderConfig>> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) {
      // Seed default Zero-Key Free Provider so Ultron works out-of-the-box for free!
      return const [
        AiProviderConfig(
          id: 'default_pollinations_free',
          name: 'Pollinations Free (Sem Chave)',
          baseUrl: 'https://text.pollinations.ai/openai',
          model: 'openai',
          apiKey: 'free',
          enabled: true,
          priority: 0,
        ),
      ];
    }
    final decoded = jsonDecode(raw) as List<Object?>;
    final list = decoded
        .cast<Map<String, Object?>>()
        .map(AiProviderConfig.fromJson)
        .toList();
    list.sort((a, b) => a.priority.compareTo(b.priority));
    return list;
  }

  Future<void> save(List<AiProviderConfig> providers) async {
    final encoded = jsonEncode(providers.map((p) => p.toJson()).toList());
    await _storage.write(key: _key, value: encoded);
  }
}

class AiReply {
  const AiReply({required this.provider, required this.text});
  final String provider;
  final String text;
}

class AiFailover {
  AiFailover({AiProviderStore? store, HttpClient Function()? httpFactory})
      : _store = store ?? AiProviderStore(),
        _httpFactory = httpFactory ?? HttpClient.new;

  final AiProviderStore _store;
  final HttpClient Function() _httpFactory;

  Future<AiReply> ask(
    String prompt, {
    List<Map<String, String>> history = const [],
    String? systemPrompt,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final providers = (await _store.load())
        .where((p) => p.enabled && p.hasUsableCredentials)
        .toList();
    if (providers.isEmpty) {
      throw StateError(
        'Nenhum provedor de IA ativo. Abra Configurações de IA e ative o Pollinations Free (Sem Chave) ou adicione uma chave gratuita.',
      );
    }

    Object? lastError;
    for (final p in providers) {
      final candidateModels = AiProviderStore.fallbackModelsFor(
        p.baseUrl,
        p.model,
      );
      for (final candidateModel in candidateModels) {
        try {
          final candidateConfig = p.copyWith(model: candidateModel);
          final text = await _askProvider(
            candidateConfig,
            prompt,
            history,
            systemPrompt,
            timeout,
          );
          final label = candidateModel == p.model
              ? p.name
              : '${p.name} ($candidateModel)';
          return AiReply(provider: label, text: text);
        } catch (err) {
          lastError = err;
        }
      }
    }
    throw StateError('Todos os provedores falharam: $lastError');
  }

  Future<String> _askProvider(
    AiProviderConfig p,
    String prompt,
    List<Map<String, String>> history,
    String? systemPrompt,
    Duration timeout,
  ) async {
    final cleanBase = p.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = _requireHttps('$cleanBase/chat/completions');
    final client = _httpFactory()..connectionTimeout = timeout;
    try {
      final request = await client.postUrl(uri).timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${p.effectiveToken}',
      );
      final messages = <Map<String, String>>[
        if (systemPrompt != null && systemPrompt.trim().isNotEmpty)
          {'role': 'system', 'content': systemPrompt.trim()},
        ...buildAiMessages(prompt, history),
      ];
      request.add(
        utf8.encode(
          jsonEncode({
            'model': p.model,
            'messages': messages,
            'temperature': 0.4,
          }),
        ),
      );
      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          '${p.name} (${p.model}) HTTP ${response.statusCode}: ${redactSecret(body, p.apiKey)}',
        );
      }
      return parseAiReply(body);
    } catch (err) {
      if (err is HttpException) rethrow;
      throw HttpException(
        '${p.name} (${p.model}): ${redactSecret(err.toString(), p.apiKey)}',
      );
    } finally {
      client.close(force: true);
    }
  }

  static Uri _requireHttps(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw ArgumentError('URL do provedor deve usar HTTPS: $rawUrl');
    }
    return uri;
  }
}

const _allowedHistoryRoles = {'user', 'assistant'};
const _maxHistoryMessages = 12;

List<Map<String, String>> buildAiMessages(
  String prompt,
  List<Map<String, String>> history,
) {
  final filtered = history
      .where(
        (m) =>
            _allowedHistoryRoles.contains(m['role']) &&
            (m['content']?.trim().isNotEmpty ?? false),
      )
      .take(_maxHistoryMessages)
      .map((m) => {'role': m['role']!, 'content': m['content']!})
      .toList();
  filtered.add({'role': 'user', 'content': prompt});
  return filtered;
}

String parseAiReply(String rawBody) {
  final decoded = jsonDecode(rawBody) as Map<String, Object?>;
  final choices = decoded['choices'] as List<Object?>?;
  if (choices == null || choices.isEmpty) {
    throw const FormatException('Resposta sem choices.');
  }
  final message =
      (choices.first as Map<String, Object?>)['message'] as Map<String, Object?>?;
  final content = message?['content'] as String?;
  if (content == null || content.trim().isEmpty) {
    throw const FormatException('Resposta vazia do provedor.');
  }
  return content.trim();
}

/// Parses `/v1/models` response and filters out non-chat models (whisper, tts,
/// guard, embeddings) while sorting modern flagship models to the top.
List<String> parseChatModelsList(String rawBody) {
  final decoded = jsonDecode(rawBody) as Map<String, Object?>;
  final data = decoded['data'] as List<Object?>? ?? const [];
  final ids = <String>[];
  for (final item in data) {
    if (item is Map<String, Object?>) {
      final id = (item['id'] as String?)?.trim() ?? '';
      final active = item['active'] as bool? ?? true;
      if (id.isEmpty || !active) continue;
      final lower = id.toLowerCase();
      if (lower.contains('whisper') ||
          lower.contains('tts') ||
          lower.contains('playai') ||
          lower.contains('orpheus') ||
          lower.contains('guard') ||
          lower.contains('safeguard') ||
          lower.contains('embed')) {
        continue;
      }
      ids.add(id);
    }
  }
  ids.sort((a, b) {
    int rank(String m) {
      final l = m.toLowerCase();
      if (l.contains(':free')) return 0;
      if (l.startsWith('openai/gpt-oss-120b')) return 1;
      if (l.startsWith('openai/gpt-oss')) return 2;
      if (l.startsWith('gemini-2.5')) return 3;
      if (l.startsWith('gpt-4.1')) return 4;
      if (l.contains('qwen3') || l.contains('kimi') || l.contains('deepseek')) {
        return 5;
      }
      return 6;
    }

    final r = rank(a).compareTo(rank(b));
    return r != 0 ? r : a.compareTo(b);
  });
  return ids;
}

String redactSecret(String text, String secret) {
  final trimmed = secret.trim();
  if (trimmed.isEmpty || trimmed.toLowerCase() == 'free') return text;
  return text.replaceAll(trimmed, '[chave ocultada]');
}
