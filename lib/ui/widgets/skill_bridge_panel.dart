import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/security/action_gate.dart';
import '../../services/obsidian_service.dart';
import '../../services/skill_bridge_service.dart';
import '../theme/ultron_theme.dart';

/// Abre a Central Bidirecional de Skills (Celular ⇄ PC) em um modal bottom sheet.
Future<void> showSkillBridgeSheet(
  BuildContext context, {
  required SkillBridgeService skillBridge,
  required List<MobileSkill> mobileSkills,
  required Future<void> Function(String skillId) onRunPcSkill,
  required Future<void> Function() onRefreshPcSkills,
  required Future<void> Function() onSyncMobileSkillsToPc,
  required Future<void> Function(MobileSkill skill) onExecuteMobileSkill,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: UltronColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      side: BorderSide(color: UltronColors.border),
    ),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.84,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Central de Skills (Celular ⇄ PC)',
                          style: TextStyle(
                            color: UltronColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Ative rotinas no PC em 1 toque ou exponha skills do celular.',
                          style: TextStyle(
                            color: UltronColors.textSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: UltronColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: SkillBridgePanel(
                    skillBridge: skillBridge,
                    mobileSkills: mobileSkills,
                    onRunPcSkill: onRunPcSkill,
                    onRefreshPcSkills: onRefreshPcSkills,
                    onSyncMobileSkillsToPc: onSyncMobileSkillsToPc,
                    onExecuteMobileSkill: onExecuteMobileSkill,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Painel bidirecional de ativação de Skills entre Celular e Desktop PC.
class SkillBridgePanel extends StatefulWidget {
  const SkillBridgePanel({
    super.key,
    required this.skillBridge,
    required this.mobileSkills,
    required this.onRunPcSkill,
    required this.onRefreshPcSkills,
    required this.onSyncMobileSkillsToPc,
    required this.onExecuteMobileSkill,
  });

  final SkillBridgeService skillBridge;
  final List<MobileSkill> mobileSkills;
  final Future<void> Function(String skillId) onRunPcSkill;
  final Future<void> Function() onRefreshPcSkills;
  final Future<void> Function() onSyncMobileSkillsToPc;
  final Future<void> Function(MobileSkill skill) onExecuteMobileSkill;

  @override
  State<SkillBridgePanel> createState() => _SkillBridgePanelState();
}

class _SkillBridgePanelState extends State<SkillBridgePanel> {
  bool _showPcTab = true;
  final TextEditingController _pcFilterController = TextEditingController();
  String _pcQuery = '';

  @override
  void dispose() {
    _pcFilterController.dispose();
    super.dispose();
  }

  Future<void> _promptAddPcShortcut() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: UltronColors.surface,
        title: const Text(
          'Novo atalho de Skill do PC',
          style: TextStyle(fontSize: 15),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              style: const TextStyle(color: UltronColors.textPrimary, fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Nome / slug da skill no PC',
                hintText: 'Ex: modo_trabalho, deploy_api',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descCtrl,
              style: const TextStyle(color: UltronColors.textPrimary, fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Descrição (opcional)',
                hintText: 'Ex: Abre VS Code + terminal + Docker',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Fixar'),
          ),
        ],
      ),
    );
    if (saved == true && nameCtrl.text.trim().isNotEmpty) {
      await widget.skillBridge.savePinnedPcSkill(
        nameCtrl.text,
        description: descCtrl.text,
      );
    }
    nameCtrl.dispose();
    descCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = UltronTheme.accentOf(context);
    final accentDark = UltronTheme.accentDarkOf(context);
    final accentBorder = UltronTheme.accentBorderOf(context);

    return ListenableBuilder(
      listenable: widget.skillBridge,
      builder: (context, _) {
        final pcAll = widget.skillBridge.pcSkills;
        final q = _pcQuery.trim().toLowerCase();
        final pcFiltered = q.isEmpty
            ? pcAll
            : pcAll
                .where(
                  (s) =>
                      s.id.toLowerCase().contains(q) ||
                      s.title.toLowerCase().contains(q) ||
                      s.description.toLowerCase().contains(q),
                )
                .toList(growable: false);

        return UltronSurfaceCard(
          highlighted: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _BridgeTabButton(
                      key: const Key('skills_bridge_tab_pc'),
                      icon: Icons.desktop_windows_rounded,
                      label: 'PC (${pcAll.length})',
                      selected: _showPcTab,
                      accent: accent,
                      accentDark: accentDark,
                      accentBorder: accentBorder,
                      onTap: () => setState(() => _showPcTab = true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _BridgeTabButton(
                      key: const Key('skills_bridge_tab_mobile'),
                      icon: Icons.smartphone_rounded,
                      label: 'Celular (${widget.mobileSkills.length})',
                      selected: !_showPcTab,
                      accent: accent,
                      accentDark: accentDark,
                      accentBorder: accentBorder,
                      onTap: () => setState(() => _showPcTab = false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_showPcTab) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const Key('skills_bridge_refresh_pc'),
                      onPressed: widget.skillBridge.isSyncing
                          ? null
                          : () => widget.onRefreshPcSkills(),
                      icon: widget.skillBridge.isSyncing
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: UltronTheme.onAccentFor(accent),
                              ),
                            )
                          : const Icon(Icons.sync_rounded, size: 16),
                      label: const Text('Atualizar do PC'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('skills_bridge_add_pc_shortcut'),
                      onPressed: _promptAddPcShortcut,
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Fixar atalho'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pcFilterController,
                        onChanged: (v) => setState(() => _pcQuery = v),
                        onSubmitted: (v) {
                          final trimmed = v.trim();
                          if (trimmed.isNotEmpty) {
                            widget.onRunPcSkill(trimmed);
                          }
                        },
                        style: const TextStyle(
                          color: UltronColors.textPrimary,
                          fontSize: 13,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Filtrar ou digitar skill do PC...',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      key: const Key('skills_bridge_run_typed_pc'),
                      tooltip: 'Executar skill digitada no PC',
                      style: IconButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: UltronTheme.onAccentFor(accent),
                      ),
                      onPressed: () {
                        final target = _pcFilterController.text.trim();
                        if (target.isNotEmpty) {
                          widget.onRunPcSkill(target);
                        }
                      },
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    ),
                  ],
                ),
                if (widget.skillBridge.lastStatusMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.skillBridge.lastStatusMessage!,
                    style: UltronTheme.mono.copyWith(
                      color: UltronColors.textMuted,
                      fontSize: 10.5,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                if (pcFiltered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Nenhuma skill do PC salva ainda.\nToque em "Atualizar do PC", "Fixar atalho" ou fale "ativar skill <nome> no pc".',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: UltronColors.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  )
                else
                  for (final entry in pcFiltered) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: UltronColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: entry.pinned ? accentBorder : UltronColors.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            constraints: const BoxConstraints(
                              minWidth: 30,
                              minHeight: 30,
                            ),
                            padding: EdgeInsets.zero,
                            tooltip: entry.pinned ? 'Desafixar' : 'Fixar atalho',
                            onPressed: () =>
                                widget.skillBridge.togglePin(entry.id),
                            icon: Icon(
                              entry.pinned
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 18,
                              color: entry.pinned
                                  ? accent
                                  : UltronColors.textMuted,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.title,
                                  style: const TextStyle(
                                    color: UltronColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  entry.description.isNotEmpty
                                      ? '${entry.id} · ${entry.description}'
                                      : entry.id,
                                  style: UltronTheme.mono.copyWith(
                                    color: UltronColors.textSecondary,
                                    fontSize: 10.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: 'Executar no PC',
                            onPressed: () => widget.onRunPcSkill(entry.id),
                            icon: Icon(
                              Icons.play_circle_filled_rounded,
                              color: accent,
                              size: 26,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
              ] else ...[
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Exponha skills locais (Skills/*.md) para o PC disparar via ponte LAN.',
                        style: TextStyle(
                          color: UltronColors.textSecondary,
                          fontSize: 11.5,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      key: const Key('skills_bridge_sync_mobile'),
                      onPressed: widget.mobileSkills.isEmpty
                          ? null
                          : () => widget.onSyncMobileSkillsToPc(),
                      icon: const Icon(Icons.upload_rounded, size: 16),
                      label: const Text('Enviar ao PC'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (widget.mobileSkills.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Nenhuma skill local encontrada em Skills/*.md.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: UltronColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  )
                else
                  for (final skill in widget.mobileSkills) ...[
                    _MobileSkillBridgeCard(
                      skill: skill,
                      accent: accent,
                      onExecute: () => widget.onExecuteMobileSkill(skill),
                      onCopyCommand: () {
                        final cmd =
                            SkillBridgeService.buildDesktopTriggerHint(skill);
                        Clipboard.setData(ClipboardData(text: cmd));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Gatilho "$cmd" copiado para acionar do PC.',
                              style: const TextStyle(fontSize: 11),
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _BridgeTabButton extends StatelessWidget {
  const _BridgeTabButton({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.accent,
    required this.accentDark,
    required this.accentBorder,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color accent;
  final Color accentDark;
  final Color accentBorder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? accentDark : UltronColors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: BorderSide(
          color: selected ? accentBorder : UltronColors.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? accent : UltronColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? UltronColors.textPrimary
                        : UltronColors.textSecondary,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileSkillBridgeCard extends StatelessWidget {
  const _MobileSkillBridgeCard({
    required this.skill,
    required this.accent,
    required this.onExecute,
    required this.onCopyCommand,
  });

  final MobileSkill skill;
  final Color accent;
  final VoidCallback onExecute;
  final VoidCallback onCopyCommand;

  @override
  Widget build(BuildContext context) {
    final desc = MobileSkillDescriptor.fromMobileSkill(skill);
    final riskColor = switch (desc.riskLevel) {
      RiskLevel.safe => UltronColors.positive,
      RiskLevel.sensitive => UltronColors.warning,
      RiskLevel.critical => UltronColors.crimson,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: UltronColors.surfaceElevated,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: UltronColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        desc.title,
                        style: const TextStyle(
                          color: UltronColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: riskColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        desc.riskLevel.name.toUpperCase(),
                        style: UltronTheme.mono.copyWith(
                          color: riskColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'RUN_SKILL:${desc.slug} · ${desc.actionCount} ação(ões)',
                  style: UltronTheme.mono.copyWith(
                    color: UltronColors.textSecondary,
                    fontSize: 10.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copiar gatilho para o PC',
            onPressed: onCopyCommand,
            icon: const Icon(
              Icons.copy_rounded,
              size: 18,
              color: UltronColors.textSecondary,
            ),
          ),
          IconButton(
            tooltip: 'Testar no celular',
            onPressed: onExecute,
            icon: Icon(
              Icons.play_arrow_rounded,
              size: 22,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}
