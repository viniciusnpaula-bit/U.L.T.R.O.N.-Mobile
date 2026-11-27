import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'okf_metadata.dart';
import 'vault_search_service.dart';

export 'okf_metadata.dart';

class MobileSkill {
  const MobileSkill({
    required this.id,
    required this.title,
    required this.content,
  });

  final String id;
  final String title;
  final String content;

  String get slug => id;
}

class ObsidianNoteSummary {
  const ObsidianNoteSummary({
    required this.relativePath,
    required this.folder,
    required this.title,
    required this.sizeBytes,
    required this.modifiedAt,
    this.okf,
  });

  final String relativePath;
  final String folder;
  final String title;
  final int sizeBytes;
  final DateTime modifiedAt;
  final OkfMetadata? okf;
}

class ObsidianTaskItem {
  const ObsidianTaskItem({
    required this.index,
    required this.relativePath,
    required this.lineNumber,
    required this.text,
    required this.completed,
  });

  final int index;
  final String relativePath;
  final int lineNumber;
  final String text;
  final bool completed;

  String formatLine() =>
      '$index. [${completed ? 'x' : ' '}] $text ($relativePath:$lineNumber)';
}

class ObsidianVaultStatus {
  const ObsidianVaultStatus({
    required this.vaultPath,
    required this.vaultName,
    required this.totalNotes,
    required this.totalSizeBytes,
    required this.countsByFolder,
    required this.searchEngine,
    required this.undoDepth,
  });

  final String vaultPath;
  final String vaultName;
  final int totalNotes;
  final int totalSizeBytes;
  final Map<String, int> countsByFolder;
  final VaultSearchEngine searchEngine;
  final int undoDepth;

  String get sizeLabel {
    if (totalSizeBytes < 1024) return '$totalSizeBytes B';
    final kb = totalSizeBytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    return '${(kb / 1024).toStringAsFixed(2)} MB';
  }

  String formatSummary() {
    final folderParts = countsByFolder.entries
        .map((e) => '${e.key}: ${e.value}')
        .join(' · ');
    return '📓 STATUS DO COFRE OBSIDIAN ($vaultName)\n'
        '• Caminho ativo: $vaultPath\n'
        '• Total de notas: $totalNotes ($sizeLabel)\n'
        '• Pastas: ${folderParts.isEmpty ? 'nenhuma' : folderParts}\n'
        '• Engine de busca: ${searchEngine.name}\n'
        '• Snapshots p/ desfazer: $undoDepth';
  }
}

class ObsidianSnapshot {
  const ObsidianSnapshot({
    required this.operation,
    required this.relativePath,
    required this.existedBefore,
    required this.previousContent,
    required this.timestampIso,
  });

  factory ObsidianSnapshot.fromJson(Map<String, dynamic> map) =>
      ObsidianSnapshot(
        operation: (map['operation'] as String?) ?? 'MUTATION',
        relativePath: (map['relativePath'] as String?) ?? '',
        existedBefore: (map['existedBefore'] as bool?) ?? false,
        previousContent: map['previousContent'] as String?,
        timestampIso: (map['timestampIso'] as String?) ?? '',
      );

  final String operation;
  final String relativePath;
  final bool existedBefore;
  final String? previousContent;
  final String timestampIso;

  Map<String, dynamic> toJson() => {
        'operation': operation,
        'relativePath': relativePath,
        'existedBefore': existedBefore,
        'previousContent': previousContent,
        'timestampIso': timestampIso,
      };
}

class ObsidianUndoResult {
  const ObsidianUndoResult({
    required this.undone,
    required this.operation,
    required this.relativePath,
    required this.deletedCreatedFile,
    required this.message,
  });

  final bool undone;
  final String operation;
  final String relativePath;
  final bool deletedCreatedFile;
  final String message;
}

/// Serviço de integração com o Cofre do Obsidian (Segundo Cérebro do U.L.T.R.O.N.).
///
/// Estrutura do Cofre:
/// - `.obsidian/`           -> Configurações para o app oficial Obsidian abrir o cofre diretamente.
/// - `Diario/YYYY-MM-DD.md` -> Daily Notes com logs de interações e reflexões temporizadas.
/// - `Memoria/`             -> Conhecimento permanente e contexto persistente:
///                             - `Operador.md`        (perfil, rotina e preferências do operador)
///                             - `Segundo_Cerebro.md` (mapa mental e índice do conhecimento)
/// - `Inbox/`               -> Captura rápida de pensamentos e ideias soltas.
/// - `Skills/*.md`          -> Automações táticas em Markdown executáveis pelo U.L.T.R.O.N.
/// - `Preferencias.md`      -> Diretrizes e regras de comportamento do assistente.
class ObsidianService {
  ObsidianService(this.root, {this.fallbackSkillsDir});

  final Directory root;
  final Directory? fallbackSkillsDir;
  final List<ObsidianSnapshot> _undoStack = <ObsidianSnapshot>[];
  bool _undoLoaded = false;

  static const _storageVaultKey = 'ultron.obsidian.custom_vault_path.v1';
  static const _undoStackFilename = '.ultron_undo_stack.json';
  static const int maxUndoDepth = 25;
  static const List<String> standardFolders = <String>[
    'Diario',
    'Memoria',
    'Inbox',
    'Inventario',
    'Pessoas',
    'Skills',
  ];

  /// Abre o cofre do Obsidian. Prioriza diretórios acessíveis pelo app oficial
  /// do Obsidian no Android (`/storage/emulated/0/Documents/ULTRON-Vault`),
  /// com suporte a caminho customizado e fallback para `Skills/` no storage privado.
  static Future<ObsidianService> openDefaultVault({
    FlutterSecureStorage? storage,
  }) async {
    final secStorage = storage ?? const FlutterSecureStorage();
    Directory? appSkillsDir;
    try {
      final docs = await getApplicationDocumentsDirectory();
      appSkillsDir = Directory(p.join(docs.path, 'ULTRON-Vault', 'Skills'));
    } catch (_) {}

    // 1. Caminho customizado configurado pelo usuário
    try {
      final customPath = await secStorage.read(key: _storageVaultKey);
      if (customPath != null && customPath.trim().isNotEmpty) {
        final customDir = Directory(customPath.trim());
        if (await customDir.exists()) {
          final s = ObsidianService(
            customDir,
            fallbackSkillsDir: appSkillsDir,
          );
          await s.initialize();
          return s;
        }
      }
    } catch (_) {}

    // 2. No Android: tentar pasta pública de Documentos para o app Obsidian enxergar
    if (Platform.isAndroid) {
      final candidates = [
        Directory('/storage/emulated/0/Documents/ULTRON-Vault'),
        Directory('/storage/emulated/0/Documents/Obsidian/ULTRON-Vault'),
      ];
      for (final dir in candidates) {
        try {
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          // Testa escrita para confirmar permissão real
          final probe = File(p.join(dir.path, '.probe'));
          await probe.writeAsString('ok');
          await probe.delete();

          final service = ObsidianService(
            dir,
            fallbackSkillsDir: appSkillsDir,
          );
          await service.initialize();
          return service;
        } catch (_) {
          // Sem permissão de escrita pública, continua para o próximo fallback
        }
      }
    }

    // 3. Fallback: pasta de documentos da aplicação
    final docs = await getApplicationDocumentsDirectory();
    final service = ObsidianService(
      Directory(p.join(docs.path, 'ULTRON-Vault')),
      fallbackSkillsDir: appSkillsDir,
    );
    await service.initialize();
    return service;
  }

