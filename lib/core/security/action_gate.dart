import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Classificação de risco de operações solicitadas pelo Operador ou geradas pela IA.
enum RiskLevel {
  /// Operações locais sem impacto destrutivo ou transmissão externa (ex: lanterna, volume, ler telemetria).
  safe,

  /// Operações com transmissão externa de mensagens ou alteração de configurações persistentes.
  sensitive,

  /// Operações com potencial destrutivo, bloqueio de estação remota ou apagamento irreversível de dados.
  critical,
}

/// Representação simulada do impacto de uma ação antes de sua execução real.
class ActionSimulation {
  const ActionSimulation({
    required this.actionCode,
    required this.riskLevel,
    required this.description,
    required this.targetResource,
    required this.requiresConfirmation,
    this.estimatedImpact = '',
    this.canDegradeToOffline = true,
  });

  final String actionCode;
  final RiskLevel riskLevel;
  final String description;
  final String targetResource;
  final bool requiresConfirmation;
  final String estimatedImpact;
  final bool canDegradeToOffline;

  Map<String, dynamic> toMap() => {
        'actionCode': actionCode,
        'riskLevel': riskLevel.name,
        'description': description,
        'targetResource': targetResource,
        'requiresConfirmation': requiresConfirmation,
        'estimatedImpact': estimatedImpact,
        'canDegradeToOffline': canDegradeToOffline,
      };
}

/// Resultado do fluxo tático estrito (Planejar -> Validar -> Executar -> Verificar -> Apresentar).
class TacticalStepResult {
  const TacticalStepResult({
    required this.step,
    required this.success,
    required this.message,
    this.telemetryFeedback,
  });

  final String step;
  final bool success;
  final String message;
  final String? telemetryFeedback;
}

/// Action Gate & Simulator: Avalia operações de hardware, rede e segurança antes da execução.
class ActionGate {
  const ActionGate();

