import 'package:flutter/material.dart';

import '../../services/smart_notification_triage_service.dart';
import '../theme/ultron_theme.dart';

/// Seção Automação: triagem inteligente de notificações em tempo real,
/// fluxos agendados com checkpoints, lembretes, agenda, briefing e Spotify.
class AutomationSection extends StatefulWidget {
  const AutomationSection({
    super.key,
    required this.triageConfig,
    required this.notificationPermissionGranted,
    required this.onUpdateTriageConfig,
    required this.onOpenNotificationAccessSettings,
    required this.onRunSlashCommand,
  });

  final NotificationTriageConfig triageConfig;
  final bool notificationPermissionGranted;
  final ValueChanged<NotificationTriageConfig> onUpdateTriageConfig;
  final VoidCallback onOpenNotificationAccessSettings;
  final Future<void> Function(String slashCommand) onRunSlashCommand;

  @override
  State<AutomationSection> createState() => _AutomationSectionState();
}

class _AutomationSectionState extends State<AutomationSection> {
  late final TextEditingController _vipsController;
  late final TextEditingController _keywordsController;

  @override
  void initState() {
    super.initState();
    _vipsController = TextEditingController(
      text: widget.triageConfig.vipContacts.join(', '),
    );
    _keywordsController = TextEditingController(
      text: widget.triageConfig.customKeywords.join(', '),
    );
  }

  @override
  void didUpdateWidget(covariant AutomationSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldVips = oldWidget.triageConfig.vipContacts.join(', ');
    final newVips = widget.triageConfig.vipContacts.join(', ');
    if (oldVips != newVips && _vipsController.text != newVips) {
      _vipsController.text = newVips;
    }
    final oldKw = oldWidget.triageConfig.customKeywords.join(', ');
    final newKw = widget.triageConfig.customKeywords.join(', ');
    if (oldKw != newKw && _keywordsController.text != newKw) {
      _keywordsController.text = newKw;
    }
  }

  @override
  void dispose() {
    _vipsController.dispose();
    _keywordsController.dispose();
    super.dispose();
  }

