import 'package:flutter/material.dart';

import '../../core/security/auth_gate.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.gate,
    required this.onSuccess,
    required this.verifyPin,
  });

  final AuthGate gate;
  final VoidCallback onSuccess;
  final Future<bool> Function(String) verifyPin;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  static const red = Color(0xFFE50914);
  String pin = '';
  String? error;

  Future<void> biometric() async {
    if (await widget.gate.authenticateBiometric() && mounted) {
      widget.onSuccess();
    }
  }

  Future<void> submit() async {
    final accepted = await widget.gate.authenticatePin(pin, widget.verifyPin);
    if (!mounted) return;
    if (accepted) {
      widget.onSuccess();
    } else {
      setState(() => error = 'PIN inválido');
    }
  }

  void pressKey(int index) {
    if (index == 11) {
      submit();
      return;
    }
    setState(() {
      if (index == 9) {
        if (pin.isNotEmpty) pin = pin.substring(0, pin.length - 1);
      } else if (pin.length < 8) {
        pin += index == 10 ? '0' : (index + 1).toString();
      }
      error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
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
              const Text(
                'PORTÃO DE ACESSO',
                style: TextStyle(color: Color(0xFFFFA0A0), letterSpacing: 4),
              ),
              Text('PIN • ${List.filled(pin.length, '●').join(' ')}'),
              Text(error ?? 'Autenticação requerida'),
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
                        onPressed: () => pressKey(index),
                        style: OutlinedButton.styleFrom(foregroundColor: red),
                        child: Text(label),
                      ),
                    ),
                  );
                }),
              ),
              TextButton.icon(
                onPressed: biometric,
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
