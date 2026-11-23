/// Utilitários de texto para a voz do U.L.T.R.O.N.
///
/// [SpeechText] converte respostas pensadas para a tela (markdown, emojis,
/// links, siglas) em frases naturais para o motor TTS e divide textos longos
/// em blocos curtos, respeitando o limite de entrada dos motores Android.
///
/// [WakeWord] reconhece a palavra de ativação "Ultron" com tolerância às
/// transcrições erradas mais comuns do reconhecedor em pt-BR.
library;

class SpeechText {
  SpeechText._();

  /// Tamanho máximo de cada bloco enviado ao TTS.
  static const int maxChunkChars = 220;

  /// Limite padrão de fala; o restante fica apenas na tela.
  static const int defaultMaxSpokenChars = 700;

  static final RegExp _codeBlock = RegExp(r'```[\s\S]*?```');
  static final RegExp _inlineCode = RegExp(r'`([^`]*)`');
  static final RegExp _mdLink = RegExp(r'\[([^\]]+)\]\((?:[^)]+)\)');
  static final RegExp _url = RegExp(r'https?://\S+|www\.\S+');
  static final RegExp _actionTag =
      RegExp(r'\[(?:ACTION|Hardware)[^\]]*\]', caseSensitive: false);
  static final RegExp _emoji = RegExp(
    r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{2190}-\u{21FF}\u{FE0F}\u{200D}\u{20E3}]',
    unicode: true,
  );
  static final RegExp _ultronDotted =
      RegExp(r'U\.?\s?L\.?\s?T\.?\s?R\.?\s?O\.?\s?N\.?', caseSensitive: false);
  static final RegExp _bullet = RegExp(r'^\s*(?:[-*•▪►]|\d{1,2}[.)])\s+');
  static final RegExp _heading = RegExp(r'^\s*#{1,6}\s*');
  static final RegExp _quote = RegExp(r'^\s*>\s?');
  static final RegExp _emphasis = RegExp(r'(\*\*|__|\*|~~)');
  static final RegExp _allCapsWord = RegExp(r'\b[A-ZÀ-Ý]{5,}\b');
  static final RegExp _currency = RegExp(r'R\$\s?(\d+(?:[.,]\d+)?)');

  /// Limpa o texto para soar natural quando falado.
  static String sanitize(String raw) {
    var text = raw;
    text = text.replaceAll(_codeBlock, ' Trecho de código exibido na tela. ');
    text = text.replaceAllMapped(_inlineCode, (m) => m.group(1) ?? '');
    text = text.replaceAllMapped(_mdLink, (m) => m.group(1) ?? '');
    text = text.replaceAll(_url, 'link na tela');
    text = text.replaceAll(_actionTag, ' ');
    text = text.replaceAll(_ultronDotted, 'Ultron');
    text = text.replaceAll(_emoji, ' ');

    final lines = text.split(RegExp(r'\r?\n'));
    final buffer = StringBuffer();
    for (final rawLine in lines) {
      var line = rawLine
          .replaceFirst(_heading, '')
          .replaceFirst(_quote, '')
          .replaceFirst(_bullet, '')
          .replaceAll(_emphasis, '')
          .replaceAll('_', ' ')
          .replaceAll('|', ', ')
          .trim();
      if (line.isEmpty || RegExp(r'^[-=_:,.\s]+$').hasMatch(line)) continue;
      if (!RegExp(r'[.!?;:…]$').hasMatch(line)) line = '$line.';
      buffer.write('$line ');
    }
    text = buffer.toString();

    // Palavras em CAIXA ALTA longas são soletradas por alguns motores.
    text = text.replaceAllMapped(_allCapsWord, (m) => m.group(0)!.toLowerCase());
    text = text.replaceAllMapped(_currency, (m) => '${m.group(1)} reais');
    text = text
        .replaceAll('°C', ' graus')
        .replaceAll('ºC', ' graus')
        .replaceAll('&', ' e ')
        .replaceAll(RegExp(r'\s*[•→]\s*'), ', ')
        .replaceAllMapped(RegExp(r'\s+([,.!?;:])'), (m) => m.group(1)!)
        .replaceAllMapped(RegExp(r'([,.!?;:])[,.!?;:]+'), (m) => m.group(1)!)
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    return text;
  }

  /// Higieniza e divide o texto em blocos curtos prontos para o TTS.
  ///
  /// Se o texto ultrapassar [maxSpokenChars], a fala é encerrada na última
  /// frase completa e um aviso curto é acrescentado.
  static List<String> prepareChunks(
    String raw, {
    int maxSpokenChars = defaultMaxSpokenChars,
  }) {
    final clean = sanitize(raw);
    if (clean.isEmpty) return const [];

    final sentences = RegExp(r'[^.!?;…]+[.!?;…]*')
        .allMatches(clean)
        .map((m) => m.group(0)!.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final chunks = <String>[];
    var spoken = 0;
    var truncated = false;
    var current = StringBuffer();

    void flush() {
      final value = current.toString().trim();
      if (value.isNotEmpty) chunks.add(value);
      current = StringBuffer();
    }

    for (final sentence in sentences) {
      if (spoken + sentence.length > maxSpokenChars && chunks.isNotEmpty) {
        truncated = true;
        break;
      }
      for (final piece in _splitLong(sentence)) {
        if (current.length + piece.length + 1 > maxChunkChars) flush();
        current.write('$piece ');
      }
      spoken += sentence.length;
    }
    flush();
    if (truncated) chunks.add('O restante está na tela.');
    return chunks;
  }

  static Iterable<String> _splitLong(String sentence) sync* {
    if (sentence.length <= maxChunkChars) {
      yield sentence;
      return;
    }
    final words = sentence.split(' ');
    var current = StringBuffer();
    for (final word in words) {
      if (current.length + word.length + 1 > maxChunkChars) {
        yield current.toString().trim();
        current = StringBuffer();
      }
      current.write('$word ');
    }
    final rest = current.toString().trim();
    if (rest.isNotEmpty) yield rest;
  }
}

