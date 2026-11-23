import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/services/briefing_service.dart';
import 'package:ultron_mobile/services/web_info_service.dart';

void main() {
  test('fetchWeather delegates to BriefingService.fetchWeather', () async {
    final briefing = BriefingService(
      weatherFetcher: (city) async => WeatherSnapshot(
        city: city.isEmpty ? 'São Paulo' : city,
        tempC: 24,
        feelsLikeC: 25,
        condition: 'Ensolarado',
        minTempC: 18,
        maxTempC: 27,
        rainChancePct: 10,
      ),
    );
    final webInfo = WebInfoService(briefingService: briefing);

    final snap = await webInfo.fetchWeather(city: 'Campinas');
    expect(snap, isNotNull);
    expect(snap!.city, 'Campinas');
    expect(snap.tempC, 24);
    expect(snap.condition, 'Ensolarado');
    expect(snap.summaryLine, contains('Campinas: 24°C'));
  });

  test('fetchNews parses RSS 2.0 XML with CDATA, entities, and source suffix',
      () async {
    const sampleRss = '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Google Notícias - Tecnologia</title>
    <item>
      <title><![CDATA[Novo chip neural acelera IA local no Android - Portal Tech]]></title>
      <link>https://example.com/news/chip-neural</link>
      <pubDate>Sun, 22 Nov 2026 18:30:00 GMT</pubDate>
      <description>&lt;p&gt;Processamento offline 3x mais rápido &amp;amp; seguro.&lt;/p&gt;</description>
      <source url="https://example.com">Portal Tech</source>
    </item>
    <item>
      <title>Baterias de estado sólido avançam em 2026 - Ciência Hoje</title>
      <link>https://example.com/news/baterias</link>
      <pubDate>Sun, 22 Nov 2026 15:10:00 GMT</pubDate>
      <description>Autonomia ampliada para smartphones.</description>
    </item>
  </channel>
</rss>
''';

    Uri? requestedUri;
    final webInfo = WebInfoService(
      httpGetText: (uri, {headers = const {}}) async {
        requestedUri = uri;
        return sampleRss;
      },
    );

    final articles = await webInfo.fetchNews(topic: 'tecnologia', limit: 5);
    expect(requestedUri.toString(), contains('q=tecnologia'));
    expect(articles.length, 2);
    expect(articles[0].title, 'Novo chip neural acelera IA local no Android');
    expect(articles[0].source, 'Portal Tech');
    expect(articles[0].pubDate, '22 Nov 18:30');
    expect(articles[0].summary, contains('3x mais rápido & seguro.'));
    expect(articles[1].title, 'Baterias de estado sólido avançam em 2026');
    expect(articles[1].source, 'Ciência Hoje');
  });

  test(
      'searchWebSummary combines DuckDuckGo Instant Answer and Wikipedia PT-BR fallback',
      () async {
    final ddgPayload = jsonEncode({
      'Heading': 'Computação Quântica',
      'AbstractText':
          'A computação quântica utiliza qubits e superposição para resolver problemas complexos.',
      'AbstractURL': 'https://pt.wikipedia.org/wiki/Computa%C3%A7%C3%A3o_qu%C3%A2ntica',
      'Answer': '',
      'RelatedTopics': [
        {
          'Text': 'Qubit - Unidade básica de informação quântica.',
          'FirstURL': 'https://duckduckgo.com/Qubit',
        },
      ],
    });
    final wikiPayload = jsonEncode({
      'query': {
        'search': [
          {
            'title': 'Supremacia quântica',
            'snippet':
                'Capacidade de um <span class="searchmatch">computador</span> quântico superar supercomputadores clássicos.',
          },
        ],
      },
    });

    final webInfo = WebInfoService(
      httpGetText: (uri, {headers = const {}}) async {
        if (uri.host.contains('duckduckgo.com')) return ddgPayload;
        if (uri.host.contains('wikipedia.org')) return wikiPayload;
        return null;
      },
    );

    final summary = await webInfo.searchWebSummary('computação quântica', limit: 4);
    expect(summary.isEmpty, isFalse);
    expect(summary.items.length, 3);
    expect(summary.items[0].title, 'Computação Quântica');
    expect(summary.items[0].snippet, contains('qubits'));
    expect(summary.items[2].title, 'Supremacia quântica');
    expect(summary.items[2].snippet, isNot(contains('<span')));
    expect(summary.formatReport(), contains('PESQUISA WEB'));
  });
}
