import 'dart:async';

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
  int stopCalls = 0;
  Completer<void>? speakGate;
  Completer<void> speakStarted = Completer<void>();
  bool _inSpeak = false;

  @override
  Future<dynamic> setLanguage(String language) async => 1;

  @override
  Future<dynamic> setPitch(double pitch) async => 1;

  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;

  @override
  Future<dynamic> setVolume(double volume) async => 1;

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

  test('VoiceService.initialize clears failed future and retries cleanly', () async {
    final fake = _FlakyTts();
    final voice = VoiceService(tts: fake);

    await expectLater(voice.initialize(), throwsStateError);
    await voice.initialize();
    expect(fake.setLanguageCalls, 2);
  });

  test('VoiceService.speak normalizes text and updates speaking state', () async {
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

  test('VoiceService.stop clears isSpeaking and suppresses onSpeakComplete', () async {
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
}
