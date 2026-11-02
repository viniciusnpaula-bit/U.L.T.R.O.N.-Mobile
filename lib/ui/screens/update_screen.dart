import 'package:flutter/material.dart';
import '../../services/app_update_service.dart';

class UpdateScreen extends StatefulWidget {
  const UpdateScreen({super.key});
  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  final service = AppUpdateService();
  UpdateInfo? update;
  String status = 'Verifique se existe uma versão publicada no GitHub.';
  String currentVersion = '';
  bool checking = false, downloading = false;
  double progress = 0;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try { currentVersion = await service.currentVersion(); if (mounted) setState(() {}); }
    catch (_) { currentVersion = 'indisponível'; if (mounted) setState(() {}); }
  }

  Future<void> _check() async {
    setState(() { checking = true; status = 'Consultando GitHub Releases…'; update = null; });
    try {
      final result = await service.check();
      if (!mounted) return;
      setState(() {
        update = result;
        status = result == null
            ? 'Nenhuma release pública com APK foi encontrada. Publique uma release no GitHub com o arquivo APK anexado.'
            : 'Versão disponível: ${result.version}. Confirme para baixar e abrir o instalador Android.';
      });
    } catch (e) {
      if (mounted) setState(() => status = 'Não foi possível verificar atualização: $e');
    } finally { if (mounted) setState(() => checking = false); }
  }

  Future<void> _download() async {
    final candidate = update;
    if (candidate == null) return;
    setState(() { downloading = true; progress = 0; status = 'Baixando APK…'; });
    try {
      await service.downloadAndInstall(candidate, (value) { if (mounted) setState(() => progress = value); });
      if (mounted) setState(() => status = 'Download concluído. O Android abriu o instalador; confirme a instalação na tela do sistema.');
    } catch (e) {
      if (mounted) setState(() => status = 'Falha no download/instalador: $e');
    } finally { if (mounted) setState(() => downloading = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Atualização do U.L.T.R.O.N.')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Icon(Icons.system_update, size: 72, color: Color(0xFFE50914)),
      const SizedBox(height: 16),
      Text('Versão instalada: ${currentVersion.isEmpty ? '…' : currentVersion}', textAlign: TextAlign.center),
      const SizedBox(height: 20),
      FilledButton.icon(onPressed: checking || downloading ? null : _check, icon: const Icon(Icons.search), label: Text(checking ? 'Verificando…' : 'Verificar atualização')),
      if (update != null) ...[
        const SizedBox(height: 12),
        Card(child: ListTile(leading: const Icon(Icons.download), title: Text('Release ${update!.version}'), subtitle: Text(update!.name))),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: downloading ? null : _download, icon: const Icon(Icons.install_mobile), label: const Text('Baixar e abrir instalador')),
      ],
      if (downloading) ...[
        const SizedBox(height: 16),
        LinearProgressIndicator(value: progress > 0 ? progress : null),
        Text('${(progress * 100).toStringAsFixed(0)}%', textAlign: TextAlign.center),
      ],
      const SizedBox(height: 20),
      Text(status),
      const SizedBox(height: 16),
      const Text('As atualizações são obtidas de GitHub Releases públicas. O Android sempre solicita confirmação para instalar. Para atualizar, a release precisa conter um APK anexado.'),
    ]),
  );
}
