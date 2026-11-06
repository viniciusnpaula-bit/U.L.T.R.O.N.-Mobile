import 'package:flutter/material.dart';

/// Paleta e escala tipográfica únicas do app.
/// Antes cada tela redefinia os mesmos hex; agora a fonte é uma só.
abstract final class AppColors {
  static const background = Color(0xFF19171B);

  /// Card/painel. Precisa se separar do fundo (#19171B) — antes era #2B0307.
  static const surface = Color(0xFF1F1C21);

  /// Borda visível de card. Antes #51080D tinha 1.18:1 contra o fundo.
  static const border = Color(0xFF3A3238);

  /// Preenchimento (botões, realces). Nunca use como cor de texto.
  static const crimson = Color(0xFF75020F);

  /// Acento para texto e ícones sobre fundo escuro (6.66:1).
  static const accent = Color(0xFFFF707C);

  static const text = Color(0xFFF0E6E7);

  /// Texto secundário (6.34:1).
  static const muted = Color(0xFFA89698);

  /// Texto terciário. Antes #635355 tinha 2.46:1 e reprovava em contraste.
  static const subtle = Color(0xFF9C8B8E);
}
