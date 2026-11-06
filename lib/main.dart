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
          fontFamily: 'monospace',
          scaffoldBackgroundColor: const Color(0xFF19171B),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF75020F),
            primary: const Color(0xFF75020F),
            secondary: const Color(0xFFFF707C),
            surface: const Color(0xFF2B0307),
            brightness: Brightness.dark,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF19171B),
            foregroundColor: Color(0xFFF0E6E7),
            elevation: 0,
            centerTitle: false,
          ),
          dividerColor: const Color(0xFF51080D),
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