  static List<String> _splitCsv(String raw) => raw
      .split(RegExp(r'[,;\n]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);

  void _saveLists() {
    widget.onUpdateTriageConfig(
      widget.triageConfig.copyWith(
        vipContacts: _splitCsv(_vipsController.text),
        customKeywords: _splitCsv(_keywordsController.text),
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Filtros da triagem inteligente salvos.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.triageConfig;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const UltronSectionLabel('Triagem inteligente em tempo real'),
        UltronSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Monitorar urgências (WhatsApp, Telegram e E-mail)',
                          style: TextStyle(
                            color: UltronColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.notificationPermissionGranted
                              ? 'Reação instantânea no Android, sem polling de bateria e com filtro anti-ruído.'
                              : 'Ative o acesso às notificações do Android para habilitar a triagem.',
                          style: const TextStyle(
                            color: UltronColors.textSecondary,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: cfg.enabled,
                    activeThumbColor: UltronColors.crimson,
                    onChanged: (v) {
                      if (v && !widget.notificationPermissionGranted) {
                        widget.onOpenNotificationAccessSettings();
                        return;
                      }
                      widget.onUpdateTriageConfig(cfg.copyWith(enabled: v));
                    },
                  ),
                ],
              ),
              if (!widget.notificationPermissionGranted) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: widget.onOpenNotificationAccessSettings,
                    icon: const Icon(
                      Icons.notifications_active_outlined,
                      size: 16,
                    ),
                    label: const Text('Liberar acesso às notificações'),
                  ),
                ),
              ],
              const Divider(height: 20, color: UltronColors.borderSubtle),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: cfg.saveToObsidian,
                activeThumbColor: UltronColors.crimson,
                onChanged: (v) => widget
                    .onUpdateTriageConfig(cfg.copyWith(saveToObsidian: v)),
                title: const Text(
                  'Registrar urgências no Obsidian',
                  style: TextStyle(
                    color: UltronColors.textPrimary,
                    fontSize: 13.5,
                  ),
                ),
                subtitle: const Text(
                  'Grava checklist em Inbox/Urgencias_AAAA-MM-DD.md',
                  style: TextStyle(
                    color: UltronColors.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: cfg.speakUrgentAlerts,
                activeThumbColor: UltronColors.crimson,
                onChanged: (v) => widget
                    .onUpdateTriageConfig(cfg.copyWith(speakUrgentAlerts: v)),
                title: const Text(
                  'Ler alertas urgentes em voz alta',
                  style: TextStyle(
                    color: UltronColors.textPrimary,
                    fontSize: 13.5,
                  ),
                ),
                subtitle: const Text(
                  'Anuncia o remetente e resumo mesmo fora do aplicativo',
                  style: TextStyle(
                    color: UltronColors.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: cfg.respectNightFocus,
                activeThumbColor: UltronColors.crimson,
                onChanged: (v) => widget
                    .onUpdateTriageConfig(cfg.copyWith(respectNightFocus: v)),
                title: const Text(
                  'Respeitar Foco Noturno (22h às 06h)',
                  style: TextStyle(
                    color: UltronColors.textPrimary,
                    fontSize: 13.5,
                  ),
                ),
                subtitle: const Text(
                  'À noite só alerta contatos VIP ou urgência crítica (>= 90%)',
                  style: TextStyle(
                    color: UltronColors.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _vipsController,
                style: const TextStyle(
                  color: UltronColors.textPrimary,
                  fontSize: 13,
                ),
                decoration: const InputDecoration(
                  labelText: 'Contatos VIP (separados por vírgula)',
                  labelStyle: TextStyle(
                    color: UltronColors.textSecondary,
                    fontSize: 12,
                  ),
                  hintText: 'Ex: Mãe, Chefe, João',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _keywordsController,
                style: const TextStyle(
                  color: UltronColors.textPrimary,
                  fontSize: 13,
                ),
                decoration: const InputDecoration(
                  labelText: 'Palavras-chave extras',
                  labelStyle: TextStyle(
                    color: UltronColors.textSecondary,
                    fontSize: 12,
                  ),
                  hintText: 'Ex: servidor, contrato, entrega',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saveLists,
                      child: const Text('Salvar VIPs e palavras'),
                    ),
                  ),
                  if (cfg.mutedSenders.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => widget.onUpdateTriageConfig(
                        cfg.copyWith(mutedSenders: const []),
                      ),
                      child: Text(
                        'Limpar silenciados (${cfg.mutedSenders.length})',
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Urgências triadas: ${cfg.triagedCount}  ·  Limiar: ${(cfg.urgencyThreshold * 100).round()}%  ·  Rajada: 3+ msgs/60s',
                style: UltronTheme.mono.copyWith(
                  color: UltronColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const UltronSectionLabel('Rotinas e briefing'),
        UltronActionTile(
          icon: Icons.wb_sunny_outlined,
          title: 'Executar briefing agora',
          subtitle: 'Agenda, lembretes pendentes, clima e status do dispositivo',
          onTap: () => widget.onRunSlashCommand('/briefing'),
        ),
        const SizedBox(height: 8),
        UltronActionTile(
          icon: Icons.event_outlined,
          title: 'Compromissos da agenda',
          subtitle: 'Consulta os eventos dos próximos dias no calendário',
          onTap: () => widget.onRunSlashCommand('/agenda hoje'),
        ),
        const SizedBox(height: 8),
        UltronActionTile(
          icon: Icons.notifications_active_outlined,
          title: 'Lembretes persistentes',
          subtitle: 'Lista lembretes agendados com restauração após reboot',
          onTap: () => widget.onRunSlashCommand('/lembretes'),
        ),
        const SizedBox(height: 16),
        const UltronSectionLabel('Fluxos agendados e checkpoints'),
        UltronActionTile(
          icon: Icons.alt_route_rounded,
          title: 'Listar fluxos agendados',
          subtitle: 'Exibe rotinas cadastradas e pontos de retomada',
          onTap: () => widget.onRunSlashCommand('/fluxo listar'),
        ),
        const SizedBox(height: 8),
        UltronActionTile(
          icon: Icons.cloud_outlined,
          title: 'Clima atual',
          subtitle: 'Consulta previsão sem dependências pesadas',
          onTap: () => widget.onRunSlashCommand('/clima'),
        ),
        const SizedBox(height: 8),
        UltronActionTile(
          icon: Icons.newspaper_outlined,
          title: 'Resumo de notícias',
          subtitle: 'Manchetes recentes via feeds configurados',
          onTap: () => widget.onRunSlashCommand('/noticias'),
        ),
        const SizedBox(height: 16),
        const UltronSectionLabel('Spotify OAuth 2.0 PKCE'),
        UltronActionTile(
          icon: Icons.music_note_outlined,
          title: 'Verificar conexão Spotify',
          subtitle: 'Estado da reprodução atual e sessão PKCE',
          onTap: () => widget.onRunSlashCommand('/spotify estado'),
        ),
        const SizedBox(height: 8),
        UltronActionTile(
          icon: Icons.link_rounded,
          title: 'Conectar conta Spotify',
          subtitle: 'Inicia autenticação segura OAuth PKCE sem client secret',
          onTap: () => widget.onRunSlashCommand('/spotify conectar'),
        ),
      ],
    );
  }
}