/// Perfis de palavra de ativação (Wake-Word) suportados pelo U.L.T.R.O.N.
enum WakeWordProfile {
  ultron(
    id: 'ultron',
    label: 'Ultron',
    target: 'ultron',
    minLength: 4,
    maxLength: 8,
  ),
  jarvis(
    id: 'jarvis',
    label: 'Jarvis',
    target: 'jarvis',
    minLength: 4,
    maxLength: 8,
  ),
  edith(
    id: 'edith',
    label: 'Edith',
    target: 'edith',
    minLength: 4,
    maxLength: 7,
  ),
  visao(
    id: 'visao',
    label: 'Visão',
    target: 'visao',
    minLength: 4,
    maxLength: 8,
  );

  const WakeWordProfile({
    required this.id,
    required this.label,
    required this.target,
    required this.minLength,
    required this.maxLength,
  });

  final String id;
  final String label;
  final String target;
  final int minLength;
  final int maxLength;

  static WakeWordProfile fromId(String? raw) {
    final clean = WakeWord.normalize(raw ?? '');
    for (final profile in WakeWordProfile.values) {
      if (profile.id == clean ||
          WakeWord.normalize(profile.label) == clean ||
          (profile == WakeWordProfile.visao && clean == 'vision')) {
        return profile;
      }
    }
    return WakeWordProfile.ultron;
  }
}

class WakeWord {
  WakeWord._();

  /// Perfil de wake-word atualmente selecionado pelo operador.
  static WakeWordProfile activeProfile = WakeWordProfile.ultron;

  static void setActiveProfile(WakeWordProfile profile) {
    activeProfile = profile;
  }

  static WakeWordProfile setActiveProfileById(String? id) {
    activeProfile = WakeWordProfile.fromId(id);
    return activeProfile;
  }

  /// Mapa de aliases fonéticos em pt-BR por perfil de wake-word.
  static const Map<WakeWordProfile, Set<String>> profileAliases = {
    WakeWordProfile.ultron: {
      'ultron',
      'ultrom',
      'outron',
      'oultron',
      'uoltron',
      'hultron',
      'ultrón',
      'utron',
      'ultrao',
      'ultrão',
      'ultram',
      'ultran',
      'altron',
    },
    WakeWordProfile.jarvis: {
      'jarvis',
      'jarves',
      'jarviz',
      'djarvis',
      'javis',
      'jarvi',
      'yarvis',
      'garvis',
      'jarbas',
    },
    WakeWordProfile.edith: {
      'edith',
      'edite',
      'edit',
      'editi',
      'edid',
      'hedith',
      'eddy',
    },
    WakeWordProfile.visao: {
      'visao',
      'visão',
      'vizao',
      'vizão',
      'vision',
      'vison',
      'fisao',
      'vizaum',
    },
  };

  /// Aliases do perfil ativo (mantém compatibilidade retroativa).
  static Set<String> get aliases => profileAliases[activeProfile]!;

