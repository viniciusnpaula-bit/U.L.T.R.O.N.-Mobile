import 'dart:io';

import 'package:path/path.dart' as p;

class ObsidianService {
  ObsidianService(this.root);

  final Directory root;

  Future<void> initialize() async {
    await root.create(recursive: true);
    await Directory(p.join(root.path, 'Diario')).create(recursive: true);
  }

  Future<String> readPreferences() async {
    final file = File(p.join(root.path, 'Preferencias.md'));
    if (!await file.exists()) return '';
    return file.readAsString();
  }

  Future<File> dailyNote(DateTime now, String text) async {
    final day =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final file = File(p.join(root.path, 'Diario', '$day.md'));
    await file.parent.create(recursive: true);
    if (!await file.exists()) await file.writeAsString('# $day\n');
    if (text.trim().isNotEmpty) {
      await file.writeAsString(
        '\n- ${now.toIso8601String()}: $text\n',
        mode: FileMode.append,
      );
    }
    return file;
  }

  Future<File> quickNote(String title, String body) async {
    final clean = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (clean.isEmpty || clean == '.' || clean == '..') {
      throw ArgumentError('Título inválido');
    }
    final file = File(p.join(root.path, '$clean.md'));
    await file.writeAsString('# $clean\n\n$body\n');
    return file;
  }
}
