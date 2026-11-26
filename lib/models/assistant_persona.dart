import 'package:flutter/material.dart';

import '../services/speech_text.dart';

/// Estilos de fala configuráveis (inspirados nos jeitos de falar do Desktop v3.0).
enum SpeechStyle {
  direto('direto', 'Direto', 'Respostas curtas, objetivas e sem rodeios.'),
  tecnico('tecnico', 'Técnico', 'Precisão de engenharia, termos exatos e passos claros.'),
  casual('casual', 'Casual', 'Tom descontraído, natural e próximo em português do Brasil.'),
  executivo('executivo', 'Executivo', 'Resumo em tópicos orientados a decisão e prioridade.'),
  didatico('didatico', 'Didático', 'Explica passo a passo com analogias simples e claras.'),
  calmo('calmo', 'Calmo', 'Tom sereno, pausado e ponderado.');

  const SpeechStyle(this.id, this.label, this.promptDirective);
  final String id;
  final String label;
  final String promptDirective;

  static SpeechStyle fromId(String? raw) {
    final norm = (raw ?? '').trim().toLowerCase();
    for (final s in SpeechStyle.values) {
      if (s.id == norm) return s;
    }
    return SpeechStyle.direto;
  }
}

/// Personalidade unificada ligada ao perfil de despertar (`WakeWordProfile`),
/// definindo identidade, tom do system prompt e paleta de tema do aplicativo.
class AssistantPersona {
  const AssistantPersona({
    required this.wakeProfile,
    required this.displayName,
    required this.tagline,
    required this.themeName,
    required this.accentColor,
    required this.accentDark,
    required this.accentBorder,
    required this.promptDirective,
    required this.defaultStyle,
  });

  final WakeWordProfile wakeProfile;
  final String displayName;
  final String tagline;
  final String themeName;
  final Color accentColor;
  final Color accentDark;
  final Color accentBorder;
  final String promptDirective;
  final SpeechStyle defaultStyle;

  static const AssistantPersona ultron = AssistantPersona(
    wakeProfile: WakeWordProfile.ultron,
    displayName: 'U.L.T.R.O.N.',
    tagline: 'Tático, objetivo e preciso',
    themeName: 'Vermelho Carmesim',
    accentColor: Color(0xFFF10D28),
    accentDark: Color(0xFF2A0C12),
    accentBorder: Color(0xFF4A1822),
    promptDirective:
        'Identidade ativa: U.L.T.R.O.N. Tom confiante, tático, conciso e altamente competente.',
    defaultStyle: SpeechStyle.direto,
  );

  static const AssistantPersona jarvis = AssistantPersona(
    wakeProfile: WakeWordProfile.jarvis,
    displayName: 'J.A.R.V.I.S.',
    tagline: 'Refinado, analítico e cortês',
    themeName: 'Azul Cobalto',
    accentColor: Color(0xFF2563EB),
    accentDark: Color(0xFF0C1A36),
    accentBorder: Color(0xFF1D3F80),
    promptDirective:
        'Identidade ativa: J.A.R.V.I.S. Tom cortês, analítico, organizado e sutilmente espirituoso.',
    defaultStyle: SpeechStyle.executivo,
  );

  static const AssistantPersona visao = AssistantPersona(
    wakeProfile: WakeWordProfile.visao,
    displayName: 'VISÃO',
    tagline: 'Calmo, ponderado e reflexivo',
    themeName: 'Amarelo Âmbar',
    accentColor: Color(0xFFF59E0B),
    accentDark: Color(0xFF2E1E06),
    accentBorder: Color(0xFF5C3D0E),
    promptDirective:
        'Identidade ativa: VISÃO. Tom calmo, empático, lógico e equilibrado.',
    defaultStyle: SpeechStyle.calmo,
  );

  static const AssistantPersona edith = AssistantPersona(
    wakeProfile: WakeWordProfile.edith,
    displayName: 'E.D.I.T.H.',
    tagline: 'Ágil, técnica e focada em execução',
    themeName: 'Verde-Água',
    accentColor: Color(0xFF14B8A6),
    accentDark: Color(0xFF082825),
    accentBorder: Color(0xFF11524B),
    promptDirective:
        'Identidade ativa: E.D.I.T.H. Tom ágil, claro, orientado a diagnóstico rápido e execução prática.',
    defaultStyle: SpeechStyle.tecnico,
  );

  static const List<AssistantPersona> all = <AssistantPersona>[
    ultron,
    jarvis,
    visao,
    edith,
  ];

  static AssistantPersona forWakeProfile(WakeWordProfile profile) =>
      switch (profile) {
        WakeWordProfile.ultron => ultron,
        WakeWordProfile.jarvis => jarvis,
        WakeWordProfile.edith => edith,
        WakeWordProfile.visao => visao,
      };
}
