import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/services/briefing_service.dart';
import 'package:ultron_mobile/services/device_control_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.viniciusnpaula.ultron_mobile/device');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
      'parseWttrJson extracts PT-BR condition, temp, city, and max rain chance',
      () {
    final raw = jsonEncode({
      'current_condition': [
        {
          'temp_C': '26',
          'FeelsLikeC': '28',
          'humidity': '65',
          'lang_pt': [
            {'value': 'Parcialmente nublado'},
          ],
          'weatherDesc': [
            {'value': 'Partly cloudy'},
          ],
        },
      ],
      'nearest_area': [
        {
          'areaName': [
            {'value': 'São Paulo'},
          ],
        },
      ],
      'weather': [
        {
          'mintempC': '19',
          'maxtempC': '29',
          'hourly': [
            {'chanceofrain': '10'},
            {'chanceofrain': '60'},
          ],
        },
      ],
    });

    final snap = BriefingService.parseWttrJson(raw);
    expect(snap, isNotNull);
    expect(snap!.city, 'São Paulo');
    expect(snap.tempC, 26);
    expect(snap.feelsLikeC, 28);
    expect(snap.condition, 'Parcialmente nublado');
    expect(snap.minTempC, 19);
    expect(snap.maxTempC, 29);
    expect(snap.rainChancePct, 60);
    expect(snap.summaryLine, contains('São Paulo: 26°C'));
    expect(snap.spokenLine, contains('chance de chuva'));
  });

  test(
      'generateBriefing combines calendar, sentinel messages, weather, and telemetry',
      () async {
    final morning = DateTime(2026, 11, 19, 8, 30);
    final eventStart = DateTime(2026, 11, 19, 9, 0).millisecondsSinceEpoch;
    final eventEnd = DateTime(2026, 11, 19, 10, 0).millisecondsSinceEpoch;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getCalendarEvents':
          return [
            {
              'id': 'evt-1',
              'title': 'Daily Tática U.L.T.R.O.N.',
              'startMs': eventStart,
              'endMs': eventEnd,
              'allDay': false,
              'location': 'Discord',
              'calendarName': 'Principal',
              'description': '',
            },
          ];
        case 'isNotificationListenerEnabled':
          return true;
        case 'getRecentMessages':
          return [
            {
              'id': 'm-1',
              'packageName': 'com.whatsapp',
              'appLabel': 'WhatsApp',
              'sender': 'Carlos',
              'text': 'Deploy aprovado',
              'timestampMs': morning.millisecondsSinceEpoch,
              'timeFormatted': '08:25',
              'canReplyInline': true,
            },
          ];
        case 'getDeviceStatus':
          return {
            'batteryLevel': 88,
            'isCharging': false,
            'batteryTempC': 30.5,
            'torchOn': false,
            'volumePercent': 60,
            'ringerMode': 'NORMAL',
            'ramUsedMb': 3200,
            'ramTotalMb': 8192,
            'ramFreeMb': 4992,
            'deviceModel': 'Galaxy A34 5G',
            'androidVersion': 'Android 14',
            'wifiConnected': true,
            'cellularConnected': true,
          };
        default:
          return null;
      }
    });

    final briefingService = BriefingService(
      deviceService: DeviceControlService(channel: channel),
      weatherFetcher: (_) async => const WeatherSnapshot(
        city: 'Curitiba',
        tempC: 22,
        feelsLikeC: 22,
        condition: 'Céu limpo',
        minTempC: 15,
        maxTempC: 25,
        rainChancePct: 5,
      ),
    );

    final briefing = await briefingService.generateBriefing(now: morning);
    expect(briefing.greeting, 'Bom dia, Operador');
    expect(briefing.events.length, 1);
    expect(briefing.events.first.title, 'Daily Tática U.L.T.R.O.N.');
    expect(briefing.messages.length, 1);
    expect(briefing.weather?.city, 'Curitiba');
    expect(briefing.formattedReport,
        contains('09:00–10:00 — Daily Tática U.L.T.R.O.N. @ Discord'));
    expect(briefing.formattedReport, contains('Carlos: "Deploy aprovado"'));
    expect(briefing.formattedReport, contains('Curitiba: 22°C'));
    expect(briefing.formattedReport, contains('Bateria 88%'));
    expect(briefing.speakText, contains('Bom dia, Operador'));
    expect(briefing.speakText, contains('Daily Tática U.L.T.R.O.N.'));
  });

  test(
      'generateBriefing degrades safely when calendar permission or network fails',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getCalendarEvents':
          throw PlatformException(
            code: 'CALENDAR_PERMISSION_DENIED',
            message: 'Permissão negada',
          );
        case 'isNotificationListenerEnabled':
          return false;
        case 'getDeviceStatus':
          return {
            'batteryLevel': 50,
            'isCharging': true,
            'ramFreeMb': 2048,
            'wifiConnected': false,
            'cellularConnected': false,
          };
        default:
          return null;
      }
    });

    final briefingService = BriefingService(
      deviceService: DeviceControlService(channel: channel),
      weatherFetcher: (_) async => null,
    );

    final briefing = await briefingService.generateBriefing(
      now: DateTime(2026, 11, 19, 19, 10),
    );
    expect(briefing.greeting, 'Boa noite, Operador');
    expect(briefing.calendarError, isNotNull);
    expect(briefing.events, isEmpty);
    expect(
        briefing.formattedReport, contains('Permissão de calendário pendente'));
    expect(briefing.formattedReport, contains('Previsão indisponível offline'));
  });
}
