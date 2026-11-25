import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'auth_gate.dart';

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

/// Resultado da avaliação hierárquica entre um [ActionSimulation] e o [AccessLevel] atual.
class ActionPrivilegeDecision {
  const ActionPrivilegeDecision({
    required this.allowed,
    required this.requiredLevel,
    required this.requiresConfirmation,
    this.reason = '',
  });

  final bool allowed;
  final AccessLevel requiredLevel;
  final bool requiresConfirmation;
  final String reason;
}

/// Action Gate & Simulator: Avalia operações de hardware, rede e segurança antes da execução.
class ActionGate {
  const ActionGate();

  static const Set<String> _desktopActions = <String>{
    'PC_OPEN_APP',
    'PC_MEDIA',
    'PC_CLIPBOARD_PUSH',
    'PC_CLIPBOARD_PULL',
    'PC_RUN_SKILL',
    'PC_STATUS',
    'PC_THERMAL',
    'PC_TEMP',
    'PC_DELEGATE_TASK',
    'PC_TASK_STATUS',
    'PC_TASK_CANCEL',
    'PC_SPOTIFY',
    'PC_POWER_PLAN',
    'PC_APP_VOLUME',
    'PC_KILL_FROZEN',
    'PC_BACKUP',
    'PC_CLEAN_DISK',
    'PC_EJECT_USB',
    'PC_EXEC_TOOL',
    'DESKTOP_PAIRING',
  };

  /// Ferramentas do Desktop v3.0.0 classificadas como risco ALTO/CRÍTICO que
  /// sempre exigem confirmação explícita mesmo quando a sessão já está em `sovereign`.
  static const Set<String> _highRiskDesktopTools = <String>{
    'ENCERRAR_APPS_TRAVADOS',
    'KILL_FROZEN',
    'LIMPAR_DISCO',
    'CLEAN_DISK',
    'EXECUTAR_BACKUP_INCREMENTAL',
    'BACKUP',
    'EJETAR_USB_OCIOSO',
    'EJECT_USB',
    'LOCK_WORKSTATION',
    'SHUTDOWN',
    'REBOOT',
    'FORMAT',
    'WIPE',
    'DELETE',
    'CREATE_MINI_APP',
    'MINI_APP',
  };

  static bool isHighOrCriticalDesktopTool(String rawSpec) {
    final upper = rawSpec.toUpperCase();
    if (upper.contains('CRITICO') ||
        upper.contains('CRÍTICO') ||
        upper.contains('CRITICAL') ||
        upper.contains('ALTO') ||
        upper.contains('HIGH')) {
      return true;
    }
    for (final token in _highRiskDesktopTools) {
      if (upper.contains(token)) return true;
    }
    return false;
  }

  /// Determina o estágio mínimo de autenticação (`basic`, `elevated`, `sovereign`)
  /// exigido para cada operação.
  AccessLevel requiredLevelFor(ActionSimulation sim) {
    final op = sim.actionCode.toUpperCase().trim();
    if (sim.riskLevel == RiskLevel.critical || _desktopActions.contains(op)) {
      return AccessLevel.sovereign;
    }
    if (sim.riskLevel == RiskLevel.sensitive) {
      return AccessLevel.elevated;
    }
    return AccessLevel.basic;
  }

