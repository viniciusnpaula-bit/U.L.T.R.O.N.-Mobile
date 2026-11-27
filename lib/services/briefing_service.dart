import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'device_control_service.dart';
import 'obsidian_service.dart';

/// Resumo meteorológico sem necessidade de chave de API (Open-Meteo / wttr.in).
class WeatherSnapshot {
  const WeatherSnapshot({
    required this.city,
    required this.tempC,
    required this.feelsLikeC,
    required this.condition,
    this.minTempC,
    this.maxTempC,
    this.rainChancePct,
    this.humidityPct,
  });

  final String city;
  final int tempC;
  final int feelsLikeC;
  final String condition;
  final int? minTempC;
  final int? maxTempC;
  final int? rainChancePct;
  final int? humidityPct;

  String get summaryLine {
    final range = (minTempC != null && maxTempC != null)
        ? ' • Min $minTempC°C / Máx $maxTempC°C'
        : '';
    final rain = rainChancePct != null ? ' • Chuva $rainChancePct%' : '';
    final label = city.isEmpty ? 'Localização atual' : city;
    return '$label: $tempC°C (sensação $feelsLikeC°C), $condition$range$rain';
  }

  String get spokenLine {
    final place = city.isEmpty ? 'Na sua região' : 'Em $city';
    final rain = (rainChancePct != null && rainChancePct! >= 40)
        ? ' com $rainChancePct por cento de chance de chuva'
        : '';
    return '$place faz $tempC graus, $condition$rain.';
  }
}

/// Briefing matinal consolidado cruzando Agenda, Sentinela, Clima e Telemetria.
class MorningBriefing {
  const MorningBriefing({
    required this.generatedAt,
    required this.greeting,
    required this.events,
    required this.messages,
    required this.weather,
    required this.deviceStatus,
    required this.calendarError,
    required this.formattedReport,
    required this.speakText,
    this.staleNotes = const <OkfNoteStatus>[],
  });

  final DateTime generatedAt;
  final String greeting;
  final List<CalendarEvent> events;
  final List<CapturedNotification> messages;
  final WeatherSnapshot? weather;
  final DeviceStatus? deviceStatus;
  final String? calendarError;
  final String formattedReport;
  final String speakText;
  final List<OkfNoteStatus> staleNotes;
}

typedef WeatherFetcher = Future<WeatherSnapshot?> Function(String city);

/// Consolida o Briefing Executivo Unificado (P4): Agenda + Sentinela + Clima + Telemetria + OKF.
class BriefingService {
  BriefingService({
    DeviceControlService? deviceService,
    FlutterSecureStorage? storage,
    WeatherFetcher? weatherFetcher,
    Future<ObsidianService> Function()? obsidianProvider,
  })  : _deviceService = deviceService ?? DeviceControlService(),
        _storage = storage ?? const FlutterSecureStorage(),
        _weatherFetcher = weatherFetcher,
        _obsidianProvider = obsidianProvider;

  final DeviceControlService _deviceService;
  final FlutterSecureStorage _storage;
  final WeatherFetcher? _weatherFetcher;
  final Future<ObsidianService> Function()? _obsidianProvider;

  static const _weatherCityKey = 'ultron.briefing.city.v1';

  Future<String> loadPreferredCity() async {
    try {
      return (await _storage.read(key: _weatherCityKey))?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> savePreferredCity(String city) =>
      _storage.write(key: _weatherCityKey, value: city.trim());

  /// Consulta clima atual via wttr.in (`?format=j1`, sem chave de API) com fallback seguro.
  Future<WeatherSnapshot?> fetchWeather({String? city}) async {
    final cleanCity = (city ?? await loadPreferredCity()).trim();
    if (_weatherFetcher != null) {
      return _weatherFetcher(cleanCity);
    }

    final encoded = cleanCity.isEmpty ? '' : Uri.encodeComponent(cleanCity);
    final uri = Uri.parse('https://wttr.in/$encoded?format=j1&lang=pt');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 5));
      req.headers.set('Accept', 'application/json');
      req.headers.set('User-Agent', 'ULTRON-Mobile/1.4');
      final resp = await req.close().timeout(const Duration(seconds: 5));
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final body = await utf8.decoder
          .bind(resp)
          .join()
          .timeout(const Duration(seconds: 5));
      return parseWttrJson(body, fallbackCity: cleanCity);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static WeatherSnapshot? parseWttrJson(
    String rawJson, {
    String fallbackCity = '',
  }) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) return null;
    final currentList = decoded['current_condition'];
    if (currentList is! List || currentList.isEmpty) return null;
    final current = currentList.first;
    if (current is! Map<String, dynamic>) return null;

