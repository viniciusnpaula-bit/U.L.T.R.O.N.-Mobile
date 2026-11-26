import 'package:flutter/material.dart';

import '../models/ultron_section.dart';
import '../theme/ultron_theme.dart';

/// Menu de navegação lateral limpo, reutilizado como Drawer no celular
/// e como barra lateral fixa em tablets (largura >= 840dp).
class UltronNavigationContent extends StatelessWidget {
  const UltronNavigationContent({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.versionLabel,
    required this.accessBadge,
    required this.hasBiometricAccess,
    required this.onLock,
    this.hasUpdate = false,
  });

  final UltronSection selected;
  final ValueChanged<UltronSection> onSelect;
  final String versionLabel;
  final String accessBadge;
  final bool hasBiometricAccess;
  final VoidCallback onLock;
  final bool hasUpdate;

  @override
  Widget build(BuildContext context) {
    final primarySections = UltronSection.values
        .where((s) => s != UltronSection.settings)
        .toList(growable: false);

    return Container(
      color: UltronColors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cabeçalho limpo da marca
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 16, 14),
              child: Row(
                children: [
                  const UltronMark(size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Flexible(
                              child: Text(
                                'U.L.T.R.O.N.',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: UltronColors.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: UltronColors.surfaceElevated,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: UltronColors.border),
                              ),
                              child: Text(
                                versionLabel,
                                style: UltronTheme.mono.copyWith(
                                  color: UltronColors.textSecondary,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: hasBiometricAccess
                                    ? UltronColors.positive
                                    : UltronColors.warning,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                accessBadge,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: UltronColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: UltronColors.borderSubtle),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                itemCount: primarySections.length,
                separatorBuilder: (_, __) => const SizedBox(height: 2),
                itemBuilder: (context, index) {
                  final section = primarySections[index];
                  return _NavItem(
                    section: section,
                    selected: selected == section,
                    onTap: () => onSelect(section),
                  );
                },
              ),
            ),
            const Divider(height: 1, color: UltronColors.borderSubtle),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                children: [
                  _NavItem(
                    section: UltronSection.settings,
                    selected: selected == UltronSection.settings,
                    showBadgeDot: hasUpdate,
                    onTap: () => onSelect(UltronSection.settings),
                  ),
                  const SizedBox(height: 4),
                  Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: onLock,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 18,
                              color: UltronColors.textMuted,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Bloquear sessão',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: UltronColors.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.section,
    required this.selected,
    required this.onTap,
    this.showBadgeDot = false,
  });

  final UltronSection section;
  final bool selected;
  final VoidCallback onTap;
  final bool showBadgeDot;

  @override
  Widget build(BuildContext context) {
    final accent = UltronTheme.accentOf(context);
    return Material(
      color: selected ? UltronColors.surfaceElevated : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected ? UltronColors.border : Colors.transparent,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 3,
                height: selected ? 16 : 0,
                margin: EdgeInsets.only(right: selected ? 9 : 0),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Icon(
                selected ? section.selectedIcon : section.icon,
                size: 19,
                color: selected ? accent : UltronColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  section.label,
                  style: TextStyle(
                    color: selected
                        ? UltronColors.textPrimary
                        : UltronColors.textSecondary,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              if (showBadgeDot)
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: UltronTheme.accentOf(context),
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
