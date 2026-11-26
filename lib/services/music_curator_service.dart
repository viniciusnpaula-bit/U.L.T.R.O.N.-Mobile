import '../models/tactical_mode.dart';
import 'obsidian_service.dart';

enum MusicMood {
  foco('foco', 'Foco Profundo', 72, 98, '4A', ['Lo-Fi Beats', 'Ambient Electronica', 'Synthwave Instrumental', 'Deep Focus']),
  treino('treino', 'Treino Pesado', 128, 146, '8A', ['Tech House', 'Phonk', 'Hardstyle Melódico', 'Electro Rock']),
  corrida('corrida', 'Corrida / Cardio', 156, 174, '10A', ['Drum & Bass', 'Liquid DnB', 'Fast Synthpop', 'Upbeat Indie']),
  festa('festa', 'Set DJ / Festa', 122, 130, '9A', ['House', 'Afro House', 'Melodic Techno', 'Nu-Disco']),
  relax('relax', 'Relaxamento', 62, 84, '2B', ['Chillout', 'Bossa Nova', 'Acoustic Lo-Fi', 'Downtempo']),
  madrugada('madrugada', 'Madrugada / Noturno', 68, 92, '6A', ['Dark Ambient', 'Midnight Synthwave', 'Trip-Hop', 'Deep Chill']),
  melancolico('melancolico', 'Introspectivo', 70, 96, '5A', ['Post-Rock', 'Indie Folk', 'Piano Minimalista', 'Dream Pop']),
  epico('epico', 'Épico / Cinematográfico', 105, 132, '11A', ['Hybrid Orchestral', 'Cyberpunk Score', 'Progressive Trance']),
  energia('energia', 'Alta Energia', 124, 138, '8B', ['Electro House', 'Funk Carioca / Megafunk', 'Big Room', 'Bass House']);

  const MusicMood(
    this.id,
    this.label,
    this.minBpm,
    this.maxBpm,
    this.defaultCamelot,
    this.genres,
  );

  final String id;
  final String label;
  final int minBpm;
  final int maxBpm;
  final String defaultCamelot;
  final List<String> genres;
}

class MediaPlayerProfile {
  const MediaPlayerProfile({
    required this.id,
    required this.label,
    required this.aliases,
    required this.category,
    this.androidPackage,
  });

  final String id;
  final String label;
  final List<String> aliases;
  final String category; // 'streaming' | 'local' | 'dj_mobile' | 'dj_desktop'
  final String? androidPackage;
}

class MusicRecommendationPlan {
  const MusicRecommendationPlan({
    required this.mood,
    required this.targetBpmMin,
    required this.targetBpmMax,
    required this.startCamelot,
    required this.compatibleCamelot,
    required this.contextLabel,
    required this.genres,
    required this.energyArc,
    required this.searchQueries,
    this.preferredPlayer,
    this.savedNotePath,
  });

  final MusicMood mood;
  final int targetBpmMin;
  final int targetBpmMax;
  final String startCamelot;
  final List<String> compatibleCamelot;
  final String contextLabel;
  final List<String> genres;
  final List<String> energyArc;
  final List<String> searchQueries;
  final String? preferredPlayer;
  final String? savedNotePath;

  MusicRecommendationPlan withSavedNotePath(String path) =>
      MusicRecommendationPlan(
        mood: mood,
        targetBpmMin: targetBpmMin,
        targetBpmMax: targetBpmMax,
        startCamelot: startCamelot,
        compatibleCamelot: compatibleCamelot,
        contextLabel: contextLabel,
        genres: genres,
        energyArc: energyArc,
        searchQueries: searchQueries,
        preferredPlayer: preferredPlayer,
        savedNotePath: path,
      );

