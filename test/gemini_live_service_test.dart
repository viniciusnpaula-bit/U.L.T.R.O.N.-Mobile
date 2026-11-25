import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:ultron_mobile/core/security/action_gate.dart';
import 'package:ultron_mobile/core/security/auth_gate.dart';
import 'package:ultron_mobile/services/audio_capture_service.dart';
import 'package:ultron_mobile/services/gemini_live_service.dart';

class _FakeLocalAuth extends LocalAuthentication {
  @override
  Future<bool> get canCheckBiometrics async => true;

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<dynamic> authMessages = const <dynamic>[],
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async =>
      true;
}

class _FakeCaptureSource implements AudioCaptureSource {
  final StreamController<Uint8List> _controller =
      StreamController<Uint8List>.broadcast();
  bool started = false;
  int? lastSampleRate;

  @override
  Stream<Uint8List> get frames => _controller.stream;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<AudioEffectsReport> start({int sampleRate = 16000}) async {
    started = true;
    lastSampleRate = sampleRate;
    return AudioEffectsReport(sampleRate: sampleRate, aecEnabled: true);
  }

  @override
  Future<void> stop() async {
    started = false;
  }

  void emitFrame(Uint8List frame) => _controller.add(frame);

  Future<void> dispose() => _controller.close();
}

class _FakePcmOutput implements PcmStreamOutput {
  bool started = false;
  int? sampleRate;
  final List<Uint8List> writtenChunks = <Uint8List>[];
  int flushCount = 0;
  int stopCount = 0;

  @override
  Future<bool> start({int sampleRate = 24000}) async {
    started = true;
    this.sampleRate = sampleRate;
    return true;
  }

  @override
  Future<void> write(Uint8List pcmBytes) async {
    writtenChunks.add(pcmBytes);
  }

  @override
  Future<void> flush() async {
    flushCount++;
  }

  @override
  Future<void> stop() async {
    started = false;
    stopCount++;
  }
}

class _FakeLiveSocket implements GeminiLiveSocket {
  final StreamController<dynamic> incoming =
      StreamController<dynamic>.broadcast();
  final List<String> sentMessages = <String>[];
  bool closed = false;

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  void sendText(String data) {
    sentMessages.add(data);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    closed = true;
    await incoming.close();
  }
}

Uint8List _sineLikePcm16(int sampleCount, int amplitude) {
  final bytes = Uint8List(sampleCount * 2);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < sampleCount; i++) {
    final val = (i % 4 < 2) ? amplitude : -amplitude;
    data.setInt16(i * 2, val, Endian.little);
  }
  return bytes;
}

