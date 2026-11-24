import 'package:flutter/material.dart';

import 'core/security/auth_gate.dart';
import 'core/security/pin_vault.dart';
import 'services/audio_capture_service.dart';
import 'services/startup_coordinator.dart';
import 'services/stt_service.dart';
import 'services/voice_service.dart';
import 'ui/screens/ai_settings_screen.dart';
import 'ui/screens/auth_screen.dart';
import 'ui/screens/boot_loading_screen.dart';
import 'ui/screens/core_screen.dart';
import 'ui/theme/ultron_theme.dart';

void main() => runApp(UltronApp(gate: AuthGate(), vault: PinVault()));

class UltronApp extends StatefulWidget {
  const UltronApp({
    super.key,
    required this.gate,
    required this.vault,
    this.voiceService,
    this.startupCoordinator,
    this.audioCapture,
    this.sttService,
  });

  final AuthGate gate;
  final PinVault vault;
  final VoiceService? voiceService;
  final StartupCoordinator? startupCoordinator;
  final AudioCaptureSource? audioCapture;
  final GroqWhisperSttService? sttService;

  @override
  State<UltronApp> createState() => _UltronAppState();
}

class _UltronAppState extends State<UltronApp> {
  late final VoiceService _voiceService;
  late final StartupCoordinator _coordinator;
  late final bool _ownsCoordinator;

  @override
  void initState() {
    super.initState();
    _voiceService = widget.voiceService ?? VoiceService();
    _ownsCoordinator = widget.startupCoordinator == null;
    _coordinator = widget.startupCoordinator ??
        StartupCoordinator(voiceService: _voiceService);
    widget.gate.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    if (!widget.gate.isAuthenticated) {
      _coordinator.reset();
    }
  }

  @override
  void dispose() {
    widget.gate.removeListener(_onAuthChanged);
    if (_ownsCoordinator) {
      _coordinator.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'U.L.T.R.O.N.',
        debugShowCheckedModeBanner: false,
        theme: UltronTheme.dark(),
        home: AnimatedBuilder(
          animation: Listenable.merge([widget.gate, _coordinator]),
          builder: (context, child) {
            if (!widget.gate.isAuthenticated) {
              return AuthScreen(gate: widget.gate, vault: widget.vault);
            }
            if (!_coordinator.isReady) {
              return BootLoadingScreen(coordinator: _coordinator);
            }
            return CoreScreen(
              gate: widget.gate,
              vault: widget.vault,
              voiceService: _voiceService,
              captureSource: widget.audioCapture,
              sttService: widget.sttService,
              shaderProgram: _coordinator.shaderProgram,
              announceOnline: true,
            );
          },
        ),
        routes: {'/ai-settings': (_) => const AiSettingsScreen()},
      );
}
