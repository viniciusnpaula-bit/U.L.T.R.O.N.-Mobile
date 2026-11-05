enum UltronCommand {
  help,
  security,
  history,
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
          'command': '/device',
          'aliases': '/celular, /telemetria',
          'description': 'Abre cockpit com telemetria circular (RAM, bateria, °C, sensores).',
        },
        {
          'command': '/lanterna [on|off|toggle]',
          'aliases': '/torch, /flash',
          'description': 'Controla o LED de flash traseiro do smartphone.',
        },
        {
          'command': '/note <texto>',
          'aliases': '/nota, /anote',
          'description': 'Quick Capture salvo em ULTRON-Vault/Diario/YYYY-MM-DD.md.',
        },
        {
          'command': '/skills [nome]',
          'aliases': '/skill',
          'description': 'Lista ou executa rotinas procedurais em Skills/*.md.',
        },
        {
          'command': '/models',
          'aliases': '/modelos',
          'description': 'Auto-discovery de modelos ativos no provedor de IA conectado.',
        },
        {
          'command': '/mensagens',
          'aliases': '/notificacoes, /ler',
          'description': 'Sentinela lê notificações recentes em voz alta.',
        },
        {
          'command': '/responder <texto>',
          'aliases': '/reply',
          'description': 'Responde notificação em 2º plano via RemoteInput nativo.',
        },
        {
          'command': '/killswitch',
          'aliases': '/travarpc, /lockpc',
          'description': 'Trava o PC Windows via LAN e encerra a sessão móvel.',
        },
        {
          'command': '/voice',
          'aliases': '/voz, /falar',
          'description': 'Inicia captura de voz ao vivo com tolerância a ruído.',
        },
        {
          'command': '/security',
          'aliases': '/seguranca, /duress',
          'description': 'Painel de segurança, Duress PIN e bloqueio biométrico.',
        },
        {
          'command': '/lock',
          'aliases': '/travar, /bloquear',
          'description': 'Bloqueia imediatamente a sessão do app.',
        },
        {
          'command': '/clear',
          'aliases': '/limpar',
          'description': 'Expurga histórico da sessão de bate-papo atual.',
        },
        {
          'command': '/vault',
          'aliases': '/obsidian, /cerebro',
          'description': 'Abre o cofre Obsidian ou gerencia o Segundo Cérebro.',
        },
      ];
}
