import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/app_update_service.dart';

class UpdateScreen extends StatefulWidget {
  const UpdateScreen({super.key});

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  static const _crimson = Color(0xFFFF1A24);
  static const _rose = Color(0xFFFF8088);
  static const _border = Color(0xFF2E0306);

  final service = AppUpdateService();
  UpdateInfo? update;
  String installed = '';
  String status = '';
  bool checking = false;
  bool downloading = false;
  bool checked = false;
  double progress = 0;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    HapticFeedback.lightImpact();
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
          status =
              'Nenhuma release pública com APK foi encontrada. Publique uma release no GitHub com o arquivo APK anexado.';
        } else if (AppUpdateService.isNewer(latest.version, installed)) {
          update = latest;
          status =
              'Versão ${latest.version} disponível (instalada: $installed).';
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
    HapticFeedback.mediumImpact();
    setState(() {
      downloading = true;
      progress = 0;
      status = 'Baixando pacote APK assinado…';
    });
    try {
      await service.downloadAndInstall(candidate, (value) {
        if (mounted) setState(() => progress = value);
      });
      if (mounted) {
        setState(() => status =
            'Download concluído. O Android abriu o instalador; confirme a instalação na tela do sistema.');
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
        ? Icons.cloud_download_outlined
        : update != null
            ? Icons.new_releases_outlined
            : Icons.verified_user_outlined;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0002),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.only(bottom: 10),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: _border)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Row(
                        children: [
                          Icon(Icons.arrow_back, size: 15, color: _crimson),
                          SizedBox(width: 4),
                          Text(
                            'VOLTAR',
                            style: TextStyle(
                              color: _crimson,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Row(
                      children: [
                        Icon(
                          Icons.cloud_download_outlined,
                          size: 15,
                          color: Colors.white,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'ATUALIZADOR GITHUB',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  children: [
                    Icon(icon, size: 64, color: _crimson),
                    const SizedBox(height: 14),
                    Text(
                      'VERSÃO INSTALADA: ${installed.isEmpty ? '…' : 'v$installed'}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _rose,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Repositório: viniciusnpaula-bit/U.L.T.R.O.N.-Mobile',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (checking)
                      const LinearProgressIndicator(color: _crimson),
                    if (update != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF180004),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _crimson.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '✓ Nova Versão Encontrada: ${update!.version}',
                              style: const TextStyle(
                                color: Color(0xFF34D399),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              update!.name,
                              style: const TextStyle(
                                color: Color(0xFFE2E8F0),
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: downloading ? null : _download,
                                style: FilledButton.styleFrom(
                                  backgroundColor: _crimson,
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: const Icon(Icons.install_mobile, size: 16),
                                label: const Text(
                                  'BAIXAR APK E ABRIR INSTALADOR',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (downloading) ...[
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        color: _crimson,
                        value: progress > 0 ? progress : null,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${(progress * 100).toStringAsFixed(0)}%',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _crimson,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E0002),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _border),
                      ),
                      child: Text(
                        status,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: checking || downloading ? null : _check,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _crimson,
                        backgroundColor: const Color(0xFF1E0004),
                        side: BorderSide(
                          color: _crimson.withValues(alpha: 0.35),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.refresh, size: 15),
                      label: Text(
                        checked
                            ? 'VERIFICAR NOVAMENTE'
                            : 'VERIFICAR RELEASES NO GITHUB',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'As atualizações são obtidas de GitHub Releases públicas via HTTPS. O Android sempre valida a assinatura do pacote antes de atualizar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFF120003),
                    foregroundColor: const Color(0xFFCBD5E1),
                    side: const BorderSide(color: _border),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'RETORNAR AO NÚCLEO',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