  /// Define um caminho personalizado para o Vault (ex: cofre já existente do Obsidian).
  static Future<void> setCustomVaultPath(
    String path, {
    FlutterSecureStorage? storage,
  }) async {
    final secStorage = storage ?? const FlutterSecureStorage();
    if (path.trim().isEmpty) {
      await secStorage.delete(key: _storageVaultKey);
    } else {
      await secStorage.write(key: _storageVaultKey, value: path.trim());
    }
  }

  /// Inicializa a arquitetura do Segundo Cérebro no diretório do cofre.
  Future<void> initialize() async {
    await root.create(recursive: true);

    // Cria as pastas principais do Segundo Cérebro
    await Directory(p.join(root.path, '.obsidian')).create(recursive: true);
    await Directory(p.join(root.path, 'Diario')).create(recursive: true);
    await Directory(p.join(root.path, 'Memoria')).create(recursive: true);
    await Directory(p.join(root.path, 'Inbox')).create(recursive: true);
    await Directory(p.join(root.path, 'Inventario')).create(recursive: true);
    await Directory(p.join(root.path, 'Pessoas')).create(recursive: true);
    final skillsDir = Directory(p.join(root.path, 'Skills'));
    await skillsDir.create(recursive: true);

    // Semeia arquivos essenciais para o app oficial Obsidian reconhecer o cofre
    await _seedObsidianConfig();
    await _seedSecondBrainIndex();
    await _seedOperatorMemory();
    await _seedDefaultSkills(skillsDir);
    if (fallbackSkillsDir != null && fallbackSkillsDir!.path != skillsDir.path) {
      try {
        await fallbackSkillsDir!.create(recursive: true);
        await _seedDefaultSkills(fallbackSkillsDir!);
      } catch (_) {}
    }
    await _loadUndoStackIfNeeded();
  }

  Future<void> _seedObsidianConfig() async {
    final appConfig = File(p.join(root.path, '.obsidian', 'app.json'));
    if (!await appConfig.exists()) {
      await appConfig.writeAsString(
        '{"legacyEditor": false, "livePreview": true, "showLineNumber": true}\n',
      );
    }
  }

  Future<void> _seedSecondBrainIndex() async {
    final indexFile = File(p.join(root.path, 'Memoria', 'Segundo_Cerebro.md'));
    if (!await indexFile.exists()) {
      final now = DateTime.now();
      final header = OkfMetadata.renderFrontmatter(
        OkfMetadata(
          sources: const ['ultron_seed'],
          verified: false,
          staleAfter: OkfMetadata.computeStaleAfter(now),
          updatedAt: now.toUtc(),
          hasFrontmatter: true,
        ),
      );
      await indexFile.writeAsString(
        '$header\n'
        '# Segundo Cérebro (U.L.T.R.O.N.)\n\n'
        'Este cofre é a memória persistente e expandida do assistente U.L.T.R.O.N., '
        'sincronizado nativamente com o aplicativo Obsidian.\n\n'
        '## Estrutura do Conhecimento\n'
        '- **[[Memoria/Operador|Perfil do Operador]]**: Informações e diretrizes do usuário.\n'
        '- **[[Diario/]]**: Notas temporais e reflexões diárias automáticas.\n'
        '- **[[Inbox/]]**: Caixa de entrada de pensamentos e ideias capturadas.\n'
        '- **[[Inventario/]]**: Arquivo de vida estruturado (notas fiscais, garantias, manuais e procedimentos de reset).\n'
        '- **[[Skills/]]**: Procedimentos e habilidades táticas executáveis.\n\n'
        '---\n*Gerado automaticamente pelo U.L.T.R.O.N. Mobile v1.4.2*\n',
      );
    }
  }

  Future<void> _seedOperatorMemory() async {
    final opFile = File(p.join(root.path, 'Memoria', 'Operador.md'));
    if (!await opFile.exists()) {
      final now = DateTime.now();
      final header = OkfMetadata.renderFrontmatter(
        OkfMetadata(
          sources: const ['ultron_seed'],
          verified: false,
          staleAfter: OkfMetadata.computeStaleAfter(now),
          updatedAt: now.toUtc(),
          hasFrontmatter: true,
        ),
      );
      await opFile.writeAsString(
        '$header\n'
        '# Perfil do Operador\n\n'
        'Diretrizes de memória permanente do U.L.T.R.O.N.:\n'
        '- **Nome**: Operador\n'
        '- **Assistente**: U.L.T.R.O.N. 2.0 Mobile\n'
        '- **Objetivo**: Produtividade máxima, comando tático e segundo cérebro.\n'
        '- **Projetos Ativos**: U.L.T.R.O.N. Mobile v1.2.1\n',
      );
    }
  }

  Future<void> _seedDefaultSkills(Directory skillsDir) async {
    const defaults = <String, String>{
      'modo_estudo': '# Modo Estudo (Pomodoro 25m)\n'
          'Silencia áudio de mídia e inicia temporizador Pomodoro de 25 minutos.\n'
          '[ACTION:VOLUME_MUTE]\n'
          '[ACTION:TIMER:1500:Pomodoro U.L.T.R.O.N.]\n',
      'foco_noturno': '# Modo Foco Noturno\n'
          'Apaga a lanterna, reduz volume para 15% e ativa sussurro noturno.\n'
          '[ACTION:TORCH_OFF]\n'
          '[ACTION:VOLUME_SET:15]\n',
      'alerta_tatico': '# Alerta Tático\n'
          'Aciona lanterna traseira no máximo e envia pulso háptico de alerta.\n'
          '[ACTION:TORCH_ON]\n'
          '[ACTION:VIBRATE]\n',
      'permutacao_do_fone': '# Permutação do Fone\n'
          'Alterna o headset dual-mode (Attack Shark L30 Pro: Dongle 2.4GHz ⇄ Bluetooth) entre PC e celular, aguardando a conexão Bluetooth e continuando a música no Spotify Connect.\n'
          '[ACTION:HEADSET_HANDOFF:auto]\n',
      'garantias': '# Arquivo de Vida — Garantias e Manuais\n'
          'Fluxo tático para catalogar notas fiscais, etiquetas de equipamentos e manuais no cofre Obsidian.\n\n'
          '## Protocolo de Extração (/visao ou /ocr)\n'
          '1. Capture a foto da nota fiscal, etiqueta ou manual usando `/visao` ou `/ocr`.\n'
          '2. Extraia os campos estruturados:\n'
          '   - **Produto / Modelo**\n'
          '   - **Data de Compra** (`YYYY-MM-DD`)\n'
          '   - **Prazo de Garantia** (ex.: 12 meses) e **Vencimento** (`YYYY-MM-DD`)\n'
          '   - **Número de Série / Loja** (se visível)\n'
          '   - **Procedimento de Reset / Manutenção**\n'
          '3. Grave no cofre com `[ACTION:OBSIDIAN_APPEND:Inventario/<Produto>.md:<bloco estruturado>]`.\n'
          '4. Calcule 15 dias antes do vencimento e agende lembrete persistente às 09:00 com:\n'
          '   `[ACTION:REMINDER_CREATE:YYYY-MM-DD 09:00:Garantia de <Produto> vence em 15 dias]`\n',
    };
    for (final entry in defaults.entries) {
      try {
        final file = File(p.join(skillsDir.path, '${entry.key}.md'));
        if (!await file.exists()) {
          await file.writeAsString(entry.value);
        }
      } catch (_) {
        // Ignora arquivo inacessível por Scoped Storage (outro UID) e mantém seeding no fallback.
      }
    }
  }