  /// Retorna os aliases configurados para um [profile] específico.
  static Set<String> aliasesFor(WakeWordProfile profile) =>
      profileAliases[profile] ?? const <String>{};

  static final RegExp _leadingFiller = RegExp(
    r'^(?:ei|hey|ok|oi|olá|ola|e ai|e aí|fala|alo|alô)[,\s]+',
    caseSensitive: false,
  );

  static String normalize(String word) => _normalize(word);

  static String _normalize(String word) {
    const from = 'áàâãäéèêëíìîïóòôõöúùûüç';
    const to = 'aaaaaeeeeiiiiooooouuuuc';
    final lower = word.toLowerCase();
    final out = StringBuffer();
    for (final rune in lower.runes) {
      final ch = String.fromCharCode(rune);
      final idx = from.indexOf(ch);
      out.write(idx >= 0 ? to[idx] : ch);
    }
    return out.toString().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static int levenshtein(String a, String b) => _levenshtein(a, b);

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 0; i < a.length; i++) {
      final curr = List<int>.filled(b.length + 1, 0);
      curr[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a[i] == b[j] ? 0 : 1;
        curr[j + 1] = [curr[j] + 1, prev[j + 1] + 1, prev[j] + cost]
            .reduce((x, y) => x < y ? x : y);
      }
      prev = curr;
    }
    return prev[b.length];
  }

  static bool _matchesSingleProfile(String normalizedToken, WakeWordProfile p) {
    if (normalizedToken.length < p.minLength ||
        normalizedToken.length > p.maxLength) {
      return false;
    }
    final normalizedAliases = profileAliases[p]!.map(_normalize);
    if (normalizedAliases.contains(normalizedToken)) return true;
    return _levenshtein(normalizedToken, p.target) <= 1;
  }

  /// Verdadeiro se [token] soa como a wake-word do [profile] (ou [activeProfile]).
  /// Se [anyProfile] for true, testa todos os perfis suportados.
  static bool isHotwordToken(
    String token, {
    WakeWordProfile? profile,
    bool anyProfile = false,
  }) {
    final n = _normalize(token);
    if (n.isEmpty) return false;
    if (anyProfile) {
      for (final p in WakeWordProfile.values) {
        if (_matchesSingleProfile(n, p)) return true;
      }
      return false;
    }
    final targetProfile = profile ?? activeProfile;
    return _matchesSingleProfile(n, targetProfile);
  }

  /// Posição (índice de palavra) da palavra de ativação, ou -1.
  static int hotwordIndex(
    String phrase, {
    WakeWordProfile? profile,
    bool anyProfile = false,
  }) {
    final trimmed = phrase.trim();
    if (trimmed.isEmpty) return -1;
    final words = trimmed.split(RegExp(r'\s+'));
    for (var i = 0; i < words.length && i < 4; i++) {
      if (isHotwordToken(words[i], profile: profile, anyProfile: anyProfile)) {
        return i;
      }
    }
    return -1;
  }

  static bool contains(
    String phrase, {
    WakeWordProfile? profile,
    bool anyProfile = false,
  }) =>
      hotwordIndex(phrase, profile: profile, anyProfile: anyProfile) >= 0;

  /// Detecta qual perfil de wake-word está presente na frase, ou null.
  static WakeWordProfile? detectProfile(String phrase) {
    if (contains(phrase, profile: activeProfile)) {
      return activeProfile;
    }
    for (final p in WakeWordProfile.values) {
      if (p != activeProfile && contains(phrase, profile: p)) {
        return p;
      }
    }
    return null;
  }

  /// Remove a saudação + wake-word ("Ei Ultron,", "Ok Jarvis,", etc.) do início
  /// e devolve apenas o comando (pode ser vazio).
  static String extractCommand(
    String phrase, {
    WakeWordProfile? profile,
    bool anyProfile = false,
  }) {
    final trimmed = phrase.trim();
    if (trimmed.isEmpty) return '';
    final words = trimmed.split(RegExp(r'\s+'));
    var idx = hotwordIndex(
      phrase,
      profile: profile,
      anyProfile: anyProfile,
    );
    if (idx < 0 && profile == null && !anyProfile) {
      idx = hotwordIndex(phrase, anyProfile: true);
    }
    if (idx < 0) return trimmed;
    final rest = words.sublist(idx + 1).join(' ');
    return rest
        .replaceFirst(RegExp(r'^[,.:;!?\s]+'), '')
        .replaceFirst(_leadingFiller, '')
        .trim();
  }
}
