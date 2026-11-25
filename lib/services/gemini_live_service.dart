import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/security/action_gate.dart';
import '../core/security/auth_gate.dart';
import 'audio_capture_service.dart';
import 'audio_vad_buffer.dart';

enum GeminiLiveState {
  disconnected('Desconectado'),
  connecting('Conectando'),
  listening('Ouvindo ao vivo'),
  speaking('Falando ao vivo'),
  error('Erro');

  const GeminiLiveState(this.label);
  final String label;

  bool get isActive =>
      this == connecting || this == listening || this == speaking;
}

/// Abstração testável de WebSocket para a Gemini Multimodal Live API.
abstract interface class GeminiLiveSocket {
  Stream<dynamic> get stream;
  void sendText(String data);
  Future<void> close([int? code, String? reason]);
}

class IoGeminiLiveSocket implements GeminiLiveSocket {
  IoGeminiLiveSocket(this._socket);

  final WebSocket _socket;

  @override
  Stream<dynamic> get stream => _socket;

  @override
  void sendText(String data) {
    _socket.add(data);
  }

  @override
  Future<void> close([int? code, String? reason]) =>
      _socket.close(code, reason);
}

typedef GeminiLiveSocketConnector = Future<GeminiLiveSocket> Function(
  Uri uri, {
  required Map<String, dynamic> headers,
});

/// Abstração testável de reprodução PCM16 24 kHz com flush instantâneo para barge-in.
abstract interface class PcmStreamOutput {
  Future<bool> start({int sampleRate = 24000});
  Future<void> write(Uint8List pcmBytes);
  Future<void> flush();
  Future<void> stop();
}