  /// Retorna o caminho absoluto do Vault para exibição no HUD.
  String get vaultPath => root.path;

  /// Retorna o nome do cofre (nome da pasta).
  String get vaultName => p.basename(root.path);

  /// URI oficial para o app Obsidian abrir este cofre diretamente.
  String get obsidianOpenUri => 'obsidian://open?vault=${Uri.encodeComponent(vaultName)}';

  /// Captura um pensamento/ideia rápida para a pasta `Inbox/`.
  Future<File> captureToInbox(String thought) async {
    final clean = thought.trim();
    if (clean.isEmpty) throw ArgumentError('Texto não pode ser vazio');
    final now = DateTime.now();
    final ts = now.millisecondsSinceEpoch;
    final filename = 'Idea_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_$ts.md';
    final file = File(p.join(root.path, 'Inbox', filename));
    await file.parent.create(recursive: true);
    await _pushSnapshotForFile(file, operation: 'INBOX');
    await file.writeAsString(
      '# Ideia Capturada\n\n'
      '- Data: ${now.toLocal()}\n'
      '- Conteúdo: $clean\n',
    );
    return file;
  }

  /// Salva ou atualiza um tópico de memória permanente em `Memoria/$topic.md` com frontmatter OKF.
  Future<File> saveMemory(
    String topic,
    String content, {
    List<String> sources = const ['operador'],
    bool verified = false,
    int staleDays = OkfMetadata.defaultStaleDays,
    DateTime? now,
  }) async {
    final cleanTopic = topic
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim();
    if (cleanTopic.isEmpty) throw ArgumentError('Tópico inválido');
    final file = File(p.join(root.path, 'Memoria', '$cleanTopic.md'));
    await file.parent.create(recursive: true);
    await _pushSnapshotForFile(file, operation: 'REMEMBER');
    final refNow = now ?? DateTime.now();
    final updateBlock =
        '\n\n## Atualização (${refNow.day.toString().padLeft(2, '0')}/${refNow.month.toString().padLeft(2, '0')} ${refNow.hour.toString().padLeft(2, '0')}:${refNow.minute.toString().padLeft(2, '0')})\n$content\n';
    if (await file.exists()) {
      final current = await file.readAsString();
      final doc = OkfMetadata.parse(current);
      if (doc.metadata.hasFrontmatter) {
        final mergedSources = <String>{
          ...doc.metadata.sources,
          ...sources.map((s) => s.trim()).where((s) => s.isNotEmpty),
        }.toList(growable: false);
        final updated = OkfMetadata.upsertFrontmatter(
          '$current$updateBlock',
          (meta) => meta.copyWith(
            sources: mergedSources,
            updatedAt: refNow.toUtc(),
          ),
        );
        await file.writeAsString(updated);
      } else {
        await file.writeAsString(updateBlock, mode: FileMode.append);
      }
    } else {
      final header = OkfMetadata.renderFrontmatter(
        OkfMetadata(
          sources: sources,
          verified: verified,
          staleAfter: OkfMetadata.computeStaleAfter(refNow, days: staleDays),
          updatedAt: refNow.toUtc(),
          hasFrontmatter: true,
        ),
      );
      await file.writeAsString(
        '$header\n# $cleanTopic\n\n- Criado em: ${refNow.toLocal()}\n\n$content\n',
      );
    }
    return file;
  }

  /// Salva `Preferencias.md` na raiz do cofre com frontmatter OKF.
  Future<File> savePreferences(
    String content, {
    List<String> sources = const ['operador'],
    bool verified = false,
    int staleDays = OkfMetadata.defaultStaleDays,
    DateTime? now,
  }) async {
    final clean = content.trim();
    if (clean.isEmpty) throw ArgumentError('Preferências não podem ser vazias.');
    final file = File(p.join(root.path, 'Preferencias.md'));
    await _pushSnapshotForFile(file, operation: 'PREFERENCES');
    final refNow = now ?? DateTime.now();
    final header = OkfMetadata.renderFrontmatter(
      OkfMetadata(
        sources: sources,
        verified: verified,
        staleAfter: OkfMetadata.computeStaleAfter(refNow, days: staleDays),
        updatedAt: refNow.toUtc(),
        hasFrontmatter: true,
      ),
    );
    final body = clean.startsWith('#') ? '$clean\n' : '# Preferências\n\n$clean\n';
    await file.writeAsString('$header\n$body');
    return file;
  }

  /// Lê a memória de longo prazo para injeção contextual no prompt do LLM,
  /// sinalizando notas vencidas (`stale_after < hoje`) ou não verificadas via OKF.
  Future<String> readLongTermMemory({
    int maxChars = 2000,
    DateTime? now,
    bool excludeStale = false,
  }) async {
    final refNow = now ?? DateTime.now();
    final buffer = StringBuffer();

    void appendContextSection(String heading, String rawContent) {
      if (rawContent.trim().isEmpty) return;
      final doc = OkfMetadata.parse(rawContent);
      final body = doc.body.trim();
      if (body.isEmpty) return;
      final isStale = doc.metadata.isStale(now: refNow);
      final tag = doc.metadata.statusTag(now: refNow, isContextNote: true);
      if (excludeStale && isStale) {
        buffer.writeln(
          '$heading [ALERTA OKF: nota vencida desde ${doc.metadata.staleAfterIso} omitida do contexto — revise ou renove com /vault verificar]',
        );
        return;
      }
      final label = tag.isEmpty ? heading : '$heading [OKF: $tag]';
      buffer.writeln('$label:');
      buffer.writeln(body);
    }

    // 1. Perfil do Operador
    final opFile = File(p.join(root.path, 'Memoria', 'Operador.md'));
    if (await opFile.exists()) {
      final content = await opFile.readAsString();
      appendContextSection('### Perfil do Operador', content);
    }

    // 2. Preferências
    final prefFile = File(p.join(root.path, 'Preferencias.md'));
    if (await prefFile.exists()) {
      final pref = await prefFile.readAsString();
      if (buffer.isNotEmpty) buffer.writeln();
      appendContextSection('### Preferências', pref);
    }

    // 3. Resumo da Nota do Dia Atual
    final todayNote = await readDailyNote(refNow);
    if (todayNote.trim().isNotEmpty) {
      final lines = todayNote.trim().split('\n');
      final recent = lines.reversed.take(6).toList().reversed.join('\n');
      buffer.writeln('\n### Registros Recentes de Hoje (${refNow.day}/${refNow.month}):');
      buffer.writeln(recent);
    }

    final result = buffer.toString().trim();
    if (result.length > maxChars) {
      return result.substring(0, maxChars);
    }
    return result;
  }

