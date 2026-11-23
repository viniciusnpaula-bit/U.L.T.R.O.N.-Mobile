import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'briefing_service.dart';

class NewsArticle {
  const NewsArticle({
    required this.title,
    required this.source,
    required this.link,
    this.pubDate = '',
    this.summary = '',
  });

  final String title;
  final String source;
  final String link;
  final String pubDate;
  final String summary;

  String formatLine() {
    final srcPart = source.isEmpty ? '' : ' [$source]';
    final datePart = pubDate.isEmpty ? '' : ' ($pubDate)';
    return '• $title$srcPart$datePart';
  }
}

class WebSearchResultItem {
  const WebSearchResultItem({
    required this.title,
    required this.snippet,
    this.url = '',
  });

  final String title;
  final String snippet;
  final String url;

  String formatLine() {
    final urlPart = url.isEmpty ? '' : '\n  🔗 $url';
    return '• $title: $snippet$urlPart';
  }
}

class WebSearchSummary {
  const WebSearchSummary({
    required this.query,
    required this.items,
  });

  final String query;
  final List<WebSearchResultItem> items;

  bool get isEmpty => items.isEmpty;

  String formatReport() {
    if (items.isEmpty) {
      return '🌐 Nenhum resumo textual encontrado para "$query".';
    }
    final lines = items.map((i) => i.formatLine()).join('\n');
    return '🌐 PESQUISA WEB ("$query"):\n$lines';
  }

  String get speakText {
    if (items.isEmpty) {
      return 'Não encontrei resumo na web sobre $query.';
    }
    final first = items.first;
    return 'Sobre $query: ${first.title}. ${first.snippet}';
  }
}

typedef HttpTextGetter = Future<String?> Function(
  Uri uri, {
  Map<String, String> headers,
});

/// Serviço de informação atual sem necessidade de chave de API:
/// - Clima (`fetchWeather`, reutilizando [BriefingService.fetchWeather])
/// - Notícias (`fetchNews` via feeds RSS públicos com parser XML nativo em Dart)
/// - Pesquisa Web resumida (`searchWebSummary` via DuckDuckGo Instant Answer / Wikipedia PT-BR API)
class WebInfoService {
  WebInfoService({
    BriefingService? briefingService,
    HttpClient Function()? httpClientFactory,
    HttpTextGetter? httpGetText,
  })  : _briefingService = briefingService,
        _httpClientFactory = httpClientFactory ?? HttpClient.new,
        _httpGetText = httpGetText;

  final BriefingService? _briefingService;
  final HttpClient Function() _httpClientFactory;
  final HttpTextGetter? _httpGetText;

  /// Consulta isolada de clima para [city], reutilizando [BriefingService.fetchWeather].
  Future<WeatherSnapshot?> fetchWeather({String? city}) async {
    if (_briefingService != null) {
      return _briefingService.fetchWeather(city: city);
    }
    final cleanCity = (city ?? '').trim();
    if (_httpGetText != null) {
      final encoded = cleanCity.isEmpty ? '' : Uri.encodeComponent(cleanCity);
      final uri = Uri.parse('https://wttr.in/$encoded?format=j1&lang=pt');
      final raw = await _httpGetText(
        uri,
        headers: const {'Accept': 'application/json'},
      );
      if (raw == null || raw.trim().isEmpty) return null;
      return BriefingService.parseWttrJson(raw, fallbackCity: cleanCity);
    }
    return BriefingService().fetchWeather(city: cleanCity);
  }

  /// Busca manchetes atualizadas via feed RSS público (Google News RSS PT-BR),
  /// fazendo parse XML leve em Dart sem dependências externas.
  Future<List<NewsArticle>> fetchNews({
    String topic = '',
    int limit = 5,
  }) async {
    final cleanTopic = topic.trim();
    final safeLimit = limit.clamp(1, 15);
    final Uri uri;
    if (cleanTopic.isEmpty ||
        cleanTopic.toLowerCase() == 'geral' ||
        cleanTopic.toLowerCase() == 'principais' ||
        cleanTopic.toLowerCase() == 'hoje') {
      uri = Uri.parse(
        'https://news.google.com/rss?hl=pt-BR&gl=BR&ceid=BR:pt-419',
      );
    } else {
      final encoded = Uri.encodeQueryComponent(cleanTopic);
      uri = Uri.parse(
        'https://news.google.com/rss/search?q=$encoded&hl=pt-BR&gl=BR&ceid=BR:pt-419',
      );
    }

    final xml = await _getText(
      uri,
      headers: const {
        'Accept': 'application/rss+xml, application/xml, text/xml;q=0.9',
      },
    );
    if (xml == null || xml.trim().isEmpty) return const [];
    return parseRssXml(xml, limit: safeLimit);
  }

