import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../models/assistant_persona.dart';
import '../ui/theme/ultron_theme.dart';
import 'ai_provider_service.dart';
import 'conversation_history.dart';
import 'voice_service.dart';

enum BootStage { vault, aiProviders, audio, shader, ready }

/// Executes post-unlock initialization sequentially in strict order:
/// `vault -> aiProviders -> audio -> shader -> ready`.
class StartupCoordinator extends ChangeNotifier {
  StartupCoordinator({
    Future<void> Function()? initVault,
    Future<void> Function()? initAiProviders,
    Future<void> Function()? initAudio,
    Future<FragmentProgram?> Function()? loadShader,
    VoiceService? voiceService,
    AiProviderStore? aiProviderStore,
    this.shaderAssetPath = 'shaders/crimson_core.frag',
  })  : _initVault = initVault,
        _initAiProviders = initAiProviders,
        _initAudio = initAudio,
        _loadShader = loadShader,
        _voiceService = voiceService,
        _aiStore = aiProviderStore;

  final Future<void> Function()? _initVault;
  final Future<void> Function()? _initAiProviders;
  final Future<void> Function()? _initAudio;
  final Future<FragmentProgram?> Function()? _loadShader;
  VoiceService? _voiceService;
  AiProviderStore? _aiStore;
  final String shaderAssetPath;

  BootStage _stage = BootStage.vault;
  String? _error;
  bool _isRunning = false;
  Future<bool>? _inFlight;
  FragmentProgram? _shaderProgram;
  bool _disposed = false;

  BootStage get stage => _stage;
  String? get error => _error;
  bool get isRunning => _isRunning;
  bool get isReady => _stage == BootStage.ready && _error == null;
  FragmentProgram? get shaderProgram => _shaderProgram;

  double get progress => switch (_stage) {
        BootStage.vault => 0.15,
        BootStage.aiProviders => 0.40,
        BootStage.audio => 0.65,
        BootStage.shader => 0.85,
        BootStage.ready => _error == null ? 1.0 : 0.85,
      };

  String get statusLabel => switch (_stage) {
        BootStage.vault => 'Abrindo cofre e histórico local…',
        BootStage.aiProviders => 'Carregando provedores de IA e STT…',
        BootStage.audio => 'Inicializando pipeline de voz…',
        BootStage.shader => 'Compilando núcleo visual crimson…',
        BootStage.ready => 'Sistemas operacionais.',
      };

  /// Starts or joins the sequential boot sequence. Returns `true` if `ready`.
  Future<bool> start() {
    if (isReady) return Future<bool>.value(true);
    final pending = _inFlight;
    if (pending != null) return pending;

    final future = _run();
    _inFlight = future;
    return future;
  }

  Future<bool> _run() async {
    _isRunning = true;
    _error = null;
    _stage = BootStage.vault;
    _notifySafely();

    try {
      await (_initVault != null
          ? _initVault()
          : ConversationHistory.instance.database.then((_) {}));
      if (_disposed) return false;

      _stage = BootStage.aiProviders;
      _notifySafely();
      await (_initAiProviders != null
          ? _initAiProviders()
          : _defaultInitAiProviders());
      if (_disposed) return false;

      _stage = BootStage.audio;
      _notifySafely();
      await (_initAudio != null ? _initAudio() : _defaultInitAudio());
      if (_disposed) return false;

      _stage = BootStage.shader;
      _notifySafely();
      _shaderProgram =
          await (_loadShader != null ? _loadShader() : _defaultLoadShader());
      if (_disposed) return false;

      _stage = BootStage.ready;
      _isRunning = false;
      _notifySafely();
      return true;
    } catch (e) {
      _error = '$e';
      _isRunning = false;
      _notifySafely();
      return false;
    } finally {
      _inFlight = null;
    }
  }

  Future<void> _defaultInitAiProviders() async {
    final store = _aiStore ??= AiProviderStore();
    await store.load();
    await store.resolveSttConfig();
  }

  Future<void> _defaultInitAudio() async {
    try {
      final voice = _voiceService ??= VoiceService();
      await voice.initialize();
      UltronTheme.setPersona(
        AssistantPersona.forWakeProfile(voice.wakeWordProfile),
      );
    } catch (_) {
      // TTS absence must not lock the user out of text/STT controls.
    }
  }

  Future<FragmentProgram?> _defaultLoadShader() async {
    try {
      return await FragmentProgram.fromAsset(shaderAssetPath);
    } catch (_) {
      return null;
    }
  }

  void reset() {
    if (_inFlight != null) return;
    _stage = BootStage.vault;
    _error = null;
    _isRunning = false;
    _shaderProgram = null;
    _notifySafely();
  }

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
