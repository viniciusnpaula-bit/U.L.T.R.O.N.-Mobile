import 'dart:io';

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

class ObsidianService {
  ObsidianService(this.root);

  final Directory root;

  static Future<ObsidianService> openDefaultVault() async {
    final docs = await getApplicationDocumentsDirectory();
    final service = ObsidianService(Directory(p.join(docs.path, 'ULTRON-Vault')));
    await service.initialize();
    return service;
  }

  Future<void> initialize() async {
    await root.create(recursive: true);
    await Directory(p.join(root.path, 'Diario')).create(recursive: true);
    final skillsDir = Directory(p.join(root.path, 'Skills'));
    await skillsDir.create(recursive: true);
    await _seedDefaultSkills(skillsDir);
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