  /// Faz parse de um documento RSS 2.0 / Atom XML simples extraindo `<item>` ou `<entry>`.
  static List<NewsArticle> parseRssXml(String rawXml, {int limit = 5}) {
    final safeLimit = limit.clamp(1, 20);
    final results = <NewsArticle>[];
    final itemMatches = RegExp(
      r'<(?:item|entry)\b[^>]*>([\s\S]*?)</(?:item|entry)>',
      caseSensitive: false,
    ).allMatches(rawXml);

    for (final match in itemMatches) {
      if (results.length >= safeLimit) break;
      final block = match.group(1) ?? '';
      var rawTitle = _extractXmlTag(block, 'title');
      if (rawTitle.isEmpty) continue;

      var source = _extractXmlTag(block, 'source');
      // Google News costuma colocar "Manchete - Fonte" no <title>
      if (source.isEmpty && rawTitle.contains(' - ')) {
        final lastDash = rawTitle.lastIndexOf(' - ');
        if (lastDash > 10 && lastDash + 3 < rawTitle.length) {
          source = rawTitle.substring(lastDash + 3).trim();
          rawTitle = rawTitle.substring(0, lastDash).trim();
        }
      } else if (source.isNotEmpty && rawTitle.endsWith(' - $source')) {
        rawTitle =
            rawTitle.substring(0, rawTitle.length - (' - $source').length).trim();
      }

      var link = _extractXmlTag(block, 'link');
      if (link.isEmpty) {
        final hrefMatch = RegExp(
          r'<link\b[^>]*\bhref=["\x27]([^"\x27]+)["\x27]',
          caseSensitive: false,
        ).firstMatch(block);
        link = hrefMatch?.group(1)?.trim() ?? '';
      }

      final pubDate = _shortenPubDate(
        _extractXmlTag(block, 'pubDate').ifEmpty(
          _extractXmlTag(block, 'published'),
        ),
      );
      final desc = _stripHtml(_extractXmlTag(block, 'description'));

      results.add(
        NewsArticle(
          title: rawTitle,
          source: source,
          link: link,
          pubDate: pubDate,
          summary: desc,
        ),
      );
    }
    return results;
  }

  /// Consulta textual resumida na web (`[ACTION:WEB_SEARCH:query]`) sem abrir navegador.
  /// Combina DuckDuckGo Instant Answer API + Wikipedia PT-BR OpenSearch/Summary como fallback.
  Future<WebSearchSummary> searchWebSummary(
    String query, {
    int limit = 4,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      throw ArgumentError('Termo de pesquisa web não pode ser vazio.');
    }
    final safeLimit = limit.clamp(1, 10);
    final items = <WebSearchResultItem>[];

    // 1. DuckDuckGo Instant Answer JSON API
    final ddgEncoded = Uri.encodeQueryComponent(cleanQuery);
    final ddgUri = Uri.parse(
      'https://api.duckduckgo.com/?q=$ddgEncoded&format=json&no_html=1&skip_disambig=1',
    );
    final ddgRaw = await _getText(
      ddgUri,
      headers: const {'Accept': 'application/json'},
    );
    if (ddgRaw != null && ddgRaw.trim().isNotEmpty) {
      items.addAll(parseDuckDuckGoJson(ddgRaw, limit: safeLimit));
    }

    // 2. Fallback/complemento via Wikipedia PT-BR API se ainda houver poucos resultados
    if (items.length < safeLimit) {
      final wikiUri = Uri.parse(
        'https://pt.wikipedia.org/w/api.php?action=query&list=search&srsearch=$ddgEncoded&utf8=1&format=json&srlimit=${safeLimit - items.length}',
      );
      final wikiRaw = await _getText(
        wikiUri,
        headers: const {'Accept': 'application/json'},
      );
      if (wikiRaw != null && wikiRaw.trim().isNotEmpty) {
        for (final w in parseWikipediaSearchJson(wikiRaw)) {
          if (items.length >= safeLimit) break;
          if (!items.any((e) => e.title.toLowerCase() == w.title.toLowerCase())) {
            items.add(w);
          }
        }
      }
    }

    return WebSearchSummary(query: cleanQuery, items: items);
  }

  static List<WebSearchResultItem> parseDuckDuckGoJson(
    String rawJson, {
    int limit = 4,
  }) {
    final results = <WebSearchResultItem>[];
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) return const [];

