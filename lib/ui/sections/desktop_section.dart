import 'package:flutter/material.dart';

import '../theme/ultron_theme.dart';

/// Seção Desktop: ponte bidirecional LAN / Tailscale, Mini-Apps e Kill Switch HMAC.
class DesktopSection extends StatefulWidget {
  const DesktopSection({
    super.key,
    required this.pcLanConfigured,
    required this.listenerRunning,
    required this.onOpenPairingScreen,
    required this.onRunSlashCommand,
  });

  final bool pcLanConfigured;
  final bool listenerRunning;
  final VoidCallback onOpenPairingScreen;
  final Future<void> Function(String slashCommand) onRunSlashCommand;

  @override
  State<DesktopSection> createState() => _DesktopSectionState();
}

class _DesktopSectionState extends State<DesktopSection> {
  final TextEditingController _miniAppController = TextEditingController();

  @override
  void dispose() {
    _miniAppController.dispose();
    super.dispose();
  }

  void _launchMiniApp() {
    final spec = _miniAppController.text.trim();
    if (spec.isEmpty) return;
    _miniAppController.clear();
    widget.onRunSlashCommand('/pc miniapp $spec');
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.pcLanConfigured || widget.listenerRunning;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const UltronSectionLabel('Estado da ponte LAN / Tailscale'),
        UltronSurfaceCard(
          highlighted: active,
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      active ? UltronColors.positive : UltronColors.textMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      active
                          ? 'Desktop pareado'
                          : 'Nenhum Desktop pareado',
                      style: const TextStyle(
                        color: UltronColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      active
                          ? 'Assinatura HMAC-SHA256 pronta para comandos remotos.'
                          : 'Use QR Code ou URI na mesma rede LAN ou Tailscale.',
                      style: const TextStyle(
                        color: UltronColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: widget.onOpenPairingScreen,
                child: Text(active ? 'Gerenciar' : 'Parear'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const UltronSectionLabel('Controle remoto'),
        UltronActionTile(
          icon: Icons.monitor_heart_outlined,
          title: 'Verificar status do PC',
          subtitle: 'Testa latência e conectividade da ponte (/pc status)',
          onTap: () => widget.onRunSlashCommand('/pc status'),
        ),
        const SizedBox(height: 8),
        UltronActionTile(
          icon: Icons.terminal_outlined,
          title: 'Listar skills e ferramentas do PC',
          subtitle: 'Consulta recursos disponíveis no U.L.T.R.O.N. Desktop',
          onTap: () => widget.onRunSlashCommand('/pc listar'),
        ),
        const SizedBox(height: 16),
        const UltronSectionLabel('Mini-App local (sandbox)'),
        UltronSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Solicitar criação de Mini-App no Desktop',
                style: TextStyle(
                  color: UltronColors.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Ação classificada como crítica no ActionGate. Sempre pede confirmação explícita antes de enviar ao PC.',
                style: TextStyle(
                  color: UltronColors.textSecondary,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _miniAppController,
                onSubmitted: (_) => _launchMiniApp(),
                style: const TextStyle(
                  color: UltronColors.textPrimary,
                  fontSize: 13,
                ),
                decoration: const InputDecoration(
                  hintText: 'Ex: calculadora de queda de tensão NBR 5410',
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _launchMiniApp,
                icon: const Icon(Icons.widgets_outlined, size: 16),
                label: const Text('Criar Mini-App via ponte'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const UltronSectionLabel('Segurança remota'),
        UltronActionTile(
          icon: Icons.power_settings_new_rounded,
          title: 'Disparar Kill Switch LAN',
          subtitle: 'Bloqueia o PC remotamente via pacote assinado HMAC-SHA256',
          accentColor: UltronColors.crimson,
          onTap: () => widget.onRunSlashCommand('/killswitch'),
        ),
      ],
    );
  }
}