  String formatChatOutput() {
    final sb = StringBuffer()
      ..writeln('Curadoria Musical / DJ — ${mood.label}')
      ..writeln('• Contexto: $contextLabel')
      ..writeln('• Faixa de BPM: $targetBpmMin–$targetBpmMax BPM')
      ..writeln('• Tom inicial (Camelot): $startCamelot  →  Compatíveis: ${compatibleCamelot.join(', ')}')
      ..writeln('• Gêneros recomendados: ${genres.join(' · ')}');
    if (preferredPlayer != null && preferredPlayer!.isNotEmpty) {
      sb.writeln('• Player / Controlador alvo: $preferredPlayer');
    }
    sb
      ..writeln('• Curva de energia do set:')
      ..writeln(energyArc.map((e) => '  - $e').join('\n'))
      ..writeln('• Buscas rápidas (Spotify / YouTube Music / Deezer / Tidal):')
      ..writeln(searchQueries.map((q) => '  - "$q"').join('\n'));
    if (savedNotePath != null) {
      sb.writeln('• Setlist salvo no Obsidian em `$savedNotePath`.');
    }
    return sb.toString().trim();
  }

  String toObsidianMarkdown({DateTime? createdAt}) {
    final dt = createdAt ?? DateTime.now();
    final dateStr =
        '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '## [$dateStr] ${mood.label} ($targetBpmMin-$targetBpmMax BPM · $startCamelot)\n'
        '- Contexto: $contextLabel\n'
        '- Gêneros: ${genres.join(', ')}\n'
        '- Transições Camelot: ${compatibleCamelot.join(', ')}\n'
        '${energyArc.map((e) => '- $e').join('\n')}\n'
        '- Buscas: ${searchQueries.join(' | ')}\n';
  }

  String get speakText =>
      'Curadoria ${mood.label} pronta entre $targetBpmMin e $targetBpmMax BPM, '
      'começando em $startCamelot com foco em ${genres.take(2).join(' e ')}.';
}

/// Motor criativo de curadoria musical e DJ: combina humor, BPM, Roda de Camelot,
/// horário/modo tático e catálogo ampliado de players e controladores DJ.
class MusicCuratorService {
  const MusicCuratorService();

  static const String setlistsNotePath = 'Memoria/Musica/Setlists.md';

  static const List<MediaPlayerProfile> supportedPlayers = <MediaPlayerProfile>[
    MediaPlayerProfile(
      id: 'spotify',
      label: 'Spotify',
      aliases: ['spotify'],
      category: 'streaming',
      androidPackage: 'com.spotify.music',
    ),
    MediaPlayerProfile(
      id: 'youtube music',
      label: 'YouTube Music',
      aliases: ['youtube music', 'yt music', 'ytmusic'],
      category: 'streaming',
      androidPackage: 'com.google.android.apps.youtube.music',
    ),
    MediaPlayerProfile(
      id: 'youtube',
      label: 'YouTube',
      aliases: ['youtube'],
      category: 'streaming',
      androidPackage: 'com.google.android.youtube',
    ),
    MediaPlayerProfile(
      id: 'deezer',
      label: 'Deezer',
      aliases: ['deezer'],
      category: 'streaming',
      androidPackage: 'deezer.android.app',
    ),
    MediaPlayerProfile(
      id: 'apple music',
      label: 'Apple Music',
      aliases: ['apple music'],
      category: 'streaming',
      androidPackage: 'com.apple.android.music',
    ),
    MediaPlayerProfile(
      id: 'soundcloud',
      label: 'SoundCloud',
      aliases: ['soundcloud', 'sound cloud'],
      category: 'streaming',
      androidPackage: 'com.soundcloud.android',
    ),
    MediaPlayerProfile(
      id: 'tidal',
      label: 'Tidal',
      aliases: ['tidal'],
      category: 'streaming',
      androidPackage: 'com.aspiro.tidal',
    ),
    MediaPlayerProfile(
      id: 'amazon music',
      label: 'Amazon Music',
      aliases: ['amazon music'],
      category: 'streaming',
      androidPackage: 'com.amazon.mp3',
    ),
    MediaPlayerProfile(
      id: 'poweramp',
      label: 'Poweramp',
      aliases: ['poweramp'],
      category: 'local',
      androidPackage: 'com.maxmpz.audioplayer',
    ),
    MediaPlayerProfile(
      id: 'vlc',
      label: 'VLC Media Player',
      aliases: ['vlc'],
      category: 'local',
      androidPackage: 'org.videolan.vlc',
    ),
    MediaPlayerProfile(
      id: 'djay',
      label: 'djay (Algoriddim)',
      aliases: ['djay', 'algoriddim'],
      category: 'dj_mobile',
      androidPackage: 'com.algoriddim.djay_free',
    ),
    MediaPlayerProfile(
      id: 'edjing',
      label: 'edjing Mix',
      aliases: ['edjing', 'edjing mix'],
      category: 'dj_mobile',
      androidPackage: 'com.edjing.edjingdjturntable',
    ),
    MediaPlayerProfile(
      id: 'cross dj',
      label: 'Cross DJ',
      aliases: ['cross dj', 'crossdj'],
      category: 'dj_mobile',
      androidPackage: 'com.mixvibes.crossdjfree',
    ),
    MediaPlayerProfile(
      id: 'rekordbox',
      label: 'Pioneer rekordbox',
      aliases: ['rekordbox', 'pioneer'],
      category: 'dj_desktop',
      androidPackage: 'jp.pioneer.mbg.rekordbox',
    ),
    MediaPlayerProfile(
      id: 'traktor',
      label: 'Traktor DJ',
      aliases: ['traktor'],
      category: 'dj_desktop',
      androidPackage: 'com.nativeinstruments.traktor',
    ),
    MediaPlayerProfile(
      id: 'serato',
      label: 'Serato DJ (Desktop LAN)',
      aliases: ['serato', 'serato dj'],
      category: 'dj_desktop',
    ),
    MediaPlayerProfile(
      id: 'virtualdj',
      label: 'VirtualDJ (Desktop LAN)',
      aliases: ['virtualdj', 'virtual dj'],
      category: 'dj_desktop',
    ),
    MediaPlayerProfile(
      id: 'bandlab',
      label: 'BandLab',
      aliases: ['bandlab'],
      category: 'dj_mobile',
      androidPackage: 'com.bandlab.bandlab',
    ),
  ];