  Future<String> readPreferences() async {
    final file = File(p.join(root.path, 'Preferencias.md'));
    if (!await file.exists()) {
      return '';
    }
    return file.readAsString();
  }

  Future<File> dailyNote(DateTime now, String text) async {
    final day =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final file = File(p.join(root.path, 'Diario', '$day.md'));
    await file.parent.create(recursive: true);
    await _pushSnapshotForFile(file, operation: 'NOTE');
    if (!await file.exists()) {
      await file.writeAsString('# $day\n');
    }
    if (text.trim().isNotEmpty) {
      await file.writeAsString(
        '\n- ${now.toIso8601String()}: $text\n',
        mode: FileMode.append,
      );
    }
    return file;
  }

  Future<File> appendDailyNote(DateTime now, String text) =>
      dailyNote(now, text);

  Future<String> readDailyNote(DateTime now) async {
    final day =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final file = File(p.join(root.path, 'Diario', '$day.md'));
    if (!await file.exists()) return '';
    return file.readAsString();
  }

  Future<File> quickNote(String title, String body) async {
    final clean = title
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim();
    if (clean.isEmpty || clean == '.' || clean == '..') {
      throw ArgumentError('Título inválido');
    }
    final file = File(p.join(root.path, '$clean.md'));
    await _pushSnapshotForFile(file, operation: 'NOTE');
    await file.writeAsString('# $clean\n\n$body\n');
    return file;
  }

  Future<void> _readSkillsFromDir(
    Directory skillsDir,
    Map<String, MobileSkill> byId,
  ) async {
    try {
      if (!await skillsDir.exists()) return;
      final entities = await skillsDir.list().toList();
      for (final entity in entities) {
        if (entity is! File || !entity.path.toLowerCase().endsWith('.md')) {
          continue;
        }
        final id = p.basenameWithoutExtension(entity.path);
        if (byId.containsKey(id)) continue;
        try {
          final content = await entity.readAsString();
          final firstLine = content
              .split('\n')
              .firstWhere((l) => l.trim().isNotEmpty, orElse: () => id)
              .replaceFirst(RegExp(r'^#+\s*'), '')
              .trim();
          byId[id] = MobileSkill(id: id, title: firstLine, content: content);
        } catch (_) {
          // Ignora arquivo protegido por Scoped Storage (outro UID).
        }
      }
    } catch (_) {
      // Ignora diretório inacessível em Android 16 Scoped Storage.
    }
  }

  Future<List<MobileSkill>> listSkills() async {
    final byId = <String, MobileSkill>{};
    final primarySkills = Directory(p.join(root.path, 'Skills'));
    await _readSkillsFromDir(primarySkills, byId);
    if (fallbackSkillsDir != null &&
        fallbackSkillsDir!.path != primarySkills.path) {
      await _readSkillsFromDir(fallbackSkillsDir!, byId);
    }
    final skills = byId.values.toList();
    skills.sort((a, b) => a.id.compareTo(b.id));
    return skills;
  }

  Future<MobileSkill?> findSkill(String query) async {
    final clean = query.trim().toLowerCase().replaceAll(' ', '_');
    final skills = await listSkills();
    for (final s in skills) {
      if (s.id.toLowerCase() == clean ||
          s.title.toLowerCase().contains(query.trim().toLowerCase())) {
        return s;
      }
    }
    return null;
  }

  /// Normaliza o identificador de uma Skill (`Skills/<id>.md`), rejeitando path traversal.
  static String sanitizeSkillId(String rawName) {
    var clean = rawName.trim();
    if (clean.toLowerCase().endsWith('.md')) {
      clean = clean.substring(0, clean.length - 3).trim();
    }
    if (clean.isEmpty ||
        clean.contains('..') ||
        clean.contains('/') ||
        clean.contains(r'\') ||
        clean.startsWith('.')) {
      throw ArgumentError('Nome de skill inválido: "$rawName"');
    }
    final slug = clean
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^a-z0-9_\-áàâãéèêíìîóòôõúùûç]'), '');
    if (slug.isEmpty) {
      throw ArgumentError('Nome de skill inválido: "$rawName"');
    }
    return slug;
  }