  /// Avalia uma tag de ação do modelo ([ACTION:...]) ou comando antes da execução.
  ActionSimulation simulate(String rawAction) {
    final clean = rawAction.replaceAll(RegExp(r'[\[\]]'), '').trim();
    final parts = clean.startsWith('ACTION:')
        ? clean.substring('ACTION:'.length).split(':')
        : clean.split(':');
    final op = parts.first.toUpperCase().trim();
    final arg1 = parts.length > 1 ? parts[1].trim() : '';
    final arg2 = parts.length > 2 ? parts[2].trim() : '';

    switch (op) {
      case 'KILL_SWITCH':
      case 'LOCK_PC':
        return const ActionSimulation(
          actionCode: 'KILL_SWITCH',
          riskLevel: RiskLevel.critical,
          description:
              'Bloqueio de Emergência da Estação de Trabalho PC via LAN',
          targetResource: 'Estação Desktop (LockWorkStation)',
          requiresConfirmation: true,
          estimatedImpact:
              'Trava imediatamente a sessão do Windows e encerra conexões ativas.',
          canDegradeToOffline: false,
        );

      case 'CLEAR_HISTORY':
      case 'WIPE_MEMORY':
        return const ActionSimulation(
          actionCode: 'CLEAR_HISTORY',
          riskLevel: RiskLevel.critical,
          description: 'Expurgo irreversível do histórico SQLite local',
          targetResource: 'Banco SQLite ultron_conversations.db',
          requiresConfirmation: true,
          estimatedImpact:
              'Todas as mensagens anteriores serão excluídas permanentemente.',
          canDegradeToOffline: true,
        );

      case 'WHATSAPP':
        return ActionSimulation(
          actionCode: 'WHATSAPP',
          riskLevel: RiskLevel.sensitive,
          description: 'Envio ativo de mensagem para contato via WhatsApp',
          targetResource: 'WhatsApp ($arg1)',
          requiresConfirmation: true,
          estimatedImpact:
              'Abre deep-link ou preenche conversa para $arg1 com texto "$arg2".',
          canDegradeToOffline: false,
        );

      case 'SMS':
        return ActionSimulation(
          actionCode: 'SMS',
          riskLevel: RiskLevel.sensitive,
          description: 'Envio de mensagem SMS para linha telefônica',
          targetResource: 'SMS ($arg1)',
          requiresConfirmation: true,
          estimatedImpact: 'Abre Intent de SMS para $arg1.',
          canDegradeToOffline: false,
        );

      case 'REPLY_MESSAGE':
        return ActionSimulation(
          actionCode: 'REPLY_MESSAGE',
          riskLevel: RiskLevel.sensitive,
          description: 'Injeção de resposta em 2º plano via RemoteInput',
          targetResource: 'Notificação Ativa ($arg1)',
          requiresConfirmation: true,
          estimatedImpact:
              'Responde à notificação sem abrir o aplicativo em primeiro plano.',
          canDegradeToOffline: false,
        );

      case 'DIAL':
        return ActionSimulation(
          actionCode: 'DIAL',
          riskLevel: RiskLevel.sensitive,
          description: 'Abertura do discador telefônico para chamada externa',
          targetResource: 'Discador ($arg1)',
          requiresConfirmation: true,
          estimatedImpact: 'Abre o discador do Android preenchido com $arg1.',
          canDegradeToOffline: false,
        );

      case 'CREATE_EVENT':
      case 'CALENDAR_EVENT':
        return ActionSimulation(
          actionCode: 'CREATE_EVENT',
          riskLevel: RiskLevel.sensitive,
          description: 'Escrita de novo compromisso na Agenda do Android',
          targetResource:
              'CalendarContract (${arg1.isEmpty ? 'Evento' : arg1})',
          requiresConfirmation: true,
          estimatedImpact:
              'Grava evento no calendário principal do aparelho${arg2.isEmpty ? '' : ' ($arg2)'}.',
          canDegradeToOffline: true,
        );

      case 'READ_CALENDAR':
      case 'BRIEFING':
        return ActionSimulation(
          actionCode: op,
          riskLevel: RiskLevel.safe,
          description: op == 'BRIEFING'
              ? 'Consolidação de Briefing Matinal (Agenda, Sentinela, Clima e Telemetria)'
              : 'Leitura de compromissos da Agenda do Android',
          targetResource: 'CalendarContract / Sentinela / Clima',
          requiresConfirmation: false,
          estimatedImpact: 'Consulta somente leitura do contexto do operador.',
          canDegradeToOffline: true,
        );

      case 'PC_OPEN_APP':
      case 'PC_MEDIA':
      case 'PC_CLIPBOARD_PUSH':
      case 'PC_CLIPBOARD_PULL':
      case 'PC_RUN_SKILL':
        return ActionSimulation(
          actionCode: op,
          riskLevel: RiskLevel.sensitive,
          description: 'Execução remota autenticada na estação Desktop LAN',
          targetResource: 'Desktop PC ($arg1)',
          requiresConfirmation: true,
          estimatedImpact:
              'Envia comando HMAC-SHA256 ($op${arg1.isEmpty ? '' : ': $arg1'}) ao PC pareado.',
          canDegradeToOffline: false,
        );

      case 'PC_STATUS':
      case 'PING':
        return const ActionSimulation(
          actionCode: 'PC_STATUS',
          riskLevel: RiskLevel.safe,
          description: 'Consulta de status e conectividade do Desktop LAN',
          targetResource: 'Desktop PC Pareado',
          requiresConfirmation: false,
          estimatedImpact:
              'Verifica latência e saúde do agente desktop na LAN.',
          canDegradeToOffline: false,
        );

      case 'HTTP_POST':
      case 'HTTP_PUT':
      case 'HTTP_PATCH':
      case 'HTTP_DELETE':
        final urlPreview = parts.skip(1).join(':').split('|').first.trim();
        return ActionSimulation(
          actionCode: op,
          riskLevel: RiskLevel.sensitive,
          description: 'Disparo de Webhook HTTP IoT/Skill ($op)',
          targetResource: urlPreview.isEmpty ? 'Endpoint HTTP' : urlPreview,
          requiresConfirmation: true,
          estimatedImpact:
              'Envia requisição HTTP mutável para integração externa/IoT.',
          canDegradeToOffline: false,
        );

      case 'HTTP_GET':
        final getUrl = parts.skip(1).join(':').split('|').first.trim();
        final isLan = _isPrivateLanUrl(getUrl);
        return ActionSimulation(
          actionCode: 'HTTP_GET',
          riskLevel: isLan ? RiskLevel.safe : RiskLevel.sensitive,
          description: 'Consulta HTTP GET em Skill/IoT',
          targetResource: getUrl.isEmpty ? 'Endpoint HTTP' : getUrl,
          requiresConfirmation: !isLan,
          estimatedImpact: isLan
              ? 'Consulta somente leitura em dispositivo na rede local (LAN).'
              : 'Consulta externa via HTTP fora da rede local.',
          canDegradeToOffline: false,
        );

      case 'TORCH_ON':
      case 'TORCH_OFF':
      case 'TORCH_TOGGLE':
        return const ActionSimulation(
          actionCode: 'TORCH',
          riskLevel: RiskLevel.safe,
          description: 'Acionamento de hardware da lanterna traseira',
          targetResource: 'CameraManager Flash Unit',
          requiresConfirmation: false,
          estimatedImpact: 'Altera o estado do LED de flash.',
          canDegradeToOffline: true,
        );

      case 'VOLUME_SET':
      case 'VOLUME_UP':
      case 'VOLUME_DOWN':
      case 'VOLUME_MUTE':
        return const ActionSimulation(
          actionCode: 'VOLUME',
          riskLevel: RiskLevel.safe,
          description: 'Modulação de volume do canal de mídia',
          targetResource: 'AudioManager STREAM_MUSIC',
          requiresConfirmation: false,
          estimatedImpact: 'Ajusta nível de decibéis do sistema.',
          canDegradeToOffline: true,
        );

      case 'NOTE':
        return const ActionSimulation(
          actionCode: 'NOTE',
          riskLevel: RiskLevel.safe,
          description: 'Gravação de Quick Capture no Cofre Obsidian',
          targetResource: 'ULTRON-Vault/Diario/YYYY-MM-DD.md',
          requiresConfirmation: false,
          estimatedImpact:
              'Persiste anotação com timestamp ISO-8601 no armazenamento local.',
          canDegradeToOffline: true,
        );

      case 'SKILL':
        return ActionSimulation(
          actionCode: 'SKILL',
          riskLevel: RiskLevel.safe,
          description: 'Execução de rotina procedural Markdown',
          targetResource: 'Skills/$arg1.md',
          requiresConfirmation: false,
          estimatedImpact: 'Encadeia comandos pré-programados no dispositivo.',
          canDegradeToOffline: true,
        );

      case 'ALARM':
      case 'TIMER':
        return ActionSimulation(
          actionCode: op,
          riskLevel: RiskLevel.safe,
          description: 'Agendamento de alarme ou temporizador no Android',
          targetResource: 'AlarmClock Provider',
          requiresConfirmation: false,
          estimatedImpact: 'Cria alarme com horário/duração configurada.',
          canDegradeToOffline: true,
        );

      default:
        return ActionSimulation(
          actionCode: op,
          riskLevel: RiskLevel.safe,
          description: 'Execução de comando padrão',
          targetResource: 'Kernel Android',
          requiresConfirmation: false,
          estimatedImpact:
              'Ação executada com permissões padrão do assistente.',
          canDegradeToOffline: true,
        );
    }
  }

  static bool _isPrivateLanUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || uri.host.isEmpty) return false;
    final host = uri.host.toLowerCase();
    if (host == 'localhost' || host == '::1' || host.endsWith('.local')) {
      return true;
    }
    final octets = host.split('.');
    if (octets.length != 4) return false;
    final b0 = int.tryParse(octets[0]);
    final b1 = int.tryParse(octets[1]);
    if (b0 == null || b1 == null) return false;
    if (b0 == 10 || b0 == 127) return true;
    if (b0 == 172 && b1 >= 16 && b1 <= 31) return true;
    if (b0 == 192 && b1 == 168) return true;
    if (b0 == 169 && b1 == 254) return true;
    return false;
  }

  /// Gera assinatura criptográfica para payloads remotos de segurança.
  static String signPayload(String payload, {required String secret}) {
    final cleanSecret = secret.trim();
    if (cleanSecret.isEmpty) {
      throw ArgumentError('Segredo HMAC LAN não pode ser vazio.');
    }
    final hmac = Hmac(sha256, utf8.encode(cleanSecret));
    return hmac.convert(utf8.encode(payload)).toString();
  }
}
