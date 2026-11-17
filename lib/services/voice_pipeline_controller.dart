import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/security/auth_gate.dart';
import 'audio_capture_service.dart';
import 'audio_vad_buffer.dart';
import 'stt_service.dart';
import 'text_normalization.dart';
import 'voice_corrections_service.dart';
import 'voice_service.dart';
import 'voice_shortcuts_service.dart';

enum VoicePipelineMode { idle, pushToTalk, continuous }

/// Matches selective barge-in stop/wake phrases with accent normalization.
class BargeInMatcher {
  BargeInMatcher._();

  static const List<String> defaultStopWords = <String>[
    'parar',
    'pare',
    'silencio',
    'cala a boca',
    'chega',
    'cancela',
    'cancelar',
    'ultron',
    'ei ultron',
    'ok ultron',
    'oi ultron',
    'ultram',
    'ultran',
    'ultrom',
    'altron',
    'outron',
  ];

  static const List<String> _stopOnlyWords = <String>[
    'parar',
    'pare',
    'silencio',
    'cala a boca',
    'chega',
    'cancela',
    'cancelar',
  ];

  static const List<String> _wakeWords = <String>[
    'ei ultron',
    'ok ultron',
    'oi ultron',
    'ultron',
    'ultram',
    'ultran',
    'ultrom',
    'altron',
    'outron',
  ];

  static String normalize(String text) =>
      PtBrTextNormalizer.normalizePhrase(text);

  static bool isBargeInPhrase(
    String transcript, {
    List<String> stopWords = defaultStopWords,
  }) {
    final normalized = normalize(transcript);
    if (normalized.isEmpty) return false;
    for (final phrase in stopWords) {
      final target = normalize(phrase);
      if (target.isEmpty) continue;
      if (_containsWholePhrase(normalized, target)) return true;
    }
    return false;
  }

  static bool isStopOnlyPhrase(String transcript) {
    final normalized = normalize(transcript);
    if (normalized.isEmpty) return false;
    return _stopOnlyWords.contains(normalized);
  }

  /// Extracts a trailing command after a wake phrase, or `''` if wake-only.
  /// Returns `null` when no wake phrase is present.
  static String? extractWakeCommand(String transcript) {
    final normalized = normalize(transcript);
    if (normalized.isEmpty) return null;
    for (final wake in _wakeWords) {
      if (normalized == wake) return '';
      if (normalized.startsWith('$wake ')) {
        return normalized.substring(wake.length).trim();
      }
    }
    for (final wake in _wakeWords) {
      if (_containsWholePhrase(normalized, wake)) {
        return transcript.trim();
      }
    }
    return null;
  }

  static bool _containsWholePhrase(String haystack, String needle) {
    if (haystack == needle) return true;
    final pattern = RegExp('(^|\\s)${RegExp.escape(needle)}(\\s|\$)');
    return pattern.hasMatch(haystack);
  }
}

/// Coordinates foreground microphone capture, VAD segmentation, STT, selective
/// TTS barge-in, and AuthGate/lifecycle fail-closed enforcement.
class VoicePipelineController extends ChangeNotifier {
  VoicePipelineController({
    required AuthGate gate,
    required AudioCaptureSource capture,
    required GroqWhisperSttService stt,
    required VoiceService voiceService,
    VadSegmenter? vadSegmenter,
    VoiceCorrectionsService? corrections,
    VoiceShortcutsService? shortcuts,
    Future<bool> Function(VoiceShortcut shortcut)? onConfirmShortcut,
    FutureOr<void> Function(VoiceShortcut shortcut)? onExecuteShortcut,
    FutureOr<void> Function(String transcript)? onTranscript,
    DateTime Function()? now,
    this.sampleRate = 16000,
    this.continuityWindow = const Duration(seconds: 8),
    this.requireWakeWordOutsideWindow = true,
    this.sttPrompt = '',
  })  : _gate = gate,
        _capture = capture,
        _stt = stt,
        _voiceService = voiceService,
        _vad = vadSegmenter ?? VadSegmenter(sampleRate: sampleRate),
        _corrections = corrections,
        _shortcuts = shortcuts,
        _onConfirmShortcut = onConfirmShortcut,
        _onExecuteShortcut = onExecuteShortcut,
        _onTranscript = onTranscript,
        _now = now ?? DateTime.now {
    _gate.addListener(_onGateChanged);
    _previousSpeakComplete = _voiceService.onSpeakComplete;
    _voiceService.onSpeakComplete = _onVoiceSpeakComplete;
  }

