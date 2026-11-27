/// Metadados OKF (Open Knowledge Format) para governança de notas no Cofre Obsidian.
///
/// Mantém 100% de retrocompatibilidade com notas Markdown legadas sem frontmatter YAML.
class OkfMetadata {
  const OkfMetadata({
    this.sources = const <String>[],
    this.verified,
    this.staleAfter,
    this.updatedAt,
    this.hasFrontmatter = false,
    this.extraFields = const <String, String>{},
  });

  static const int defaultStaleDays = 30;

  final List<String> sources;
  final bool? verified;
  final DateTime? staleAfter;
  final DateTime? updatedAt;
  final bool hasFrontmatter;
  final Map<String, String> extraFields;

  bool get isVerified => verified == true;
  bool get isUnverified => verified == false;
  bool get hasOkfFields =>
      verified != null ||
      staleAfter != null ||
      updatedAt != null ||
      sources.isNotEmpty;

  String? get staleAfterIso =>
      staleAfter == null ? null : formatIsoDate(staleAfter!);

  static bool isContextNotePath(String relativePath) {
    final norm = relativePath.trim().replaceAll(r'\', '/').toLowerCase();
    return norm.startsWith('memoria/') ||
        norm.startsWith('inventario/') ||
        norm == 'preferencias.md';
  }

  static String formatIsoDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static DateTime computeStaleAfter(
    DateTime now, {
    int days = defaultStaleDays,
  }) {
    final dayStart = DateTime(now.year, now.month, now.day);
    return dayStart.add(Duration(days: days));
  }

  bool isStale({DateTime? now}) {
    if (staleAfter == null) return false;
    final ref = now ?? DateTime.now();
    final today = DateTime(ref.year, ref.month, ref.day);
    final exp = DateTime(staleAfter!.year, staleAfter!.month, staleAfter!.day);
    return exp.isBefore(today);
  }

  String statusTag({DateTime? now, bool isContextNote = false}) {
    final flags = <String>[];
    if (isStale(now: now)) {
      flags.add('VENCIDA desde $staleAfterIso');
    }
    if (verified == false) {
      flags.add('NÃO VERIFICADA');
    } else if (isContextNote && verified == null) {
      flags.add('SEM VERIFICAÇÃO');
    }
    return flags.join(' · ');
  }

  OkfMetadata copyWith({
    List<String>? sources,
    bool? verified,
    bool clearVerified = false,
    DateTime? staleAfter,
    bool clearStaleAfter = false,
    DateTime? updatedAt,
    bool clearUpdatedAt = false,
    bool? hasFrontmatter,
    Map<String, String>? extraFields,
  }) =>
      OkfMetadata(
        sources: sources ?? this.sources,
        verified: clearVerified ? null : (verified ?? this.verified),
        staleAfter: clearStaleAfter ? null : (staleAfter ?? this.staleAfter),
        updatedAt: clearUpdatedAt ? null : (updatedAt ?? this.updatedAt),
        hasFrontmatter: hasFrontmatter ?? this.hasFrontmatter,
        extraFields: extraFields ?? this.extraFields,
      );

  /// Faz parse do frontmatter YAML opcional no topo de [rawContent].
  static OkfDocument parse(String rawContent) {
    final normalized = rawContent.replaceAll('\r\n', '\n');
    final lines = normalized.split('\n');
    if (lines.isEmpty || lines.first.trim() != '---') {
      return OkfDocument(
        metadata: const OkfMetadata(),
        body: rawContent,
      );
    }

    var endIdx = -1;
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim() == '---') {
        endIdx = i;
        break;
      }
    }
    if (endIdx < 0) {
      return OkfDocument(
        metadata: const OkfMetadata(),
        body: rawContent,
      );
    }

    final fmLines = lines.sublist(1, endIdx);
    final body = lines.sublist(endIdx + 1).join('\n');

    final sources = <String>[];
    bool? verified;
    DateTime? staleAfter;
    DateTime? updatedAt;
    final extraFields = <String, String>{};

    var readingSourcesList = false;
    for (final rawLine in fmLines) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      if (readingSourcesList) {
        final bulletMatch = RegExp(r'^-\s+(.+)$').firstMatch(trimmed);
        if (bulletMatch != null) {
          final item = _unquote(bulletMatch.group(1)!.trim());
          if (item.isNotEmpty) sources.add(item);
          continue;
        }
        readingSourcesList = false;
      }

      final colonIdx = trimmed.indexOf(':');
      if (colonIdx <= 0) continue;
      final key = trimmed.substring(0, colonIdx).trim();
      final val = trimmed.substring(colonIdx + 1).trim();
      final lowerKey = key.toLowerCase();

