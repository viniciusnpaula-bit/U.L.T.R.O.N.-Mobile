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
  undo,
  reminder,
  weather,
  news,
  websearch,
  flow,
  spotify,
  files,
  mode,
  eletrica,
  research,
  opengym,
  island,
  dj,
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
    '/obsidian_notas': UltronCommand.vault,
    '/obsidian_ler': UltronCommand.vault,
    '/obsidian_anexar': UltronCommand.vault,
    '/obsidian_tarefas': UltronCommand.vault,
    '/obsidian_status': UltronCommand.vault,
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
    '/cancelar_evento': UltronCommand.calendar,
    '/briefing': UltronCommand.briefing,
    '/bomdia': UltronCommand.briefing,
    '/resumodia': UltronCommand.briefing,
    '/audit': UltronCommand.audit,
    '/auditoria': UltronCommand.audit,
    '/logs': UltronCommand.audit,
    '/desfazer': UltronCommand.undo,
    '/undo': UltronCommand.undo,
    '/reverter': UltronCommand.undo,
    '/lembrete': UltronCommand.reminder,
    '/lembretes': UltronCommand.reminder,
    '/reminder': UltronCommand.reminder,
    '/reminders': UltronCommand.reminder,
    '/clima': UltronCommand.weather,
    '/weather': UltronCommand.weather,
    '/tempo': UltronCommand.weather,
    '/noticias': UltronCommand.news,
    '/noticia': UltronCommand.news,
    '/news': UltronCommand.news,
    '/manchetes': UltronCommand.news,
    '/pesquisar_web': UltronCommand.websearch,
    '/web': UltronCommand.websearch,
    '/websearch': UltronCommand.websearch,
    '/fluxo': UltronCommand.flow,
    '/fluxos': UltronCommand.flow,
    '/flow': UltronCommand.flow,
    '/flows': UltronCommand.flow,
    '/spotify': UltronCommand.spotify,
    '/spotify_buscar': UltronCommand.spotify,
    '/spotify_estado': UltronCommand.spotify,
    '/spotify_tocar': UltronCommand.spotify,
    '/spotify_listar_playlists': UltronCommand.spotify,
    '/spotify_adicionar_playlist': UltronCommand.spotify,
    '/arquivos': UltronCommand.files,
    '/files': UltronCommand.files,
    '/limpar_duplicados': UltronCommand.files,
    '/converter_imagens': UltronCommand.files,
    '/organizar_pdf_downloads': UltronCommand.files,
    '/etl': UltronCommand.files,
    '/lote_documentos': UltronCommand.files,
    '/modo': UltronCommand.mode,
    '/mode': UltronCommand.mode,
    '/agente': UltronCommand.mode,
    '/helper': UltronCommand.mode,
    '/eletrica': UltronCommand.eletrica,
    '/projetista': UltronCommand.eletrica,
    '/cadesimu': UltronCommand.eletrica,
    '/motor': UltronCommand.eletrica,
    '/pesquisa': UltronCommand.research,
    '/pesquisar': UltronCommand.research,
    '/research': UltronCommand.research,
    '/deep': UltronCommand.research,
    '/opengym': UltronCommand.opengym,
    '/open_gym': UltronCommand.opengym,
    '/gym': UltronCommand.opengym,
    '/treino_sync': UltronCommand.opengym,
    '/ilha': UltronCommand.island,
    '/island': UltronCommand.island,
    '/cutout': UltronCommand.island,
    '/ilha_dinamica': UltronCommand.island,
    '/dj': UltronCommand.dj,
    '/curador': UltronCommand.dj,
    '/bpm': UltronCommand.dj,
    '/setlist': UltronCommand.dj,
  };

  static CommandResult? parse(String input) {
    final text = input.trim();
    if (!text.startsWith('/')) return null;
    final parts = text.split(RegExp(r'\s+'));
    final commandKey = parts.first.toLowerCase();
    final command = commands[commandKey];
    if (command == null) return null;
    final rawArg = parts.skip(1).join(' ').trim();
    return switch (commandKey) {
      '/obsidian_notas' => CommandResult(
          command,
          rawArg.isEmpty ? 'notas' : 'notas $rawArg',
        ),
      '/obsidian_ler' => CommandResult(
          command,
          rawArg.isEmpty ? 'ler' : 'ler $rawArg',
        ),
      '/obsidian_anexar' => CommandResult(
          command,
          rawArg.isEmpty ? 'anexar' : 'anexar $rawArg',
        ),
      '/obsidian_tarefas' => CommandResult(
          command,
          rawArg.isEmpty ? 'tarefas' : 'tarefas $rawArg',
        ),
      '/obsidian_status' => const CommandResult(
          UltronCommand.vault,
          'status',
        ),
      '/cancelar_evento' => CommandResult(
          command,
          rawArg.isEmpty ? 'cancelar' : 'cancelar $rawArg',
        ),
      '/spotify_buscar' => CommandResult(
          command,
          rawArg.isEmpty ? 'buscar' : 'buscar $rawArg',
        ),
      '/spotify_estado' => const CommandResult(
          UltronCommand.spotify,
          'estado',
        ),
      '/spotify_tocar' => CommandResult(
          command,
          rawArg.isEmpty ? 'tocar' : 'tocar $rawArg',
        ),
      '/spotify_listar_playlists' => const CommandResult(
          UltronCommand.spotify,
          'playlists',
        ),
      '/spotify_adicionar_playlist' => CommandResult(
          command,
          rawArg.isEmpty ? 'adicionar' : 'adicionar $rawArg',
        ),
      '/limpar_duplicados' => CommandResult(
          command,
          rawArg.isEmpty ? 'duplicados' : 'duplicados $rawArg',
        ),
      '/converter_imagens' => CommandResult(
          command,
          rawArg.isEmpty ? 'converter' : 'converter $rawArg',
        ),
      '/organizar_pdf_downloads' => CommandResult(
          command,
          rawArg.isEmpty ? 'pdfs' : 'pdfs $rawArg',
        ),
      '/etl' || '/lote_documentos' => CommandResult(
          command,
          rawArg.isEmpty ? 'lote' : 'lote $rawArg',
        ),
      _ => CommandResult(command, rawArg),
    };
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
        {
          'command': '/desfazer',
          'aliases': '/undo, /reverter',
          'description':
              'Desfaz a última operação mutável realizada no cofre Obsidian.',
        },
        {
          'command': '/lembrete [listar|cancelar <id>|<texto e horário>]',
          'aliases': '/lembretes, /reminder',
          'description':
              'Gerencia lembretes persistentes em SQLite com notificação agendada via AlarmManager.',
        },
        {
          'command': '/clima [cidade]',
          'aliases': '/weather, /tempo',
          'description':
              'Consulta previsão meteorológica atual sem necessidade de chave de API.',
        },
        {
          'command': '/noticias [tema]',
          'aliases': '/news, /manchetes',
          'description':
              'Busca manchetes atualizadas via feeds RSS públicos em português.',
        },
        {
          'command': '/pesquisar_web <consulta>',
          'aliases': '/web, /websearch',
          'description':
              'Pesquisa textual resumida direto no chat sem abrir o navegador.',
        },
        {
          'command':
              '/fluxo [listar|criar <nome>|<passos>|[horario]|rodar <nome>|agendar <nome>|<horario>|excluir <nome>]',
          'aliases': '/fluxos, /flow',
          'description':
              'Gerencia fluxos dinâmicos encadeando ações/skills com agendamento nativo e AuthGate.',
        },
        {
          'command':
              '/spotify [estado|buscar <termo>|tocar <faixa/uri>|playlists|adicionar <playlist>|[faixa]]',
          'aliases': '/spotify_tocar, /spotify_buscar, /spotify_estado',
          'description':
              'Controla a Spotify Web API via OAuth 2.0 PKCE (estado, busca, reprodução e playlists).',
        },
        {
          'command':
              '/arquivos [duplicados [pasta]|converter [jpg|png] [pasta]|pdfs [pasta]|lote [saf|pasta]]',
          'aliases':
              '/limpar_duplicados, /converter_imagens, /organizar_pdf_downloads, /etl',
          'description':
              'Utilitários de arquivos via SAF/Downloads: limpeza SHA-256, conversão .webp/.heic, padronização de PDFs e ETL em lote para Inbox/ do Obsidian.',
        },
        {
          'command': '/modo [geral|engenharia|estudos|treino|dev|musica]',
          'aliases': '/mode, /agente, /helper',
          'description':
              'Alterna entre Modos Táticos isolados com memória filtrada no Obsidian, histórico separado e ferramentas enxutas.',
        },
        {
          'command':
              '/eletrica [direta|reversao|estrela|sequencia] [X cv] [220v|380v] [cfw500|ad600m] [pc]',
          'aliases': '/projetista, /cadesimu, /motor',
          'description':
              'Projetista Elétrico offline (NBR 5410, auditoria estrutural, Netlist, SVG IEC e envio ao Desktop/CADe_SIMU).',
        },
        {
          'command': '/pesquisa [pc] <tema> | /pesquisa status | /pesquisa cancelar <id>',
          'aliases': '/pesquisar, /research, /deep',
          'description':
              'Executa pesquisa profunda assíncrona (local ou delegada ao PC via LAN) com relatório Markdown no Obsidian.',
        },
        {
          'command': '/opengym [importar|auto|resumo|abrir]',
          'aliases': '/open_gym, /gym, /treino_sync',
          'description':
              'Importa backups JSON/CSV offline do app openGym para o Obsidian (Modo Treino) com PRs, volume e peso corporal.',
        },
        {
          'command': '/ilha [on|off|status]',
          'aliases': '/island, /cutout, /ilha_dinamica',
          'description':
              'Ativa ou desativa a Ilha Dinâmica (Expressive Cutout) ancorada no recorte da câmera frontal.',
        },
        {
          'command': '/dj [humor/bpm|transicao <chave>|players|salvar <pedido>|pc <app>]',
          'aliases': '/curador, /bpm, /setlist',
          'description':
              'Curadoria criativa por humor, BPM, contexto e Roda de Camelot, com integração multi-player e controladores DJ.',
        },
      ];
}
