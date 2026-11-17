import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:ultron_mobile/services/voice_service.dart';

class _FlakyTts extends FlutterTts {
  int setLanguageCalls = 0;

  @override
  Future<dynamic> setLanguage(String language) async {
    setLanguageCalls += 1;
    if (setLanguageCalls == 1) {
      throw StateError('tts init failed once');
    }
    return 1;
  }

  @override
  Future<dynamic> setPitch(double pitch) async => 1;

  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;

  @override
  Future<dynamic> setVolume(double volume) async => 1;

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async => 1;
}

class _RecordingTts extends FlutterTts {
  final List<String> spoken = <String>[];
  final List<String> events = <String>[];
  double? lastPitch;
  double? lastRate;
  Map<String, String>? lastVoice;
  List<Map<String, String>> voices = const [
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
  int stopCalls = 0;
  Completer<void>? speakGate;
  Completer<void> speakStarted = Completer<void>();
  bool _inSpeak = false;

  @override
  Future<dynamic> get getVoices async => voices;

  @override
  Future<dynamic> setLanguage(String language) async {
    events.add('setLanguage:$language');
    return 1;
  }

  @override
  Future<dynamic> setPitch(double pitch) async {
    lastPitch = pitch;
    events.add('setPitch:$pitch');
    return 1;
  }

  @override
  Future<dynamic> setSpeechRate(double rate) async {
    lastRate = rate;
    events.add('setSpeechRate:$rate');
    return 1;
  }

  @override
  Future<dynamic> setVolume(double volume) async {
    events.add('setVolume:$volume');
    return 1;
  }

  @override
  Future<dynamic> setVoice(Map<String, String> voice) async {
    lastVoice = voice;
    events.add('setVoice:${voice['name']}');
    return 1;
  }

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async => 1;

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    spoken.add(text);
    _inSpeak = true;
    if (!speakStarted.isCompleted) {
      speakStarted.complete();
    }
    try {
      final gate = speakGate;
      if (gate != null) {
        await gate.future;
      }
    } finally {
      _inSpeak = false;
    }
    return 1;
  }

  @override
  Future<dynamic> stop() async {
    stopCalls += 1;
    final gate = speakGate;
    if (_inSpeak && gate != null && !gate.isCompleted) {
      gate.complete();
    }
    return 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('VoiceService.initialize clears failed future and retries cleanly',
      () async {
    final fake = _FlakyTts();
    final voice = VoiceService(tts: fake);

    await expectLater(voice.initialize(), throwsStateError);
    await voice.initialize();
    expect(fake.setLanguageCalls, 2);
  });

  test('VoiceService.speak normalizes text and updates speaking state',
      () async {
    final fake = _RecordingTts();
    fake.speakGate = Completer<void>();
    var completed = 0;
    final voice = VoiceService(
      tts: fake,
      onSpeakComplete: () => completed += 1,
    );

    final speakingFuture = voice.speak('U.L.T.R.O.N. pronto');
    await fake.speakStarted.future;
    expect(fake.spoken, ['Ultron pronto.']);
    expect(voice.isSpeaking, isTrue);

    fake.speakGate!.complete();
    await speakingFuture;
    expect(voice.isSpeaking, isFalse);
    expect(completed, 1);
  });

  test('VoiceService.stop clears isSpeaking and suppresses onSpeakComplete',
      () async {
    final fake = _RecordingTts();
    fake.speakGate = Completer<void>();
    var completed = 0;
    final voice = VoiceService(
      tts: fake,
      onSpeakComplete: () => completed += 1,
    );

    final speakingFuture = voice.speak('I.A. falando agora');
    await fake.speakStarted.future;
    expect(voice.isSpeaking, isTrue);

    await voice.stop();
    await speakingFuture;
    expect(voice.isSpeaking, isFalse);
    expect(completed, 0);
  });

  test(
      'setPreferredVoice and setProfile apply voice before pitch/rate and preserve user choice',
      () async {
    FlutterSecureStorage.setMockInitialValues(const {
      'ultron.tts.profile.v1': 'grave',
    });
    final fake = _RecordingTts();
    final voice = VoiceService(tts: fake);

    // Explicitly switch profile before initialize finishes; must NOT be overwritten by storage.
    await voice.setProfile(VoiceProfile.agil);
    expect(voice.profile, VoiceProfile.agil);
    expect(fake.lastPitch, VoiceProfile.agil.pitch);
    expect(fake.lastRate, VoiceProfile.agil.rate);

    final firstVoiceIdx =
        fake.events.indexWhere((e) => e.startsWith('setVoice:'));
    final lastPitchIdx =
        fake.events.lastIndexWhere((e) => e.startsWith('setPitch:'));
    expect(firstVoiceIdx, isNonNegative);
    expect(lastPitchIdx, greaterThan(firstVoiceIdx));

    fake.events.clear();
    const chosen = TtsVoiceOption(
      name: 'pt-br-x-pte-local',
      locale: 'pt-BR',
      offline: true,
      quality: 'high',
    );
    await voice.setPreferredVoice(chosen);
    expect(voice.activeVoiceName, 'pt-br-x-pte-local');
    expect(fake.lastVoice?['name'], 'pt-br-x-pte-local');

    final voiceEvt = fake.events.indexOf('setVoice:pt-br-x-pte-local');
    final pitchAfterVoice =
        fake.events.lastIndexWhere((e) => e.startsWith('setPitch:'));
    expect(voiceEvt, isNonNegative);
    expect(pitchAfterVoice, greaterThan(voiceEvt));
  });
}
