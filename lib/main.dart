import 'package:flutter/material.dart';

import 'core/security/auth_gate.dart';
import 'core/security/pin_vault.dart';
import 'ui/screens/ai_settings_screen.dart';
import 'ui/screens/auth_screen.dart';
import 'ui/screens/core_screen.dart';
import 'ui/theme/ultron_colors.dart';

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
          scaffoldBackgroundColor: UltronColors.background,
          colorScheme: ColorScheme.fromSeed(
            seedColor: UltronColors.redAlert,
            primary: UltronColors.redAlert,
            secondary: UltronColors.electricBlue,
            surface: UltronColors.surface,
            brightness: Brightness.dark,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: UltronColors.black,
            foregroundColor: UltronColors.textPrimary,
            elevation: 0,
            centerTitle: false,
          ),
          dividerColor: UltronColors.border,
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
