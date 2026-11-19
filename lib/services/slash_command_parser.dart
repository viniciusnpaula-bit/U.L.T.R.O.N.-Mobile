enum UltronCommand {
  help,
  security,
  history,
  memory,
  desktop,
  settings,
  device,
  torch,
  skills,
  note,
  models,
  messages,
  reply,
  killswitch,
  voice,
  clear,
  lock,
  status,
  vault,
  search,
  vision,
  pc,
  calendar,
  briefing,
  audit,
}

class CommandResult {
  const CommandResult(this.command, this.argument);
  final UltronCommand command;
  final String argument;
}

/// Parser inteligente determinístico de Slash Commands com suporte a sinônimos
/// e argumentos encadeados.
class SlashCommandParser {
  static const commands = <String, UltronCommand>{
    '/help': UltronCommand.help,
    '/?': UltronCommand.help,
    '/ajuda': UltronCommand.help,
    '/security': UltronCommand.security,
    '/seguranca': UltronCommand.security,
    '/duress': UltronCommand.security,
    '/history': UltronCommand.history,
    '/historico': UltronCommand.history,
    '/memory': UltronCommand.memory,
    '/memoria': UltronCommand.memory,
    '/desktop': UltronCommand.desktop,
    '/settings': UltronCommand.settings,
    '/config': UltronCommand.settings,
    '/configuracoes': UltronCommand.settings,
    '/ajustes': UltronCommand.settings,
    '/device': UltronCommand.device,
    '/celular': UltronCommand.device,
    '/telemetria': UltronCommand.device,
    '/lanterna': UltronCommand.torch,
    '/torch': UltronCommand.torch,
    '/flash': UltronCommand.torch,
    '/skills': UltronCommand.skills,
    '/skill': UltronCommand.skills,
    '/note': UltronCommand.note,
    '/nota': UltronCommand.note,
    '/anote': UltronCommand.note,
    '/anotar': UltronCommand.note,
    '/models': UltronCommand.models,
    '/modelos': UltronCommand.models,
    '/messages': UltronCommand.messages,
    '/mensagens': UltronCommand.messages,
    '/notificacoes': UltronCommand.messages,
    '/ler': UltronCommand.messages,
    '/reply': UltronCommand.reply,
    '/responder': UltronCommand.reply,
    '/responda': UltronCommand.reply,
    '/killswitch': UltronCommand.killswitch,
    '/travarpc': UltronCommand.killswitch,
    '/lockpc': UltronCommand.killswitch,
    '/voice': UltronCommand.voice,
    '/voz': UltronCommand.voice,
    '/falar': UltronCommand.voice,
    '/clear': UltronCommand.clear,
    '/limpar': UltronCommand.clear,
    '/expurgar': UltronCommand.clear,
    '/lock': UltronCommand.lock,
    '/travar': UltronCommand.lock,
    '/bloquear': UltronCommand.lock,
    '/status': UltronCommand.status,
    '/diag': UltronCommand.status,
    '/saude': UltronCommand.status,
    '/vault': UltronCommand.vault,
    '/obsidian': UltronCommand.vault,
    '/cerebro': UltronCommand.vault,
    '/segundocerebro': UltronCommand.vault,
    '/search': UltronCommand.search,
    '/buscar': UltronCommand.search,
    '/rag': UltronCommand.search,
    '/visao': UltronCommand.vision,
    '/vision': UltronCommand.vision,
    '/camera': UltronCommand.vision,
    '/ocr': UltronCommand.vision,
    '/pc': UltronCommand.pc,
    '/agenda': UltronCommand.calendar,
    '/calendar': UltronCommand.calendar,
    '/evento': UltronCommand.calendar,
    '/eventos': UltronCommand.calendar,
    '/briefing': UltronCommand.briefing,
    '/bomdia': UltronCommand.briefing,
    '/resumodia': UltronCommand.briefing,
    '/audit': UltronCommand.audit,
    '/auditoria': UltronCommand.audit,
    '/logs': UltronCommand.audit,
  };

  static CommandResult? parse(String input) {
    final text = input.trim();
    if (!text.startsWith('/')) return null;
    final parts = text.split(RegExp(r'\s+'));
    final commandKey = parts.first.toLowerCase();
    final command = commands[commandKey];
    if (command == null) return null;
    return CommandResult(command, parts.skip(1).join(' ').trim());
  }

