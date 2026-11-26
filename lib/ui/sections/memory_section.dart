import 'package:flutter/material.dart';

import '../../services/obsidian_service.dart';
import '../theme/ultron_theme.dart';

/// Seção Memória: Obsidian Vault (Diário, Inbox, Inventário, Pessoas), RAG FTS5, Skills e Histórico.
class MemorySection extends StatefulWidget {
  const MemorySection({
    super.key,
    required this.quickNoteController,
    required this.mobileSkills,
    required this.onSaveDailyNote,
    required this.onSaveInbox,
    required this.onExecuteSkill,
    required this.onRunSlashCommand,
    required this.onOpenHistory,
    required this.onOpenMemorySettings,
  });

  final TextEditingController quickNoteController;
  final List<MobileSkill> mobileSkills;
  final Future<void> Function(String text) onSaveDailyNote;
  final Future<void> Function(String text) onSaveInbox;
  final Future<void> Function(MobileSkill skill) onExecuteSkill;
  final Future<void> Function(String slashCommand) onRunSlashCommand;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenMemorySettings;

  @override
  State<MemorySection> createState() => _MemorySectionState();
}

class _MemorySectionState extends State<MemorySection> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _runSearch() {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;
    widget.onRunSlashCommand('/buscar $q');
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const UltronSectionLabel('Captura rápida no Obsidian'),
        UltronSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: widget.quickNoteController,
                maxLines: 3,
                minLines: 2,
                style: const TextStyle(
                  color: UltronColors.textPrimary,
                  fontSize: 14,
                ),
                decoration: const InputDecoration(
                  hintText: 'Anote uma ideia, tarefa ou registro...',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          widget.onSaveDailyNote(widget.quickNoteController.text),
                      icon: const Icon(Icons.edit_note_rounded, size: 17),
                      label: const Text('Salvar no Diário'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          widget.onSaveInbox(widget.quickNoteController.text),
                      icon: const Icon(Icons.inbox_outlined, size: 17),
                      label: const Text('Enviar ao Inbox'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const UltronSectionLabel('Busca no cofre (FTS5 / BM25)'),
        UltronSurfaceCard(
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _runSearch(),
                  style: const TextStyle(
                    color: UltronColors.textPrimary,
                    fontSize: 14,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Buscar em notas, Inventário ou Pessoas...',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.symmetric(horizontal: 6),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Pesquisar no cofre',
                onPressed: _runSearch,
                icon: Icon(
                  Icons.search_rounded,
                  color: UltronTheme.accentOf(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const UltronSectionLabel('Pastas e arquivos'),
        UltronActionTile(
          icon: Icons.folder_copy_outlined,
          title: 'Inspecionar cofre Obsidian',
          subtitle: 'Listar pastas Diario, Inbox, Inventario, Pessoas e Skills',
          onTap: () => widget.onRunSlashCommand('/vault listar'),
        ),
        const SizedBox(height: 8),
        UltronActionTile(
          icon: Icons.fitness_center_rounded,
          title: 'Sincronizar openGym (Modo Treino)',
          subtitle: 'Importar backup JSON ou CSV offline para PRs e volume no Obsidian',
          onTap: () => widget.onRunSlashCommand('/opengym importar'),
        ),
        const SizedBox(height: 8),
        UltronActionTile(
          icon: Icons.history_rounded,
          title: 'Histórico criptografado de conversas',
          subtitle: 'Banco SQLCipher isolado por modo tático',
          onTap: widget.onOpenHistory,
        ),
        const SizedBox(height: 8),
        UltronActionTile(
          icon: Icons.tune_rounded,
          title: 'Correções de voz, atalhos e preferências',
          subtitle: 'Gerenciar dicionário pessoal e gatilhos salvos',
          onTap: widget.onOpenMemorySettings,
        ),
        const SizedBox(height: 8),
        UltronActionTile(
          icon: Icons.undo_rounded,
          title: 'Desfazer última alteração no cofre',
          subtitle: 'Restaura o backup automático mais recente (/undo)',
          onTap: () => widget.onRunSlashCommand('/undo'),
        ),
        if (widget.mobileSkills.isNotEmpty) ...[
          const SizedBox(height: 16),
          const UltronSectionLabel('Skills locais (.md)'),
          ...widget.mobileSkills.map(
            (skill) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: UltronActionTile(
                icon: Icons.auto_stories_outlined,
                title: skill.title,
                subtitle: skill.slug,
                trailing: Icon(
                  Icons.play_arrow_rounded,
                  size: 18,
                  color: UltronTheme.accentOf(context),
                ),
                onTap: () => widget.onExecuteSkill(skill),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