  final AuthGate _gate;
  final AudioCaptureSource _capture;
  final GroqWhisperSttService _stt;
  final VoiceService _voiceService;
  final VadSegmenter _vad;
  final VoiceCorrectionsService? _corrections;
  final VoiceShortcutsService? _shortcuts;
  final Future<bool> Function(VoiceShortcut shortcut)? _onConfirmShortcut;
  final FutureOr<void> Function(VoiceShortcut shortcut)? _onExecuteShortcut;
  final FutureOr<void> Function(String transcript)? _onTranscript;
  final DateTime Function() _now;
  final int sampleRate;
  final Duration continuityWindow;
  final bool requireWakeWordOutsideWindow;
  String sttPrompt;

  VoidCallback? _previousSpeakComplete;
  StreamSubscription<Uint8List>? _frameSub;
  Future<void> _frameQueue = Future<void>.value();
  final BytesBuilder _pttBuffer = BytesBuilder(copy: false);

  VoicePipelineMode _mode = VoicePipelineMode.idle;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  bool _isTranscribing = false;
  DateTime? _continuityUntil;
  String? _lastError;
  AudioEffectsReport? _lastEffectsReport;
  bool _disposed = false;

  VoicePipelineMode get mode => _mode;
  bool get isCapturing => _mode != VoicePipelineMode.idle;
  bool get isContinuousEnabled => _mode == VoicePipelineMode.continuous;
  bool get isPushToTalkActive => _mode == VoicePipelineMode.pushToTalk;
  bool get isTranscribing => _isTranscribing;
  String? get lastError => _lastError;
  AudioEffectsReport? get lastEffectsReport => _lastEffectsReport;

  bool get isContinuityWindowActive {
    final until = _continuityUntil;
    return until != null && _now().isBefore(until);
  }

  bool get _canCapture =>
      !_disposed &&
      _gate.isAuthenticated &&
      _lifecycleState == AppLifecycleState.resumed;

  void _onGateChanged() {
    if (!_gate.isAuthenticated) {
      unawaited(stopAll());
    }
  }

  void _onVoiceSpeakComplete() {
    _previousSpeakComplete?.call();
    if (_mode == VoicePipelineMode.continuous && _canCapture) {
      _continuityUntil = _now().add(continuityWindow);
      _notifySafely();
    }
  }

  Future<bool> _ensurePermission() async {
    if (await _capture.hasPermission()) return true;
    return _capture.requestPermission();
  }

  Future<bool> startPushToTalk() async {
    if (!_canCapture) {
      _lastError = 'Captura bloqueada sem sessão autenticada em primeiro plano.';
      _notifySafely();
      return false;
    }

    final permitted = await _ensurePermission();
    if (!permitted || !_canCapture) {
      _lastError = 'Permissão de microfone negada.';
      _notifySafely();
      return false;
    }

    await stopAll();
    if (!_canCapture) return false;

    try {
      _pttBuffer.clear();
      _frameSub = _capture.frames.listen((frame) {
        if (_mode == VoicePipelineMode.pushToTalk && _canCapture) {
          _pttBuffer.add(frame);
        }
      });
      _lastEffectsReport = await _capture.start(sampleRate: sampleRate);
      _mode = VoicePipelineMode.pushToTalk;
      _lastError = null;
      _notifySafely();
      return true;
    } catch (e) {
      await stopAll();
      _lastError = '$e';
      _notifySafely();
      return false;
    }
  }

  Future<String?> stopPushToTalk() async {
    if (_mode != VoicePipelineMode.pushToTalk) return null;
    await _frameSub?.cancel();
    _frameSub = null;
    try {
      await _capture.stop();
    } catch (_) {}

    final pcm = _pttBuffer.takeBytes();
    _mode = VoicePipelineMode.idle;
    _notifySafely();

    if (!_canCapture || pcm.isEmpty) return null;
    return _transcribeAndDispatch(pcm);
  }

  Future<bool> startContinuousListening() async {
    if (!_canCapture) {
      _lastError = 'Escuta contínua bloqueada sem sessão em primeiro plano.';
      _notifySafely();
      return false;
    }
    if (_mode == VoicePipelineMode.continuous) return true;

    final permitted = await _ensurePermission();
    if (!permitted || !_canCapture) {
      _lastError = 'Permissão de microfone negada.';
      _notifySafely();
      return false;
    }

    await stopAll();
    if (!_canCapture) return false;

    try {
      _vad.reset();
      _frameSub = _capture.frames.listen((frame) {
        if (_mode == VoicePipelineMode.continuous && _canCapture) {
          _frameQueue = _frameQueue
              .then((_) => _processContinuousFrame(frame))
              .catchError((_) {});
        }
      });
      _lastEffectsReport = await _capture.start(sampleRate: sampleRate);
      _mode = VoicePipelineMode.continuous;
      _lastError = null;
      _notifySafely();
      return true;
    } catch (e) {
      await stopAll();
      _lastError = '$e';
      _notifySafely();
      return false;
    }
  }