  /// Avalia se o nível atual da sessão permite executar [sim] e se confirmação
  /// explícita ainda é exigida:
  /// - `basic` (PIN): apenas ações `safe` locais (sem Desktop nem ações sensíveis/críticas).
  /// - `elevated` (NFC): libera ações `safe` e `sensitive` do celular (com confirmação), bloqueia Desktop e críticas.
  /// - `sovereign` (Biometria): libera tudo sem confirmação, EXIGIND0 confirmação apenas em ações críticas/autodestrutivas.
  ActionPrivilegeDecision evaluatePrivilege(
    ActionSimulation sim,
    AccessLevel currentLevel,
  ) {
    final required = requiredLevelFor(sim);
    if (currentLevel == AccessLevel.locked) {
      return ActionPrivilegeDecision(
        allowed: false,
        requiredLevel: required,
        requiresConfirmation: true,
        reason: 'Sessão bloqueada.',
      );
    }
    if (currentLevel == AccessLevel.guarded) {
      final allowedInDuress = sim.riskLevel == RiskLevel.safe &&
          !_desktopActions.contains(sim.actionCode.toUpperCase().trim());
      return ActionPrivilegeDecision(
        allowed: allowedInDuress,
        requiredLevel: required,
        requiresConfirmation: true,
        reason: allowedInDuress
            ? ''
            : 'Ação restrita no modo atual.',
      );
    }

    int rank(AccessLevel l) => switch (l) {
          AccessLevel.locked => 0,
          AccessLevel.guarded => 1,
          AccessLevel.basic => 2,
          AccessLevel.elevated => 3,
          AccessLevel.sovereign => 4,
        };

    if (rank(currentLevel) < rank(required)) {
      final needLabel = switch (required) {
        AccessLevel.elevated => 'Chave NFC (Nível 2) ou Biometria (Nível 3)',
        AccessLevel.sovereign => 'Biometria do Dono (Nível 3)',
        _ => 'Autenticação',
      };
      return ActionPrivilegeDecision(
        allowed: false,
        requiredLevel: required,
        requiresConfirmation: true,
        reason: 'Requer $needLabel para ${sim.actionCode}.',
      );
    }

    // Na Biometria (Nível 3): sem fricção em ações normais/sensíveis; confirmação só nos críticos/autodestrutivos e em exclusão de Skills/Arquivos Duplicados.
    final op = sim.actionCode.toUpperCase().trim();
    final alwaysConfirmInSovereign = sim.riskLevel == RiskLevel.critical ||
        op == 'SKILL_DELETE' ||
        op == 'CLEAN_DUPLICATES';
    final needsConfirm = currentLevel == AccessLevel.sovereign
        ? alwaysConfirmInSovereign
        : sim.requiresConfirmation;

    return ActionPrivilegeDecision(
      allowed: true,
      requiredLevel: required,
      requiresConfirmation: needsConfirm,
    );
  }

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