  /// Retorna lista de sintaxes disponíveis com documentação tática.
  static List<Map<String, String>> commandCatalog() => [
        {
          'command': '/help',
          'aliases': '/?, /ajuda',
          'description': 'Exibe este catálogo de comandos e sintaxes táticas.',
        },
        {
          'command': '/device',
          'aliases': '/celular, /telemetria',
          'description':
              'Abre cockpit com telemetria circular (RAM, bateria, °C, sensores).',
        },
        {
          'command': '/status',
          'aliases': '/diag, /saude',
          'description':
              'Exibe resumo instantâneo de saúde e telemetria do aparelho.',
        },
        {
          'command': '/lanterna [on|off|toggle]',
          'aliases': '/torch, /flash',
          'description': 'Controla o LED de flash traseiro do smartphone.',
        },
        {
          'command': '/note <texto>',
          'aliases': '/nota, /anote, /anotar',
          'description':
              'Quick Capture salvo em ULTRON-Vault/Diario/YYYY-MM-DD.md.',
        },
        {
          'command': '/skills [nome]',
          'aliases': '/skill',
          'description': 'Lista ou executa rotinas procedurais em Skills/*.md.',
        },
        {
          'command': '/models',
          'aliases': '/modelos',
          'description':
              'Auto-discovery de modelos ativos no provedor de IA conectado.',
        },
        {
          'command': '/mensagens',
          'aliases': '/messages, /notificacoes, /ler',
          'description': 'Sentinela lê notificações recentes em voz alta.',
        },
        {
          'command': '/responder <texto>',
          'aliases': '/reply, /responda',
          'description':
              'Responde notificação em 2º plano via RemoteInput nativo.',
        },
        {
          'command': '/killswitch',
          'aliases': '/travarpc, /lockpc',
          'description': 'Trava o PC Windows via LAN e encerra a sessão móvel.',
        },
        {
          'command': '/voice',
          'aliases': '/voz, /falar',
          'description':
              'Inicia captura de voz ao vivo com tolerância a ruído.',
        },
        {
          'command': '/memory',
          'aliases': '/memoria',
          'description':
              'Gerencia correções fonéticas, atalhos de voz e preferências.',
        },
        {
          'command': '/desktop',
          'aliases': '/pc',
          'description':
              'Pareamento e controle bidirecional Desktop LAN via HMAC-SHA256.',
        },
        {
          'command': '/security',
          'aliases': '/seguranca, /duress',
          'description': 'Painel de segurança, Duress PIN e Kill Switch LAN.',
        },
        {
          'command': '/settings',
          'aliases': '/config, /configuracoes, /ajustes',
          'description':
              'Abre a central de provedores de IA, chaves e modelos.',
        },
        {
          'command': '/history',
          'aliases': '/historico',
          'description':
              'Abre o histórico completo de conversas salvo no SQLCipher local.',
        },
        {
          'command': '/lock',
          'aliases': '/travar, /bloquear',
          'description': 'Bloqueia imediatamente a sessão do app.',
        },
        {
          'command': '/clear',
          'aliases': '/limpar, /expurgar',
          'description':
              'Expurga permanentemente o histórico local de conversas.',
        },
        {
          'command': '/vault',
          'aliases': '/obsidian, /cerebro, /segundocerebro',
          'description':
              'Abre o cofre Obsidian ou salva ideia rápida no Inbox.',
        },
        {
          'command': '/buscar <consulta>',
          'aliases': '/search, /rag',
          'description':
              'Busca léxica local (SQLite FTS5) nas notas do ULTRON-Vault.',
        },
        {
          'command': '/visao [camera|galeria]',
          'aliases': '/vision, /camera, /ocr',
          'description':
              'Captura foto ou seleciona print para análise visual (OCR/QR/VLM).',
        },
        {
          'command': '/pc <status|abrir|midia|clipboard|skill>',
          'aliases': '/desktop',
          'description':
              'Envia comandos remotos autenticados ao PC pareado na LAN.',
        },
        {
          'command': '/agenda [hoje|semana|criar <evento>]',
          'aliases': '/calendar, /evento, /eventos',
          'description':
              'Lê compromissos do Android ou agenda um novo evento (CalendarContract).',
        },
        {
          'command': '/briefing [cidade|cidade <nome>]',
          'aliases': '/bomdia, /resumodia',
          'description':
              'Briefing matinal unificado: Agenda + Sentinela de Mensagens + Clima + Telemetria.',
        },
        {
          'command': '/audit',
          'aliases': '/auditoria, /logs',
          'description':
              'Verifica a cadeia SHA-256 do log imutável de auditoria e exibe ações recentes.',
        },
      ];
}
