import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:ultron_mobile/services/audio_capture_service.dart';
import 'package:ultron_mobile/services/voice_service.dart';
import 'package:ultron_mobile/ui/widgets/voice_selector_sheet.dart';

class _FakeFishService extends FishAudioTtsService {
  final List<String> synthesizedTexts = <String>[];

  @override
  Future<Uint8List> synthesize(
    String text, {
    FishAudioConfig? overrideConfig,
    String? profileId,
  }) async {
    synthesizedTexts.add(text);
    return Uint8List.fromList([1, 2, 3]);
  }
}

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

class _FakeAudioInputRouter implements AudioInputRouterService {
  int selectedId = -1;
  bool btGranted = true;
  final List<AudioInputDevice> savedSelections = <AudioInputDevice>[];

  @override
  Future<bool> hasBluetoothPermission() async => btGranted;

  @override
  Future<bool> requestBluetoothPermission() async {
    btGranted = true;
    return true;
  }

  @override
  Future<AudioInputSelection> getPreferredInputDevice() async {
    return AudioInputSelection(
      id: selectedId,
      type: selectedId == 2 ? 15 : -1,
      name: selectedId == 2
          ? 'Microfone do Celular'
          : 'Automático (Padrão do Android)',
      isAuto: selectedId == -1,
    );
  }

  @override
  Future<List<AudioInputDevice>> listInputDevices() async {
    return [
      AudioInputDevice.auto(selected: selectedId == -1),
      AudioInputDevice(
        id: 7,
        type: 7,
        category: 'bluetooth',
        name: 'Galaxy Buds (Bluetooth)',
        typeLabel: 'Bluetooth (HFP/SCO)',
        isBluetooth: true,
        isSelected: selectedId == 7,
      ),
      AudioInputDevice(
        id: 2,
        type: 15,
        category: 'builtin',
        name: 'Microfone do Celular',
        typeLabel: 'Microfone do aparelho',
        isBuiltIn: true,
        isSelected: selectedId == 2,
      ),
    ];
  }

  @override
  Future<bool> setPreferredInputDevice(AudioInputDevice device) async {
    selectedId = device.id;
    savedSelections.add(device);
    return true;
  }
}

class _FakeMicCaptureSource implements AudioCaptureSource {
  final StreamController<Uint8List> _controller =
      StreamController<Uint8List>.broadcast();
  bool started = false;
  bool stopped = false;

  @override
  Stream<Uint8List> get frames => _controller.stream;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<AudioEffectsReport> start({int sampleRate = 16000}) async {
    started = true;
    return AudioEffectsReport(
      aecEnabled: true,
      nsEnabled: true,
      agcEnabled: true,
      sampleRate: sampleRate,
      routedDeviceName: 'Microfone do Celular',
      routedDeviceType: 15,
    );
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }

  Future<void> close() => _controller.close();
}

void main() {
  testWidgets(
    'VoiceSelectorSheet lists installed PT-BR voices and applies voice + profile immediately with preview',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
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
      await tester.scrollUntilVisible(
        find.text('pt-br-x-pte-local'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('pt-br-x-pte-local'), findsOneWidget);
      expect(find.text('pt-br-x-ptd-local'), findsOneWidget);

      await tester.tap(find.text('pt-br-x-pte-local'));
      await tester.pumpAndSettle();

      expect(voiceService.activeVoiceName, 'pt-br-x-pte-local');
      expect(fakeTts.selectedVoice?['name'], 'pt-br-x-pte-local');
      expect(fakeTts.spoken, isNotEmpty);
      expect(changedCount, greaterThanOrEqualTo(1));

      await tester.drag(find.byType(ListView), const Offset(0, 500));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('NATURAL'),
        -150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('NATURAL'));
      await tester.pumpAndSettle();

      expect(voiceService.profile, VoiceProfile.natural);
      expect(fakeTts.pitch, VoiceProfile.natural.pitch);
    },
  );

  testWidgets(
    'VoiceSelectorSheet saves Fish Studio API credentials, tests voice, and disables Fish when picking local voice',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});

      const channel = MethodChannel('com.viniciusnpaula.ultron_mobile/device');
      var nativePlayed = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'playTtsAudioBytes') {
          nativePlayed += 1;
          return true;
        }
        return true;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final fish = _FakeFishService();
      final fakeTts = _StubTts();
      final voiceService = VoiceService(tts: fakeTts, fishService: fish);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: VoiceSelectorSheet(voiceService: voiceService),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('fish_audio_header')),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('fish_audio_header')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('fish_api_key_field')),
        'fish-token-123',
      );
      await tester.enterText(
        find.byKey(const ValueKey('fish_reference_id_field')),
        'ultron-model-id',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('fish_save_test_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('fish_save_test_button')));
      await tester.pumpAndSettle();

      expect(voiceService.isFishAudioActive, isTrue);
      expect(voiceService.fishConfig.referenceId, 'ultron-model-id');
      expect(voiceService.fishConfig.language, 'pt');
      expect(voiceService.activeVoiceLabel, 'Fish Audio (pt • s2.1-pro)');
      expect(nativePlayed, greaterThanOrEqualTo(1));

      await tester.scrollUntilVisible(
        find.text('Voz ativa: Fish Audio (pt • s2.1-pro)'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
          find.text('Voz ativa: Fish Audio (pt • s2.1-pro)'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('pt-br-x-pte-local'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('pt-br-x-pte-local'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('pt-br-x-pte-local'));
      await tester.pumpAndSettle();

      expect(voiceService.isFishAudioActive, isFalse);
      expect(voiceService.activeVoiceName, 'pt-br-x-pte-local');
    },
  );

  testWidgets(
    'VoiceSelectorSheet lists input microphones, switches to built-in phone mic, and runs capture route test',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      final fakeTts = _StubTts();
      final voiceService = VoiceService(tts: fakeTts);
      final audioInput = _FakeAudioInputRouter();
      final captureSource = _FakeMicCaptureSource();
      addTearDown(captureSource.close);
      var changedCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: VoiceSelectorSheet(
              voiceService: voiceService,
              audioInputService: audioInput,
              captureSource: captureSource,
              onChanged: () => changedCount += 1,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Galaxy Buds (Bluetooth)'), findsOneWidget);
      expect(find.text('Microfone do Celular'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('mic_option_2_builtin')));
      await tester.pumpAndSettle();
      // Aguarda o SnackBar de 2s sumir antes de clicar em mic_test_button.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(audioInput.selectedId, 2);
      expect(audioInput.savedSelections.single.name, 'Microfone do Celular');
      expect(find.text('Ativo: Microfone do Celular'), findsOneWidget);
      expect(changedCount, 1);

      await tester.ensureVisible(find.byKey(const Key('mic_test_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mic_test_button')));
      await tester.pump(const Duration(milliseconds: 50));

      expect(captureSource.started, isTrue);
      expect(find.textContaining('Microfone do Celular'), findsWidgets);

      await tester.tap(find.byKey(const Key('mic_test_button')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(captureSource.stopped, isTrue);
    },
  );
}
