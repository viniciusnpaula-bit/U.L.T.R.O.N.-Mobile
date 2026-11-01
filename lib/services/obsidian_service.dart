import 'dart:io';
import 'package:path/path.dart' as p;
class ObsidianService { ObsidianService(this.root); final Directory root;
 Future<void> initialize() async {await root.create(recursive:true);await Directory(p.join(root.path,'Diario')).create(recursive:true);}
 Future<String> readPreferences() async {final f=File(p.join(root.path,'Preferencias.md'));return await f.exists()?f.readAsString():'';}
 Future<File> dailyNote(DateTime now,String text) async {final day='${now.year.toString().padLeft(4,'0')}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';final f=File(p.join(root.path,'Diario','$day.md'));await f.parent.create(recursive:true);if(!await f.exists())await f.writeAsString('# $day\n');if(text.trim().isNotEmpty)await f.writeAsString('\n- ${now.toIso8601String()}: $text\n',mode:FileMode.append);return f;}
 Future<File> quickNote(String title,String body) async {final clean=title.replaceAll(RegExp(r'[\\/:*?"<>|]'),'_').trim();if(clean.isEmpty||clean=='.'||clean=='..')throw ArgumentError('Título inválido');final f=File(p.join(root.path,'$clean.md'));await f.writeAsString('# $clean\n\n$body\n');return f;}
}
