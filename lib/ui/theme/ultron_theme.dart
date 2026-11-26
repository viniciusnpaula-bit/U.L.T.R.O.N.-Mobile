import 'package:flutter/material.dart';

import '../../models/assistant_persona.dart';

/// Tokens visuais do U.L.T.R.O.N. Mobile (AMOLED com destaque dinâmico por persona).
abstract final class UltronColors {
  static const Color bg = Color(0xFF080808);
  static const Color surface = Color(0xFF111114);
  static const Color surfaceElevated = Color(0xFF18181D);
  static const Color crimson = Color(0xFFF10D28);
  static const Color crimsonDark = Color(0xFF2A0C12);
  static const Color crimsonBorder = Color(0xFF4A1822);
  static const Color border = Color(0xFF222228);
  static const Color borderSubtle = Color(0xFF1A1A20);
  static const Color textPrimary = Color(0xFFEEEEEE);
  static const Color textSecondary = Color(0xFF9A9AA3);
  static const Color textMuted = Color(0xFF686872);
  static const Color positive = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
}

abstract final class UltronTheme {
  static final ValueNotifier<AssistantPersona> personaNotifier =
      ValueNotifier<AssistantPersona>(AssistantPersona.ultron);

  static void setPersona(AssistantPersona persona) {
    if (personaNotifier.value.wakeProfile != persona.wakeProfile) {
      personaNotifier.value = persona;
    }
  }

  static Color accentOf(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  static Color accentDarkOf(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    for (final p in AssistantPersona.all) {
      if (p.accentColor == primary) return p.accentDark;
    }
    return Color.lerp(primary, UltronColors.bg, 0.84)!;
  }

  static Color accentBorderOf(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    for (final p in AssistantPersona.all) {
      if (p.accentColor == primary) return p.accentBorder;
    }
    return Color.lerp(primary, UltronColors.bg, 0.65)!;
  }

  static Color onAccentFor(Color accent) =>
      accent.computeLuminance() > 0.42
          ? const Color(0xFF0B0B0D)
          : UltronColors.textPrimary;

  static const TextStyle mono = TextStyle(
    fontFamily: 'monospace',
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static ThemeData dark({AssistantPersona persona = AssistantPersona.ultron}) {
    final accent = persona.accentColor;
    final onAccent = onAccentFor(accent);
    final colorScheme = ColorScheme.dark(
      primary: accent,
      onPrimary: onAccent,
      secondary: accent,
      onSecondary: onAccent,
      surface: UltronColors.surface,
      onSurface: UltronColors.textPrimary,
      error: UltronColors.crimson,
      onError: UltronColors.textPrimary,
      outline: UltronColors.border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: UltronColors.bg,
      colorScheme: colorScheme,
      canvasColor: UltronColors.surface,
      dividerColor: UltronColors.borderSubtle,
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return UltronColors.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return persona.accentDark;
          return UltronColors.surfaceElevated;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return persona.accentBorder;
          }
          return UltronColors.border;
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
      appBarTheme: const AppBarTheme(
        backgroundColor: UltronColors.bg,
        foregroundColor: UltronColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: UltronColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: UltronColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: UltronColors.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: UltronColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: UltronColors.border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: UltronColors.surfaceElevated,
        contentTextStyle: const TextStyle(
          color: UltronColors.textPrimary,
          fontSize: 13,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: UltronColors.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: UltronColors.textPrimary,
          side: const BorderSide(color: UltronColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: UltronColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: UltronColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: UltronColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent),
        ),
        hintStyle: const TextStyle(
          color: UltronColors.textMuted,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// Rótulo discreto de grupo dentro de uma seção.
class UltronSectionLabel extends StatelessWidget {
  const UltronSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: UltronColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

/// Superfície padrão limpa, sem excesso de brilho ou gradientes decorativos.
class UltronSurfaceCard extends StatelessWidget {
  const UltronSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.highlighted = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: UltronColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted ? UltronColors.border : UltronColors.borderSubtle,
        ),
      ),
      child: child,
    );
  }
}

/// Linha de ação limpa com ícone vetorial outline e navegação clara.
class UltronActionTile extends StatelessWidget {
  const UltronActionTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.accentColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final fg = accentColor ?? UltronColors.textPrimary;
    return Material(
      color: UltronColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: UltronColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: UltronColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: UltronColors.borderSubtle),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: accentColor ?? UltronColors.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: fg,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: UltronColors.textSecondary,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ] else if (onTap != null) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: UltronColors.textMuted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Emblema geométrico minimalista do U.L.T.R.O.N.
class UltronMark extends StatelessWidget {
  const UltronMark({super.key, this.size = 24, this.accentColor});

  final double size;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? UltronTheme.accentOf(context);
    final accentDark = accentColor == null
        ? UltronTheme.accentDarkOf(context)
        : Color.lerp(accent, UltronColors.bg, 0.84)!;
    return CustomPaint(
      size: Size.square(size),
      painter: _UltronMarkPainter(accent: accent, accentDark: accentDark),
    );
  }
}

class _UltronMarkPainter extends CustomPainter {
  const _UltronMarkPainter({required this.accent, required this.accentDark});

  final Color accent;
  final Color accentDark;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = size.center(Offset.zero);
    final r = s * 0.44;
    final hex = Path();
    for (var i = 0; i < 6; i++) {
      final angle = (i * 60 - 90) * 3.141592653589793 / 180.0;
      final pt = Offset(
        center.dx + r * _cos(angle),
        center.dy + r * _sin(angle),
      );
      if (i == 0) {
        hex.moveTo(pt.dx, pt.dy);
      } else {
        hex.lineTo(pt.dx, pt.dy);
      }
    }
    hex.close();

    canvas.drawPath(
      hex,
      Paint()
        ..color = accentDark
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      hex,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.08,
    );
    canvas.drawCircle(
      center,
      s * 0.14,
      Paint()..color = accent,
    );
  }

  static double _cos(double rad) {
    // Simple exact values for hexagon vertices (0, 60, 120, 180, 240, 300 deg - 90 deg)
    final norm = ((rad * 180 / 3.141592653589793).round() % 360 + 360) % 360;
    return switch (norm) {
      270 => 0.0,
      330 => 0.8660254,
      30 => 0.8660254,
      90 => 0.0,
      150 => -0.8660254,
      210 => -0.8660254,
      _ => 0.0,
    };
  }

  static double _sin(double rad) {
    final norm = ((rad * 180 / 3.141592653589793).round() % 360 + 360) % 360;
    return switch (norm) {
      270 => -1.0,
      330 => -0.5,
      30 => 0.5,
      90 => 1.0,
      150 => 0.5,
      210 => -0.5,
      _ => 0.0,
    };
  }

  @override
  bool shouldRepaint(covariant _UltronMarkPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.accentDark != accentDark;
}
