import 'package:flutter/material.dart';

import '../../models/assistant_persona.dart';
import '../../services/audio_vad_buffer.dart';
import '../../services/speech_text.dart';
import '../../services/voice_service.dart';
import '../theme/ultron_theme.dart';

/// Seção Configurações: voz, personalidade, Auto-VAD adaptativo, foco noturno, diagnóstico e atualizações.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.isAudioOn,
    required this.nightFocusMode,
    required this.selectedVoiceProfile,
    required this.vadProfile,
    required this.vadHangoverMs,
    required this.vadNoiseFloorDb,
    required this.vadStartThresholdDb,
    required this.installedVersion,
    required this.hasUpdate,
    required this.onToggleAudio,
    required this.onToggleNightFocus,
    required this.onSelectVadProfile,
    required this.onSelectVadHangoverMs,
    required this.onOpenVoiceSelector,
    required this.onOpenWakeDiagnostics,
    required this.onOpenAiSettings,
    required this.onOpenUpdates,
    required this.onOpenHelp,
    this.activePersona = AssistantPersona.ultron,
    this.speechStyle = SpeechStyle.direto,
    this.onSelectPersona,
    this.onSelectSpeechStyle,
    this.dynamicIslandEnabled = false,
    this.onToggleDynamicIsland,
    this.onConfigureDynamicIsland,
  });

  final bool isAudioOn;
  final bool nightFocusMode;
  final bool dynamicIslandEnabled;
  final VoiceProfile selectedVoiceProfile;
  final VadProfile vadProfile;
  final int vadHangoverMs;
  final double vadNoiseFloorDb;
  final double vadStartThresholdDb;
  final String installedVersion;
  final bool hasUpdate;
  final VoidCallback onToggleAudio;
  final VoidCallback onToggleNightFocus;
  final VoidCallback? onToggleDynamicIsland;
  final VoidCallback? onConfigureDynamicIsland;
  final ValueChanged<VadProfile> onSelectVadProfile;
  final ValueChanged<int> onSelectVadHangoverMs;
  final VoidCallback onOpenVoiceSelector;
  final VoidCallback onOpenWakeDiagnostics;
  final VoidCallback onOpenAiSettings;
  final VoidCallback onOpenUpdates;
  final VoidCallback onOpenHelp;
  final AssistantPersona activePersona;
  final SpeechStyle speechStyle;
  final ValueChanged<WakeWordProfile>? onSelectPersona;
  final ValueChanged<SpeechStyle>? onSelectSpeechStyle;

  @override
  Widget build(BuildContext context) {
    final accent = UltronTheme.accentOf(context);
    final accentBorder = UltronTheme.accentBorderOf(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const UltronSectionLabel('Voz e áudio (microfone nativo)'),
        UltronActionTile(
          icon: Icons.record_voice_over_outlined,
          title: 'Perfil de voz e síntese',
          subtitle: 'Ativo: ${selectedVoiceProfile.label}',
          onTap: onOpenVoiceSelector,
        ),
        if (onSelectPersona != null || onSelectSpeechStyle != null) ...[
          const SizedBox(height: 8),
          UltronSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: activePersona.accentColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Personalidade e tema visual',
                      style: TextStyle(
                        color: UltronColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${activePersona.tagline} · Tema: ${activePersona.themeName}',
                  style: const TextStyle(
                    color: UltronColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                if (onSelectPersona != null) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: AssistantPersona.all.map((persona) {
                      final selected =
                          activePersona.wakeProfile == persona.wakeProfile;
                      return ChoiceChip(
                        avatar: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: persona.accentColor,
                          ),
                        ),
                        label: Text(persona.displayName),
                        selected: selected,
                        onSelected: (_) =>
                            onSelectPersona!(persona.wakeProfile),
                        selectedColor: persona.accentDark,
                        backgroundColor: UltronColors.bg,
                        side: BorderSide(
                          color: selected
                              ? persona.accentColor
                              : UltronColors.borderSubtle,
                        ),
                        labelStyle: TextStyle(
                          color: selected
                              ? UltronColors.textPrimary
                              : UltronColors.textSecondary,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          fontSize: 12,
                        ),
                      );
                    }).toList(),
                  ),
                ],
                if (onSelectSpeechStyle != null) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Jeito de responder',
                    style: TextStyle(
                      color: UltronColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: SpeechStyle.values.map((style) {
                      final selected = speechStyle == style;
                      return ChoiceChip(
                        label: Text(style.label),
                        selected: selected,
                        onSelected: (_) => onSelectSpeechStyle!(style),
                        selectedColor: UltronColors.surfaceElevated,
                        backgroundColor: UltronColors.bg,
                        side: BorderSide(
                          color: selected
                              ? UltronColors.textSecondary
                              : UltronColors.borderSubtle,
                        ),
                        labelStyle: TextStyle(
                          color: selected
                              ? UltronColors.textPrimary
                              : UltronColors.textSecondary,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          fontSize: 12,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        UltronSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Auto-VAD adaptativo',
                style: TextStyle(
                  color: UltronColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                vadProfile.description,
                style: const TextStyle(
                  color: UltronColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: VadProfile.values.map((p) {
                  final selected = vadProfile == p;
                  return ChoiceChip(
                    label: Text(p.label),
                    selected: selected,
                    onSelected: (_) => onSelectVadProfile(p),
                    selectedColor: UltronColors.surfaceElevated,
                    backgroundColor: UltronColors.bg,
                    side: BorderSide(
                      color: selected ? accent : UltronColors.borderSubtle,
                    ),
                    labelStyle: TextStyle(
                      color: selected
                          ? UltronColors.textPrimary
                          : UltronColors.textSecondary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 12,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              const Text(
                'Pausa para encerrar fala',
                style: TextStyle(
                  color: UltronColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  (600, 'Rápido (0,6s)'),
                  (850, 'Natural (0,85s)'),
                  (1200, 'Longo (1,2s)'),
                ].map((opt) {
                  final selected = vadHangoverMs == opt.$1;
                  return ChoiceChip(
                    label: Text(opt.$2),
                    selected: selected,
                    onSelected: (_) => onSelectVadHangoverMs(opt.$1),
                    selectedColor: UltronColors.surfaceElevated,
                    backgroundColor: UltronColors.bg,
                    side: BorderSide(
                      color: selected
                          ? UltronColors.textSecondary
                          : UltronColors.borderSubtle,
                    ),
                    labelStyle: TextStyle(
                      color: selected
                          ? UltronColors.textPrimary
                          : UltronColors.textSecondary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 12,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              Text(
                'Piso ambiente: ${vadNoiseFloorDb.toStringAsFixed(1)} dBFS  ·  Limiar: ${vadStartThresholdDb.toStringAsFixed(1)} dBFS',
                style: UltronTheme.mono.copyWith(
                  color: UltronColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        UltronSurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: isAudioOn,
                onChanged: (_) => onToggleAudio(),
                activeThumbColor: accent,
                title: const Text(
                  'Respostas por voz',
                  style: TextStyle(
                    color: UltronColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
                subtitle: const Text(
                  'Ativa ou silencia a fala automática do assistente',
                  style: TextStyle(
                    color: UltronColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              const Divider(height: 1, color: UltronColors.borderSubtle),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: nightFocusMode,
                onChanged: (_) => onToggleNightFocus(),
                activeThumbColor: accent,
                title: const Text(
                  'Modo foco noturno',
                  style: TextStyle(
                    color: UltronColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
                subtitle: const Text(
                  'Reduz energia do CoreOrb e ativa voz em modo sussurro',
                  style: TextStyle(
                    color: UltronColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              if (onToggleDynamicIsland != null) ...[
                const Divider(height: 1, color: UltronColors.borderSubtle),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: dynamicIslandEnabled,
                  onChanged: (_) => onToggleDynamicIsland!(),
                  activeThumbColor: accent,
                  title: const Text(
                    'Ilha Dinâmica (Expressive Cutout)',
                    style: TextStyle(
                      color: UltronColors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: const Text(
                    'Pílula animada ao redor da câmera para voz, mídia, alertas e carga',
                    style: TextStyle(
                      color: UltronColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (onConfigureDynamicIsland != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onConfigureDynamicIsland,
                        icon: Icon(
                          Icons.open_with_rounded,
                          size: 17,
                          color: accent,
                        ),
                        label: const Text('Configurar ilha dinâmica'),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        UltronActionTile(
          icon: Icons.graphic_eq_rounded,
          title: 'Diagnóstico da palavra de ativação',
          subtitle: 'Permissões de segundo plano, bateria e sentinela offline',
          onTap: onOpenWakeDiagnostics,
        ),
        const SizedBox(height: 16),
        const UltronSectionLabel('Inteligência e sistema'),
        UltronActionTile(
          icon: Icons.tune_rounded,
          title: 'Provedores de IA, STT e diagnóstico acústico',
          subtitle: 'Chaves seguras, prioridade de failover e medidor dBFS',
          onTap: onOpenAiSettings,
        ),
        const SizedBox(height: 8),
        UltronActionTile(
          icon: Icons.system_update_outlined,
          title: 'Atualizações do aplicativo',
          subtitle: hasUpdate
              ? 'Nova versão disponível no GitHub ($installedVersion instalada)'
              : 'Versão instalada: $installedVersion',
          trailing: hasUpdate
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: UltronColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: accentBorder),
                  ),
                  child: Text(
                    'Nova',
                    style: TextStyle(
                      color: accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : null,
          onTap: onOpenUpdates,
        ),
        const SizedBox(height: 8),
        UltronActionTile(
          icon: Icons.help_outline_rounded,
          title: 'Guia de comandos slash',
          subtitle: 'Lista de comandos rápidos offline e online',
          onTap: onOpenHelp,
        ),
      ],
    );
  }
}