  /// Detecta player ou app DJ citado em uma frase em linguagem natural.
  static MediaPlayerProfile? detectPlayerMention(String text) {
    final lower = text.toLowerCase();
    // Ordena aliases maiores primeiro para "youtube music" vencer "youtube".
    final sorted = [...supportedPlayers]..sort((a, b) {
        final maxA = a.aliases.fold<int>(0, (m, s) => s.length > m ? s.length : m);
        final maxB = b.aliases.fold<int>(0, (m, s) => s.length > m ? s.length : m);
        return maxB.compareTo(maxA);
      });
    for (final player in sorted) {
      for (final alias in player.aliases) {
        if (lower.contains(alias)) return player;
      }
    }
    return null;
  }

  /// Calcula chaves harmonicamente compatíveis na Roda de Camelot (1A..12B).
  static List<String> compatibleCamelotKeys(String rawKey) {
    final m = RegExp(r'^(1[0-2]|[1-9])([AB])$', caseSensitive: false)
        .firstMatch(rawKey.trim());
    if (m == null) return const <String>[];
    final numVal = int.parse(m.group(1)!);
    final letter = m.group(2)!.toUpperCase();
    final other = letter == 'A' ? 'B' : 'A';
    int wrap(int n) => ((n - 1) % 12 + 12) % 12 + 1;
    return <String>[
      '$numVal$letter (mesmo tom)',
      '$numVal$other (relativo)',
      '${wrap(numVal - 1)}$letter (-1 suave)',
      '${wrap(numVal + 1)}$letter (+1 energia)',
      '${wrap(numVal + 2)}$letter (+2 boost)',
    ];
  }

