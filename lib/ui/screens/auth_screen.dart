import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final stored = await widget.vault.hasPin;
      if (mounted) setState(() => hasPin = stored);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        hasPin = false;
        error = 'Armazenamento seguro indisponível: $e';
      });
    }
  }

  bool get isSetup => hasPin == false;

  Future<void> _submit() async {
    if (busy) return;
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
  }

  Future<void> _biometric() async {
    if (busy) return;
    setState(() => busy = true);
    final ok = await widget.gate.authenticateBiometric();
    if (!mounted) return;
    setState(() {
      busy = false;
      if (!ok) error = 'Biometria indisponível ou cancelada';
    });
  }

  void _handleKey(int index, String label) {
    if (busy) return;
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

  String get _title => !isSetup
      ? 'PORTÃO DE ACESSO'
      : firstEntry == null
          ? 'CRIE SEU PIN'
          : 'REPITA O PIN';

  String get _hint {
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
              Text(_hint),
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
                        onPressed: busy ? null : () => _handleKey(index, label),
                        style: OutlinedButton.styleFrom(foregroundColor: red),
                        child: Text(label),
                      ),
                    ),
                  );
                }),
              ),
              if (!isSetup)
                TextButton.icon(
                  onPressed: busy ? null : _biometric,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Biometria'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