void main() {
  group('GeminiLiveService (Real-Time WebSocket 16kHz/24kHz)', () {
    late AuthGate authGate;
    late _FakeCaptureSource capture;
    late _FakePcmOutput output;
    late _FakeLiveSocket socket;

    setUp(() async {
      authGate = AuthGate(
        auth: _FakeLocalAuth(),
      );
      await authGate.authenticateBiometric();
      capture = _FakeCaptureSource();
      output = _FakePcmOutput();
      socket = _FakeLiveSocket();
    });

    tearDown(() async {
      await capture.dispose();
    });

    test('sends API key strictly in x-goog-api-key header and never in URL', () async {
      Uri? connectedUri;
      Map<String, dynamic>? connectedHeaders;

      final live = GeminiLiveService(
        authGate: authGate,
        capture: capture,
        output: output,
        connector: (uri, {required headers}) async {
          connectedUri = uri;
          connectedHeaders = headers;
          return socket;
        },
      );

      final ok = await live.connect(apiKey: 'AIzaTestSecretHeaderOnly');
      expect(ok, isTrue);
      expect(connectedUri, isNotNull);
      expect(connectedUri.toString(), isNot(contains('AIzaTestSecretHeaderOnly')));
      expect(connectedUri!.queryParameters.containsKey('key'), isFalse);
      expect(connectedHeaders?['x-goog-api-key'], 'AIzaTestSecretHeaderOnly');
      expect(capture.lastSampleRate, 16000);
      expect(output.sampleRate, 24000);
      expect(socket.sentMessages, isNotEmpty);

      // Reject explicit URL with key query param
      await expectLater(
        () => live.connect(
          apiKey: 'AIzaTestSecretHeaderOnly',
          endpoint: Uri.parse('wss://example.com/live?key=LEAK'),
        ),
        throwsArgumentError,
      );

      live.dispose();
    });

    test('streams 16kHz input, plays 24kHz output, and triggers instant barge-in flush', () async {
      final live = GeminiLiveService(
        authGate: authGate,
        capture: capture,
        output: output,
        localBargeInRmsThreshold: 900.0,
        connector: (uri, {required headers}) async => socket,
      );

      await live.connect(apiKey: 'AIzaTestKey');

      // 1. Emit 16 kHz mic frame -> sent as realtimeInput mediaChunk
      final micFrame = _sineLikePcm16(320, 400);
      capture.emitFrame(micFrame);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        socket.sentMessages.any((m) => m.contains('audio/pcm;rate=16000')),
        isTrue,
      );

      // 2. Receive 24 kHz audio from Gemini Live -> played via PcmStreamOutput
      final outPcm = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      socket.incoming.add(
        jsonEncode({
          'serverContent': {
            'modelTurn': {
              'parts': [
                {
                  'inlineData': {
                    'mimeType': 'audio/pcm;rate=24000',
                    'data': base64Encode(outPcm),
                  },
                },
              ],
            },
          },
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(live.state, GeminiLiveState.speaking);
      expect(output.writtenChunks, hasLength(1));
      expect(output.writtenChunks.first, outPcm);

      // 3. Local loud speech (2 consecutive frames) triggers instant barge-in flush
      capture.emitFrame(_sineLikePcm16(320, 2400));
      capture.emitFrame(_sineLikePcm16(320, 2400));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(output.flushCount, greaterThanOrEqualTo(1));
      expect(live.bargeInCount, greaterThanOrEqualTo(1));
      expect(live.state, GeminiLiveState.listening);

      live.dispose();
    });

    test('gates toolCall through ActionGate + AuthGate before execution', () async {
      final executed = <String>[];
      final confirmedActions = <String>[];

      // Start with PIN-only basic session -> Desktop/critical tools must be blocked
      final pinGate = AuthGate();
      await pinGate.authenticatePin('1234', (p) async => p == '1234');

      final live = GeminiLiveService(
        authGate: pinGate,
        capture: capture,
        output: output,
        connector: (uri, {required headers}) async => socket,
        onConfirmTool: (ActionSimulation sim) async {
          confirmedActions.add(sim.actionCode);
          return true;
        },
        onExecuteActionTag: (tag) async {
          executed.add(tag);
          return 'executado:$tag';
        },
      );

      await live.connect(apiKey: 'AIzaTestKey');

      // Critical/Desktop tool call under basic PIN must be BLOCKED
      socket.incoming.add(
        jsonEncode({
          'toolCall': {
            'functionCalls': [
              {
                'id': 'call_1',
                'name': 'execute_ultron_action',
                'args': {'action_tag': 'KILL_SWITCH'},
              },
            ],
          },
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(executed, isEmpty);
      expect(
        socket.sentMessages.any(
          (m) => m.contains('"call_1"') && m.contains('"blocked"'),
        ),
        isTrue,
      );

      // Safe local tool call under basic PIN is ALLOWED
      socket.incoming.add(
        jsonEncode({
          'toolCall': {
            'functionCalls': [
              {
                'id': 'call_2',
                'name': 'execute_ultron_action',
                'args': {'action_tag': 'TORCH_ON'},
              },
            ],
          },
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(executed, ['[ACTION:TORCH_ON]']);
      expect(
        socket.sentMessages.any(
          (m) => m.contains('"call_2"') && m.contains('"ok"'),
        ),
        isTrue,
      );

      // Locking session disconnects fail-closed immediately
      pinGate.lock();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(live.state, GeminiLiveState.disconnected);
      expect(socket.closed, isTrue);

      live.dispose();
    });
  });
}
