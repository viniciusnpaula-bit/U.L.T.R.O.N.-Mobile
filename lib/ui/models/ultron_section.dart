import 'package:flutter/material.dart';

/// Seções principais da navegação lateral do U.L.T.R.O.N. Mobile.
enum UltronSection {
  home(
    label: 'Início',
    subtitle: 'CoreOrb, conversa e voz',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
  ),
  device(
    label: 'Celular',
    subtitle: 'Hardware, mídia e controles',
    icon: Icons.smartphone_outlined,
    selectedIcon: Icons.smartphone_rounded,
  ),
  intelligence(
    label: 'Inteligência',
    subtitle: 'Modelos, failover, visão e OCR',
    icon: Icons.psychology_outlined,
    selectedIcon: Icons.psychology_rounded,
  ),
  memory(
    label: 'Memória',
    subtitle: 'Obsidian, RAG, inventário e skills',
    icon: Icons.memory_outlined,
    selectedIcon: Icons.memory_rounded,
  ),
  engineering(
    label: 'Engenharia',
    subtitle: 'NBR 5410, inversores e diagramas',
    icon: Icons.electrical_services_outlined,
    selectedIcon: Icons.electrical_services_rounded,
  ),
  files(
    label: 'Arquivos',
    subtitle: 'SAF, conversão e ETL em lote',
    icon: Icons.folder_outlined,
    selectedIcon: Icons.folder_rounded,
  ),
  automation(
    label: 'Automação',
    subtitle: 'Fluxos, lembretes, agenda e briefing',
    icon: Icons.alt_route_outlined,
    selectedIcon: Icons.alt_route_rounded,
  ),
  desktop(
    label: 'Desktop',
    subtitle: 'PC, LAN, Tailscale e Mini-Apps',
    icon: Icons.desktop_windows_outlined,
    selectedIcon: Icons.desktop_windows_rounded,
  ),
  security(
    label: 'Segurança',
    subtitle: 'PIN, biometria, NFC e auditoria',
    icon: Icons.shield_outlined,
    selectedIcon: Icons.shield_rounded,
  ),
  settings(
    label: 'Configurações',
    subtitle: 'Voz, preferências e diagnóstico',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
  );

  const UltronSection({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final IconData selectedIcon;
}
