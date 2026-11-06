import 'package:flutter/material.dart';

import 'core/security/auth_gate.dart';
import 'core/security/pin_vault.dart';
import 'ui/screens/ai_settings_screen.dart';
import 'ui/screens/auth_screen.dart';
import 'ui/screens/core_screen.dart';
import 'ui/theme.dart';

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
          scaffoldBackgroundColor: AppColors.background,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.crimson,
            primary: AppColors.crimson,
            secondary: AppColors.accent,
            surface: AppColors.surface,
            brightness: Brightness.dark,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: AppColors.background,
            foregroundColor: AppColors.text,
            elevation: 0,
            centerTitle: false,
          ),
          dividerColor: AppColors.border,
          useMaterial3: true,
          textTheme: const TextTheme(
            bodyLarge: TextStyle(fontSize: 16, color: AppColors.text),
            bodyMedium: TextStyle(fontSize: 14, color: AppColors.text),
            bodySmall: TextStyle(fontSize: 12, color: AppColors.muted),
            labelLarge: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
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
