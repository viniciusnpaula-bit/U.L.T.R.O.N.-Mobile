import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:ultron_mobile/core/security/auth_gate.dart';
import 'package:ultron_mobile/services/audio_capture_service.dart';
import 'package:ultron_mobile/services/audio_vad_buffer.dart';
import 'package:ultron_mobile/services/stt_service.dart';
import 'package:ultron_mobile/services/voice_pipeline_controller.dart';
import 'package:ultron_mobile/services/voice_service.dart';

Uint8List _pcmFrame({int samples = 320, int amplitude = 500}) {
  final bytes = Uint8List(samples * 2);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < samples; i++) {
    data.setInt16(i * 2, i.isEven ? amplitude : -amplitude, Endian.little);
  }
  return bytes;
}

class _FakeAudioCaptureSource implements AudioCaptureSource {
  final StreamController<Uint8List> _controller =
      StreamController<Uint8List>.broadcast();
  bool permissionGranted = true;
  int startCalls = 0;
  int stopCalls = 0;
  bool isRunning = false;
  Completer<void>? startGate;

  @override
  Stream<Uint8List> get frames => _controller.stream;

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<AudioEffectsReport> start({int sampleRate = 16000}) async {
    startCalls += 1;
    if (startGate != null) {
      await startGate!.future;
    }
    isRunning = true;
    return AudioEffectsReport(
      aecEnabled: true,
      nsEnabled: true,
      agcEnabled: true,
      sampleRate: sampleRate,
    );
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    isRunning = false;
  }

  void emitFrame(Uint8List frame) {
    _controller.add(frame);
  }

  Future<void> close() => _controller.close();
}

class _FakeTts extends FlutterTts {
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

Future<AuthGate> _unlockedGate() async {
  final gate = AuthGate();
  await gate.authenticatePin('1234', (_) async => true);
  return gate;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides? previousHttpOverrides;

  setUpAll(() {
    previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
  });

  tearDownAll(() {
    HttpOverrides.global = previousHttpOverrides;
  });

  test('refuses capture when AuthGate is locked', () async {
    final gate = AuthGate();
    final capture = _FakeAudioCaptureSource();
    final stt = GroqWhisperSttService(
      config: const SttConfig(endpointUrl: 'http://127.0.0.1:1', apiKey: 'k'),
    );
    final voice = VoiceService(tts: _FakeTts());
    final controller = VoicePipelineController(
      gate: gate,
      capture: capture,
      stt: stt,
      voiceService: voice,
    );
    addTearDown(() async {
      controller.dispose();
      await capture.close();
    });

    expect(await controller.startPushToTalk(), isFalse);
    expect(await controller.startContinuousListening(), isFalse);
    expect(capture.startCalls, 0);
  });

  test('stops capture immediately on lifecycle pause/inactive or gate.lock()', () async {
    final gate = await _unlockedGate();
    final capture = _FakeAudioCaptureSource();
    final stt = GroqWhisperSttService(
      config: const SttConfig(endpointUrl: 'http://127.0.0.1:1', apiKey: 'k'),
    );
    final tts = _FakeTts();
    final voice = VoiceService(tts: tts);
    final controller = VoicePipelineController(
      gate: gate,
      capture: capture,
      stt: stt,
      voiceService: voice,
    );
    addTearDown(() async {
      controller.dispose();
      await capture.close();
    });

    expect(await controller.startContinuousListening(), isTrue);
    expect(capture.isRunning, isTrue);

    controller.handleLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);
    expect(capture.isRunning, isFalse);
    expect(capture.stopCalls, greaterThanOrEqualTo(1));

    controller.handleLifecycleState(AppLifecycleState.resumed);
    expect(await controller.startPushToTalk(), isTrue);
    expect(capture.isRunning, isTrue);

    gate.lock();
    await Future<void>.delayed(Duration.zero);
    expect(capture.isRunning, isFalse);
  });

