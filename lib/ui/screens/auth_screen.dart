import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/security/auth_gate.dart';
import '../../core/security/pin_vault.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.gate, required this.vault});

  final AuthGate gate;
  final PinVault vault;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  static const red = Color(0xFFE50914);

  String pin = '';
  String? firstEntry;
  String? error;
  bool? hasPin;
  bool busy = false;
  Duration lockLeft = Duration.zero;
  List<BiometricType> biometrics = const [];
  Timer? _lockTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final stored = await widget.vault.hasPin;
      final left = await widget.vault.lockRemaining();
      final available = await widget.gate.biometrics();
      if (!mounted) return;
      setState(() {
        hasPin = stored;
        lockLeft = left;
        biometrics = available;
      });
      _startLockTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        hasPin = false;
        error = 'Armazenamento seguro indisponível: $e';
      });
    }
  }

  /// Counts the wait down on screen; the vault enforces it either way.
  void _startLockTimer() {
    _lockTimer?.cancel();
    if (lockLeft <= Duration.zero) return;
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final left = await widget.vault.lockRemaining();
      if (!mounted) return;
      setState(() {
        lockLeft = left;
        if (left <= Duration.zero) error = null;
      });
      if (left <= Duration.zero) _lockTimer?.cancel();
    });
  }

  Future<void> _refreshLock() async {
    final left = await widget.vault.lockRemaining();
    if (!mounted) return;
    setState(() => lockLeft = left);
    _startLockTimer();
  }

  bool get isSetup => hasPin == false;
  bool get blocked => busy || lockLeft > Duration.zero;

  Future<void> _submit() async {
    if (blocked) return;
    if (isSetup && firstEntry == null) {
      if (pin.length < 4) {
        setState(() => error = 'Use de 4 a 8 dígitos');
        return;
      }
      setState(() {
        firstEntry = pin;
        pin = '';
        error = null;
      });
      return;
    }
    if (pin.length < 4) {
      setState(() => error = 'Use de 4 a 8 dígitos');
      return;
    }
    if (isSetup) {
      if (pin != firstEntry) {
        setState(() {
          firstEntry = null;
          pin = '';
          error = 'Os PINs não coincidem. Tente de novo.';
        });
        return;
      }
      setState(() => busy = true);
      await widget.vault.setPin(pin);
      final ok = await widget.gate.authenticatePin(pin, widget.vault.verify);
      if (!mounted) return;
      setState(() => busy = false);
      if (!ok) setState(() => error = 'Não foi possível salvar o PIN');
      return;
    }
    setState(() => busy = true);
    final ok = await widget.gate.authenticatePin(pin, widget.vault.verify);
    if (!mounted) return;
    setState(() {
      busy = false;
      pin = '';
      if (!ok) error = 'PIN inválido';
    });
    if (!ok) await _refreshLock();
  }

  Future<void> _biometric() async {
    if (busy) return;
    setState(() => busy = true);
    final ok = await widget.gate.authenticateBiometric();
    if (!mounted) return;
    setState(() {
      busy = false;
      if (!ok) {
        error = 'Sensor indisponível, cancelado ou bloqueado pelo sistema. Use o PIN.';
      }
    });
  }

  void _handleKey(int index, String label) {
    if (blocked) return;
    if (index == 11) {
      _submit();
      return;
    }
    setState(() {
      if (index == 9) {
        if (pin.isNotEmpty) pin = pin.substring(0, pin.length - 1);
      } else if (pin.length < 8) {
        pin += label;
      }
      error = null;
    });
  }

  String get _biometricLabel {
    if (biometrics.contains(BiometricType.face)) return 'Reconhecimento facial';
    if (biometrics.contains(BiometricType.fingerprint)) return 'Impressão digital';
    if (biometrics.contains(BiometricType.iris)) return 'Íris';
    // Android reports strong/weak without naming the sensor; BiometricPrompt
    // uses whichever biometric the user enrolled, face included.
    return 'Face ou digital';
  }

  IconData get _biometricIcon => biometrics.contains(BiometricType.face)
      ? Icons.face_retouching_natural
      : Icons.fingerprint;

  String get _title => !isSetup
      ? 'PORTÃO DE ACESSO'
      : firstEntry == null
          ? 'CRIE SEU PIN'
          : 'REPITA O PIN';

  static String _formatWait(Duration wait) {
    final seconds = wait.inSeconds;
    if (seconds < 60) return '${seconds}s';
    return '${wait.inMinutes}m${(seconds % 60).toString().padLeft(2, '0')}s';
  }

  String get _hint {
    if (lockLeft > Duration.zero) {
      return 'Muitas tentativas. Aguarde ${_formatWait(lockLeft)}';
    }
    if (error != null) return error!;
    if (isSetup) {
      return firstEntry == null
          ? 'PIN de 4 a 8 dígitos'
          : 'Digite o mesmo PIN';
    }
    return 'Autenticação requerida';
  }

  @override
  Widget build(BuildContext context) {
    if (hasPin == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0002),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0A0002),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.radar, size: 72, color: red),
              const SizedBox(height: 12),
              Text(
                _title,
                style: const TextStyle(
                  color: Color(0xFFFFA0A0),
                  letterSpacing: 4,
                ),
              ),
              Text('PIN • ${List.filled(pin.length, '●').join(' ')}'),
              Text(_hint, textAlign: TextAlign.center),
              if (busy) const LinearProgressIndicator(),
              Wrap(
                alignment: WrapAlignment.center,
                children: List.generate(12, (index) {
                  final label = switch (index) {
                    9 => '⌫',
                    10 => '0',
                    11 => '✓',
                    _ => (index + 1).toString(),
                  };
                  return SizedBox(
                    width: 76,
                    height: 64,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: OutlinedButton(
                        onPressed: blocked ? null : () => _handleKey(index, label),
                        style: OutlinedButton.styleFrom(foregroundColor: red),
                        child: Text(label),
                      ),
                    ),
                  );
                }),
              ),
              if (!isSetup && biometrics.isNotEmpty)
                TextButton.icon(
                  onPressed: busy ? null : _biometric,
                  icon: Icon(_biometricIcon),
                  label: Text(_biometricLabel),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
