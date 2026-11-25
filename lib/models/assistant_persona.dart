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
/// definindo identidade, tom do system prompt e cor de destaque do CoreOrb.
class AssistantPersona {
  const AssistantPersona({
    required this.wakeProfile,
    required this.displayName,
    required this.tagline,
    required this.accentColor,
    required this.promptDirective,
    required this.defaultStyle,
  });

  final WakeWordProfile wakeProfile;
  final String displayName;
  final String tagline;
  final Color accentColor;
  final String promptDirective;
  final SpeechStyle defaultStyle;

  static const AssistantPersona ultron = AssistantPersona(
    wakeProfile: WakeWordProfile.ultron,
    displayName: 'U.L.T.R.O.N.',
    tagline: 'Tático, objetivo e preciso',
    accentColor: Color(0xFFF10D28),
    promptDirective:
        'Identidade ativa: U.L.T.R.O.N. Tom confiante, tático, conciso e altamente competente.',
    defaultStyle: SpeechStyle.direto,
  );

  static const AssistantPersona jarvis = AssistantPersona(
    wakeProfile: WakeWordProfile.jarvis,
    displayName: 'J.A.R.V.I.S.',
    tagline: 'Refinado, analítico e cortês',
    accentColor: Color(0xFFF59E0B),
    promptDirective:
        'Identidade ativa: J.A.R.V.I.S. Tom cortês, analítico, organizado e sutilmente espirituoso.',
    defaultStyle: SpeechStyle.executivo,
  );

  static const AssistantPersona edith = AssistantPersona(
    wakeProfile: WakeWordProfile.edith,
    displayName: 'E.D.I.T.H.',
    tagline: 'Ágil, técnica e focada em execução',
    accentColor: Color(0xFF38BDF8),
    promptDirective:
        'Identidade ativa: E.D.I.T.H. Tom ágil, claro, orientado a diagnóstico rápido e execução prática.',
    defaultStyle: SpeechStyle.tecnico,
  );

  static const AssistantPersona visao = AssistantPersona(
    wakeProfile: WakeWordProfile.visao,
    displayName: 'VISÃO',
    tagline: 'Calmo, ponderado e reflexivo',
    accentColor: Color(0xFF22C55E),
    promptDirective:
        'Identidade ativa: VISÃO. Tom calmo, empático, lógico e equilibrado.',
    defaultStyle: SpeechStyle.calmo,
  );

  static const List<AssistantPersona> all = <AssistantPersona>[
    ultron,
    jarvis,
    edith,
    visao,
  ];

  static AssistantPersona forWakeProfile(WakeWordProfile profile) =>
      switch (profile) {
        WakeWordProfile.ultron => ultron,
        WakeWordProfile.jarvis => jarvis,
        WakeWordProfile.edith => edith,
        WakeWordProfile.visao => visao,
      };
}
