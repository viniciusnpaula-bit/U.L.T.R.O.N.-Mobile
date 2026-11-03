import 'package:flutter/material.dart';

import 'core/security/auth_gate.dart';
import 'core/security/pin_vault.dart';
import 'ui/screens/ai_settings_screen.dart';
import 'ui/screens/auth_screen.dart';
import 'ui/screens/core_screen.dart';

void main() => runApp(UltronApp(gate: AuthGate(), vault: PinVault()));

class UltronApp extends StatelessWidget {
  const UltronApp({super.key, required this.gate, required this.vault});

  final AuthGate gate;
  final PinVault vault;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'U.L.T.R.O.N.',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0A0002),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFE50914),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    home: AnimatedBuilder(
      animation: gate,
      builder: (context, child) => gate.isAuthenticated
          ? CoreScreen(gate: gate, vault: vault)
          : AuthScreen(gate: gate, vault: vault),
    ),
    routes: {'/ai-settings': (_) => const AiSettingsScreen()},
  );
}
