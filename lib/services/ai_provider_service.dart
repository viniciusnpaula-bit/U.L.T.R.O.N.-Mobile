import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AiProviderConfig {
  const AiProviderConfig({required this.id, required this.name, required this.baseUrl, required this.model, required this.apiKey, this.enabled = true, this.priority = 0});
  final String id, name, baseUrl, model, apiKey;
  final bool enabled;
  final int priority;
  Map<String,dynamic> toJson() => {'id':id,'name':name,'baseUrl':baseUrl,'model':model,'apiKey':apiKey,'enabled':enabled,'priority':priority};
  factory AiProviderConfig.fromJson(Map<String,dynamic> j) => AiProviderConfig(id:j['id'],name:j['name'],baseUrl:j['baseUrl'],model:j['model'],apiKey:j['apiKey'],enabled:j['enabled']??true,priority:j['priority']??0);
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
        endpointUrl:
            (j['endpointUrl'] as String?)?.trim().isNotEmpty == true
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

class AiProviderStore {
  AiProviderStore({FlutterSecureStorage? storage}) : _storage=storage??const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _key='ultron.ai.providers.v1';
  static const _sttKey='ultron.ai.stt.v1';
  Future<List<AiProviderConfig>> load() async {
    final raw=await _storage.read(key:_key); if(raw==null)return [];
    try { return (jsonDecode(raw) as List).map((e)=>AiProviderConfig.fromJson(Map<String,dynamic>.from(e))).toList(); } catch (_) { return []; }
  }
  Future<void> save(List<AiProviderConfig> providers) => _storage.write(key:_key,value:jsonEncode(providers.map((e)=>e.toJson()).toList()));
  Future<void> deleteAll() async {
    await _storage.delete(key:_key);
    await _storage.delete(key:_sttKey);
  }

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
}
class AiReply { const AiReply(this.provider, this.text); final String provider,text; }
class AiFailover {
  AiFailover({AiProviderStore? store}) : _store=store??AiProviderStore();
  final AiProviderStore _store;
  Future<AiReply> ask(String prompt, {List<Map<String,String>> history = const []}) async {
    final providers=(await _store.load()).where((p)=>p.enabled && p.apiKey.trim().isNotEmpty && p.model.trim().isNotEmpty).toList()
      ..sort((a,b)=>a.priority.compareTo(b.priority));
    if(providers.isEmpty) throw StateError('Nenhum provedor de IA ativo e configurado.');
    final errors=<String>[];
    for(final p in providers) {
      try { return AiReply(p.name, await _request(p,prompt,history:history)); }
      catch(e) { errors.add('${p.name}: ${e.toString()}'); }
    }
    throw HttpException('Todos os provedores falharam. ${errors.join(' | ')}');
  }
  Future<String> test(AiProviderConfig p) => _request(p,'Responda somente: conexão OK');
  Future<String> _request(AiProviderConfig p,String prompt,{List<Map<String,String>> history=const []}) async {
    final client=HttpClient()..connectionTimeout=const Duration(seconds:15);
    try {
      final base=p.baseUrl.trim().replaceAll(RegExp(r'/+$'),'');
      final uri=Uri.parse(base.endsWith('/chat/completions')?base:'$base/chat/completions');
      final req=await client.postUrl(uri).timeout(const Duration(seconds:20));
      req.headers.set(HttpHeaders.authorizationHeader,'Bearer ${p.apiKey}');
      req.headers.contentType=ContentType.json;
      final messages=buildAiMessages(prompt,history);
      req.write(jsonEncode({'model':p.model,'messages':messages,'temperature':0.4}));
      final response=await req.close().timeout(const Duration(seconds:25));
      final body=await response.transform(utf8.decoder).join().timeout(const Duration(seconds:30));
      if(response.statusCode<200||response.statusCode>=300) {
        String message='Falha HTTP ${response.statusCode}';
        try { final error=jsonDecode(body); message=(error['error']?['message']??error['message']??message).toString(); } catch (_) {}
        message=redactSecret(message,p.apiKey);
        if(message.length>220) message=message.substring(0,220);
        throw HttpException('HTTP ${response.statusCode}: $message');
      }
      return parseAiReply(body);
    } finally { client.close(force:true); }
  }
}

/// Keeps only usable turns, caps the window and appends the new prompt.
List<Map<String,String>> buildAiMessages(String prompt, List<Map<String,String>> history) {
  final messages=<Map<String,String>>[];
  for(final item in history.take(12)) {
    final role=item['role'], content=item['content'];
    if((role=='user'||role=='assistant') && content!=null && content.trim().isNotEmpty) {
      messages.add({'role':role!,'content':content});
    }
  }
  messages.add({'role':'user','content':prompt});
  return messages;
}

String parseAiReply(String body) {
  final data=jsonDecode(body) as Map<String,dynamic>;
  final text=((data['choices'] as List?)?.first['message']?['content']??'').toString();
  if(text.trim().isEmpty) throw const FormatException('Resposta vazia');
  return text;
}

/// Provider errors echo the request back; never let the key reach the UI.
String redactSecret(String message, String secret) {
  if(secret.trim().isEmpty) return message;
  return message.replaceAll(secret,'[chave ocultada]');
}