  Future<void> stopContinuousListening() => stopAll();

  void handleLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (state != AppLifecycleState.resumed) {
      unawaited(stopAll());
      unawaited(_voiceService.stop());
    }
  }

  Future<void> stopAll() async {
    final wasActive = _mode != VoicePipelineMode.idle;
    _mode = VoicePipelineMode.idle;
    _continuityUntil = null;
    _pttBuffer.clear();
    _vad.reset();

    await _frameSub?.cancel();
    _frameSub = null;
    try {
      await _capture.stop();
    } catch (_) {}

    if (wasActive) {
      _notifySafely();
    }
  }

  Future<void> _processContinuousFrame(Uint8List frame) async {
    if (_mode != VoicePipelineMode.continuous || !_canCapture) return;
    await for (final segment in _vad.processFrame(frame)) {
      if (_mode != VoicePipelineMode.continuous || !_canCapture) break;
      await _handleContinuousSegment(segment);
    }
  }

  Future<String> _effectivePrompt() async {
    if (sttPrompt.trim().isNotEmpty) return sttPrompt;
    final corrections = _corrections;
    if (corrections == null) return '';
    try {
      return await corrections.buildWhisperPrompt();
    } catch (_) {
      return '';
    }
  }

  Future<void> _dispatchProcessedTranscript(String rawText) async {
    var text = rawText.trim();
    final corrections = _corrections;
    if (corrections != null) {
      try {
        text = await corrections.apply(text);
      } catch (_) {}
    }

    final shortcuts = _shortcuts;
    if (shortcuts != null) {
      VoiceShortcut? matched;
      try {
        matched = await shortcuts.match(text);
      } catch (_) {
        matched = null;
      }
      if (matched != null) {
        final onExecute = _onExecuteShortcut;
        if (onExecute == null) return;
        await shortcuts.execute(
          matched,
          confirm: _onConfirmShortcut ?? (_) async => false,
          run: (s) async => onExecute(s),
        );
        return;
      }
    }

    await _onTranscript?.call(text);
  }

  Future<void> _handleContinuousSegment(Uint8List segment) async {
    _isTranscribing = true;
    _notifySafely();
    try {
      final prompt = await _effectivePrompt();
      final result = await _stt.transcribe(
        segment,
        sampleRate: sampleRate,
        prompt: prompt,
      );
      if (_disposed ||
          _mode != VoicePipelineMode.continuous ||
          !_canCapture) {
        return;
      }
      if (result.error != null) {
        _lastError = result.error;
        return;
      }
      if (!result.hasText) return;

      final text = result.text!.trim();
      if (_voiceService.isSpeaking) {
        if (!BargeInMatcher.isBargeInPhrase(text)) {
          return;
        }
        await _voiceService.stop();
        if (BargeInMatcher.isStopOnlyPhrase(text)) {
          return;
        }
        final wakeCommand = BargeInMatcher.extractWakeCommand(text);
        if (wakeCommand == null) return;
        if (wakeCommand.isEmpty) {
          _continuityUntil = _now().add(continuityWindow);
          return;
        }
        await _dispatchProcessedTranscript(wakeCommand);
        return;
      }

      if (isContinuityWindowActive || !requireWakeWordOutsideWindow) {
        await _dispatchProcessedTranscript(text);
        return;
      }

      final wakeCommand = BargeInMatcher.extractWakeCommand(text);
      if (wakeCommand == null) return;
      if (wakeCommand.isEmpty) {
        _continuityUntil = _now().add(continuityWindow);
        return;
      }
      await _dispatchProcessedTranscript(wakeCommand);
    } finally {
      _isTranscribing = false;
      _notifySafely();
    }
  }

  Future<String?> _transcribeAndDispatch(Uint8List pcm) async {
    _isTranscribing = true;
    _notifySafely();
    try {
      final prompt = await _effectivePrompt();
      final result = await _stt.transcribe(
        pcm,
        sampleRate: sampleRate,
        prompt: prompt,
      );
      if (result.error != null) {
        _lastError = result.error;
        return null;
      }
      if (!result.hasText) return null;
      final rawText = result.text!.trim();
      final corrections = _corrections;
      final corrected = corrections != null
          ? await corrections.apply(rawText).catchError((_) => rawText)
          : rawText;
      await _dispatchProcessedTranscript(rawText);
      return corrected;
    } finally {
      _isTranscribing = false;
      _notifySafely();
    }
  }

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _gate.removeListener(_onGateChanged);
    if (_voiceService.onSpeakComplete == _onVoiceSpeakComplete) {
      _voiceService.onSpeakComplete = _previousSpeakComplete;
    }
    unawaited(_frameSub?.cancel());
    unawaited(_capture.stop());
    super.dispose();
  }
}