  /// Gera plano criativo combinando humor, faixa de BPM, contexto horário e modo tático.
  MusicRecommendationPlan curate(
    String request, {
    DateTime? now,
    TacticalMode mode = TacticalMode.musica,
    bool nightFocusMode = false,
    String? preferredPlayer,
  }) {
    final refNow = now ?? DateTime.now();
    final lower = request.toLowerCase();

    final mood = _detectMood(
      lower,
      hour: refNow.hour,
      mode: mode,
      nightFocusMode: nightFocusMode,
    );

    final bpmMatch = RegExp(r'\b(\d{2,3})\s*(?:bpm)?\b').firstMatch(lower);
    int minBpm = mood.minBpm;
    int maxBpm = mood.maxBpm;
    if (bpmMatch != null) {
      final parsed = int.tryParse(bpmMatch.group(1)!);
      if (parsed != null && parsed >= 55 && parsed <= 210) {
        minBpm = (parsed - 4).clamp(55, 210);
        maxBpm = (parsed + 4).clamp(55, 210);
      }
    } else if (nightFocusMode && minBpm > 96) {
      minBpm = (minBpm - 18).clamp(62, 120);
      maxBpm = (maxBpm - 18).clamp(72, 130);
    }

    final keyMatch = RegExp(r'\b(1[0-2]|[1-9])([ab])\b', caseSensitive: false)
        .firstMatch(lower);
    final startKey = keyMatch != null
        ? '${keyMatch.group(1)}${keyMatch.group(2)!.toUpperCase()}'
        : mood.defaultCamelot;

    final compatible = compatibleCamelotKeys(startKey);
    final dayPeriod = _periodLabel(refNow.hour);
    final contextBits = <String>[
      dayPeriod,
      'Modo ${mode.label}',
      if (nightFocusMode) 'Foco Noturno ativo',
    ];

    final detectedPlayer = preferredPlayer ?? detectPlayerMention(request)?.label;
    final midBpm = ((minBpm + maxBpm) / 2).round();
    final energyArc = <String>[
      'Aquecimento (0-15 min): ${mood.genres.first} em $minBpm BPM ($startKey)',
      'Pico (15-40 min): ${mood.genres[mood.genres.length > 1 ? 1 : 0]} em $midBpm–$maxBpm BPM (${compatible.length > 3 ? compatible[3] : startKey})',
      'Fechamento (40-55 min): ${mood.genres.last} retornando para ${(minBpm - 6).clamp(60, 180)} BPM (${compatible.length > 1 ? compatible[1] : startKey})',
    ];

    final queries = <String>[
      '${mood.genres.first} $midBpm bpm ${mood.id}',
      '${mood.genres.length > 1 ? mood.genres[1] : mood.genres.first} mix $minBpm-$maxBpm bpm',
      if (mode == TacticalMode.treino) 'workout gym ${mood.genres.first} $maxBpm bpm',
      if (mode != TacticalMode.treino) '${mood.genres.last} $dayPeriod instrumental',
    ];

    return MusicRecommendationPlan(
      mood: mood,
      targetBpmMin: minBpm,
      targetBpmMax: maxBpm,
      startCamelot: startKey,
      compatibleCamelot: compatible,
      contextLabel: contextBits.join(' · '),
      genres: mood.genres,
      energyArc: energyArc,
      searchQueries: queries,
      preferredPlayer: detectedPlayer,
    );
  }

  Future<MusicRecommendationPlan> saveSetlistToObsidian(
    MusicRecommendationPlan plan,
    ObsidianService obsidian, {
    DateTime? now,
  }) async {
    await obsidian.initialize();
    await obsidian.appendToNote(
      setlistsNotePath,
      plan.toObsidianMarkdown(createdAt: now),
      createIfMissing: true,
    );
    return plan.withSavedNotePath(setlistsNotePath);
  }

  String formatSupportedPlayersList() {
    final streaming = supportedPlayers
        .where((p) => p.category == 'streaming')
        .map((p) => p.label)
        .join(', ');
    final local = supportedPlayers
        .where((p) => p.category == 'local')
        .map((p) => p.label)
        .join(', ');
    final djMobile = supportedPlayers
        .where((p) => p.category == 'dj_mobile')
        .map((p) => p.label)
        .join(', ');
    final djDesktop = supportedPlayers
        .where((p) => p.category == 'dj_desktop')
        .map((p) => p.label)
        .join(', ');
    return 'Players e Controladores DJ integrados:\n'
        '• Streaming Android: $streaming\n'
        '• Players locais Android: $local\n'
        '• Apps DJ Mobile: $djMobile\n'
        '• Controladores / Software DJ (via Ponte Desktop LAN): $djDesktop';
  }