    final tempC = int.tryParse('${current['temp_C'] ?? ''}') ?? 0;
    final feelsC = int.tryParse('${current['FeelsLikeC'] ?? ''}') ?? tempC;
    final humidity = int.tryParse('${current['humidity'] ?? ''}');

    var condition = '';
    final ptList = current['lang_pt'];
    if (ptList is List && ptList.isNotEmpty && ptList.first is Map) {
      condition = '${(ptList.first as Map)['value'] ?? ''}'.trim();
    }
    if (condition.isEmpty) {
      final descList = current['weatherDesc'];
      if (descList is List && descList.isNotEmpty && descList.first is Map) {
        condition = '${(descList.first as Map)['value'] ?? ''}'.trim();
      }
    }
    if (condition.isEmpty) condition = 'Tempo estável';

    var city = fallbackCity;
    final areaList = decoded['nearest_area'];
    if (city.isEmpty && areaList is List && areaList.isNotEmpty) {
      final area = areaList.first;
      if (area is Map) {
        final areaNames = area['areaName'];
        if (areaNames is List &&
            areaNames.isNotEmpty &&
            areaNames.first is Map) {
          city = '${(areaNames.first as Map)['value'] ?? ''}'.trim();
        }
      }
    }

    int? minTempC;
    int? maxTempC;
    int? rainPct;
    final days = decoded['weather'];
    if (days is List && days.isNotEmpty && days.first is Map) {
      final today = days.first as Map;
      minTempC = int.tryParse('${today['mintempC'] ?? ''}');
      maxTempC = int.tryParse('${today['maxtempC'] ?? ''}');
      final hourly = today['hourly'];
      if (hourly is List && hourly.isNotEmpty) {
        final maxRain = hourly
            .whereType<Map>()
            .map((h) => int.tryParse('${h['chanceofrain'] ?? ''}') ?? 0)
            .fold<int>(0, (prev, el) => el > prev ? el : prev);
        rainPct = maxRain;
      }
    }