  test('Push-to-Talk captures frames while held and transcribes on release', () async {
    final gate = await _unlockedGate();
    final capture = _FakeAudioCaptureSource();

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      await req.drain<void>();
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'text': 'Ligar modo silencioso'}));
      await req.response.close();
    });

    final stt = GroqWhisperSttService(
      config: SttConfig(
        endpointUrl: 'http://127.0.0.1:${server.port}/transcriptions',
        apiKey: 'gsk_test',
      ),
    );
    final voice = VoiceService(tts: _FakeTts());
    final transcripts = <String>[];
    final controller = VoicePipelineController(
      gate: gate,
      capture: capture,
      stt: stt,
      voiceService: voice,
      onTranscript: transcripts.add,
    );
    addTearDown(() async {
      controller.dispose();
      await capture.close();
    });

    expect(await controller.startPushToTalk(), isTrue);
    capture.emitFrame(_pcmFrame(samples: 320, amplitude: 600));
    capture.emitFrame(_pcmFrame(samples: 320, amplitude: 600));
    await Future<void>.delayed(Duration.zero);

    final text = await controller.stopPushToTalk();
    expect(capture.isRunning, isFalse);
    expect(text, 'Ligar modo silencioso');
    expect(transcripts, ['Ligar modo silencioso']);
  });

  test('continuous mode enforces selective barge-in while TTS is speaking', () async {
    final gate = await _unlockedGate();
    final capture = _FakeAudioCaptureSource();
    final responses = <String>[
      'O tempo está ótimo hoje',
      'Silêncio',
      'Ei Últron',
    ];
    var respIdx = 0;

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      await req.drain<void>();
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'text': responses[respIdx++]}));
      await req.response.close();
    });

    final stt = GroqWhisperSttService(
      config: SttConfig(
        endpointUrl: 'http://127.0.0.1:${server.port}/transcriptions',
        apiKey: 'gsk_test',
      ),
    );
    final tts = _FakeTts();
    final voice = VoiceService(tts: tts);
    final transcripts = <String>[];
    final controller = VoicePipelineController(
      gate: gate,
      capture: capture,
      stt: stt,
      voiceService: voice,
      vadSegmenter: VadSegmenter(
        sampleRate: 16000,
        speechThreshold: 50.0,
        preSpeechDuration: const Duration(milliseconds: 20),
        silenceHangover: const Duration(milliseconds: 20),
      ),
      onTranscript: transcripts.add,
    );
    addTearDown(() async {
      controller.dispose();
      await capture.close();
    });

    expect(await controller.startContinuousListening(), isTrue);

    // Start TTS speaking
    tts.speakGate = Completer<void>();
    final speakFuture = voice.speak('Relatório completo');
    await tts.speakStarted.future;
    expect(voice.isSpeaking, isTrue);

    // 1st utterance: ordinary speech -> must NOT stop TTS or emit transcript
    capture.emitFrame(_pcmFrame(amplitude: 600));
    capture.emitFrame(_pcmFrame(amplitude: 0));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(voice.isSpeaking, isTrue);
    expect(transcripts, isEmpty);

    // 2nd utterance: "Silêncio" -> stops TTS!
    capture.emitFrame(_pcmFrame(amplitude: 600));
    capture.emitFrame(_pcmFrame(amplitude: 0));
    await speakFuture.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(voice.isSpeaking, isFalse);
    expect(transcripts, isEmpty);

    // Also test BargeInMatcher directly for accent/variant normalization
    expect(BargeInMatcher.isBargeInPhrase('parar'), isTrue);
    expect(BargeInMatcher.isBargeInPhrase('Silêncio!'), isTrue);
    expect(BargeInMatcher.isBargeInPhrase('Ei Últron'), isTrue);
    expect(BargeInMatcher.isBargeInPhrase('ultram'), isTrue);
    expect(BargeInMatcher.isBargeInPhrase('Qual é a previsão'), isFalse);
  });

  test('continuous mode opens configurable continuity window after TTS completes', () async {
    final gate = await _unlockedGate();
    final capture = _FakeAudioCaptureSource();
    var currentTime = DateTime.utc(2026, 11, 16, 12, 0, 0);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      await req.drain<void>();
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'text': 'Qual a próxima reunião?'}));
      await req.response.close();
    });

    final stt = GroqWhisperSttService(
      config: SttConfig(
        endpointUrl: 'http://127.0.0.1:${server.port}/transcriptions',
        apiKey: 'gsk_test',
      ),
    );
    final tts = _FakeTts();
    final voice = VoiceService(tts: tts);
    final transcripts = <String>[];
    final controller = VoicePipelineController(
      gate: gate,
      capture: capture,
      stt: stt,
      voiceService: voice,
      vadSegmenter: VadSegmenter(
        sampleRate: 16000,
        speechThreshold: 50.0,
        preSpeechDuration: const Duration(milliseconds: 20),
        silenceHangover: const Duration(milliseconds: 20),
      ),
      continuityWindow: const Duration(seconds: 6),
      now: () => currentTime,
      onTranscript: transcripts.add,
    );
    addTearDown(() async {
      controller.dispose();
      await capture.close();
    });

    expect(await controller.startContinuousListening(), isTrue);
    expect(controller.isContinuityWindowActive, isFalse);

    await voice.speak('Tudo pronto.');
    expect(controller.isContinuityWindowActive, isTrue);

    // Inside continuity window -> accepts ordinary follow-up without wake word
    currentTime = currentTime.add(const Duration(seconds: 3));
    capture.emitFrame(_pcmFrame(amplitude: 600));
    capture.emitFrame(_pcmFrame(amplitude: 0));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(transcripts, ['Qual a próxima reunião?']);

    // After continuity window expires -> ignores non-wake utterance
    currentTime = currentTime.add(const Duration(seconds: 10));
    expect(controller.isContinuityWindowActive, isFalse);
    capture.emitFrame(_pcmFrame(amplitude: 600));
    capture.emitFrame(_pcmFrame(amplitude: 0));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(transcripts, ['Qual a próxima reunião?']);
  });

  test('aborts in-flight start when gate locks or lifecycle pauses before start resolves', () async {
    final gate = await _unlockedGate();
    final capture = _FakeAudioCaptureSource()..startGate = Completer<void>();
    final stt = GroqWhisperSttService(
      config: const SttConfig(endpointUrl: 'http://127.0.0.1:1', apiKey: 'k'),
    );
    final voice = VoiceService(tts: _FakeTts());
    final controller = VoicePipelineController(
      gate: gate,
      capture: capture,
      stt: stt,
      voiceService: voice,
    );
    addTearDown(() async {
      controller.dispose();
      await capture.close();
    });

    final startFuture = controller.startContinuousListening();
    await Future<void>.delayed(Duration.zero);
    expect(capture.startCalls, 1);

    // Pause lifecycle while capture.start() is still awaiting native AudioRecord.
    controller.handleLifecycleState(AppLifecycleState.paused);
    capture.startGate!.complete();

    expect(await startFuture, isFalse);
    expect(controller.mode, VoicePipelineMode.idle);
    expect(controller.isCapturing, isFalse);
    expect(capture.isRunning, isFalse);
  });

  test('cancels in-flight Push-to-Talk start when stopPushToTalk fires early', () async {
    final gate = await _unlockedGate();
    final capture = _FakeAudioCaptureSource()..startGate = Completer<void>();
    final stt = GroqWhisperSttService(
      config: const SttConfig(endpointUrl: 'http://127.0.0.1:1', apiKey: 'k'),
    );
    final voice = VoiceService(tts: _FakeTts());
    final controller = VoicePipelineController(
      gate: gate,
      capture: capture,
      stt: stt,
      voiceService: voice,
    );
    addTearDown(() async {
      controller.dispose();
      await capture.close();
    });

    final startFuture = controller.startPushToTalk();
    await Future<void>.delayed(Duration.zero);
    expect(capture.startCalls, 1);

    // User releases PTT finger before native start completes.
    final stopResult = await controller.stopPushToTalk();
    expect(stopResult, isNull);

    capture.startGate!.complete();
    expect(await startFuture, isFalse);
    expect(controller.mode, VoicePipelineMode.idle);
    expect(controller.isCapturing, isFalse);
    expect(capture.isRunning, isFalse);
  });
}
