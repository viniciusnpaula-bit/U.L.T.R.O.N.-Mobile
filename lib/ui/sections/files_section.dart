import 'package:flutter/material.dart';

import '../theme/ultron_theme.dart';

/// Seção Arquivos: utilitários SAF locais e ETL em lote para o Obsidian Inbox.
class FilesSection extends StatelessWidget {
  const FilesSection({
    super.key,
    required this.onRunSlashCommand,
    required this.pcLanConfigured,
  });

  final Future<void> Function(String slashCommand) onRunSlashCommand;
  final bool pcLanConfigured;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const UltronSectionLabel('Processamento em lote (ETL)'),
        UltronSurfaceCard(
          highlighted: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Consolidar documentos no Obsidian',
                style: TextStyle(
                  color: UltronColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                pcLanConfigured
                    ? 'Seleciona múltiplos arquivos via SAF. Arquivos .txt, .md e .csv são consolidados offline; PDFs podem ser enviados ao Desktop pareado.'
                    : 'Seleciona múltiplos arquivos via SAF (.txt, .md e .csv) e gera uma nota Markdown tabular em Inbox/. Pareie o Desktop para delegar PDFs.',
                style: const TextStyle(
                  color: UltronColors.textSecondary,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => onRunSlashCommand('/arquivos lote'),
                  icon: const Icon(Icons.layers_outlined, size: 17),
                  label: const Text('Selecionar arquivos para ETL'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const UltronSectionLabel('Utilitários SAF offline'),
        UltronActionTile(
          icon: Icons.copy_all_outlined,
          title: 'Localizar arquivos duplicados',
          subtitle: 'Varredura por hash SHA-256 em pasta autorizada via SAF',
          onTap: () => onRunSlashCommand('/arquivos duplicados'),
        ),
        const SizedBox(height: 8),
        UltronActionTile(
          icon: Icons.image_outlined,
          title: 'Converter imagens',
          subtitle: 'Converte para JPEG, PNG ou WebP localmente',
          onTap: () => onRunSlashCommand('/arquivos converter'),
        ),
        const SizedBox(height: 8),
        UltronActionTile(
          icon: Icons.picture_as_pdf_outlined,
          title: 'Organizar documentos e PDFs',
          subtitle: 'Classifica arquivos selecionados por categoria',
          onTap: () => onRunSlashCommand('/arquivos organizar'),
        ),
        const SizedBox(height: 8),
        UltronActionTile(
          icon: Icons.receipt_long_outlined,
          title: 'Registrar garantia ou manual',
          subtitle: 'Abre o fluxo da skill de garantias com lembrete automático',
          onTap: () => onRunSlashCommand('/skill garantias'),
        ),
      ],
    );
  }
}