      final heading = (decoded['Heading'] as String? ?? '').trim();
      final abstractText = _stripHtml(
        (decoded['AbstractText'] as String? ?? '').trim(),
      );
      final abstractUrl = (decoded['AbstractURL'] as String? ?? '').trim();
      final answer = _stripHtml((decoded['Answer'] as String? ?? '').trim());

      if (answer.isNotEmpty) {
        results.add(
          WebSearchResultItem(
            title: heading.isEmpty ? 'Resposta Direta' : heading,
            snippet: answer,
            url: abstractUrl,
          ),
        );
      }
      if (abstractText.isNotEmpty && results.length < limit) {
        results.add(
          WebSearchResultItem(
            title: heading.isEmpty ? 'Resumo' : heading,
            snippet: abstractText,
            url: abstractUrl,
          ),
        );
      }

      final related = decoded['RelatedTopics'];
      if (related is List) {
        for (final entry in related) {
          if (results.length >= limit) break;
          if (entry is Map) {
            final text = _stripHtml('${entry['Text'] ?? ''}'.trim());
            final firstUrl = '${entry['FirstURL'] ?? ''}'.trim();
            if (text.isNotEmpty) {
              results.add(
                WebSearchResultItem(
                  title: heading.isEmpty ? 'Tópico Relacionado' : heading,
                  snippet: text,
                  url: firstUrl,
                ),
              );
            }
          }
        }
      }
    } catch (_) {}
    return results.take(limit).toList();
  }

  static List<WebSearchResultItem> parseWikipediaSearchJson(
    String rawJson, {
    int limit = 4,
  }) {
    final results = <WebSearchResultItem>[];
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) return const [];
      final queryObj = decoded['query'];
      if (queryObj is! Map) return const [];
      final searchList = queryObj['search'];
      if (searchList is! List) return const [];

      for (final item in searchList) {
        if (results.length >= limit) break;
        if (item is Map) {
          final title = '${item['title'] ?? ''}'.trim();
          final snippet = _stripHtml('${item['snippet'] ?? ''}'.trim());
          if (title.isNotEmpty && snippet.isNotEmpty) {
            final slug = Uri.encodeComponent(title.replaceAll(' ', '_'));
            results.add(
              WebSearchResultItem(
                title: title,
                snippet: snippet,
                url: 'https://pt.wikipedia.org/wiki/$slug',
              ),
            );
          }
        }
      }
    } catch (_) {}
    return results;
  }

  Future<String?> _getText(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    if (_httpGetText != null) {
      return _httpGetText(uri, headers: headers);
    }
    final client = _httpClientFactory()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 6));
      req.headers.set('User-Agent', 'ULTRON-Mobile/1.5');
      for (final entry in headers.entries) {
        req.headers.set(entry.key, entry.value);
      }
      final resp = await req.close().timeout(const Duration(seconds: 6));
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      return await utf8.decoder
          .bind(resp)
          .join()
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static String _extractXmlTag(String xmlBlock, String tag) {
    final match = RegExp(
      '<$tag(?:\\s[^>]*)?>([\\s\\S]*?)</$tag>',
      caseSensitive: false,
    ).firstMatch(xmlBlock);
    if (match == null) return '';
    var inner = (match.group(1) ?? '').trim();
    final cdataMatch = RegExp(
      r'^<!\[CDATA\[([\s\S]*?)\]\]>$',
      caseSensitive: false,
    ).firstMatch(inner);
    if (cdataMatch != null) {
      inner = cdataMatch.group(1)!.trim();
    }
    return _decodeXmlEntities(inner);
  }

  static String _decodeXmlEntities(String input) => input
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ')
      .trim();

  static String _stripHtml(String input) => _decodeXmlEntities(
        input.replaceAll(RegExp(r'<[^>]+>'), ' '),
      ).replaceAll(RegExp(r'\s{2,}'), ' ').trim();

  static String _shortenPubDate(String rawDate) {
    final trimmed = rawDate.trim();
    if (trimmed.isEmpty) return '';
    // Ex: "Sun, 22 Nov 2026 18:30:00 GMT" -> "22 Nov 18:30"
    final rfcMatch = RegExp(
      r'\b(\d{1,2}\s+[A-Za-z]{3})\s+\d{4}\s+(\d{2}:\d{2})',
    ).firstMatch(trimmed);
    if (rfcMatch != null) {
      return '${rfcMatch.group(1)} ${rfcMatch.group(2)}';
    }
    return trimmed.length > 22 ? trimmed.substring(0, 22) : trimmed;
  }
}

extension _StringIfEmpty on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
