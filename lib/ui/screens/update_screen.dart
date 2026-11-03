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
  String installed = '';
  String status = '';
  bool checking = false, downloading = false, checked = false;
  double progress = 0;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      checking = true;
      update = null;
      progress = 0;
      status = 'Consultando GitHub Releases…';
    });
    try {
      installed = await service.currentVersion();
      final latest = await service.check();
      if (!mounted) return;
      setState(() {
        checked = true;
        if (latest == null) {
          status = 'Nenhuma release pública com APK foi encontrada. Publique uma release no GitHub com o arquivo APK anexado.';
        } else if (AppUpdateService.isNewer(latest.version, installed)) {
          update = latest;
          status = 'Versão ${latest.version} disponível (instalada: $installed).';
        } else {
          status = 'Você já está na versão mais recente ($installed).';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        checked = true;
        status = 'Não foi possível verificar atualização: $e';
      });
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> _download() async {
    final candidate = update;
    if (candidate == null) return;
    setState(() {
      downloading = true;
      progress = 0;
      status = 'Baixando APK…';
    });
    try {
      await service.downloadAndInstall(candidate, (value) {
        if (mounted) setState(() => progress = value);
      });
      if (mounted) {
        setState(() => status = 'Download concluído. O Android abriu o instalador; confirme a instalação na tela do sistema.');
      }
    } catch (e) {
      if (mounted) setState(() => status = 'Falha no download/instalador: $e');
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = checking
        ? Icons.cloud_download
        : update != null
            ? Icons.new_releases
            : Icons.verified_user;
    return Scaffold(
      appBar: AppBar(title: const Text('Atualização do U.L.T.R.O.N.')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(icon, size: 72, color: const Color(0xFFE50914)),
          const SizedBox(height: 16),
          Text(
            'Versão instalada: ${installed.isEmpty ? '…' : installed}',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          if (checking) const LinearProgressIndicator(),
          if (update != null) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.download),
                title: Text('Release ${update!.version}'),
                subtitle: Text(update!.name),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: downloading ? null : _download,
              icon: const Icon(Icons.install_mobile),
              label: const Text('Baixar e abrir instalador'),
            ),
          ],
          if (downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: progress > 0 ? progress : null),
            Text(
              '${(progress * 100).toStringAsFixed(0)}%',
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 20),
          Text(status, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: checking || downloading ? null : _check,
            icon: const Icon(Icons.refresh),
            label: Text(checked ? 'Verificar novamente' : 'Verificar atualização'),
          ),
          const SizedBox(height: 16),
          const Text('As atualizações são obtidas de GitHub Releases públicas. O Android sempre solicita confirmação para instalar. Para atualizar, a release precisa conter um APK anexado.'),
        ],
      ),
    );
  }
}
