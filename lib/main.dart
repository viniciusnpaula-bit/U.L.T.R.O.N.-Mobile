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
          scaffoldBackgroundColor: const Color(0xFF0A0002),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFFF1A24),
            primary: const Color(0xFFFF1A24),
            secondary: const Color(0xFFFF8088),
            surface: const Color(0xFF0E0002),
            brightness: Brightness.dark,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF0A0002),
            foregroundColor: Color(0xFFE2E8F0),
            elevation: 0,
            centerTitle: false,
          ),
          dividerColor: const Color(0xFF2E0306),
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