  /// Diretriz dinâmica enxuta para injetar no System Prompt do Modo Música/DJ.
  static String buildPromptGuidance({
    DateTime? now,
    TacticalMode mode = TacticalMode.musica,
    bool nightFocusMode = false,
  }) {
    final refNow = now ?? DateTime.now();
    final period = _periodLabel(refNow.hour);
    final suggestedMood = _detectMood(
      '',
      hour: refNow.hour,
      mode: mode,
      nightFocusMode: nightFocusMode,
    );
    return '=== MOTOR CRIATIVO DE MÚSICA & DJ ===\n'
        'Período atual: $period | Sugestão base: ${suggestedMood.label} '
        '(${suggestedMood.minBpm}-${suggestedMood.maxBpm} BPM, chave ${suggestedMood.defaultCamelot}).\n'
        'Ao recomendar músicas, playlists ou sets: combine explicitamente humor + faixa de BPM + contexto do usuário '
        '(horário, atividade, energia e transições harmônicas Camelot quando for set DJ).\n'
        'Players suportados no Android e Desktop LAN: Spotify, YouTube Music, Deezer, Apple Music, SoundCloud, '
        'Tidal, Amazon Music, Poweramp, VLC, djay, edjing Mix, Cross DJ, rekordbox, Traktor, Serato e VirtualDJ.';
  }

  static MusicMood _detectMood(
    String lower, {
    required int hour,
    required TacticalMode mode,
    required bool nightFocusMode,
  }) {
    if (RegExp(r'\b(corrida|correr|cardio|sprint|hiit|esteira)\b').hasMatch(lower)) {
      return MusicMood.corrida;
    }
    if (RegExp(r'\b(treino|academia|musculacao|musculação|pesado|gym|forca|força)\b')
        .hasMatch(lower)) {
      return MusicMood.treino;
    }
    if (RegExp(r'\b(festa|balada|set|pista|club|house|techno|dj)\b')
        .hasMatch(lower)) {
      return MusicMood.festa;
    }
    if (RegExp(r'\b(foco|estudar|estudo|programar|codigo|código|trabalho|concentracao|concentração|deep)\b')
        .hasMatch(lower)) {
      return MusicMood.foco;
    }
    if (RegExp(r'\b(relax|descansar|calmo|calma|dormir|chill|suave|bossa)\b')
        .hasMatch(lower)) {
      return MusicMood.relax;
    }
    if (RegExp(r'\b(madrugada|noite|noturno|lofi|lo-fi|chuva)\b')
        .hasMatch(lower)) {
      return MusicMood.madrugada;
    }
    if (RegExp(r'\b(triste|melancolic|melancólic|reflex|pensar|saudade)\b')
        .hasMatch(lower)) {
      return MusicMood.melancolico;
    }
    if (RegExp(r'\b(epico|épico|cinema|trilha|batalha|cyberpunk)\b')
        .hasMatch(lower)) {
      return MusicMood.epico;
    }
    if (RegExp(r'\b(energia|animar|hype|up|empolgar|motivacao|motivação)\b')
        .hasMatch(lower)) {
      return MusicMood.energia;
    }

    // Sem palavra-chave explícita: inferir por contexto (Modo + Foco Noturno + Horário)
    if (nightFocusMode || hour >= 23 || hour < 5) return MusicMood.madrugada;
    if (mode == TacticalMode.treino) return MusicMood.treino;
    if (mode == TacticalMode.estudos || mode == TacticalMode.dev || mode == TacticalMode.engenharia) {
      return MusicMood.foco;
    }
    if (hour >= 5 && hour < 12) return MusicMood.energia;
    if (hour >= 18) return MusicMood.festa;
    return MusicMood.foco;
  }

  static String _periodLabel(int hour) {
    if (hour >= 5 && hour < 12) return 'manhã';
    if (hour >= 12 && hour < 18) return 'tarde';
    if (hour >= 18 && hour < 23) return 'noite';
    return 'madrugada';
  }
}