class MethodChannelPcmStreamOutput implements PcmStreamOutput {
  MethodChannelPcmStreamOutput({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('com.viniciusnpaula.ultron_mobile/pcm_player');

  final MethodChannel _channel;

  @override
  Future<bool> start({int sampleRate = 24000}) async {
    final ok = await _channel.invokeMethod<bool>(
      'start',
      <String, Object?>{'sampleRate': sampleRate},
    );
    return ok ?? false;
  }

  @override
  Future<void> write(Uint8List pcmBytes) async {
    if (pcmBytes.isEmpty) return;
    await _channel.invokeMethod<int>(
      'write',
      <String, Object?>{'bytes': pcmBytes},
    );
  }

  @override
  Future<void> flush() async {
    await _channel.invokeMethod<bool>('flush');
  }

  @override
  Future<void> stop() async {
    await _channel.invokeMethod<bool>('stop');
  }
}

typedef GeminiLiveToolConfirm = Future<bool> Function(
  ActionSimulation simulation,
);

typedef GeminiLiveToolExecutor = Future<String> Function(
  String actionTag,
);

/// Cliente WebSocket bidirecional em tempo real para Gemini Live (`voz_live.py` -> Dart):
/// - Entrada: 16 kHz PCM16 exclusivamente via microfone nativo (`AudioCaptureSource` / `AudioRecord`).
/// - Saída: 24 kHz PCM16 via `AudioTrack` nativo (`PcmStreamOutput`).
/// - Segurança: chave de API enviada APENAS no header `x-goog-api-key` (NUNCA na query URL).
/// - Tool calling: toda `functionCall` passa obrigatoriamente por `ActionGate` + `AuthGate`.
/// - Barge-in instantâneo: interrompe o buffer `AudioTrack` em < 20 ms ao detectar fala local ou `interrupted`.
class GeminiLiveService extends ChangeNotifier {
  GeminiLiveService({
    required AuthGate authGate,
    required AudioCaptureSource capture,
    PcmStreamOutput? output,
    ActionGate actionGate = const ActionGate(),
    GeminiLiveSocketConnector? connector,
    this.inputSampleRate = 16000,
    this.outputSampleRate = 24000,
    this.localBargeInRmsThreshold = 950.0,
    this.onConfirmTool,
    this.onExecuteActionTag,
    this.onTranscript,
    this.onRmsChanged,
  })  : _authGate = authGate,
        _capture = capture,
        _output = output ?? MethodChannelPcmStreamOutput(),
        _actionGate = actionGate,
        _connector = connector ?? _defaultSocketConnector {
    _authGate.addListener(_onAuthChanged);
  }

  static final Uri defaultEndpoint = Uri.parse(
    'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent',
  );

  static const String defaultLiveModel = 'models/gemini-2.0-flash-live-001';

  final AuthGate _authGate;
  final AudioCaptureSource _capture;
  final PcmStreamOutput _output;
  final ActionGate _actionGate;
  final GeminiLiveSocketConnector _connector;
  final int inputSampleRate;
  final int outputSampleRate;
  final double localBargeInRmsThreshold;
  final GeminiLiveToolConfirm? onConfirmTool;
  final GeminiLiveToolExecutor? onExecuteActionTag;
  final void Function(String role, String text)? onTranscript;
  final ValueChanged<double>? onRmsChanged;

  GeminiLiveSocket? _socket;
  StreamSubscription<dynamic>? _socketSub;
  StreamSubscription<Uint8List>? _captureSub;
  GeminiLiveState _state = GeminiLiveState.disconnected;
  String? _lastError;
  int _bargeInCount = 0;
  int _consecutiveLoudFrames = 0;
  bool _disposed = false;
  final StringBuffer _modelTurnTranscript = StringBuffer();

  GeminiLiveState get state => _state;
  bool get isActive => _state.isActive;
  String? get lastError => _lastError;
  int get bargeInCount => _bargeInCount;

  static Future<GeminiLiveSocket> _defaultSocketConnector(
    Uri uri, {
    required Map<String, dynamic> headers,
  }) async {
    final ws = await WebSocket.connect(
      uri.toString(),
      headers: headers,
    ).timeout(const Duration(seconds: 12));
    return IoGeminiLiveSocket(ws);
  }

  void _onAuthChanged() {
    if (!_authGate.isAuthenticated && isActive) {
      unawaited(disconnect());
    }
  }

  /// Inicia sessão bidirecional de voz ao vivo com a API Gemini Live.
  /// A chave [apiKey] trafega exclusivamente no header HTTP `x-goog-api-key`.
  Future<bool> connect({
    required String apiKey,
    String model = defaultLiveModel,
    String systemInstruction = '',
    String voiceName = 'Aoede',
    Uri? endpoint,
  }) async {
    if (_disposed) return false;
    if (!_authGate.isAuthenticated) {
      _setError('Sessão bloqueada: autentique-se antes de iniciar o Gemini Live.');
      return false;
    }

    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty || cleanKey.toLowerCase() == 'free') {
      _setError('Configure uma chave válida do Google Gemini Studio para usar o modo Live.');
      return false;
    }

    final targetUri = endpoint ?? defaultEndpoint;
    if (targetUri.queryParameters.containsKey('key') ||
        targetUri.query.toLowerCase().contains('key=')) {
      throw ArgumentError(
        'Chave de API não pode trafegar na URL; use exclusivamente o header x-goog-api-key.',
      );
    }

    final granted = await _capture.hasPermission() ||
        await _capture.requestPermission();
    if (!granted) {
      _setError('Permissão de microfone negada.');
      return false;
    }

    await disconnect();
    _state = GeminiLiveState.connecting;
    _lastError = null;
    _notifySafely();

    try {
      final socket = await _connector(
        targetUri,
        headers: <String, dynamic>{
          'x-goog-api-key': cleanKey,
        },
      );
      _socket = socket;
      await _output.start(sampleRate: outputSampleRate);

      _socketSub = socket.stream.listen(
        _handleServerEvent,
        onError: (Object err) {
          _setError('Conexão Live interrompida: $err');
          unawaited(disconnect(preserveError: true));
        },
        onDone: () {
          if (_state != GeminiLiveState.disconnected) {
            unawaited(disconnect());
          }
        },
      );

      final normalizedModel =
          model.startsWith('models/') ? model : 'models/$model';

      final setupPayload = <String, Object?>{
        'setup': <String, Object?>{
          'model': normalizedModel,
          'generationConfig': <String, Object?>{
            'responseModalities': const <String>['AUDIO'],
            'speechConfig': <String, Object?>{
              'voiceConfig': <String, Object?>{
                'prebuiltVoiceConfig': <String, Object?>{
                  'voiceName': voiceName,
                },
              },
            },
          },
          if (systemInstruction.trim().isNotEmpty)
            'systemInstruction': <String, Object?>{
              'parts': <Map<String, String>>[
                {'text': systemInstruction.trim()},
              ],
            },
          'tools': <Map<String, Object?>>[
            {
              'functionDeclarations': <Map<String, Object?>>[
                {
                  'name': 'execute_ultron_action',
                  'description':
                      'Executa uma ação tática do ULTRON Mobile ou Desktop sujeita ao ActionGate/AuthGate (ex.: TORCH_ON, VOLUME_SET:50, NOTE:texto, PC_TEMP, PC_MEDIA:pause).',
                  'parameters': <String, Object?>{
                    'type': 'OBJECT',
                    'properties': <String, Object?>{
                      'action_tag': <String, Object?>{
                        'type': 'STRING',
                        'description':
                            'Comando no formato OP ou OP:ARG1:ARG2 (ex.: TORCH_ON, NOTE:comprar cabo, PC_TEMP).',
                      },
                    },
                    'required': const <String>['action_tag'],
                  },
                },
              ],
            },
          ],
        },
      };

      socket.sendText(jsonEncode(setupPayload));

      _captureSub = _capture.frames.listen(_handleMicFrame);
      await _capture.start(sampleRate: inputSampleRate);

      _state = GeminiLiveState.listening;
      _notifySafely();
      return true;
    } catch (e) {
      _setError('Falha ao conectar Gemini Live: $e');
      await disconnect(preserveError: true);
      return false;
    }
  }

  /// Envia texto pontual dentro da sessão Live ativa.
  void sendClientText(String text) {
    final clean = text.trim();
    if (clean.isEmpty || _socket == null || !isActive) return;
    _socket!.sendText(
      jsonEncode(<String, Object?>{
        'clientContent': <String, Object?>{
          'turns': <Map<String, Object?>>[
            {
              'role': 'user',
              'parts': <Map<String, String>>[
                {'text': clean},
              ],
            },
          ],
          'turnComplete': true,
        },
      }),
    );
  }

  /// Dispara barge-in manual imediato (silencia reprodução 24 kHz sem derrubar o socket).
  Future<void> triggerBargeIn() async {
    _bargeInCount++;
    _consecutiveLoudFrames = 0;
    await _output.flush();
    if (isActive) {
      _state = GeminiLiveState.listening;
      _notifySafely();
    }
  }

  Future<void> disconnect({bool preserveError = false}) async {
    await _captureSub?.cancel();
    _captureSub = null;
    try {
      await _capture.stop();
    } catch (_) {}

    await _socketSub?.cancel();
    _socketSub = null;
    final sock = _socket;
    _socket = null;
    if (sock != null) {
      try {
        await sock.close();
      } catch (_) {}
    }

    try {
      await _output.stop();
    } catch (_) {}

    _consecutiveLoudFrames = 0;
    _modelTurnTranscript.clear();
    onRmsChanged?.call(0.0);
    if (!preserveError) {
      _lastError = null;
      _state = GeminiLiveState.disconnected;
    } else {
      _state = GeminiLiveState.error;
    }
    _notifySafely();
  }

  void _handleMicFrame(Uint8List pcm16Frame) {
    if (!isActive || _socket == null || pcm16Frame.isEmpty) return;

    final rms = PcmEnergy.dcRemovedRmsInt16(pcm16Frame);
    onRmsChanged?.call((rms / 4000.0).clamp(0.0, 1.0));

    // Barge-in local instantâneo quando o usuário começa a falar durante a fala da IA.
    if (_state == GeminiLiveState.speaking) {
      if (rms >= localBargeInRmsThreshold) {
        _consecutiveLoudFrames++;
        if (_consecutiveLoudFrames >= 2) {
          unawaited(triggerBargeIn());
        }
      } else {
        _consecutiveLoudFrames = 0;
      }
    } else {
      _consecutiveLoudFrames = 0;
    }

    final payload = <String, Object?>{
      'realtimeInput': <String, Object?>{
        'mediaChunks': <Map<String, String>>[
          {
            'mimeType': 'audio/pcm;rate=$inputSampleRate',
            'data': base64Encode(pcm16Frame),
          },
        ],
      },
    };
    try {
      _socket?.sendText(jsonEncode(payload));
    } catch (_) {}
  }

  void _handleServerEvent(dynamic rawEvent) {
    if (_disposed) return;
    String? jsonStr;
    if (rawEvent is String) {
      jsonStr = rawEvent;
    } else if (rawEvent is List<int>) {
      jsonStr = utf8.decode(rawEvent, allowMalformed: true);
    }
    if (jsonStr == null || jsonStr.trim().isEmpty) return;

    Map<String, dynamic> msg;
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map<String, dynamic>) return;
      msg = decoded;
    } catch (_) {
      return;
    }

