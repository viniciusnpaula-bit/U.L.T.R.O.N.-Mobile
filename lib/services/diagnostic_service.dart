import 'package:connectivity_plus/connectivity_plus.dart';

import 'ai_service.dart';

enum DiagnosticStatus { available, notConfigured, unavailable, error, unverified }

class DiagnosticItem {
  const DiagnosticItem(this.name, this.status, this.detail);
  final String name;
  final DiagnosticStatus status;
  final String detail;
}

class DiagnosticService {
  DiagnosticService({required AiService ai});

  Future<List<DiagnosticItem>> inspect({required bool speechReady, required bool ttsReady}) async {
    final providers = await AiService().providers();
    final configured = providers.any((p) => p.enabled);
    DiagnosticStatus connectivityStatus = DiagnosticStatus.unverified;
    var connectivityDetail = 'Não verificado';
    try {
      final results = await Connectivity().checkConnectivity();
      final online = results.any((r) => r != ConnectivityResult.none);
      connectivityStatus = online ? DiagnosticStatus.available : DiagnosticStatus.unavailable;
      connectivityDetail = online ? 'Conexão de rede disponível (sem teste de internet/API)' : 'Sem conexão de rede';
    } catch (e) {
      connectivityStatus = DiagnosticStatus.error;
      connectivityDetail = 'Erro ao consultar conectividade';
    }
    return [
      const DiagnosticItem('IA', DiagnosticStatus.available, 'Provedor habilitado; API não testada'),
      const DiagnosticItem('Reconhecimento de voz', DiagnosticStatus.unavailable, 'Não inicializado ou indisponível'),
      const DiagnosticItem('TTS', DiagnosticStatus.unverified, 'Não verificado'),
      const DiagnosticItem('Memória', DiagnosticStatus.unverified, 'Persistência de conversa não implementada nesta sessão'),
      const DiagnosticItem('Armazenamento', DiagnosticStatus.unverified, 'Não verificado'),
      DiagnosticItem('Conectividade', DiagnosticStatus.unverified, 'Não verificado'),
      const DiagnosticItem('Atualização', DiagnosticStatus.unverified, 'Não verificada'),
    ];
  }
}