      case 'CANCEL_EVENT':
      case 'CANCELAR_EVENTO':
        return ActionSimulation(
          actionCode: 'CANCEL_EVENT',
          riskLevel: RiskLevel.sensitive,
          description: 'Remoção de compromisso da Agenda do Android',
          targetResource:
              'CalendarContract (${arg1.isEmpty ? 'Evento' : arg1})',
          requiresConfirmation: true,
          estimatedImpact:
              'Exclui o evento correspondente do calendário do aparelho.',
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

      case 'OBSIDIAN_LIST':
      case 'OBSIDIAN_NOTAS':
        return ActionSimulation(
          actionCode: 'OBSIDIAN_LIST',
          riskLevel: RiskLevel.safe,
          description: 'Listagem de notas Markdown do cofre Obsidian',
          targetResource:
              'ULTRON-Vault/${arg1.isEmpty ? '*' : arg1}',
          requiresConfirmation: false,
          estimatedImpact: 'Consulta somente leitura dos arquivos do cofre.',
          canDegradeToOffline: true,
        );

      case 'OBSIDIAN_READ':
      case 'OBSIDIAN_LER':
        return ActionSimulation(
          actionCode: 'OBSIDIAN_READ',
          riskLevel: RiskLevel.safe,
          description: 'Leitura de nota específica do cofre Obsidian',
          targetResource:
              'ULTRON-Vault/${arg1.isEmpty ? 'nota.md' : arg1}',
          requiresConfirmation: false,
          estimatedImpact:
              'Leitura sanitizada dentro do diretório raiz do cofre.',
          canDegradeToOffline: true,
        );

      case 'OBSIDIAN_STATUS':
        return const ActionSimulation(
          actionCode: 'OBSIDIAN_STATUS',
          riskLevel: RiskLevel.safe,
          description: 'Consulta de estatísticas e motor de busca do cofre Obsidian',
          targetResource: 'ULTRON-Vault',
          requiresConfirmation: false,
          estimatedImpact:
              'Retorna contagem de notas, tamanho, caminho ativo e engine FTS.',
          canDegradeToOffline: true,
        );

      case 'OBSIDIAN_APPEND':
      case 'OBSIDIAN_ANEXAR':
        return ActionSimulation(
          actionCode: 'OBSIDIAN_APPEND',
          riskLevel: RiskLevel.safe,
          description: 'Anexação de texto a uma nota no cofre Obsidian',
          targetResource:
              'ULTRON-Vault/${arg1.isEmpty ? 'nota.md' : arg1}',
          requiresConfirmation: false,
          estimatedImpact:
              'Acrescenta conteúdo ao arquivo Markdown com snapshot para UNDO.',
          canDegradeToOffline: true,
        );

      case 'OBSIDIAN_TASKS':
      case 'OBSIDIAN_TAREFAS':
        return ActionSimulation(
          actionCode: 'OBSIDIAN_TASKS',
          riskLevel: RiskLevel.safe,
          description:
              'Listagem ou marcação/desmarcação de checkboxes Markdown no Obsidian',
          targetResource:
              'ULTRON-Vault/${arg1.isEmpty ? 'Tarefas' : arg1}',
          requiresConfirmation: false,
          estimatedImpact:
              'Consulta ou alterna estado (- [ ] / - [x]) com suporte a UNDO.',
          canDegradeToOffline: true,
        );

      case 'UNDO':
      case 'DESFAZER':
        return const ActionSimulation(
          actionCode: 'UNDO',
          riskLevel: RiskLevel.safe,
          description:
              'Reversão da última operação mutável realizada no cofre Obsidian',
          targetResource: 'ULTRON-Vault (Snapshot Undo Stack)',
          requiresConfirmation: false,
          estimatedImpact:
              'Restaura o estado anterior da nota modificada mais recentemente.',
          canDegradeToOffline: true,
        );

      case 'REMINDER_LIST':
        return const ActionSimulation(
          actionCode: 'REMINDER_LIST',
          riskLevel: RiskLevel.safe,
          description: 'Listagem de lembretes locais agendados',
          targetResource: 'SQLite ultron_reminders.db',
          requiresConfirmation: false,
          estimatedImpact: 'Consulta somente leitura dos lembretes pendentes.',
          canDegradeToOffline: true,
        );

      case 'REMINDER_CREATE':
        return ActionSimulation(
          actionCode: 'REMINDER_CREATE',
          riskLevel: RiskLevel.safe,
          description:
              'Criação de lembrete persistente com alarme local agendado',
          targetResource:
              'ReminderService / AlarmManager (${arg1.isEmpty ? 'Lembrete' : arg1})',
          requiresConfirmation: false,
          estimatedImpact:
              'Persiste lembrete no SQLite e agenda notificação nativa via AlarmManager.',
          canDegradeToOffline: true,
        );

      case 'REMINDER_CANCEL':
        return ActionSimulation(
          actionCode: 'REMINDER_CANCEL',
          riskLevel: RiskLevel.safe,
          description: 'Cancelamento de lembrete agendado',
          targetResource:
              'ReminderService / AlarmManager (${arg1.isEmpty ? 'Lembrete' : arg1})',
          requiresConfirmation: false,
          estimatedImpact:
              'Marca lembrete como cancelado no SQLite e remove o alarme agendado.',
          canDegradeToOffline: true,
        );

      case 'PC_OPEN_APP':
      case 'PC_MEDIA':
      case 'PC_CLIPBOARD_PUSH':
      case 'PC_CLIPBOARD_PULL':
      case 'PC_RUN_SKILL':
      case 'PC_DELEGATE_TASK':
      case 'PC_TASK_CANCEL':
      case 'PC_SPOTIFY':
      case 'PC_POWER_PLAN':
      case 'PC_APP_VOLUME':
      case 'PC_KILL_FROZEN':
      case 'PC_BACKUP':
      case 'PC_CLEAN_DISK':
      case 'PC_EJECT_USB':
        return ActionSimulation(
          actionCode: op,
          riskLevel: RiskLevel.sensitive,
          description: switch (op) {
            'PC_DELEGATE_TASK' =>
              'Delegação de tarefa longa / pesquisa profunda para subagente no Desktop',
            'PC_TASK_CANCEL' =>
              'Cancelamento de tarefa em andamento na fila de subagentes do Desktop',
            'PC_SPOTIFY' =>
              'Controle de reprodução ou playlists do Spotify no Desktop via LAN',
            'PC_POWER_PLAN' =>
              'Alteração do plano de energia da estação Desktop (controlar_plano_energia)',
            'PC_APP_VOLUME' =>
              'Controle ou listagem de volume por aplicativo no Desktop (ajustar_volume_app)',
            'PC_KILL_FROZEN' =>
              'Encerramento de processos/aplicativos travados no Desktop (encerrar_apps_travados)',
            'PC_BACKUP' =>
              'Disparo de backup incremental na estação Desktop (executar_backup_incremental)',
            'PC_CLEAN_DISK' =>
              'Limpeza de arquivos temporários e cache de disco no Desktop (limpar_disco)',
            'PC_EJECT_USB' =>
              'Ejeção segura de armazenamento USB ocioso no Desktop (ejetar_usb_ocioso)',
            _ => 'Execução remota autenticada na estação Desktop LAN',
          },
          targetResource:
              'Desktop PC (${arg1.isEmpty ? op : arg1})',
          requiresConfirmation: true,
          estimatedImpact:
              'Envia comando HMAC-SHA256 ($op${arg1.isEmpty ? '' : ': $arg1'}) ao PC pareado.',
          canDegradeToOffline: false,
        );

      case 'PC_THERMAL':
      case 'PC_TEMP':
        return ActionSimulation(
          actionCode: op,
          riskLevel: RiskLevel.safe,
          description: op == 'PC_TEMP'
              ? 'Leitura de temperatura da CPU/GPU da estação Desktop (processos_ops)'
              : 'Consulta de proteção térmica e telemetria CPU/GPU/RAM do Desktop (verificar_protecao_termica)',
          targetResource: 'Desktop PC Pareado (Sensores Térmicos)',
          requiresConfirmation: false,
          estimatedImpact:
              'Leitura de temperatura e carga de CPU/GPU/RAM da estação Desktop via LAN.',
          canDegradeToOffline: false,
        );

      case 'PC_TASK_STATUS':
      case 'PC_TASKS':
        return const ActionSimulation(
          actionCode: 'PC_TASK_STATUS',
          riskLevel: RiskLevel.safe,
          description:
              'Consulta de status das tarefas/subagentes em execução no Desktop',
          targetResource: 'Desktop PC (GerenciadorTarefas)',
          requiresConfirmation: false,
          estimatedImpact:
              'Lista tarefas ativas, concluídas e progresso dos subagentes do Desktop via LAN.',
          canDegradeToOffline: false,
        );

      case 'DEEP_RESEARCH':
      case 'PESQUISA_PROFUNDA':
        return ActionSimulation(
          actionCode: 'DEEP_RESEARCH',
          riskLevel: RiskLevel.safe,
          description:
              'Execução de pesquisa profunda assíncrona com coleta web e relatório Markdown no Obsidian',
          targetResource:
              'DeepResearchService (${arg1.isEmpty ? 'Tema' : arg1})',
          requiresConfirmation: false,
          estimatedImpact:
              'Coleta fontes em paralelo com isolamento [DADOS EXTERNOS] e salva relatório em Memoria/Pesquisas/.',
          canDegradeToOffline: false,
        );

      case 'PC_EXEC_TOOL':
        final fullToolSpec = parts.skip(1).join(':').trim();
        final toolName = fullToolSpec.split('|').first.trim();
        final isMiniApp = toolName.toLowerCase() == 'create_mini_app' ||
            fullToolSpec.toLowerCase().contains('create_mini_app');
        final isHighOrCritical =
            isMiniApp || isHighOrCriticalDesktopTool(fullToolSpec);
        return ActionSimulation(
          actionCode: 'PC_EXEC_TOOL',
          riskLevel:
              isHighOrCritical ? RiskLevel.critical : RiskLevel.sensitive,
          description: isMiniApp
              ? 'Geração e execução sandboxed de Mini-App local no Desktop (create_mini_app)'
              : isHighOrCritical
                  ? 'Despacho de ferramenta Desktop v3.0.0 de risco ALTO/CRÍTICO ($toolName)'
                  : 'Despacho genérico de ferramenta registrada no Desktop v3.0.0 ($toolName)',
          targetResource:
              'Desktop Tool (${toolName.isEmpty ? 'v3.0.0' : toolName})',
          requiresConfirmation: true,
          estimatedImpact: isMiniApp
              ? 'Gera mini-app HTML/JS/Python em diretório isolado no PC com porta efêmera LAN/Tailscale, token de sessão e auto-encerramento (TTL). Confirmação explícita obrigatória.'
              : isHighOrCritical
                  ? 'Executa ferramenta administrativa de alto impacto no Desktop; confirmação explícita obrigatória.'
                  : 'Envia chamada assinada com HMAC-SHA256 + timestamp + nonce para a ferramenta "$toolName" no Desktop.',
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
        final mutUri = Uri.tryParse(urlPreview);
        final mutMetadata = mutUri != null && isBlockedMetadataHost(mutUri.host);
        return ActionSimulation(
          actionCode: op,
          riskLevel: mutMetadata ? RiskLevel.critical : RiskLevel.sensitive,
          description: mutMetadata
              ? 'Requisição HTTP bloqueada por política anti-SSRF/metadata ($op)'
              : 'Disparo de Webhook HTTP IoT/Skill ($op)',
          targetResource: urlPreview.isEmpty ? 'Endpoint HTTP' : urlPreview,
          requiresConfirmation: true,
          estimatedImpact: mutMetadata
              ? 'Alvo aponta para host de link-local/metadata bloqueado.'
              : 'Envia requisição HTTP mutável para integração externa/IoT.',
          canDegradeToOffline: false,
        );

      case 'HTTP_GET':
        final getUrl = parts.skip(1).join(':').split('|').first.trim();
        final getUri = Uri.tryParse(getUrl);
        final getMetadata = getUri != null && isBlockedMetadataHost(getUri.host);
        if (getMetadata) {
          return ActionSimulation(
            actionCode: 'HTTP_GET',
            riskLevel: RiskLevel.critical,
            description: 'Consulta HTTP GET bloqueada por política anti-SSRF/metadata',
            targetResource: getUrl.isEmpty ? 'Endpoint HTTP' : getUrl,
            requiresConfirmation: true,
            estimatedImpact:
                'Alvo aponta para endereço link-local/metadata (SSRF bloqueado).',
            canDegradeToOffline: false,
          );
        }
        final isLan = isPrivateLanUrl(getUrl);
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

      case 'SKILL_CREATE':
        final skillName = arg1.split('|').first.trim();
        return ActionSimulation(
          actionCode: 'SKILL_CREATE',
          riskLevel: RiskLevel.sensitive,
          description:
              'Criação ou atualização de Skill procedural executável em Skills/*.md',
          targetResource:
              'Skills/${skillName.isEmpty ? 'nova_skill' : skillName}.md',
          requiresConfirmation: true,
          estimatedImpact:
              'Grava arquivo de automação Markdown executável no cofre Obsidian.',
          canDegradeToOffline: true,
        );

      case 'SKILL_DELETE':
        return ActionSimulation(
          actionCode: 'SKILL_DELETE',
          riskLevel: RiskLevel.sensitive,
          description: 'Remoção de Skill procedural de Skills/*.md',
          targetResource: 'Skills/${arg1.isEmpty ? 'skill' : arg1}.md',
          requiresConfirmation: true,
          estimatedImpact:
              'Exclui a skill do cofre Obsidian (reversível via UNDO).',
          canDegradeToOffline: true,
        );

      case 'WEATHER':
      case 'CLIMA':
        return ActionSimulation(
          actionCode: 'WEATHER',
          riskLevel: RiskLevel.safe,
          description: 'Consulta meteorológica atual sem chave de API',
          targetResource:
              'wttr.in (${arg1.isEmpty ? 'Cidade padrão' : arg1})',
          requiresConfirmation: false,
          estimatedImpact: 'Consulta somente leitura de previsão do tempo.',
          canDegradeToOffline: false,
        );

      case 'NEWS':
      case 'NOTICIAS':
        return ActionSimulation(
          actionCode: 'NEWS',
          riskLevel: RiskLevel.safe,
          description: 'Leitura de manchetes de notícias via feed RSS público',
          targetResource:
              'RSS Público (${arg1.isEmpty ? 'Principais' : arg1})',
          requiresConfirmation: false,
          estimatedImpact: 'Consulta somente leitura de feeds RSS em XML.',
          canDegradeToOffline: false,
        );

      case 'WEB_SEARCH':
      case 'PESQUISAR_WEB':
        final q = parts.skip(1).join(':').trim();
        return ActionSimulation(
          actionCode: 'WEB_SEARCH',
          riskLevel: RiskLevel.safe,
          description: 'Pesquisa web textual resumida no chat',
          targetResource: 'WebInfoService (${q.isEmpty ? 'Consulta' : q})',
          requiresConfirmation: false,
          estimatedImpact:
              'Retorna resumo textual direto no chat sem abrir navegador.',
          canDegradeToOffline: false,
        );

      case 'FLOW_LIST':
        return const ActionSimulation(
          actionCode: 'FLOW_LIST',
          riskLevel: RiskLevel.safe,
          description: 'Listagem de fluxos automatizados e agendamentos',
          targetResource: 'WorkflowSchedulerService (SQLite)',
          requiresConfirmation: false,
          estimatedImpact: 'Consulta somente leitura dos fluxos cadastrados.',
          canDegradeToOffline: true,
        );

      case 'FLOW_RUN':
        return ActionSimulation(
          actionCode: 'FLOW_RUN',
          riskLevel: RiskLevel.safe,
          description: 'Execução imediata de fluxo encadeado',
          targetResource:
              'WorkflowSchedulerService (${arg1.isEmpty ? 'Fluxo' : arg1})',
          requiresConfirmation: false,
          estimatedImpact:
              'Executa os passos do fluxo validando cada passo pelo ActionGate/AuthGate.',
          canDegradeToOffline: true,
        );

      case 'FLOW_CREATE':
      case 'FLOW_SCHEDULE':
      case 'FLOW_DELETE':
        return ActionSimulation(
          actionCode: op,
          riskLevel: RiskLevel.sensitive,
          description: switch (op) {
            'FLOW_CREATE' =>
              'Criação de fluxo dinâmico encadeando ações e skills',
            'FLOW_SCHEDULE' =>
              'Agendamento de fluxo recorrente ou temporizado via AlarmManager',
            _ => 'Exclusão de fluxo agendado',
          },
          targetResource:
              'WorkflowSchedulerService (${arg1.isEmpty ? 'Fluxo' : arg1})',
          requiresConfirmation: true,
          estimatedImpact:
              'Altera a tabela persistente de automações e alarmes agendados do dispositivo.',
          canDegradeToOffline: true,
        );

      case 'SPOTIFY_SEARCH':
      case 'SPOTIFY_BUSCAR':
        return ActionSimulation(
          actionCode: 'SPOTIFY_SEARCH',
          riskLevel: RiskLevel.safe,
          description: 'Busca de faixas na Spotify Web API',
          targetResource: 'Spotify API (${arg1.isEmpty ? 'Busca' : arg1})',
          requiresConfirmation: false,
          estimatedImpact: 'Consulta somente leitura do catálogo do Spotify.',
          canDegradeToOffline: false,
        );

      case 'SPOTIFY_STATE':
      case 'SPOTIFY_ESTADO':
        return const ActionSimulation(
          actionCode: 'SPOTIFY_STATE',
          riskLevel: RiskLevel.safe,
          description:
              'Consulta do estado de reprodução e dispositivo ativo no Spotify',
          targetResource: 'Spotify Web API (/v1/me/player)',
          requiresConfirmation: false,
          estimatedImpact:
              'Retorna faixa atual, artista, progresso e dispositivo ativo.',
          canDegradeToOffline: false,
        );

      case 'SPOTIFY_PLAY':
      case 'SPOTIFY_TOCAR':
        return ActionSimulation(
          actionCode: 'SPOTIFY_PLAY',
          riskLevel: RiskLevel.safe,
          description: 'Início de reprodução de faixa ou URI no Spotify',
          targetResource:
              'Spotify Player (${arg1.isEmpty ? 'Retomar' : arg1})',
          requiresConfirmation: false,
          estimatedImpact:
              'Aciona reprodução de mídia na conta Spotify autenticada via OAuth PKCE.',
          canDegradeToOffline: false,
        );

      case 'SPOTIFY_PLAYLISTS':
      case 'SPOTIFY_LISTAR_PLAYLISTS':
        return const ActionSimulation(
          actionCode: 'SPOTIFY_PLAYLISTS',
          riskLevel: RiskLevel.safe,
          description: 'Listagem de playlists do operador no Spotify',
          targetResource: 'Spotify Web API (/v1/me/playlists)',
          requiresConfirmation: false,
          estimatedImpact: 'Consulta somente leitura das playlists do usuário.',
          canDegradeToOffline: false,
        );

      case 'SPOTIFY_ADD_PLAYLIST':
      case 'SPOTIFY_ADICIONAR_PLAYLIST':
        return ActionSimulation(
          actionCode: 'SPOTIFY_ADD_PLAYLIST',
          riskLevel: RiskLevel.safe,
          description: 'Adição de faixa a uma playlist do Spotify',
          targetResource:
              'Spotify Playlist (${arg1.isEmpty ? 'Playlist' : arg1})',
          requiresConfirmation: false,
          estimatedImpact:
              'Adiciona a faixa especificada (ou a que está tocando) à playlist.',
          canDegradeToOffline: false,
        );

      case 'CLEAN_DUPLICATES':
      case 'LIMPAR_DUPLICADOS':
        return ActionSimulation(
          actionCode: 'CLEAN_DUPLICATES',
          riskLevel: RiskLevel.sensitive,
          description:
              'Remoção de arquivos duplicados idênticos verificados por hash SHA-256 (limpar_duplicados)',
          targetResource:
              'SAF / Downloads (${arg1.isEmpty ? 'Downloads' : arg1})',
          requiresConfirmation: true,
          estimatedImpact:
              'Apaga cópias com hash SHA-256 idêntico mantendo o arquivo original intacto.',
          canDegradeToOffline: true,
        );

      case 'CONVERT_IMAGES':
      case 'CONVERTER_IMAGENS':
        return ActionSimulation(
          actionCode: 'CONVERT_IMAGES',
          riskLevel: RiskLevel.safe,
          description:
              'Conversão de imagens .webp/.heic para .jpg/.png em destino seguro (converter_imagens)',
          targetResource:
              'SAF / Downloads (${arg1.isEmpty ? 'jpg' : arg1})',
          requiresConfirmation: false,
          estimatedImpact:
              'Gera cópias convertidas (.jpg/.png) sem sobrescrever nem apagar as imagens originais.',
          canDegradeToOffline: true,
        );

      case 'ORGANIZE_PDFS':
      case 'ORGANIZAR_PDF_DOWNLOADS':
        return ActionSimulation(
          actionCode: 'ORGANIZE_PDFS',
          riskLevel: RiskLevel.sensitive,
          description:
              'Renomeação assistida de PDFs em Downloads para o padrão AAAA-MM-DD - Assunto.pdf (organizar_pdf_downloads)',
          targetResource:
              'SAF / Downloads (${arg1.isEmpty ? 'Downloads/*.pdf' : arg1})',
          requiresConfirmation: true,
          estimatedImpact:
              'Padroniza os nomes dos arquivos PDF sem sobrescrever arquivos existentes.',
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

  /// Identifica hosts de metadata/link-local bloqueados por política anti-SSRF
  /// (`169.254.0.0/16`, `0.0.0.0`, `fe80::/10` e hostnames de cloud metadata).
  static bool isBlockedMetadataHost(String host) {
    var lower = host.trim().toLowerCase();
    if (lower.startsWith('[') && lower.endsWith(']') && lower.length > 2) {
      lower = lower.substring(1, lower.length - 1);
    }
    if (lower.isEmpty) return false;
    if (lower == '0.0.0.0' ||
        lower == 'metadata.google.internal' ||
        lower == 'metadata' ||
        lower == 'instance-data') {
      return true;
    }
    if (lower.startsWith('fe8') ||
        lower.startsWith('fe9') ||
        lower.startsWith('fea') ||
        lower.startsWith('feb')) {
      return true;
    }
    final octets = lower.split('.');
    if (octets.length == 4) {
      final b0 = int.tryParse(octets[0]);
      final b1 = int.tryParse(octets[1]);
      if (b0 == 169 && b1 == 254) {
        return true;
      }
    }
    return false;
  }

  /// Verifica se [rawUrl] aponta exclusivamente para rede local (LAN) / loopback / `.local`.
  static bool isPrivateLanUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || uri.host.isEmpty) return false;
    final host = uri.host.toLowerCase();
    if (isBlockedMetadataHost(host)) return false;
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