    final serverContent = msg['serverContent'];
    if (serverContent is Map<String, dynamic>) {
      if (serverContent['interrupted'] == true) {
        unawaited(triggerBargeIn());
        return;
      }

      final inputTranscript = serverContent['inputTranscription'];
      if (inputTranscript is Map<String, dynamic>) {
        final text = (inputTranscript['text'] as String? ?? '').trim();
        if (text.isNotEmpty) {
          onTranscript?.call('user', text);
        }
      }

      final outputTranscript = serverContent['outputTranscription'];
      if (outputTranscript is Map<String, dynamic>) {
        final text = (outputTranscript['text'] as String? ?? '').trim();
        if (text.isNotEmpty) {
          _modelTurnTranscript.write(text);
        }
      }

      final modelTurn = serverContent['modelTurn'];
      if (modelTurn is Map<String, dynamic>) {
        final parts = modelTurn['parts'];
        if (parts is List) {
          for (final part in parts) {
            if (part is! Map<String, dynamic>) continue;
            final textPart = (part['text'] as String? ?? '').trim();
            if (textPart.isNotEmpty) {
              _modelTurnTranscript.write(textPart);
            }
            final inlineData = part['inlineData'];
            if (inlineData is Map<String, dynamic>) {
              final mime = (inlineData['mimeType'] as String? ?? '').toLowerCase();
              final b64 = (inlineData['data'] as String? ?? '').trim();
              if (mime.startsWith('audio/pcm') && b64.isNotEmpty) {
                try {
                  final pcmBytes = base64Decode(b64);
                  if (_state != GeminiLiveState.speaking) {
                    _state = GeminiLiveState.speaking;
                    _notifySafely();
                  }
                  unawaited(_output.write(pcmBytes));
                } catch (_) {}
              }
            }
          }
        }
      }

      if (serverContent['turnComplete'] == true) {
        final transcript = _modelTurnTranscript.toString().trim();
        _modelTurnTranscript.clear();
        if (transcript.isNotEmpty) {
          onTranscript?.call('assistant', transcript);
        }
        if (isActive) {
          _state = GeminiLiveState.listening;
          _notifySafely();
        }
      }
    }