  /// SKILL_CREATE: Cria ou atualiza uma Skill em `Skills/<nome>.md`, registrando snapshot para UNDO.
  Future<MobileSkill> createSkill(String name, String content) async {
    final id = sanitizeSkillId(name);
    final cleanContent = content.trim();
    if (cleanContent.isEmpty) {
      throw ArgumentError('Conteúdo da skill não pode ser vazio.');
    }
    final file = resolveSafeNoteFile('Skills/$id.md');
    await file.parent.create(recursive: true);
    await _pushSnapshotForFile(file, operation: 'SKILL_CREATE');

    final normalizedBody =
        cleanContent.startsWith('#') ? '$cleanContent\n' : '# $name\n\n$cleanContent\n';
    await file.writeAsString(normalizedBody);

    final firstLine = normalizedBody
        .split('\n')
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => id)
        .replaceFirst(RegExp(r'^#+\s*'), '')
        .trim();
    return MobileSkill(id: id, title: firstLine, content: normalizedBody);
  }

  /// SKILL_DELETE: Remove uma Skill de `Skills/<nome>.md` (e do fallback, se existir),
  /// registrando snapshot na pilha de UNDO para permitir restauração.
  Future<bool> deleteSkill(String name) async {
    final id = sanitizeSkillId(name);
    var file = resolveSafeNoteFile('Skills/$id.md');
    if (!await file.exists()) {
      final found = await findSkill(name);
      if (found != null) {
        file = resolveSafeNoteFile('Skills/${found.id}.md');
      }
    }

    var deleted = false;
    if (await file.exists()) {
      await _pushSnapshotForFile(file, operation: 'SKILL_DELETE');
      await file.delete();
      deleted = true;
    }

    if (fallbackSkillsDir != null) {
      final fallbackFile = File(p.join(fallbackSkillsDir!.path, '$id.md'));
      if (await fallbackFile.exists()) {
        try {
          await fallbackFile.delete();
          deleted = true;
        } catch (_) {}
      }
    }
    return deleted;
  }

  /// Sanitiza e resolve um caminho relativo estritamente dentro de [root.path],
  /// bloqueando path traversal (`..`, caminhos absolutos, drives ou pastas ocultas `.obsidian`).
  File resolveSafeNoteFile(
    String rawRelativePath, {
    bool ensureMarkdownExtension = true,
  }) {
    var trimmed = rawRelativePath.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Caminho da nota não pode ser vazio.');
    }
    if (trimmed.contains('\u0000')) {
      throw ArgumentError('Caminho da nota contém caractere nulo inválido.');
    }

    // Rejeita drives Windows (C:\...) ou caminhos iniciados com / ou \
    if (RegExp(r'^[a-zA-Z]:').hasMatch(trimmed) ||
        trimmed.startsWith('/') ||
        trimmed.startsWith(r'\')) {
      throw ArgumentError(
        'Path traversal bloqueado: caminhos absolutos não são permitidos ("$rawRelativePath").',
      );
    }

    final normalizedRel = trimmed.replaceAll(r'\', '/');
    final rawSegments = normalizedRel
        .split('/')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (rawSegments.isEmpty) {
      throw ArgumentError('Caminho da nota inválido.');
    }
    for (final seg in rawSegments) {
      if (seg == '.' || seg == '..' || seg.startsWith('.')) {
        throw ArgumentError(
          'Path traversal ou acesso a arquivo oculto bloqueado: "$rawRelativePath".',
        );
      }
      if (RegExp(r'[:*?"<>|]').hasMatch(seg)) {
        throw ArgumentError(
          'Caractere inválido no caminho da nota: "$rawRelativePath".',
        );
      }
    }

    var safeRel = rawSegments.join(p.separator);
    if (ensureMarkdownExtension && !safeRel.toLowerCase().endsWith('.md')) {
      safeRel = '$safeRel.md';
    }

    final rootNorm = p.normalize(root.absolute.path);
    final candidateNorm = p.normalize(p.join(rootNorm, safeRel));
    if (!p.isWithin(rootNorm, candidateNorm)) {
      throw ArgumentError(
        'Path traversal bloqueado: "$rawRelativePath" está fora do cofre.',
      );
    }
    return File(candidateNorm);
  }

  /// Normaliza o nome de uma pasta do cofre (ex.: `diario` -> `Diario`).
  static String? normalizeFolderFilter(String? folder) {
    final clean = (folder ?? '')
        .trim()
        .replaceAll(r'\', '/')
        .replaceAll(RegExp(r'^/+|/+$'), '');
    if (clean.isEmpty ||
        clean.toLowerCase() == 'all' ||
        clean.toLowerCase() == 'todas' ||
        clean.toLowerCase() == 'todos' ||
        clean == '*') {
      return null;
    }
    if (clean.contains('..') || clean.startsWith('.')) {
      throw ArgumentError('Pasta inválida: "$folder"');
    }
    final lower = clean.toLowerCase();
    return switch (lower) {
      'diario' || 'diário' || 'daily' => 'Diario',
      'memoria' || 'memória' || 'memory' => 'Memoria',
      'inbox' || 'ideias' => 'Inbox',
      'inventario' || 'inventário' || 'garantias' || 'garantia' || 'inventory' =>
        'Inventario',
      'pessoas' || 'pessoa' || 'contatos' || 'people' => 'Pessoas',
      'skills' || 'skill' => 'Skills',
      _ => clean,
    };
  }

  /// Calcula a data do lembrete preventivo (por padrão 15 dias antes do fim da garantia).
  static DateTime computeWarrantyReminderDate({
    required DateTime purchaseDate,
    int warrantyMonths = 12,
    int leadDays = 15,
    int reminderHour = 9,
  }) {
    final totalMonths = purchaseDate.month - 1 + warrantyMonths;
    final expYear = purchaseDate.year + (totalMonths ~/ 12);
    final expMonth = (totalMonths % 12) + 1;
    final lastDayOfMonth = DateTime(expYear, expMonth + 1, 0).day;
    final expDay =
        purchaseDate.day > lastDayOfMonth ? lastDayOfMonth : purchaseDate.day;
    final expiration = DateTime(expYear, expMonth, expDay, reminderHour, 0);
    return expiration.subtract(Duration(days: leadDays));
  }

  /// Gera nota Markdown padronizada para `Inventario/<produto>.md` otimizada para busca FTS5 e OKF.
  static String buildWarrantyNoteMarkdown({
    required String product,
    required DateTime purchaseDate,
    required int warrantyMonths,
    String resetProcedure = 'Consultar manual salvo.',
    String? serialNumber,
    String? vendor,
    int leadDays = 15,
    DateTime? now,
    bool verified = false,
    List<String> sources = const ['arquivo_de_vida'],
    int staleDays = OkfMetadata.defaultStaleDays,
  }) {
    String fmtDate(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final refNow = now ?? DateTime.now();
    final staleAfter = OkfMetadata.computeStaleAfter(refNow, days: staleDays);
    final reminderAt = computeWarrantyReminderDate(
      purchaseDate: purchaseDate,
      warrantyMonths: warrantyMonths,
      leadDays: leadDays,
    );
    final expiration = reminderAt.add(Duration(days: leadDays));
    final renderedSources = sources.isEmpty
        ? '[]'
        : '[${sources.map((s) => s.trim()).where((s) => s.isNotEmpty).join(', ')}]';
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('tipo: garantia')
      ..writeln('produto: "${product.trim()}"')
      ..writeln('data_compra: ${fmtDate(purchaseDate)}')
      ..writeln('garantia_meses: $warrantyMonths')
      ..writeln('garantia_ate: ${fmtDate(expiration)}')
      ..writeln('lembrete_preventivo: ${fmtDate(reminderAt)}')
      ..writeln('sources: $renderedSources')
      ..writeln('verified: $verified')
      ..writeln('stale_after: ${fmtDate(staleAfter)}')
      ..writeln('updated_at: ${refNow.toUtc().toIso8601String()}')
      ..writeln('---')
      ..writeln('# ${product.trim()}')
      ..writeln()
      ..writeln('- **Data de Compra:** ${fmtDate(purchaseDate)}')
      ..writeln('- **Prazo de Garantia:** $warrantyMonths meses (vence em ${fmtDate(expiration)})')
      ..writeln('- **Alerta Preventivo (-$leadDays dias):** ${fmtDate(reminderAt)} 09:00');
    if (vendor != null && vendor.trim().isNotEmpty) {
      buffer.writeln('- **Loja / Fornecedor:** ${vendor.trim()}');
    }
    if (serialNumber != null && serialNumber.trim().isNotEmpty) {
      buffer.writeln('- **Número de Série:** `${serialNumber.trim()}`');
    }
    buffer
      ..writeln()
      ..writeln('## Procedimento de Reset / Manutenção')
      ..writeln(resetProcedure.trim());
    return buffer.toString();
  }

  /// Gera ficha estruturada em `Pessoas/<Nome>.md` separando contexto público de dados privados.
  static String buildPersonProfileMarkdown({
    required String name,
    String? nickname,
    String? relation,
    String? profession,
    String? phone,
    String? email,
    String? address,
    String? interests,
    String? notes,
  }) {
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('tipo: pessoa')
      ..writeln('nome: "${name.trim()}"');
    if (nickname != null && nickname.trim().isNotEmpty) {
      buffer.writeln('apelido: "${nickname.trim()}"');
    }
    if (relation != null && relation.trim().isNotEmpty) {
      buffer.writeln('relacao: "${relation.trim()}"');
    }
    buffer
      ..writeln('---')
      ..writeln('# ${name.trim()}')
      ..writeln();
    if (relation != null && relation.trim().isNotEmpty) {
      buffer.writeln('- **Relação:** ${relation.trim()}');
    }
    if (profession != null && profession.trim().isNotEmpty) {
      buffer.writeln('- **Profissão:** ${profession.trim()}');
    }
    if (interests != null && interests.trim().isNotEmpty) {
      buffer.writeln('- **Preferências / Interesses:** ${interests.trim()}');
    }
    if (notes != null && notes.trim().isNotEmpty) {
      buffer.writeln('- **Contexto:** ${notes.trim()}');
    }
    if ((phone?.trim().isNotEmpty ?? false) ||
        (email?.trim().isNotEmpty ?? false) ||
        (address?.trim().isNotEmpty ?? false)) {
      buffer
        ..writeln()
        ..writeln('## Dados Privados (Filtrados de APIs Externas)');
      if (phone != null && phone.trim().isNotEmpty) {
        buffer.writeln('- **Telefone:** ${phone.trim()}');
      }
      if (email != null && email.trim().isNotEmpty) {
        buffer.writeln('- **E-mail:** ${email.trim()}');
      }
      if (address != null && address.trim().isNotEmpty) {
        buffer.writeln('- **Endereço:** ${address.trim()}');
      }
    }
    return buffer.toString();
  }

  static final RegExp _privateFieldLineRegex = RegExp(
    r'^\s*[-*]?\s*(?:\*\*)?(?:telefone|celular|whatsapp|e-?mail|endere[cç]o|cpf|rg|cep|biometria)(?:\*\*)?\s*:',
    caseSensitive: false,
  );
  static final RegExp _emailInlineRegex = RegExp(
    r'\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b',
  );
  static final RegExp _cpfInlineRegex = RegExp(
    r'\b\d{3}\.\d{3}\.\d{3}-\d{2}\b',
  );
  static final RegExp _brPhoneInlineRegex = RegExp(
    r'(?:\+?55\s*)?(?:\(?\d{2}\)?\s*)?(?:9\d{4}|\d{4})[-\s]\d{4}\b',
  );

  /// Filtro de privacidade (Marco 4 — v1.9.0): remove linhas de dados sensíveis
  /// e redige telefones, e-mails e CPFs antes de injetar notas do Obsidian em APIs externas.
  static String sanitizeForExternalAi(String rawContent) {
    if (rawContent.trim().isEmpty) return rawContent;
    final outLines = <String>[];
    for (final line in rawContent.split('\n')) {
      if (_privateFieldLineRegex.hasMatch(line)) {
        continue;
      }
      var clean = line.replaceAll(_emailInlineRegex, '[email ocultado]');
      clean = clean.replaceAll(_cpfInlineRegex, '[cpf ocultado]');
      clean = clean.replaceAll(_brPhoneInlineRegex, '[telefone ocultado]');
      outLines.add(clean);
    }
    return outLines.join('\n').trim();
  }

  /// OBSIDIAN_LIST: Lista notas Markdown do cofre, opcionalmente filtradas por pasta
  /// (`Diario/`, `Memoria/`, `Inbox/`, `Skills/`).
  Future<List<ObsidianNoteSummary>> listNotes({String? folder}) async {
    final normalizedFolder = normalizeFolderFilter(folder);
    final targetDir = normalizedFolder == null
        ? root
        : Directory(p.join(root.path, normalizedFolder));

    final rootNorm = p.normalize(root.absolute.path);
    final targetNorm = p.normalize(targetDir.absolute.path);
    if (normalizedFolder != null && !p.isWithin(rootNorm, targetNorm)) {
      throw ArgumentError('Path traversal bloqueado na pasta: "$folder".');
    }
    if (!await targetDir.exists()) return const [];

    final notes = <ObsidianNoteSummary>[];
    await for (final entity in targetDir.list(recursive: true)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.md')) {
        continue;
      }
      final rel = p
          .relative(entity.path, from: root.path)
          .replaceAll(r'\', '/');
      final parts = rel.split('/');
      if (parts.any((s) => s.startsWith('.'))) continue;

      try {
        final stat = await entity.stat();
        final content = await entity.readAsString();
        final parsed = OkfMetadata.parse(content);
        final title = _extractNoteTitle(rel, content);
        final folderName = parts.length > 1 ? parts.first : '';
        notes.add(
          ObsidianNoteSummary(
            relativePath: rel,
            folder: folderName,
            title: title,
            sizeBytes: stat.size,
            modifiedAt: stat.modified,
            okf: parsed.metadata,
          ),
        );
      } catch (_) {}
    }

    notes.sort((a, b) {
      final cmp = b.modifiedAt.compareTo(a.modifiedAt);
      return cmp != 0 ? cmp : a.relativePath.compareTo(b.relativePath);
    });
    return notes;
  }

  /// OBSIDIAN_READ: Lê o conteúdo de uma nota específica com sanitização estrita
  /// contra path traversal. Se o caminho direto não existir, também procura correspondência
  /// pelo nome do arquivo dentro das pastas padrão (`Diario/`, `Memoria/`, `Inbox/`, `Skills/`).
  Future<String> readNote(String notePath) async {
    final file = await _resolveExistingOrTargetNote(
      notePath,
      mustExist: true,
    );
    return file.readAsString();
  }

  /// OBSIDIAN_APPEND: Anexa texto a uma nota existente (ou cria a nota caso [createIfMissing] seja true),
  /// gravando snapshot prévio na pilha de UNDO e aplicando frontmatter OKF em notas de contexto.
  Future<File> appendToNote(
    String notePath,
    String text, {
    bool createIfMissing = false,
    DateTime? now,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      throw ArgumentError('Texto para anexar não pode ser vazio.');
    }
    final file = await _resolveExistingOrTargetNote(
      notePath,
      mustExist: !createIfMissing,
    );
    await file.parent.create(recursive: true);
    await _pushSnapshotForFile(file, operation: 'OBSIDIAN_APPEND');
    final refNow = now ?? DateTime.now();
    final relPath = p
        .relative(file.path, from: root.path)
        .replaceAll(r'\', '/');
    if (await file.exists()) {
      final current = await file.readAsString();
      final prefix = current.isEmpty || current.endsWith('\n') ? '' : '\n';
      final doc = OkfMetadata.parse(current);
      if (doc.metadata.hasFrontmatter) {
        final combined = '$current$prefix$cleanText\n';
        await file.writeAsString(
          OkfMetadata.upsertFrontmatter(
            combined,
            (meta) => meta.copyWith(updatedAt: refNow.toUtc()),
          ),
        );
      } else {
        await file.writeAsString('$prefix$cleanText\n', mode: FileMode.append);
      }
    } else {
      if (cleanText.startsWith('---\n') || cleanText.startsWith('---\r\n')) {
        await file.writeAsString('$cleanText\n');
      } else if (OkfMetadata.isContextNotePath(relPath)) {
        final title = p.basenameWithoutExtension(file.path);
        final header = OkfMetadata.renderFrontmatter(
          OkfMetadata(
            sources: const ['obsidian_append'],
            verified: false,
            staleAfter: OkfMetadata.computeStaleAfter(refNow),
            updatedAt: refNow.toUtc(),
            hasFrontmatter: true,
          ),
        );
        final body = cleanText.startsWith('#')
            ? '$cleanText\n'
            : '# $title\n\n$cleanText\n';
        await file.writeAsString('$header\n$body');
      } else {
        final title = p.basenameWithoutExtension(file.path);
        await file.writeAsString('# $title\n\n$cleanText\n');
      }
    }
    return file;
  }

  /// OKF: Marca uma nota como verificada (ou rejeita verificação) e renova `stale_after` / `updated_at`,
  /// gravando snapshot na pilha de UNDO.
  Future<OkfNoteStatus> verifyNote(
    String notePath, {
    bool verified = true,
    int renewDays = OkfMetadata.defaultStaleDays,
    DateTime? staleAfter,
    List<String>? addSources,
    DateTime? now,
  }) async {
    final file = await _resolveExistingOrTargetNote(
      notePath,
      mustExist: true,
    );
    await _pushSnapshotForFile(file, operation: 'OBSIDIAN_VERIFY');
    final refNow = now ?? DateTime.now();
    final nextStaleAfter =
        staleAfter ?? OkfMetadata.computeStaleAfter(refNow, days: renewDays);
    final raw = await file.readAsString();
    final updated = OkfMetadata.upsertFrontmatter(raw, (current) {
      final merged = <String>{
        ...current.sources,
        if (addSources != null)
          ...addSources.map((s) => s.trim()).where((s) => s.isNotEmpty),
      };
      if (verified && merged.isEmpty) {
        merged.add('revisao_humana');
      }
      return current.copyWith(
        sources: merged.toList(growable: false),
        verified: verified,
        staleAfter: nextStaleAfter,
        updatedAt: refNow.toUtc(),
        hasFrontmatter: true,
      );
    });
    await file.writeAsString(updated);
    final rel = p.relative(file.path, from: root.path).replaceAll(r'\', '/');
    final parsed = OkfMetadata.parse(updated);
    return OkfNoteStatus(
      relativePath: rel,
      title: _extractNoteTitle(rel, updated),
      metadata: parsed.metadata,
      isStale: parsed.metadata.isStale(now: refNow),
      isUnverified: !parsed.metadata.isVerified,
    );
  }

  /// Lista notas com `stale_after < hoje` (vencidas para revisão OKF).
  Future<List<OkfNoteStatus>> listStaleNotes({
    DateTime? now,
    bool onlyContextFolders = false,
  }) async {
    final refNow = now ?? DateTime.now();
    final notes = await listNotes();
    final stale = <OkfNoteStatus>[];
    for (final n in notes) {
      if (onlyContextFolders && !OkfMetadata.isContextNotePath(n.relativePath)) {
        continue;
      }
      final meta = n.okf;
      if (meta == null || !meta.isStale(now: refNow)) continue;
      stale.add(
        OkfNoteStatus(
          relativePath: n.relativePath,
          title: n.title,
          metadata: meta,
          isStale: true,
          isUnverified: !meta.isVerified,
        ),
      );
    }
    stale.sort((a, b) {
      final da = a.metadata.staleAfter;
      final db = b.metadata.staleAfter;
      if (da != null && db != null) {
        final cmp = da.compareTo(db);
        if (cmp != 0) return cmp;
      }
      return a.relativePath.compareTo(b.relativePath);
    });
    return stale;
  }

  /// Lista notas de contexto (`Memoria/`, `Inventario/`, `Preferencias.md`) sem verificação humana.
  Future<List<OkfNoteStatus>> listUnverifiedContextNotes({DateTime? now}) async {
    final refNow = now ?? DateTime.now();
    final notes = await listNotes();
    final unverified = <OkfNoteStatus>[];
    for (final n in notes) {
      if (!OkfMetadata.isContextNotePath(n.relativePath)) continue;
      final meta = n.okf ?? const OkfMetadata();
      if (meta.isVerified) continue;
      unverified.add(
        OkfNoteStatus(
          relativePath: n.relativePath,
          title: n.title,
          metadata: meta,
          isStale: meta.isStale(now: refNow),
          isUnverified: true,
        ),
      );
    }
    return unverified;
  }

  static final RegExp _taskLineRegex = RegExp(
    r'^(\s*[-*]\s+\[)([ xX])(\]\s+)(.+)$',
  );

  /// OBSIDIAN_TASKS (listagem): Lista checkboxes Markdown (`- [ ]` / `- [x]`)
  /// de uma nota específica ou de todo o cofre.
  Future<List<ObsidianTaskItem>> listTasks({
    String? notePath,
    bool? onlyCompleted,
  }) async {
    final files = <File>[];
    if (notePath != null && notePath.trim().isNotEmpty) {
      final single = await _resolveExistingOrTargetNote(
        notePath,
        mustExist: true,
      );
      files.add(single);
    } else {
      final summaries = await listNotes();
      for (final s in summaries) {
        files.add(resolveSafeNoteFile(s.relativePath));
      }
    }

    final tasks = <ObsidianTaskItem>[];
    var runningIndex = 1;
    for (final file in files) {
      if (!await file.exists()) continue;
      final rel = p
          .relative(file.path, from: root.path)
          .replaceAll(r'\', '/');
      final lines = await file.readAsLines();
      for (var i = 0; i < lines.length; i++) {
        final match = _taskLineRegex.firstMatch(lines[i]);
        if (match == null) continue;
        final isDone = match.group(2)!.toLowerCase() == 'x';
        if (onlyCompleted != null && isDone != onlyCompleted) {
          continue;
        }
        tasks.add(
          ObsidianTaskItem(
            index: runningIndex++,
            relativePath: rel,
            lineNumber: i + 1,
            text: match.group(4)!.trim(),
            completed: isDone,
          ),
        );
      }
    }
    return tasks;
  }

  /// OBSIDIAN_TASKS (marcação/desmarcação): Marca ou desmarca uma tarefa Markdown
  /// (`- [ ]` <-> `- [x]`) por índice (1-based) ou trecho do texto da tarefa.
  Future<ObsidianTaskItem> setTaskCompletion({
    String? notePath,
    int? taskIndex,
    String? queryText,
    bool? completed,
  }) async {
    final allTasks = await listTasks(notePath: notePath);
    if (allTasks.isEmpty) {
      throw StateError('Nenhuma tarefa Markdown (- [ ] / - [x]) encontrada.');
    }

    ObsidianTaskItem? target;
    if (taskIndex != null) {
      for (final t in allTasks) {
        if (t.index == taskIndex) {
          target = t;
          break;
        }
      }
    }
    final cleanQuery = (queryText ?? '').trim().toLowerCase();
    if (target == null && cleanQuery.isNotEmpty) {
      final asIndex = int.tryParse(cleanQuery);
      if (asIndex != null) {
        for (final t in allTasks) {
          if (t.index == asIndex) {
            target = t;
            break;
          }
        }
      }
      if (target == null) {
        for (final t in allTasks) {
          if (t.text.toLowerCase().contains(cleanQuery)) {
            target = t;
            break;
          }
        }
      }
    }

    if (target == null) {
      throw ArgumentError(
        'Tarefa não encontrada (${taskIndex ?? queryText ?? ''}).',
      );
    }

    final file = resolveSafeNoteFile(target.relativePath);
    await _pushSnapshotForFile(file, operation: 'OBSIDIAN_TASKS');
    final rawContent = await file.readAsString();
    final usesCrLf = rawContent.contains('\r\n');
    final lines = rawContent.split(RegExp(r'\r?\n'));
    final lineIdx = target.lineNumber - 1;
    if (lineIdx < 0 || lineIdx >= lines.length) {
      throw StateError('Linha da tarefa fora de sincronia.');
    }

    final match = _taskLineRegex.firstMatch(lines[lineIdx]);
    if (match == null) {
      throw StateError('A linha selecionada não contém um checkbox Markdown.');
    }

    final nextState = completed ?? !target.completed;
    final mark = nextState ? 'x' : ' ';
    lines[lineIdx] = '${match.group(1)}$mark${match.group(3)}${match.group(4)}';
    await file.writeAsString(lines.join(usesCrLf ? '\r\n' : '\n'));

    return ObsidianTaskItem(
      index: target.index,
      relativePath: target.relativePath,
      lineNumber: target.lineNumber,
      text: target.text,
      completed: nextState,
    );
  }

  /// OBSIDIAN_STATUS: Retorna estatísticas completas do cofre (contagem de notas,
  /// tamanho em bytes, caminho ativo, engine [VaultSearchEngine] e profundidade do UNDO).
  Future<ObsidianVaultStatus> getVaultStatus({
    VaultSearchEngine searchEngine = VaultSearchEngine.fts5,
  }) async {
    await _loadUndoStackIfNeeded();
    final notes = await listNotes();
    final counts = <String, int>{
      for (final f in standardFolders) f: 0,
    };
    var totalBytes = 0;
    for (final n in notes) {
      totalBytes += n.sizeBytes;
      final key = n.folder.isEmpty ? 'Raiz' : n.folder;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return ObsidianVaultStatus(
      vaultPath: vaultPath,
      vaultName: vaultName,
      totalNotes: notes.length,
      totalSizeBytes: totalBytes,
      countsByFolder: counts,
      searchEngine: searchEngine,
      undoDepth: _undoStack.length,
    );
  }

  /// Quantidade de snapshots disponíveis na pilha de desfazer (`UNDO`).
  Future<int> getUndoDepth() async {
    await _loadUndoStackIfNeeded();
    return _undoStack.length;
  }

  /// Desfaz a última operação mutável no cofre (`OBSIDIAN_APPEND`, `NOTE`, `INBOX`, `REMEMBER`, `OBSIDIAN_TASKS`).
  Future<ObsidianUndoResult> undoLastMutation() async {
    await _loadUndoStackIfNeeded();
    if (_undoStack.isEmpty) {
      return const ObsidianUndoResult(
        undone: false,
        operation: 'NONE',
        relativePath: '',
        deletedCreatedFile: false,
        message: 'Nenhuma alteração recente no cofre Obsidian para desfazer.',
      );
    }

    final snap = _undoStack.removeLast();
    await _persistUndoStack();
    final file = resolveSafeNoteFile(snap.relativePath);

    if (!snap.existedBefore) {
      if (await file.exists()) {
        await file.delete();
      }
      return ObsidianUndoResult(
        undone: true,
        operation: snap.operation,
        relativePath: snap.relativePath,
        deletedCreatedFile: true,
        message:
            '↩️ Desfeito (${snap.operation}): arquivo criado "${snap.relativePath}" foi removido.',
      );
    } else {
      await file.parent.create(recursive: true);
      await file.writeAsString(snap.previousContent ?? '');
      return ObsidianUndoResult(
        undone: true,
        operation: snap.operation,
        relativePath: snap.relativePath,
        deletedCreatedFile: false,
        message:
            '↩️ Desfeito (${snap.operation}): conteúdo anterior de "${snap.relativePath}" restaurado.',
      );
    }
  }

  Future<File> _resolveExistingOrTargetNote(
    String rawPath, {
    required bool mustExist,
  }) async {
    final direct = resolveSafeNoteFile(rawPath);
    if (await direct.exists()) return direct;

    // Se o usuário informou apenas o nome da nota sem a pasta (ex: "Operador"),
    // verifica se já existe em alguma das pastas padrão dentro do root.
    final normalized = rawPath.trim().replaceAll(r'\', '/');
    if (!normalized.contains('/')) {
      for (final folder in standardFolders) {
        final candidate = resolveSafeNoteFile('$folder/$normalized');
        if (await candidate.exists()) {
          return candidate;
        }
      }
      // Match case-insensitive nas notas existentes
      final all = await listNotes();
      final targetBase = p
          .basenameWithoutExtension(direct.path)
          .toLowerCase();
      for (final n in all) {
        if (p.basenameWithoutExtension(n.relativePath).toLowerCase() ==
                targetBase ||
            n.title.toLowerCase() == targetBase) {
          return resolveSafeNoteFile(n.relativePath);
        }
      }
    }

    if (mustExist) {
      throw FileSystemException('Nota não encontrada no cofre', rawPath);
    }
    return direct;
  }

  File get _undoStackFile =>
      File(p.join(root.path, '.obsidian', _undoStackFilename));

  Future<void> _loadUndoStackIfNeeded() async {
    if (_undoLoaded) return;
    _undoLoaded = true;
    try {
      final f = _undoStackFile;
      if (!await f.exists()) return;
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _undoStack
          ..clear()
          ..addAll(
            decoded
                .whereType<Map<String, dynamic>>()
                .map(ObsidianSnapshot.fromJson),
          );
      }
    } catch (_) {}
  }

  Future<void> _persistUndoStack() async {
    try {
      final f = _undoStackFile;
      await f.parent.create(recursive: true);
      final encoded = jsonEncode(_undoStack.map((s) => s.toJson()).toList());
      await f.writeAsString(encoded);
    } catch (_) {}
  }

  Future<void> _pushSnapshotForFile(
    File file, {
    required String operation,
  }) async {
    await _loadUndoStackIfNeeded();
    final rel = p
        .relative(file.path, from: root.path)
        .replaceAll(r'\', '/');
    final exists = await file.exists();
    String? prevContent;
    if (exists) {
      try {
        prevContent = await file.readAsString();
      } catch (_) {
        prevContent = '';
      }
    }
    _undoStack.add(
      ObsidianSnapshot(
        operation: operation,
        relativePath: rel,
        existedBefore: exists,
        previousContent: prevContent,
        timestampIso: DateTime.now().toUtc().toIso8601String(),
      ),
    );
    while (_undoStack.length > maxUndoDepth) {
      _undoStack.removeAt(0);
    }
    await _persistUndoStack();
  }

  static String _extractNoteTitle(String relPath, String content) {
    final body = OkfMetadata.parse(content).body;
    for (final line in body.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('#')) {
        final heading = trimmed.replaceFirst(RegExp(r'^#+\s*'), '').trim();
        if (heading.isNotEmpty) return heading;
      }
    }
    return p.basenameWithoutExtension(relPath);
  }
}
