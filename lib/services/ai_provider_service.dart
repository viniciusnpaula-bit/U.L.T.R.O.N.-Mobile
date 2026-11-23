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

  String get effectiveToken => apiKey.trim().isEmpty ? 'free' : apiKey.trim();

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

class SttConfig {
  const SttConfig({
    this.endpointUrl = defaultEndpointUrl,
    this.model = defaultModel,
    this.apiKey = '',
    this.language = 'pt',
  });

  static const String defaultEndpointUrl =
      'https://api.groq.com/openai/v1/audio/transcriptions';
  static const String defaultModel = 'whisper-large-v3';

  final String endpointUrl;
  final String model;
  final String apiKey;
  final String language;

  Map<String, dynamic> toJson() => {
        'endpointUrl': endpointUrl,
        'model': model,
        'apiKey': apiKey,
        'language': language,
      };

  factory SttConfig.fromJson(Map<String, dynamic> j) => SttConfig(
        endpointUrl: (j['endpointUrl'] as String?)?.trim().isNotEmpty == true
            ? (j['endpointUrl'] as String).trim()
            : defaultEndpointUrl,
        model: (j['model'] as String?)?.trim().isNotEmpty == true
            ? (j['model'] as String).trim()
            : defaultModel,
        apiKey: (j['apiKey'] as String?) ?? '',
        language: (j['language'] as String?)?.trim().isNotEmpty == true
            ? (j['language'] as String).trim()
            : 'pt',
      );
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
  static const _sttKey = 'ultron.ai.stt.v1';
  final FlutterSecureStorage _storage;