    final toolCall = msg['toolCall'];
    if (toolCall is Map<String, dynamic>) {
      final calls = toolCall['functionCalls'];
      if (calls is List && calls.isNotEmpty) {
        unawaited(_handleToolCalls(calls));
      }
    }
  }

  Future<void> _handleToolCalls(List<dynamic> calls) async {
    final responses = <Map<String, Object?>>[];

    for (final rawCall in calls) {
      if (rawCall is! Map<String, dynamic>) continue;
      final callId = (rawCall['id'] as String? ?? '').trim();
      final name = (rawCall['name'] as String? ?? '').trim();
      final args = rawCall['args'] is Map<String, dynamic>
          ? rawCall['args'] as Map<String, dynamic>
          : const <String, dynamic>{};

      final actionTag = _resolveActionTag(name, args);
      if (actionTag.isEmpty) {
        responses.add(<String, Object?>{
          if (callId.isNotEmpty) 'id': callId,
          'name': name,
          'response': <String, Object?>{
            'status': 'error',
            'detail': 'Ferramenta ou ação vazia.',
          },
        });
        continue;
      }

      // Portão obrigatório de segurança: ActionGate + AuthGate
      final sim = _actionGate.simulate('[ACTION:$actionTag]');
      final decision = _actionGate.evaluatePrivilege(sim, _authGate.level);
      if (!decision.allowed) {
        responses.add(<String, Object?>{
          if (callId.isNotEmpty) 'id': callId,
          'name': name,
          'response': <String, Object?>{
            'status': 'blocked',
            'reason': decision.reason.isEmpty
                ? 'Nível de autenticação insuficiente para ${sim.actionCode}.'
                : decision.reason,
          },
        });
        continue;
      }

      if (decision.requiresConfirmation) {
        final confirmed = onConfirmTool != null
            ? await onConfirmTool!(sim)
            : false;
        if (!confirmed) {
          responses.add(<String, Object?>{
            if (callId.isNotEmpty) 'id': callId,
            'name': name,
            'response': <String, Object?>{
              'status': 'denied',
              'reason': 'Ação recusada pelo operador no ActionGate.',
            },
          });
          continue;
        }
      }

      if (onExecuteActionTag == null) {
        responses.add(<String, Object?>{
          if (callId.isNotEmpty) 'id': callId,
          'name': name,
          'response': <String, Object?>{
            'status': 'unsupported',
            'reason': 'Executor de ferramentas não conectado.',
          },
        });
        continue;
      }

      try {
        final result = await onExecuteActionTag!('[ACTION:$actionTag]');
        responses.add(<String, Object?>{
          if (callId.isNotEmpty) 'id': callId,
          'name': name,
          'response': <String, Object?>{
            'status': 'ok',
            'result': result,
          },
        });
      } catch (e) {
        responses.add(<String, Object?>{
          if (callId.isNotEmpty) 'id': callId,
          'name': name,
          'response': <String, Object?>{
            'status': 'error',
            'detail': '$e',
          },
        });
      }
    }

    if (responses.isNotEmpty && _socket != null) {
      _socket!.sendText(
        jsonEncode(<String, Object?>{
          'toolResponse': <String, Object?>{
            'functionResponses': responses,
          },
        }),
      );
    }
  }

  static String _resolveActionTag(String name, Map<String, dynamic> args) {
    final direct = (args['action_tag'] as String? ?? '').trim();
    if (direct.isNotEmpty) {
      return direct
          .replaceFirst(RegExp(r'^\[ACTION:', caseSensitive: false), '')
          .replaceFirst(RegExp(r'\]$'), '')
          .trim();
    }
    if (name.isEmpty) return '';
    final arg = (args['arg'] ?? args['query'] ?? args['text'] ?? '').toString().trim();
    return arg.isEmpty ? name.toUpperCase() : '${name.toUpperCase()}:$arg';
  }

  void _setError(String message) {
    _lastError = message;
    _state = GeminiLiveState.error;
    _notifySafely();
  }

  void _notifySafely() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _authGate.removeListener(_onAuthChanged);
    unawaited(disconnect());
    super.dispose();
  }
}
