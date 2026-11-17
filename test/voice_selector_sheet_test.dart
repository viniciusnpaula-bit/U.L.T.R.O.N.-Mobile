import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:ultron_mobile/services/voice_service.dart';
import 'package:ultron_mobile/ui/widgets/voice_selector_sheet.dart';

class _StubTts extends FlutterTts {
  final List<String> spoken = <String>[];
  Map<String, String>? selectedVoice;
  double? pitch;
  double? rate;

  @override
  Future<dynamic> get getVoices async => const [
        {
          'name': 'pt-br-x-pte-local',
          'locale': 'pt-BR',
          'network_required': '0',
          'quality': 'high',
        },
        {
          'name': 'pt-br-x-ptd-local',
          'locale': 'pt-BR',
          'network_required': '0',
          'quality': 'very high',
        },
      ];

  @override
  Future<dynamic> setLanguage(String language) async => 1;

  @override
  Future<dynamic> setPitch(double p) async {
    pitch = p;
    return 1;
  }

  @override
  Future<dynamic> setSpeechRate(double r) async {
    rate = r;
    return 1;
  }

  @override
  Future<dynamic> setVolume(double volume) async => 1;

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async => 1;

  @override
  Future<dynamic> setVoice(Map<String, String> voice) async {
    selectedVoice = voice;
    return 1;
  }

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    spoken.add(text);
    return 1;
  }

  @override
  Future<dynamic> stop() async => 1;
}

void main() {
  testWidgets(
    'VoiceSelectorSheet lists installed PT-BR voices and applies voice + profile immediately with preview',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues(const {});
      final fakeTts = _StubTts();
      final voiceService = VoiceService(tts: fakeTts);
      var changedCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: VoiceSelectorSheet(
              voiceService: voiceService,
              onChanged: () => changedCount += 1,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Voz ativa: pt-br-x-ptd-local'), findsOneWidget);
      expect(find.text('pt-br-x-pte-local'), findsOneWidget);
      expect(find.text('pt-br-x-ptd-local'), findsOneWidget);

      await tester.tap(find.text('pt-br-x-pte-local'));
      await tester.pumpAndSettle();

      expect(voiceService.activeVoiceName, 'pt-br-x-pte-local');
      expect(fakeTts.selectedVoice?['name'], 'pt-br-x-pte-local');
      expect(fakeTts.spoken, isNotEmpty);
      expect(changedCount, greaterThanOrEqualTo(1));

      await tester.tap(find.text('NATURAL'));
      await tester.pumpAndSettle();

      expect(voiceService.profile, VoiceProfile.natural);
      expect(fakeTts.pitch, VoiceProfile.natural.pitch);
    },
  );
}
