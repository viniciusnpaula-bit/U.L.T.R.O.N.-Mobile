import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:ultron_mobile/models/assistant_persona.dart';
import 'package:ultron_mobile/services/briefing_service.dart';
import 'package:ultron_mobile/services/cognicao_service.dart';
import 'package:ultron_mobile/services/device_control_service.dart';
import 'package:ultron_mobile/services/speech_text.dart';
import 'package:ultron_mobile/services/voice_service.dart';
import 'package:ultron_mobile/services/web_info_service.dart';

class _FakeTts extends FlutterTts {
  final List<double> pitchCalls = <double>[];
  final List<double> rateCalls = <double>[];
  final List<String> spoken = <String>[];

  @override
  Future<dynamic> setLanguage(String language) async => 1;

  @override
  Future<dynamic> setPitch(double pitch) async {
    pitchCalls.add(pitch);
    return 1;
  }

  @override
  Future<dynamic> setSpeechRate(double rate) async {
    rateCalls.add(rate);
    return 1;
  }

  @override
  Future<dynamic> setVolume(double volume) async => 1;

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async => 1;

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    spoken.add(text);
    return 1;
  }

  @override
  Future<dynamic> stop() async => 1;

  @override
  Future<dynamic> get getVoices async => const <dynamic>[];

  @override
  Future<dynamic> setVoice(Map<String, String> voice) async => 1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VoiceEmotionParser & TTS Modulation', () {
    test('extracts explicit emotion tag and strips it cleanly', () {
      final parsed = VoiceEmotionParser.parse(
        '[alerta] Temperatura da CPU acima de 90 graus.',
      );
      expect(parsed.explicitTag, isTrue);
      expect(parsed.emotion, VoiceEmotion.alerta);
      expect(parsed.cleanText, 'Temperatura da CPU acima de 90 graus.');
    });

    test('infers local PT-BR nuances without extra LLM calls', () {
      expect(
        VoiceEmotionParser.parse('Sinto muito, a conexão falhou.').emotion,
        VoiceEmotion.lamento,
      );
      expect(
        VoiceEmotionParser.parse('Parabéns, deploy concluído com sucesso!').emotion,
        VoiceEmotion.comemorando,
      );
      expect(
        VoiceEmotionParser.parse('Você quer salvar isso no Obsidian?').emotion,
        VoiceEmotion.duvida,
      );
      expect(
        VoiceEmotionParser.parse('Sistema operando normalmente.').emotion,
        VoiceEmotion.neutro,
      );
    });

    test('VoiceService modulates pitch/rate within ±15% and restores profile', () async {
      final fakeTts = _FakeTts();
      final voice = VoiceService(tts: fakeTts);
      await voice.initialize();
      fakeTts.pitchCalls.clear();
      fakeTts.rateCalls.clear();

      await voice.speak('[comemorando] Tarefa finalizada com sucesso!');

      expect(voice.lastDetectedEmotion, VoiceEmotion.comemorando);
      expect(fakeTts.spoken, hasLength(1));
      expect(fakeTts.spoken.first, isNot(contains('[comemorando]')));
      expect(fakeTts.spoken.first, contains('Tarefa finalizada com sucesso'));

      // Modulated pitch/rate should be applied before speak and restored after
      expect(fakeTts.pitchCalls.length, greaterThanOrEqualTo(2));
      expect(fakeTts.rateCalls.length, greaterThanOrEqualTo(2));
      final basePitch = VoiceProfile.grave.pitch;
      final baseRate = VoiceProfile.grave.rate;
      expect(
        fakeTts.pitchCalls.first,
        closeTo((basePitch * VoiceEmotion.comemorando.pitchFactor).clamp(0.5, 2.0), 0.02),
      );
      expect(
        fakeTts.rateCalls.first,
        closeTo((baseRate * VoiceEmotion.comemorando.rateFactor).clamp(0.2, 1.0), 0.02),
      );
      // Restored in finally
      expect(fakeTts.pitchCalls.last, closeTo(basePitch, 0.01));
      expect(fakeTts.rateCalls.last, closeTo(baseRate, 0.01));
    });

    test('CognicaoService strips leading emotion tag and exposes detectedEmotion', () {
      const cog = CognicaoService();
      final audit = cog.auditResponse(
        cleanReplyText: '[serio] Bateria em 14%. Conecte o carregador.',
        executedTools: const <String>[],
      );
      expect(audit.detectedEmotion, VoiceEmotion.serio);
      expect(audit.text, 'Bateria em 14%. Conecte o carregador.');
      expect(audit.speakText, isNot(contains('[serio]')));
    });
  });

  group('AssistantPersona & SpeechStyle', () {
    test('maps all 4 wake-word profiles to distinct personas and accent colors', () {
      final colors = <Color>{};
      for (final profile in WakeWordProfile.values) {
        final persona = AssistantPersona.forWakeProfile(profile);
        expect(persona.wakeProfile, profile);
        expect(persona.displayName, isNotEmpty);
        expect(persona.promptDirective, isNotEmpty);
        colors.add(persona.accentColor);
      }
      expect(colors.length, 4);
      expect(AssistantPersona.all.length, 4);
    });

    test('SpeechStyle.fromId parses valid ids and falls back to direto', () {
      expect(SpeechStyle.fromId('tecnico'), SpeechStyle.tecnico);
      expect(SpeechStyle.fromId('EXECUTIVO'), SpeechStyle.executivo);
      expect(SpeechStyle.fromId('inexistente'), SpeechStyle.direto);
    });
  });

  group('Zero-LLM Natural Language Shortcuts', () {
    test('resolves local time, local date, weather and news without LLM', () async {
      final fakeWeb = WebInfoService(
        httpGetText: (uri, {headers = const {}}) async {
          final url = uri.toString();
          if (url.contains('wttr.in')) {
            return '''
            {
              "current_condition": [{
                "temp_C": "26",
                "FeelsLikeC": "28",
                "humidity": "62",
                "lang_pt": [{"value": "Parcialmente nublado"}]
              }],
              "nearest_area": [{"areaName": [{"value": "São Paulo"}]}]
            }
            ''';
          }
          if (url.contains('news.google.com/rss')) {
            return '''
            <rss><channel>
              <item>
                <title>Avanço em baterias de estado sólido - TechBR</title>
                <link>https://example.com/baterias</link>
                <pubDate>Tue, 24 Nov 2026 10:00:00 GMT</pubDate>
              </item>
            </channel></rss>
            ''';
          }
          return null;
        },
      );

      final device = DeviceControlService(
        webInfoProvider: () => fakeWeb,
      );

      final timeRes = await device.tryExecuteNaturalCommand('que horas são?');
      expect(timeRes, isNotNull);
      expect(timeRes!.handled, isTrue);
      expect(timeRes.message, contains(':'));

      final dateRes = await device.tryExecuteNaturalCommand('que dia é hoje?');
      expect(dateRes, isNotNull);
      expect(dateRes!.handled, isTrue);
      expect(dateRes.message, contains('Hoje é'));

      final weatherRes = await device.tryExecuteNaturalCommand(
        'qual a temperatura em São Paulo?',
      );
      expect(weatherRes, isNotNull);
      expect(weatherRes!.handled, isTrue);
      expect(weatherRes.message, contains('26'));

      final newsRes = await device.tryExecuteNaturalCommand('notícias de tecnologia');
      expect(newsRes, isNotNull);
      expect(newsRes!.handled, isTrue);
      expect(newsRes.message, contains('baterias de estado sólido'));

      final snap = await fakeWeb.fetchWeather(city: 'São Paulo');
      expect(snap, isA<WeatherSnapshot>());
    });
  });
}
