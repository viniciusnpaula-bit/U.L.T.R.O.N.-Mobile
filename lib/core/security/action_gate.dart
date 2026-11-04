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
        return ActionSimulation(
          actionCode: 'KILL_SWITCH',
          riskLevel: RiskLevel.critical,
          description: 'Bloqueio de Emergência da Estação de Trabalho PC via LAN',
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
          estimatedImpact: 'Todas as mensagens anteriores serão excluídas permanentemente.',
          canDegradeToOffline: true,
        );

      case 'WHATSAPP':
        return ActionSimulation(
          actionCode: 'WHATSAPP',
          riskLevel: RiskLevel.sensitive,
          description: 'Envio ativo de mensagem para contato via WhatsApp',
          targetResource: 'WhatsApp ($arg1)',
          requiresConfirmation: false,
          estimatedImpact: 'Abre deep-link ou preenche conversa para $arg1 com texto "$arg2".',
          canDegradeToOffline: false,
        );

      case 'SMS':
        return ActionSimulation(
          actionCode: 'SMS',
          riskLevel: RiskLevel.sensitive,
          description: 'Envio de mensagem SMS para linha telefônica',
          targetResource: 'SMS ($arg1)',
          requiresConfirmation: false,
          estimatedImpact: 'Abre Intent de SMS para $arg1.',
          canDegradeToOffline: false,
        );

      case 'REPLY_MESSAGE':
        return ActionSimulation(
          actionCode: 'REPLY_MESSAGE',
          riskLevel: RiskLevel.sensitive,
          description: 'Injeção de resposta em 2º plano via RemoteInput',
          targetResource: 'Notificação Ativa ($arg1)',
          requiresConfirmation: false,
          estimatedImpact: 'Responde à notificação sem abrir o aplicativo em primeiro plano.',
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
        return ActionSimulation(
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
          estimatedImpact: 'Persiste anotação com timestamp ISO-8601 no armazenamento local.',
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
          estimatedImpact: 'Ação executada com permissões padrão do assistente.',
          canDegradeToOffline: true,
        );
    }
  }

  /// Gera assinatura criptográfica para payloads remotos de segurança.
  static String signPayload(String payload, {String secret = 'ULTRON_LAN_GUARD'}) {
    final hmac = Hmac(sha256, utf8.encode(secret));
    return hmac.convert(utf8.encode(payload)).toString();
  }
}