  Future<SttConfig?> loadSttConfig() async {
    final raw = await _storage.read(key: _sttKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return SttConfig.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSttConfig(SttConfig config) =>
      _storage.write(key: _sttKey, value: jsonEncode(config.toJson()));

  Future<void> deleteSttConfig() => _storage.delete(key: _sttKey);

  /// Resolves the active STT configuration, reusing an enabled Groq chat
  /// provider key automatically when no dedicated STT key was saved.
  Future<SttConfig> resolveSttConfig() async {
    final saved = await loadSttConfig();
    if (saved != null && saved.apiKey.trim().isNotEmpty) {
      return saved;
    }
    final providers = (await load())
        .where((p) => p.enabled && p.apiKey.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
    for (final p in providers) {
      final baseLower = p.baseUrl.toLowerCase();
      final nameLower = p.name.toLowerCase();
      if (baseLower.contains('api.groq.com') || nameLower.contains('groq')) {
        return SttConfig(
          endpointUrl: saved?.endpointUrl ?? SttConfig.defaultEndpointUrl,
          model: saved?.model ?? SttConfig.defaultModel,
          apiKey: p.apiKey,
          language: saved?.language ?? 'pt',
        );
      }
    }
    return saved ?? const SttConfig();
  }

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

  /// Indica se o identificador de modelo suporta entrada multimodal (imagem).
  static bool isVisionCapableModel(String model) {
    final lower = model.trim().toLowerCase();
    if (lower.isEmpty) return false;
    return lower == 'openai' ||
        lower == 'openai-large' ||
        lower.contains('gemini-2') ||
        lower.contains('gemini-1.5') ||
        lower.contains('gpt-4o') ||
        lower.contains('gpt-4.1') ||
        lower.contains('vision') ||
        lower.contains('-vl') ||
        lower.contains('pixtral') ||
        lower.contains('scout') ||
        lower.contains('maverick') ||
        lower.contains('llava');
  }

  /// Fallback models tried automatically if the primary model on a provider
  /// is unavailable, rate-limited, or decommissioned.
  static List<String> fallbackModelsFor(
    String baseUrl,
    String primaryModel, {
    bool requiresVision = false,
  }) {
    final lowerUrl = baseUrl.toLowerCase();
    final candidates = <String>[
      if (!requiresVision || isVisionCapableModel(primaryModel)) primaryModel,
    ];
    if (lowerUrl.contains('pollinations.ai')) {
      final models = requiresVision
          ? const ['openai', 'openai-large']
          : const ['openai', 'mistral', 'qwen-coder'];
      for (final m in models) {
        if (!candidates.contains(m)) candidates.add(m);
      }
    } else if (lowerUrl.contains('groq.com')) {
      final groqModels = requiresVision
          ? const [
              'meta-llama/llama-4-scout-17b-16e-instruct',
              'meta-llama/llama-4-maverick-17b-128e-instruct',
            ]
          : const [
              'openai/gpt-oss-120b',
              'openai/gpt-oss-20b',
              'qwen/qwen3-32b',
              'moonshotai/kimi-k2-instruct',
              'llama-3.3-70b-versatile',
            ];
      for (final m in groqModels) {
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
      final openRouterModels = requiresVision
          ? const [
              'google/gemini-2.0-flash-exp:free',
              'qwen/qwen2.5-vl-72b-instruct:free',
              'meta-llama/llama-3.2-11b-vision-instruct:free',
            ]
          : const [
              'deepseek/deepseek-r1:free',
              'deepseek/deepseek-chat-v3-0324:free',
              'qwen/qwen3-235b-a22b:free',
              'google/gemini-2.0-flash-exp:free',
              'meta-llama/llama-3.3-70b-instruct:free',
            ];
      for (final m in openRouterModels) {
        if (!candidates.contains(m)) candidates.add(m);
      }
    } else if (lowerUrl.contains('inference.ai.azure.com') ||
        lowerUrl.contains('github')) {
      for (final m in const ['gpt-4o-mini', 'gpt-4o']) {
        if (!candidates.contains(m)) candidates.add(m);
      }
    } else if (lowerUrl.contains('cerebras.ai')) {
      for (final m in const ['llama-3.3-70b', 'qwen-3-32b', 'llama3.1-8b']) {
        if (!candidates.contains(m)) candidates.add(m);
      }
    } else if (lowerUrl.contains('mistral.ai')) {
      final mistralModels = requiresVision
          ? const ['pixtral-12b-2409']
          : const ['mistral-small-latest', 'open-mistral-nemo'];
      for (final m in mistralModels) {
        if (!candidates.contains(m)) candidates.add(m);
      }
    }
    if (!candidates.contains(primaryModel) && primaryModel.trim().isNotEmpty) {
      candidates.add(primaryModel);
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

class AiUsageInfo {
  const AiUsageInfo({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
    required this.estimated,
  });

  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final bool estimated;
}

class ParsedAiReply {
  const ParsedAiReply({
    required this.text,
    required this.usage,
  });

  final String text;
  final AiUsageInfo usage;
}

class AiReply {
  const AiReply({
    required this.provider,
    required this.text,
    this.failedAttempts = 0,
    this.elapsedMs = 0,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
    this.tokensEstimated = false,
  });

  final String provider;
  final String text;
  final int failedAttempts;
  final int elapsedMs;
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final bool tokensEstimated;

  bool get usedFailover => failedAttempts > 0;
}

/// Telemetria acumulada da sessão ativa do cockpit (BRAIN, latência, turnos e tokens).
class SessionTelemetry {
  const SessionTelemetry({
    required this.startedAt,
    this.turns = 0,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
    this.hasEstimatedTokens = false,
    this.lastProvider = 'Failover Pronto',
    this.lastLatencyMs = 0,
    this.lastFailedAttempts = 0,
    this.failoverEvents = 0,
  });

  factory SessionTelemetry.initial({
    DateTime? startedAt,
    String initialProvider = 'Failover Pronto',
  }) =>
      SessionTelemetry(
        startedAt: startedAt ?? DateTime.now(),
        lastProvider: initialProvider,
      );

  final DateTime startedAt;
  final int turns;
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final bool hasEstimatedTokens;
  final String lastProvider;
  final int lastLatencyMs;
  final int lastFailedAttempts;
  final int failoverEvents;

  bool get lastUsedFailover => lastFailedAttempts > 0;

  SessionTelemetry recordReply(AiReply reply) {
    final addedTotal = reply.totalTokens > 0
        ? reply.totalTokens
        : reply.promptTokens + reply.completionTokens;
    return SessionTelemetry(
      startedAt: startedAt,
      turns: turns + 1,
      promptTokens: promptTokens + reply.promptTokens,
      completionTokens: completionTokens + reply.completionTokens,
      totalTokens: totalTokens + addedTotal,
      hasEstimatedTokens: hasEstimatedTokens || reply.tokensEstimated,
      lastProvider: reply.provider,
      lastLatencyMs: reply.elapsedMs,
      lastFailedAttempts: reply.failedAttempts,
      failoverEvents: failoverEvents + (reply.usedFailover ? 1 : 0),
    );
  }

  SessionTelemetry withActiveProvider(String providerName) => SessionTelemetry(
        startedAt: startedAt,
        turns: turns,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        totalTokens: totalTokens,
        hasEstimatedTokens: hasEstimatedTokens,
        lastProvider: providerName,
        lastLatencyMs: lastLatencyMs,
        lastFailedAttempts: lastFailedAttempts,
        failoverEvents: failoverEvents,
      );

  static String formatCompactTokens(int tokens) {
    if (tokens >= 1000000) {
      return '${(tokens / 1000000).toStringAsFixed(1)}M';
    }
    if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(1)}k';
    }
    return '$tokens';
  }
}

class _ProviderHttpException implements Exception {
  _ProviderHttpException(this.statusCode, this.message);

  final int? statusCode;
  final String message;

  bool get isAuthFailure => statusCode == 401 || statusCode == 403;
  bool get isRateLimited => statusCode == 429;
  bool get skipRemainingModels => isAuthFailure || isRateLimited;

  @override
  String toString() => message;
}

class _ProviderCircuitState {
  int failures = 0;
  DateTime? openUntil;
}

class AiFailover {
  AiFailover({
    AiProviderStore? store,
    HttpClient Function()? httpFactory,
    this.circuitCooldown = const Duration(seconds: 45),
    this.authCooldown = const Duration(minutes: 2),
    this.failureThreshold = 2,
    DateTime Function()? now,
  })  : _store = store ?? AiProviderStore(),
        _httpFactory = httpFactory ?? HttpClient.new,
        _now = now ?? DateTime.now;

  static final Map<String, _ProviderCircuitState> _circuits = {};

  /// Limpa os circuit breakers globais (útil em testes e após editar provedores).
  static void resetCircuitBreakers() => _circuits.clear();

  final AiProviderStore _store;
  final HttpClient Function() _httpFactory;
  final Duration circuitCooldown;
  final Duration authCooldown;
  final int failureThreshold;
  final DateTime Function() _now;

  static String _circuitKey(AiProviderConfig p) => '${p.id}::${p.baseUrl.trim()}';

  Future<AiReply> ask(
    String prompt, {
    List<Map<String, String>> history = const [],
    String? systemPrompt,
    String? imageBase64,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final providers = (await _store.load())
        .where((p) => p.enabled && p.hasUsableCredentials)
        .toList();
    if (providers.isEmpty) {
      throw StateError(
        'Nenhum provedor de IA ativo. Abra Configurações de IA e ative o Pollinations Free (Sem Chave) ou adicione uma chave gratuita.',
      );
    }

    final requiresVision = imageBase64 != null && imageBase64.isNotEmpty;
    final effectiveTimeout = requiresVision && timeout < const Duration(seconds: 18)
        ? const Duration(seconds: 18)
        : timeout;

    final now = _now();
    final activeProviders = <AiProviderConfig>[];
    for (final p in providers) {
      final state = _circuits[_circuitKey(p)];
      if (state?.openUntil == null || !now.isBefore(state!.openUntil!)) {
        activeProviders.add(p);
      }
    }
    if (activeProviders.isEmpty) {
      // Todos os provedores em cooldown: tenta primeiro o que expira mais cedo (half-open).
      final sorted = [...providers]..sort((a, b) {
          final aUntil = _circuits[_circuitKey(a)]?.openUntil ?? now;
          final bUntil = _circuits[_circuitKey(b)]?.openUntil ?? now;
          return aUntil.compareTo(bUntil);
        });
      activeProviders.add(sorted.first);
    }

    final sw = Stopwatch()..start();
    var failedAttempts = 0;
    Object? lastError;

    for (final p in activeProviders) {
      final key = _circuitKey(p);
      final candidateModels = AiProviderStore.fallbackModelsFor(
        p.baseUrl,
        p.model,
        requiresVision: requiresVision,
      );
      for (final candidateModel in candidateModels) {
        try {
          final candidateConfig = p.copyWith(model: candidateModel);
          final parsed = await _askProvider(
            candidateConfig,
            prompt,
            history,
            systemPrompt,
            effectiveTimeout,
            imageBase64: imageBase64,
          );
          _circuits.remove(key);
          sw.stop();
          final label = candidateModel == p.model
              ? p.name
              : '${p.name} ($candidateModel)';
          return AiReply(
            provider: label,
            text: parsed.text,
            failedAttempts: failedAttempts,
            elapsedMs: sw.elapsedMilliseconds,
            promptTokens: parsed.usage.promptTokens,
            completionTokens: parsed.usage.completionTokens,
            totalTokens: parsed.usage.totalTokens,
            tokensEstimated: parsed.usage.estimated,
          );
        } catch (err) {
          failedAttempts++;
          lastError = err;
          final state = _circuits.putIfAbsent(key, _ProviderCircuitState.new);
          if (err is _ProviderHttpException && err.isAuthFailure) {
            state.failures = failureThreshold;
            state.openUntil = _now().add(authCooldown);
            break;
          }
          if (err is _ProviderHttpException && err.isRateLimited) {
            state.failures = failureThreshold;
            state.openUntil = _now().add(circuitCooldown);
            break;
          }
          state.failures++;
          if (state.failures >= failureThreshold) {
            state.openUntil = _now().add(circuitCooldown);
            break;
          }
        }
      }
    }
    sw.stop();
    throw StateError('Todos os provedores falharam: $lastError');
  }

  Future<ParsedAiReply> _askProvider(
    AiProviderConfig p,
    String prompt,
    List<Map<String, String>> history,
    String? systemPrompt,
    Duration timeout, {
    String? imageBase64,
  }) async {
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
      final messages = <Map<String, Object>>[
        if (systemPrompt != null && systemPrompt.trim().isNotEmpty)
          {'role': 'system', 'content': systemPrompt.trim()},
        ...buildAiMessages(prompt, history, imageBase64: imageBase64),
      ];
      final promptChars = _countPromptChars(messages);
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
      final body =
          await response.transform(utf8.decoder).join().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _ProviderHttpException(
          response.statusCode,
          '${p.name} (${p.model}) HTTP ${response.statusCode}: ${redactSecret(body, p.apiKey)}',
        );
      }
      return parseAiReplyWithUsage(body, fallbackPromptChars: promptChars);
    } catch (err) {
      if (err is _ProviderHttpException) rethrow;
      throw _ProviderHttpException(
        null,
        '${p.name} (${p.model}): ${redactSecret(err.toString(), p.apiKey)}',
      );
    } finally {
      client.close(force: true);
    }
  }

  static int _countPromptChars(List<Map<String, Object>> messages) {
    var total = 0;
    for (final msg in messages) {
      final content = msg['content'];
      if (content is String) {
        total += content.length;
      } else if (content is List) {
        for (final part in content) {
          if (part is Map) {
            final text = part['text'];
            if (text is String) {
              total += text.length;
            } else if (part['type'] == 'image_url') {
              // Estimativa fixa conservadora para imagem multimodal (~256 tokens)
              total += 1024;
            }
          }
        }
      }
    }
    return total;
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

List<Map<String, Object>> buildAiMessages(
  String prompt,
  List<Map<String, String>> history, {
  String? imageBase64,
}) {
  final filtered = <Map<String, Object>>[];
  for (final m in history) {
    if (_allowedHistoryRoles.contains(m['role']) &&
        (m['content']?.trim().isNotEmpty ?? false)) {
      filtered.add({'role': m['role']!, 'content': m['content']!});
      if (filtered.length >= _maxHistoryMessages) break;
    }
  }

  if (imageBase64 != null && imageBase64.isNotEmpty) {
    final imageUri = imageBase64.startsWith('data:')
        ? imageBase64
        : 'data:image/jpeg;base64,$imageBase64';
    filtered.add({
      'role': 'user',
      'content': [
        {'type': 'text', 'text': prompt},
        {
          'type': 'image_url',
          'image_url': {'url': imageUri},
        },
      ],
    });
  } else {
    filtered.add({'role': 'user', 'content': prompt});
  }
  return filtered;
}

/// Estimativa determinística de tokens (~4 caracteres por token).
int estimateTokenCountFromChars(int charCount) {
  if (charCount <= 0) return 0;
  return (charCount + 3) ~/ 4;
}

int _readNonNegativeInt(Object? raw) {
  if (raw is int && raw >= 0) return raw;
  if (raw is num && raw >= 0) return raw.toInt();
  if (raw is String) {
    final parsed = int.tryParse(raw.trim());
    if (parsed != null && parsed >= 0) return parsed;
  }
  return 0;
}

ParsedAiReply parseAiReplyWithUsage(
  String rawBody, {
  int fallbackPromptChars = 0,
}) {
  final decoded = jsonDecode(rawBody) as Map<String, Object?>;
  final choices = decoded['choices'] as List<Object?>?;
  if (choices == null || choices.isEmpty) {
    throw const FormatException('Resposta sem choices.');
  }
  final message = (choices.first as Map<String, Object?>)['message']
      as Map<String, Object?>?;
  final content = message?['content'] as String?;
  if (content == null || content.trim().isEmpty) {
    throw const FormatException('Resposta vazia do provedor.');
  }
  final text = content.trim();

  final usageMap = decoded['usage'] as Map<String, Object?>?;
  var promptTokens = _readNonNegativeInt(
    usageMap?['prompt_tokens'] ?? usageMap?['input_tokens'],
  );
  var completionTokens = _readNonNegativeInt(
    usageMap?['completion_tokens'] ?? usageMap?['output_tokens'],
  );
  var totalTokens = _readNonNegativeInt(usageMap?['total_tokens']);
  var estimated = false;

  if (promptTokens == 0 && completionTokens == 0 && totalTokens == 0) {
    promptTokens = estimateTokenCountFromChars(fallbackPromptChars);
    completionTokens = estimateTokenCountFromChars(text.length);
    totalTokens = promptTokens + completionTokens;
    estimated = true;
  } else {
    if (promptTokens == 0 && totalTokens > completionTokens) {
      promptTokens = totalTokens - completionTokens;
    }
    if (completionTokens == 0 && totalTokens > promptTokens) {
      completionTokens = totalTokens - promptTokens;
    }
    if (totalTokens == 0) {
      totalTokens = promptTokens + completionTokens;
    }
  }

  return ParsedAiReply(
    text: text,
    usage: AiUsageInfo(
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: totalTokens,
      estimated: estimated,
    ),
  );
}

String parseAiReply(String rawBody) => parseAiReplyWithUsage(rawBody).text;

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
