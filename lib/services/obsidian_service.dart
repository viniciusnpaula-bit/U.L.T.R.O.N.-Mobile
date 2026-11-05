import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
  ObsidianService(this.root);

  final Directory root;

  static const _storageVaultKey = 'ultron.obsidian.custom_vault_path.v1';

  /// Abre o cofre do Obsidian. Prioriza diretórios acessíveis pelo app oficial
  /// do Obsidian no Android (`/storage/emulated/0/Documents/ULTRON-Vault`),
  /// com suporte a caminho customizado e fallback transparente.
  static Future<ObsidianService> openDefaultVault({
    FlutterSecureStorage? storage,
  }) async {
    final secStorage = storage ?? const FlutterSecureStorage();

    // 1. Caminho customizado configurado pelo usuário
    try {
      final customPath = await secStorage.read(key: _storageVaultKey);
      if (customPath != null && customPath.trim().isNotEmpty) {
        final customDir = Directory(customPath.trim());
        if (await customDir.exists()) {
          final s = ObsidianService(customDir);
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

          final service = ObsidianService(dir);
          await service.initialize();
          return service;
        } catch (_) {
          // Sem permissão de escrita pública, continua para o próximo fallback
        }
      }
    }

    // 3. Fallback: pasta de documentos da aplicação
    final docs = await getApplicationDocumentsDirectory();
    final service = ObsidianService(Directory(p.join(docs.path, 'ULTRON-Vault')));
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
    final skillsDir = Directory(p.join(root.path, 'Skills'));
    await skillsDir.create(recursive: true);

    // Semeia arquivos essenciais para o app oficial Obsidian reconhecer o cofre
    await _seedObsidianConfig();
    await _seedSecondBrainIndex();
    await _seedOperatorMemory();
    await _seedDefaultSkills(skillsDir);
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
      await indexFile.writeAsString(
        '# Segundo Cérebro (U.L.T.R.O.N.)\n\n'
        'Este cofre é a memória persistente e expandida do assistente U.L.T.R.O.N., '
        'sincronizado nativamente com o aplicativo Obsidian.\n\n'
        '## Estrutura do Conhecimento\n'
        '- **[[Memoria/Operador|Perfil do Operador]]**: Informações e diretrizes do usuário.\n'
        '- **[[Diario/]]**: Notas temporais e reflexões diárias automáticas.\n'
        '- **[[Inbox/]]**: Caixa de entrada de pensamentos e ideias capturadas.\n'
        '- **[[Skills/]]**: Procedimentos e habilidades táticas executáveis.\n\n'
        '---\n*Gerado automaticamente pelo U.L.T.R.O.N. Mobile v1.2.1*\n',
      );
    }
  }

  Future<void> _seedOperatorMemory() async {
    final opFile = File(p.join(root.path, 'Memoria', 'Operador.md'));
    if (!await opFile.exists()) {
      await opFile.writeAsString(
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
    };
    for (final entry in defaults.entries) {
      final file = File(p.join(skillsDir.path, '${entry.key}.md'));
      if (!await file.exists()) {
        await file.writeAsString(entry.value);
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
    await file.writeAsString(
      '# Ideia Capturada\n\n'
      '- Data: ${now.toLocal()}\n'
      '- Conteúdo: $clean\n',
    );
    return file;
  }

  /// Salva ou atualiza um tópico de memória permanente em `Memoria/$topic.md`.
  Future<File> saveMemory(String topic, String content) async {
    final cleanTopic = topic
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim();
    if (cleanTopic.isEmpty) throw ArgumentError('Tópico inválido');
    final file = File(p.join(root.path, 'Memoria', '$cleanTopic.md'));
    final now = DateTime.now();
    if (await file.exists()) {
      await file.writeAsString(
        '\n\n## Atualização (${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')})\n$content\n',
        mode: FileMode.append,
      );
    } else {
      await file.writeAsString(
        '# $cleanTopic\n\n- Criado em: ${now.toLocal()}\n\n$content\n',
      );
    }
    return file;
  }

  /// Lê a memória de longo prazo para injeção contextual no prompt do LLM.
  Future<String> readLongTermMemory({int maxChars = 2000}) async {
    final buffer = StringBuffer();

    // 1. Perfil do Operador
    final opFile = File(p.join(root.path, 'Memoria', 'Operador.md'));
    if (await opFile.exists()) {
      final content = await opFile.readAsString();
      if (content.trim().isNotEmpty) {
        buffer.writeln('### Perfil do Operador:');
        buffer.writeln(content.trim());
      }
    }

    // 2. Preferências
    final prefFile = File(p.join(root.path, 'Preferencias.md'));
    if (await prefFile.exists()) {
      final pref = await prefFile.readAsString();
      if (pref.trim().isNotEmpty) {
        buffer.writeln('\n### Preferências:');
        buffer.writeln(pref.trim());
      }
    }

    // 3. Resumo da Nota do Dia Atual
    final now = DateTime.now();
    final todayNote = await readDailyNote(now);
    if (todayNote.trim().isNotEmpty) {
      final lines = todayNote.trim().split('\n');
      final recent = lines.reversed.take(6).toList().reversed.join('\n');
      buffer.writeln('\n### Registros Recentes de Hoje (${now.day}/${now.month}):');
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
    await file.writeAsString('# $clean\n\n$body\n');
    return file;
  }

  Future<List<MobileSkill>> listSkills() async {
    final skillsDir = Directory(p.join(root.path, 'Skills'));
    if (!await skillsDir.exists()) return const [];
    final entities = await skillsDir.list().toList();
    final skills = <MobileSkill>[];
    for (final entity in entities) {
      if (entity is File && entity.path.toLowerCase().endsWith('.md')) {
        final id = p.basenameWithoutExtension(entity.path);
        final content = await entity.readAsString();
        final firstLine = content
            .split('\n')
            .firstWhere((l) => l.trim().isNotEmpty, orElse: () => id)
            .replaceFirst(RegExp(r'^#+\s*'), '')
            .trim();
        skills.add(MobileSkill(id: id, title: firstLine, content: content));
      }
    }
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
}