      switch (lowerKey) {
        case 'sources':
          if (val.isEmpty) {
            readingSourcesList = true;
          } else if (val.startsWith('[') && val.endsWith(']')) {
            final inner = val.substring(1, val.length - 1).trim();
            if (inner.isNotEmpty) {
              for (final part in inner.split(',')) {
                final clean = _unquote(part.trim());
                if (clean.isNotEmpty) sources.add(clean);
              }
            }
          } else {
            final clean = _unquote(val);
            if (clean.isNotEmpty) sources.add(clean);
          }
          break;
        case 'verified':
          final lowerVal = _unquote(val).toLowerCase();
          if (lowerVal == 'true') {
            verified = true;
          } else if (lowerVal == 'false') {
            verified = false;
          }
          break;
        case 'stale_after':
          final parsedDate = _parseIsoDate(_unquote(val));
          if (parsedDate != null) staleAfter = parsedDate;
          break;
        case 'updated_at':
          final parsedTs = DateTime.tryParse(_unquote(val));
          if (parsedTs != null) updatedAt = parsedTs;
          break;
        default:
          extraFields[key] = val;
          break;
      }
    }

    return OkfDocument(
      metadata: OkfMetadata(
        sources: List<String>.unmodifiable(sources),
        verified: verified,
        staleAfter: staleAfter,
        updatedAt: updatedAt,
        hasFrontmatter: true,
        extraFields: Map<String, String>.unmodifiable(extraFields),
      ),
      body: body,
    );
  }

  static String renderFrontmatter(OkfMetadata meta) {
    final buf = StringBuffer()..writeln('---');
    for (final entry in meta.extraFields.entries) {
      buf.writeln('${entry.key}: ${entry.value}');
    }
    if (meta.sources.isEmpty) {
      buf.writeln('sources: []');
    } else {
      final rendered = meta.sources.map(_formatYamlScalar).join(', ');
      buf.writeln('sources: [$rendered]');
    }
    if (meta.verified != null) {
      buf.writeln('verified: ${meta.verified}');
    }
    if (meta.staleAfter != null) {
      buf.writeln('stale_after: ${formatIsoDate(meta.staleAfter!)}');
    }
    if (meta.updatedAt != null) {
      buf.writeln('updated_at: ${meta.updatedAt!.toUtc().toIso8601String()}');
    }
    buf.write('---');
    return buf.toString();
  }

  static String upsertFrontmatter(
    String rawContent,
    OkfMetadata Function(OkfMetadata current) updater,
  ) {
    final doc = parse(rawContent);
    final next = updater(doc.metadata).copyWith(hasFrontmatter: true);
    final cleanBody = doc.body.trimLeft();
    final trailing = cleanBody.endsWith('\n') || cleanBody.isEmpty ? '' : '\n';
    return '${renderFrontmatter(next)}\n$cleanBody$trailing';
  }

  static String _unquote(String raw) {
    if (raw.length >= 2) {
      if ((raw.startsWith('"') && raw.endsWith('"')) ||
          (raw.startsWith("'") && raw.endsWith("'"))) {
        return raw.substring(1, raw.length - 1).trim();
      }
    }
    return raw;
  }

  static String _formatYamlScalar(String raw) {
    final clean = raw.replaceAll('"', r'\"').trim();
    if (RegExp(r'^[a-zA-Z0-9_.\-/]+$').hasMatch(clean)) {
      return clean;
    }
    return '"$clean"';
  }

  static DateTime? _parseIsoDate(String raw) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw.trim());
    if (m != null) {
      final y = int.tryParse(m.group(1)!);
      final mo = int.tryParse(m.group(2)!);
      final d = int.tryParse(m.group(3)!);
      if (y != null && mo != null && d != null) {
        return DateTime(y, mo, d);
      }
    }
    return DateTime.tryParse(raw.trim());
  }
}

class OkfDocument {
  const OkfDocument({
    required this.metadata,
    required this.body,
  });

  final OkfMetadata metadata;
  final String body;
}

class OkfNoteStatus {
  const OkfNoteStatus({
    required this.relativePath,
    required this.title,
    required this.metadata,
    required this.isStale,
    required this.isUnverified,
  });

  final String relativePath;
  final String title;
  final OkfMetadata metadata;
  final bool isStale;
  final bool isUnverified;

  String formatReviewLine() {
    final staleInfo = metadata.staleAfterIso ?? 'sem data';
    final flags = <String>[
      if (isStale) 'vencida em $staleInfo',
      if (isUnverified) 'não verificada',
    ];
    final suffix = flags.isEmpty ? '' : ' — ${flags.join(' · ')}';
    return '• $relativePath$suffix';
  }
}
