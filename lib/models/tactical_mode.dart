/// Categorias de tags `[ACTION:...]` disponibilizadas ao LLM conforme o modo tático.
enum TacticalActionCategory {
  /// Núcleo mínimo transversal sempre disponível (notas, lembretes, volume, timer).
  core,

  /// Hardware do aparelho (lanterna, apps, câmera, configurações, vibração, mídia).
  hardware,

  /// Mensagens e ligações (WhatsApp, SMS, notificações, discagem).
  messaging,

  /// CRUD completo do cofre Obsidian (listar, tarefas, status, desfazer).
  obsidian,

  /// Skills procedurais e Fluxos agendados.
  skillsAndFlows,

  /// Pesquisa web, clima e notícias RSS.
  webAndInfo,

  /// Agenda / calendário do dispositivo.
  calendar,

  /// Spotify Web API.
  spotify,

  /// Controle remoto do PC / Desktop via Ponte LAN.
  desktop,
}

/// Perfil/Modo Tático isolado ("Helper") com diretriz enxuta, pasta de memória
/// específica no cofre Obsidian, histórico separado e ferramentas filtradas.
class TacticalMode {
  const TacticalMode({
    required this.id,
    required this.label,
    required this.shortLabel,
    required this.description,
    required this.conversationId,
    required this.allowedCategories,
    required this.personaDirective,
    this.vaultPathPrefix,
  });

  final String id;
  final String label;
  final String shortLabel;
  final String description;
  final String conversationId;
  final String? vaultPathPrefix;
  final Set<TacticalActionCategory> allowedCategories;
  final String personaDirective;

  bool get isGeneral => id == geral.id;

  static const geral = TacticalMode(
    id: 'geral',
    label: 'Geral',
    shortLabel: 'GERAL',
    description: 'Assistente completo com acesso a todo o cofre e todas as ferramentas.',
    conversationId: 'default',
    vaultPathPrefix: null,
    allowedCategories: {
      TacticalActionCategory.core,
      TacticalActionCategory.hardware,
      TacticalActionCategory.messaging,
      TacticalActionCategory.obsidian,
      TacticalActionCategory.skillsAndFlows,
      TacticalActionCategory.webAndInfo,
      TacticalActionCategory.calendar,
      TacticalActionCategory.spotify,
      TacticalActionCategory.desktop,
    },
    personaDirective:
        'Modo Geral ativo: acesso completo ao hardware Android, Obsidian, web e ponte LAN Desktop.',
  );

  static const engenharia = TacticalMode(
    id: 'engenharia',
    label: 'Engenharia / Automação',
    shortLabel: 'ENG',
    description: 'Foco em eletrônica, automação, hardware, cálculos técnicos e Ponte Desktop.',
    conversationId: 'mode_engenharia',
    vaultPathPrefix: 'Memoria/Engenharia',
    allowedCategories: {
      TacticalActionCategory.core,
      TacticalActionCategory.obsidian,
      TacticalActionCategory.webAndInfo,
      TacticalActionCategory.desktop,
    },
    personaDirective:
        'Você está no MODO ENGENHARIA/AUTOMAÇÃO do U.L.T.R.O.N. Seja preciso em cálculos, '
        'eletrônica, protocolos, automação e diagnóstico técnico. Salve aprendizados técnicos em Memoria/Engenharia/.',
  );

  static const estudos = TacticalMode(
    id: 'estudos',
    label: 'Estudos / ENEM',
    shortLabel: 'ESTUDOS',
    description: 'Tutor didático focado em resumos, questões, revisão espaçada e foco.',
    conversationId: 'mode_estudos',
    vaultPathPrefix: 'Memoria/Estudos',
    allowedCategories: {
      TacticalActionCategory.core,
      TacticalActionCategory.obsidian,
      TacticalActionCategory.webAndInfo,
      TacticalActionCategory.calendar,
    },
    personaDirective:
        'Você está no MODO ESTUDOS/ENEM do U.L.T.R.O.N. Explique passo a passo com clareza, '
        'use analogias objetivas, proponha exercícios rápidos e salve resumos em Memoria/Estudos/.',
  );

  static const treino = TacticalMode(
    id: 'treino',
    label: 'Treino / Dieta',
    shortLabel: 'TREINO',
    description: 'Acompanhamento de treinos, progressão de carga, nutrição e recuperação.',
    conversationId: 'mode_treino',
    vaultPathPrefix: 'Memoria/Treino',
    allowedCategories: {
      TacticalActionCategory.core,
      TacticalActionCategory.obsidian,
      TacticalActionCategory.calendar,
      TacticalActionCategory.spotify,
    },
    personaDirective:
        'Você está no MODO TREINO/DIETA do U.L.T.R.O.N. Registre séries, cargas, metas calóricas '
        'e rotina de descanso de forma direta em Memoria/Treino/. Priorize segurança biomecânica.',
  );

  static const dev = TacticalMode(
    id: 'dev',
    label: 'Dev / Código',
    shortLabel: 'DEV',
    description: 'Arquitetura de software, debugging, scripts e execução assistida no PC.',
    conversationId: 'mode_dev',
    vaultPathPrefix: 'Memoria/Dev',
    allowedCategories: {
      TacticalActionCategory.core,
      TacticalActionCategory.obsidian,
      TacticalActionCategory.webAndInfo,
      TacticalActionCategory.desktop,
    },
    personaDirective:
        'Você está no MODO DEV/CÓDIGO do U.L.T.R.O.N. Responda com código limpo, análise de causa raiz, '
        'boas práticas de segurança e arquitetura. Salve notas técnicas em Memoria/Dev/.',
  );

  static const List<TacticalMode> presets = <TacticalMode>[
    geral,
    engenharia,
    estudos,
    treino,
    dev,
  ];

  /// Resolve um modo tático a partir de nome, apelido ou ID.
  static TacticalMode? parse(String raw) {
    final norm = raw
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ç', 'c');
    if (norm.isEmpty) return null;
    return switch (norm) {
      'geral' || 'default' || 'padrao' || 'normal' || 'todos' || 'all' => geral,
      'engenharia' || 'eng' || 'automacao' || 'hardware' => engenharia,
      'estudos' || 'estudo' || 'enem' || 'prova' || 'escola' => estudos,
      'treino' || 'dieta' || 'academia' || 'saude' || 'fitness' => treino,
      'dev' || 'codigo' || 'code' || 'programacao' || 'software' => dev,
      _ => null,
    };
  }
}