    return WeatherSnapshot(
      city: city,
      tempC: tempC,
      feelsLikeC: feelsC,
      condition: condition,
      minTempC: minTempC,
      maxTempC: maxTempC,
      rainChancePct: rainPct,
      humidityPct: humidity,
    );
  }

  /// Gera o briefing unificado cruzando Agenda, Sentinela, Clima e Telemetria.
  Future<MorningBriefing> generateBriefing({
    String? cityOverride,
    DateTime? now,
    int calendarDaysAhead = 1,
  }) async {
    final current = now ?? DateTime.now();
    final dayStart = DateTime(current.year, current.month, current.day);
    final greeting = _greetingForHour(current.hour);

    List<CalendarEvent> events = const [];
    String? calendarError;
    final calendarFuture = () async {
      try {
        events = await _deviceService.getCalendarEvents(
          from: dayStart,
          daysAhead: calendarDaysAhead,
        );
      } catch (e) {
        calendarError = '$e';
      }
    }();

    List<CapturedNotification> messages = const [];
    final messagesFuture = () async {
      try {
        final enabled = await _deviceService.isNotificationListenerEnabled();
        if (enabled) {
          messages = await _deviceService.getRecentMessages(limit: 8);
        }
      } catch (_) {}
    }();

    WeatherSnapshot? weather;
    final weatherFuture = () async {
      try {
        weather = await fetchWeather(city: cityOverride);
      } catch (_) {}
    }();

    DeviceStatus? status;
    final statusFuture = () async {
      try {
        status = await _deviceService.getStatus();
      } catch (_) {}
    }();

    List<OkfNoteStatus> staleNotes = const [];
    final staleNotesFuture = () async {
      try {
        final vault = _obsidianProvider != null
            ? await _obsidianProvider()
            : await _deviceService.getObsidianVault();
        staleNotes = await vault.listStaleNotes(now: current);
      } catch (_) {}
    }();

    await Future.wait([
      calendarFuture,
      messagesFuture,
      weatherFuture,
      statusFuture,
      staleNotesFuture,
    ]);

    final report = _buildReport(
      greeting: greeting,
      current: current,
      events: events,
      messages: messages,
      weather: weather,
      status: status,
      calendarError: calendarError,
      staleNotes: staleNotes,
    );
    final spoken = _buildSpeakText(
      greeting: greeting,
      events: events,
      messages: messages,
      weather: weather,
      status: status,
      staleNotes: staleNotes,
    );

    return MorningBriefing(
      generatedAt: current,
      greeting: greeting,
      events: events,
      messages: messages,
      weather: weather,
      deviceStatus: status,
      calendarError: calendarError,
      formattedReport: report,
      speakText: spoken,
      staleNotes: staleNotes,
    );
  }

  static String _greetingForHour(int hour) {
    if (hour >= 5 && hour < 12) return 'Bom dia, Operador';
    if (hour >= 12 && hour < 18) return 'Boa tarde, Operador';
    return 'Boa noite, Operador';
  }

  static String _buildReport({
    required String greeting,
    required DateTime current,
    required List<CalendarEvent> events,
    required List<CapturedNotification> messages,
    required WeatherSnapshot? weather,
    required DeviceStatus? status,
    required String? calendarError,
    List<OkfNoteStatus> staleNotes = const <OkfNoteStatus>[],
  }) {
    String two(int v) => v.toString().padLeft(2, '0');
    final dateHeader =
        '${two(current.day)}/${two(current.month)}/${current.year} • ${two(current.hour)}:${two(current.minute)}';
    final buf = StringBuffer()
      ..writeln('☀️ BRIEFING TÁTICO — $greeting ($dateHeader)')
      ..writeln('');

    buf.writeln('🌤️ CLIMA');
    buf.writeln(
      weather != null
          ? '• ${weather.summaryLine}'
          : '• Previsão indisponível offline (use /briefing cidade <nome> para fixar cidade).',
    );
    buf.writeln('');

    buf.writeln('📅 AGENDA DO DIA (${events.length})');
    if (calendarError != null) {
      buf.writeln('• Permissão de calendário pendente ou indisponível.');
    } else if (events.isEmpty) {
      buf.writeln('• Nenhum compromisso agendado para hoje.');
    } else {
      for (final e in events.take(6)) {
        buf.writeln(e.formatLine());
      }
      if (events.length > 6) {
        buf.writeln('• ... e mais ${events.length - 6} compromisso(s).');
      }
    }
    buf.writeln('');

    buf.writeln('📨 SENTINELA DE MENSAGENS (${messages.length} recentes)');
    if (messages.isEmpty) {
      buf.writeln('• Sem novas notificações capturadas.');
    } else {
      for (final m in messages.take(4)) {
        buf.writeln(
          '• [${m.timeFormatted}] ${m.appLabel} — ${m.sender}: "${m.text}"',
        );
      }
    }

    if (staleNotes.isNotEmpty) {
      buf.writeln('');
      buf.writeln(
        '📚 REVISÃO DO COFRE OKF (${staleNotes.length} nota(s) vencida(s))',
      );
      for (final note in staleNotes.take(6)) {
        buf.writeln(note.formatReviewLine());
      }
      if (staleNotes.length > 6) {
        buf.writeln('• ... e mais ${staleNotes.length - 6} nota(s).');
      }
      buf.writeln('• Use /vault verificar <nota> para aprovar e renovar validade.');
    }

    if (status != null) {
      buf.writeln('');
      final net = status.wifiConnected
          ? 'Wi-Fi'
          : status.cellularConnected
              ? 'Dados 5G/4G'
              : 'Offline';
      final bat = status.batteryLevel >= 0 ? '${status.batteryLevel}%' : 'N/D';
      buf.writeln(
        '🔋 SISTEMA: Bateria $bat${status.isCharging ? ' (carregando)' : ''} • RAM livre ${status.ramFreeMb} MB • Rede: $net',
      );
    }

    return buf.toString().trimRight();
  }

  static String _buildSpeakText({
    required String greeting,
    required List<CalendarEvent> events,
    required List<CapturedNotification> messages,
    required WeatherSnapshot? weather,
    required DeviceStatus? status,
    List<OkfNoteStatus> staleNotes = const <OkfNoteStatus>[],
  }) {
    final parts = <String>['$greeting.'];
    if (weather != null) {
      parts.add(weather.spokenLine);
    }
    if (events.isEmpty) {
      parts.add('Sua agenda está livre hoje.');
    } else if (events.length == 1) {
      final first = events.first;
      parts.add(
        'Você tem 1 compromisso hoje: ${first.title}, ${first.allDay ? 'o dia inteiro' : 'às ${first.timeRangeLabel}'}.',
      );
    } else {
      final first = events.first;
      parts.add(
        'Você tem ${events.length} compromissos hoje. O primeiro é ${first.title}, às ${first.timeRangeLabel}.',
      );
    }
    if (messages.isEmpty) {
      parts.add('Nenhuma mensagem recente na Sentinela.');
    } else {
      final latest = messages.first;
      parts.add(
        'Há ${messages.length} mensagens recentes, incluindo ${latest.appLabel} de ${latest.sender}.',
      );
    }
    if (staleNotes.isNotEmpty) {
      parts.add(
        'Atenção: há ${staleNotes.length} nota${staleNotes.length == 1 ? '' : 's'} vencida${staleNotes.length == 1 ? '' : 's'} no cofre Obsidian para revisão.',
      );
    }
    if (status != null && status.batteryLevel >= 0) {
      parts.add('Bateria em ${status.batteryLevel} por cento.');
    }
    return parts.join(' ');
  }
}
