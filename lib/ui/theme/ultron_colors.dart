import 'package:flutter/material.dart';

/// Paleta oficial do U.L.T.R.O.N.
abstract class UltronColors {
  /// Aço escuro — #252A30 — base metálica de containers e superfícies
  static const steel = Color(0xFF252A30);

  /// Prata fria — #BFC7CE — placas, detalhes, ícones e rótulos
  static const silver = Color(0xFFBFC7CE);

  /// Vermelho de alerta — #D92332 — olhos, luzes, reator e alertas críticos
  static const redAlert = Color(0xFFD92332);

  /// Preto — #0B0D10 — sombras, contornos e fundo geral do app
  static const black = Color(0xFF0B0D10);

  /// Azul elétrico — #3E8FBF — brilho tecnológico cibernético e telemetria
  static const electricBlue = Color(0xFF3E8FBF);

  // Derivações ergonômicas para superfícies e legibilidade:
  /// Fundo do app (scaffold)
  static const background = black;

  /// Superfície de cartões e blocos de comandos
  static const surface = steel;

  /// Superfície ligeiramente mais escura para profundidade
  static const surfaceDark = Color(0xFF191D22);

  /// Superfície destacada (hover / ativo)
  static const surfaceHighlight = Color(0xFF2E343C);

  /// Bordas de placas de blindagem
  static const border = Color(0xFF383F47);

  /// Bordas escuras secundárias
  static const borderDark = Color(0xFF1A1E24);

  /// Texto primário de alto contraste (quase branco prateado)
  static const textPrimary = Color(0xFFF2F5F8);

  /// Texto secundário metálico
  static const textSecondary = silver;

  /// Texto atenuado / legendas / hints
  static const textMuted = Color(0xFF737E88);

  /// Variação suave de vermelho para brilho/hotspot
  static const redBright = Color(0xFFFF4554);
}
