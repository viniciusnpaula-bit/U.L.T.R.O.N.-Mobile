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

enum VoicePipelineMode { idle, pushToTalk, singleTurn, continuous }

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
    'jarvis',
    'ei jarvis',
    'ok jarvis',
    'oi jarvis',
    'jarves',
    'edith',
    'ei edith',
    'ok edith',
    'oi edith',
    'edite',
    'visao',
    'ei visao',
    'ok visao',
    'oi visao',
    'vizao',
    'vision',
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
    'ei jarvis',
    'ok jarvis',
    'oi jarvis',
    'jarvis',
    'jarves',
    'ei edith',
    'ok edith',
    'oi edith',
    'edith',
    'edite',
    'ei visao',
    'ok visao',
    'oi visao',
    'visao',
    'vizao',
    'vision',
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
    ValueChanged<double>? onRmsChanged,
    DateTime Function()? now,
    this.sampleRate = 16000,
    this.continuityWindow = const Duration(seconds: 8),
    this.singleTurnIdleTimeout = const Duration(milliseconds: 7500),
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
        _onRmsChanged = onRmsChanged,
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
  final ValueChanged<double>? _onRmsChanged;
  final DateTime Function() _now;
  final int sampleRate;
  final Duration continuityWindow;
  final Duration singleTurnIdleTimeout;
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
  int _captureOpToken = 0;
  int _sessionGeneration = 0;
  bool _pttReleaseRequested = false;
  int _singleTurnBufferedBytes = 0;
  Timer? _singleTurnIdleTimer;

  VoicePipelineMode get mode => _mode;
  bool get isCapturing => _mode != VoicePipelineMode.idle;
  bool get isContinuousEnabled => _mode == VoicePipelineMode.continuous;
  bool get isPushToTalkActive => _mode == VoicePipelineMode.pushToTalk;
  bool get isSingleTurnActive => _mode == VoicePipelineMode.singleTurn;
  bool get isTranscribing => _isTranscribing;
  String? get lastError => _lastError;
  AudioEffectsReport? get lastEffectsReport => _lastEffectsReport;
  VadSegmenter get vadSegmenter => _vad;

  /// Updates the live Auto-VAD sensitivity profile and optional silence hangover.
  void updateVadConfig(VadProfile profile, {Duration? silenceHangover}) {
    _vad.applyProfile(profile, silenceHangover: silenceHangover);
    _notifySafely();
  }

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
      _lastError =
          'Captura bloqueada sem sessão autenticada em primeiro plano.';
      _notifySafely();
      return false;
    }

    _pttReleaseRequested = false;
    final permitted = await _ensurePermission();
    if (!permitted) {
      _lastError = 'Permissão de microfone negada.';
      _notifySafely();
      return false;
    }
    if (!_canCapture || _pttReleaseRequested) {
      return false;
    }

    await stopAll();
    if (!_canCapture || _pttReleaseRequested) return false;
    final token = ++_captureOpToken;

    try {
      _pttBuffer.clear();
      _frameSub = _capture.frames.listen((frame) {
        if (_mode == VoicePipelineMode.pushToTalk && _canCapture) {
          _pttBuffer.add(frame);
          _emitRms(frame);
        }
      });
      final report = await _capture.start(sampleRate: sampleRate);
      if (_disposed ||
          !_canCapture ||
          token != _captureOpToken ||
          _pttReleaseRequested) {
        await _frameSub?.cancel();
        _frameSub = null;
        try {
          await _capture.stop();
        } catch (_) {}
        _pttBuffer.clear();
        _mode = VoicePipelineMode.idle;
        _notifySafely();
        return false;
      }
      _lastEffectsReport = report;
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
    if (_mode != VoicePipelineMode.pushToTalk) {
      _pttReleaseRequested = true;
      return null;
    }
    _mode = VoicePipelineMode.idle;
    _captureOpToken++;
    await _frameSub?.cancel();
    _frameSub = null;
    try {
      await _capture.stop();
    } catch (_) {}

    final pcm = _pttBuffer.takeBytes();
    _onRmsChanged?.call(0.0);
    _notifySafely();

    if (!_canCapture || pcm.isEmpty) return null;
    return _transcribeAndDispatch(pcm);
  }

  /// Captura um comando de voz único pelo microfone nativo (`AudioRecord`),
  /// finalizando automaticamente no silêncio (VAD) ou ao chamar
  /// [stopSingleTurnListening]. Nunca aciona reconhecimento do Google.
  Future<bool> startSingleTurnListening() async {
    if (!_canCapture) {
      _lastError =
          'Captura bloqueada sem sessão autenticada em primeiro plano.';
      _notifySafely();
      return false;
    }
    if (_mode == VoicePipelineMode.singleTurn) return true;

    final permitted = await _ensurePermission();
    if (!permitted) {
      _lastError = 'Permissão de microfone negada.';
      _notifySafely();
      return false;
    }
    if (!_canCapture) return false;

    await stopAll();
    if (!_canCapture) return false;
    final token = ++_captureOpToken;

    try {
      _pttBuffer.clear();
      _singleTurnBufferedBytes = 0;
      _vad.reset();
      _frameSub = _capture.frames.listen((frame) {
        if (_mode == VoicePipelineMode.singleTurn &&
            _canCapture &&
            token == _captureOpToken) {
          _pttBuffer.add(frame);
          _singleTurnBufferedBytes += frame.length;
          _emitRms(frame);
          _frameQueue = _frameQueue
              .then((_) => _processSingleTurnFrame(frame, token))
              .catchError((_) {});
        }
      });
      final report = await _capture.start(sampleRate: sampleRate);
      if (_disposed || !_canCapture || token != _captureOpToken) {
        await _frameSub?.cancel();
        _frameSub = null;
        try {
          await _capture.stop();
        } catch (_) {}
        _pttBuffer.clear();
        _singleTurnBufferedBytes = 0;
        _vad.reset();
        _mode = VoicePipelineMode.idle;
        _onRmsChanged?.call(0.0);
        _notifySafely();
        return false;
      }
      _lastEffectsReport = report;
      _mode = VoicePipelineMode.singleTurn;
      _lastError = null;
      _singleTurnIdleTimer?.cancel();
      if (singleTurnIdleTimeout > Duration.zero) {
        _singleTurnIdleTimer = Timer(singleTurnIdleTimeout, () {
          if (!_disposed &&
              _mode == VoicePipelineMode.singleTurn &&
              token == _captureOpToken &&
              !_vad.isInSpeech) {
            unawaited(stopAll());
          }
        });
      }
      _notifySafely();
      return true;
    } catch (e) {
      await stopAll();
      _lastError = '$e';
      _notifySafely();
      return false;
    }
  }

  Future<String?> stopSingleTurnListening() async {
    if (_mode != VoicePipelineMode.singleTurn) return null;
    final pcm = await _drainSingleTurnCapture();
    if (!_canCapture || pcm.isEmpty) return null;
    return _transcribeAndDispatch(pcm);
  }

  Future<Uint8List> _drainSingleTurnCapture() async {
    _singleTurnIdleTimer?.cancel();
    _singleTurnIdleTimer = null;
    _mode = VoicePipelineMode.idle;
    _captureOpToken++;
    _vad.reset();
    await _frameSub?.cancel();
    _frameSub = null;
    try {
      await _capture.stop();
    } catch (_) {}
    final pcm = _pttBuffer.takeBytes();
    _singleTurnBufferedBytes = 0;
    _onRmsChanged?.call(0.0);
    _notifySafely();
    return pcm;
  }

  Future<void> _processSingleTurnFrame(Uint8List frame, int token) async {
    if (_mode != VoicePipelineMode.singleTurn ||
        !_canCapture ||
        token != _captureOpToken) {
      return;
    }
    await for (final segment in _vad.processFrame(frame)) {
      if (_mode != VoicePipelineMode.singleTurn ||
          !_canCapture ||
          token != _captureOpToken) {
        break;
      }
      await _drainSingleTurnCapture();
      if (_canCapture && segment.isNotEmpty) {
        await _transcribeAndDispatch(segment);
      }
      return;
    }
    if (_vad.isInSpeech && _singleTurnIdleTimer != null) {
      _singleTurnIdleTimer?.cancel();
      _singleTurnIdleTimer = null;
    }
    final maxBytes = sampleRate * 2 * 25;
    if (_mode == VoicePipelineMode.singleTurn &&
        token == _captureOpToken &&
        _singleTurnBufferedBytes >= maxBytes) {
      final pcm = await _drainSingleTurnCapture();
      if (_canCapture && pcm.isNotEmpty) {
        await _transcribeAndDispatch(pcm);
      }
    }
  }

  Future<bool> startContinuousListening() async {
    if (!_canCapture) {
      _lastError = 'Escuta contínua bloqueada sem sessão em primeiro plano.';
      _notifySafely();
      return false;
    }
    if (_mode == VoicePipelineMode.continuous) return true;

    final permitted = await _ensurePermission();
    if (!permitted) {
      _lastError = 'Permissão de microfone negada.';
      _notifySafely();
      return false;
    }
    if (!_canCapture) {
      return false;
    }

    await stopAll();
    if (!_canCapture) return false;
    final token = ++_captureOpToken;

    try {
      _vad.reset();
      _frameSub = _capture.frames.listen((frame) {
        if (_mode == VoicePipelineMode.continuous && _canCapture) {
          _emitRms(frame);
          _frameQueue = _frameQueue
              .then((_) => _processContinuousFrame(frame))
              .catchError((_) {});
        }
      });
      final report = await _capture.start(sampleRate: sampleRate);
      if (_disposed || !_canCapture || token != _captureOpToken) {
        await _frameSub?.cancel();
        _frameSub = null;
        try {
          await _capture.stop();
        } catch (_) {}
        _vad.reset();
        _mode = VoicePipelineMode.idle;
        _notifySafely();
        return false;
      }
      _lastEffectsReport = report;
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

  void handleLifecycleState(
    AppLifecycleState state, {
    bool stopTtsOnBackground = false,
  }) {
    _lifecycleState = state;
    if (state != AppLifecycleState.resumed) {
      unawaited(stopAll());
      if (stopTtsOnBackground) {
        unawaited(_voiceService.stop());
      }
    }
  }

  Future<void> stopAll() async {
    final wasActive = _mode != VoicePipelineMode.idle;
    _singleTurnIdleTimer?.cancel();
    _singleTurnIdleTimer = null;
    _captureOpToken++;
    _sessionGeneration++;
    _pttReleaseRequested = false;
    _mode = VoicePipelineMode.idle;
    _continuityUntil = null;
    _pttBuffer.clear();
    _singleTurnBufferedBytes = 0;
    _vad.reset();
    _onRmsChanged?.call(0.0);

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

  Future<void> _dispatchProcessedTranscript(
    String rawText, {
    bool applyCorrections = true,
  }) async {
    var text = rawText.trim();
    final corrections = _corrections;
    if (applyCorrections && corrections != null) {
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
    final sessionGen = _sessionGeneration;
    _isTranscribing = true;
    _notifySafely();
    try {
      final prompt = await _effectivePrompt();
      final sttSw = Stopwatch()..start();
      final result = await _stt.transcribe(
        segment,
        sampleRate: sampleRate,
        prompt: prompt,
      );
      sttSw.stop();
      AcousticDiagnosticsTracker.instance
          .recordSttLatency(sttSw.elapsedMilliseconds);
      debugPrint(
        '[ULTRON][LATENCY] STT=${sttSw.elapsedMilliseconds}ms '
        'bytes=${segment.length} ok=${result.hasText}',
      );
      if (_disposed ||
          sessionGen != _sessionGeneration ||
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
      final sttSw = Stopwatch()..start();
      final result = await _stt.transcribe(
        pcm,
        sampleRate: sampleRate,
        prompt: prompt,
      );
      sttSw.stop();
      AcousticDiagnosticsTracker.instance
          .recordSttLatency(sttSw.elapsedMilliseconds);
      debugPrint(
        '[ULTRON][LATENCY] STT=${sttSw.elapsedMilliseconds}ms '
        'bytes=${pcm.length} ok=${result.hasText}',
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
      await _dispatchProcessedTranscript(corrected, applyCorrections: false);
      return corrected;
    } finally {
      _isTranscribing = false;
      _notifySafely();
    }
  }

  void _emitRms(Uint8List frame) {
    if (frame.isEmpty) return;
    final rms = PcmEnergy.dcRemovedRmsInt16(frame);
    if (_vad.adaptiveNoiseFloor) {
      AcousticDiagnosticsTracker.instance.recordNoiseFloorDb(_vad.noiseFloorDb);
    } else {
      AcousticDiagnosticsTracker.instance.recordPcmNoiseFrame(frame);
    }
    final cb = _onRmsChanged;
    if (cb == null) return;
    final normalized = (rms / 2500.0).clamp(0.0, 1.0);
    cb(normalized);
  }

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _singleTurnIdleTimer?.cancel();
    _singleTurnIdleTimer = null;
    _gate.removeListener(_onGateChanged);
    if (_voiceService.onSpeakComplete == _onVoiceSpeakComplete) {
      _voiceService.onSpeakComplete = _previousSpeakComplete;
    }
    unawaited(_frameSub?.cancel());
    unawaited(_capture.stop());
    super.dispose();
  }
}
