import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AiProvider {
  const AiProvider({
    required this.name,
    required this.baseUrl,
    required this.model,
    required this.enabled,
  });

  final String name;
  final String baseUrl;
  final String model;
  final bool enabled;

  Map<String, dynamic> toJson() => {
        'name': name,
        'baseUrl': baseUrl,
        'model': model,
        'enabled': enabled,
      };

  factory AiProvider.fromJson(Map<String, dynamic> json) => AiProvider(
        name: json['name'] as String,
        baseUrl: json['baseUrl'] as String,
        model: json['model'] as String,
        enabled: json['enabled'] as bool? ?? true,
      );
}

class AiService {
  AiService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _providersKey = 'ai.providers';
  static const _keysPrefix = 'ai.key.';

  Future<List<AiProvider>> providers() async {
    final raw = await _storage.read(key: _providersKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((item) => AiProvider.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveProvider(AiProvider provider, String apiKey) async {
    final list = await providers();
    final updated = [...list.where((p) => p.name != provider.name), provider];
    await _storage.write(key: _providersKey, value: jsonEncode(updated.map((p) => p.toJson()).toList()));
    if (apiKey.isNotEmpty) {
      await _storage.write(key: '$_keysPrefix${provider.name}', value: apiKey);
    }
  }

  Future<String> testProvider(AiProvider provider) async {
    final key = await _storage.read(key: '$_keysPrefix${provider.name}');
    if (key == null || key.isEmpty) throw Exception('API Key não cadastrada.');
    final uri = Uri.parse('${provider.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions');
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $key')
        ..contentType = ContentType.json;
      request.write(jsonEncode({
        'model': provider.model,
        'messages': [{'role': 'user', 'content': 'Responda somente: conexão OK'}],
        'max_tokens': 20,
      }));
      final response = await request.close().timeout(const Duration(seconds: 20));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}: ${body.substring(0, body.length.clamp(0, 300).toInt())}');
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final answer = decoded['choices']?[0]?['message']?['content'];
      if (answer is! String || answer.trim().isEmpty) throw Exception('Resposta inválida da API.');
      return answer;
    } finally {
      client.close(force: true);
    }
  }

  Future<String> ask(String prompt) async {
    final enabled = (await providers()).where((p) => p.enabled).toList();
    if (enabled.isEmpty) throw Exception('Cadastre e habilite um provedor em Configurações.');
    final errors = <String>[];
    for (final provider in enabled) {
      try {
        final key = await _storage.read(key: '$_keysPrefix${provider.name}');
        if (key == null || key.isEmpty) throw Exception('API Key ausente');
        final uri = Uri.parse('${provider.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions');
        final client = HttpClient();
        try {
          final request = await client.postUrl(uri).timeout(const Duration(seconds: 20));
          request.headers
            ..set(HttpHeaders.authorizationHeader, 'Bearer $key')
            ..contentType = ContentType.json;
          request.write(jsonEncode({
            'model': provider.model,
            'messages': [{'role': 'user', 'content': prompt}],
          }));
          final response = await request.close().timeout(const Duration(seconds: 45));
          final body = await response.transform(utf8.decoder).join();
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw Exception('HTTP ${response.statusCode}: ${body.substring(0, body.length.clamp(0, 250).toInt())}');
          }
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          final answer = decoded['choices']?[0]?['message']?['content'];
          if (answer is! String || answer.trim().isEmpty) throw Exception('Resposta vazia');
          return answer.trim();
        } finally {
          client.close(force: true);
        }
      } catch (error) {
        errors.add('${provider.name}: $error');
      }
    }
    throw Exception('Todos os provedores falharam. ${errors.join(' | ')}');
  }
}
