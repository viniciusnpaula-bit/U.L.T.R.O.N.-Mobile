import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class ReminderItem {
  const ReminderItem({
    required this.id,
    required this.title,
    required this.scheduledAt,
    required this.status,
    required this.createdAt,
  });

  factory ReminderItem.fromRow(Map<String, Object?> row) => ReminderItem(
        id: (row['id'] as num).toInt(),
        title: (row['title'] as String? ?? '').trim(),
        scheduledAt: DateTime.fromMillisecondsSinceEpoch(
          (row['scheduled_ms'] as num).toInt(),
        ),
        status: (row['status'] as String? ?? 'PENDING').trim().toUpperCase(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (row['created_ms'] as num?)?.toInt() ??
              (row['scheduled_ms'] as num).toInt(),
        ),
      );

  final int id;
  final String title;
  final DateTime scheduledAt;
  final String status;
  final DateTime createdAt;

  bool get isPending => status == 'PENDING';

  static String _two(int v) => v.toString().padLeft(2, '0');

  String get formattedSchedule =>
      '${_two(scheduledAt.day)}/${_two(scheduledAt.month)} ${_two(scheduledAt.hour)}:${_two(scheduledAt.minute)}';

  String formatLine() => '• [#$id] $formattedSchedule — $title ($status)';
}

class ParsedReminderDraft {
  const ParsedReminderDraft({
    required this.title,
    required this.scheduledAt,
  });

  final String title;
  final DateTime scheduledAt;
}

/// Serviço persistente de lembretes locais em SQLite com agendamento de
/// notificação nativa via `AlarmManager` no Android (`scheduleReminderAlarm` / `cancelReminderAlarm`).
class ReminderService {
  ReminderService._(this._db, {MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('com.viniciusnpaula.ultron_mobile/device');

  final Database _db;
  final MethodChannel _channel;
  static ReminderService? _sharedInstance;

  static Future<ReminderService> instance({MethodChannel? channel}) async {
    if (_sharedInstance != null && _sharedInstance!._db.isOpen) {
      return _sharedInstance!;
    }
    final svc = await open(channel: channel);
    _sharedInstance = svc;
    return svc;
  }

  static Future<ReminderService> open({
    Database? database,
    String? dbPath,
    MethodChannel? channel,
  }) async {
    late final Database db;
    if (database != null) {
      db = database;
    } else {
      final resolved =
          dbPath ?? p.join(await getDatabasesPath(), 'ultron_reminders.db');
      db = await openDatabase(resolved, version: 1);
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reminders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        scheduled_ms INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'PENDING',
        created_ms INTEGER NOT NULL
      )
    ''');
    return ReminderService._(db, channel: channel);
  }

  /// Cria um novo lembrete persistente no SQLite e agenda o alarme local nativo (`AlarmManager`).
  Future<ReminderItem> createReminder({
    required String title,
    required DateTime scheduledAt,
    DateTime? now,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw ArgumentError('Título do lembrete não pode ser vazio.');
    }
    final createdMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final scheduledMs = scheduledAt.millisecondsSinceEpoch;

    final id = await _db.insert('reminders', {
      'title': cleanTitle,
      'scheduled_ms': scheduledMs,
      'status': 'PENDING',
      'created_ms': createdMs,
    });

    try {
      await _channel.invokeMethod<bool>('scheduleReminderAlarm', {
        'id': id,
        'title': cleanTitle,
        'triggerAtMs': scheduledMs,
      });
    } catch (_) {
      // Em ambiente de teste headless sem handler nativo, mantém persistência SQLite.
    }

    return ReminderItem(
      id: id,
      title: cleanTitle,
      scheduledAt: scheduledAt,
      status: 'PENDING',
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdMs),
    );
  }

  /// Reagenda no `AlarmManager` nativo todos os lembretes `PENDING` ainda futuros
  /// (usado no boot do app e após reinício do sistema para garantir persistência
  /// de lembretes de longo prazo, como vencimentos de garantia).
  Future<int> reschedulePendingAlarms({DateTime? now}) async {
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final rows = await _db.query(
      'reminders',
      where: 'status = ? AND scheduled_ms > ?',
      whereArgs: ['PENDING', nowMs],
      orderBy: 'scheduled_ms ASC, id ASC',
    );
    var rescheduled = 0;
    for (final row in rows) {
      final item = ReminderItem.fromRow(row);
      try {
        final ok = await _channel.invokeMethod<bool>('scheduleReminderAlarm', {
          'id': item.id,
          'title': item.title,
          'triggerAtMs': item.scheduledAt.millisecondsSinceEpoch,
        });
        if (ok ?? true) {
          rescheduled++;
        }
      } catch (_) {
        // Ambiente headless sem canal nativo.
      }
    }
    return rescheduled;
  }

  /// Lista lembretes persistidos no banco SQLite.
  Future<List<ReminderItem>> listReminders({
    bool onlyPending = true,
    int limit = 30,
  }) async {
    final rows = await _db.query(
      'reminders',
      where: onlyPending ? 'status = ?' : null,
      whereArgs: onlyPending ? ['PENDING'] : null,
      orderBy: 'scheduled_ms ASC, id ASC',
      limit: limit.clamp(1, 100),
    );
    return rows.map(ReminderItem.fromRow).toList();
  }

  /// Cancela um lembrete por ID (`#1`, `1`) ou trecho do título e desativa o `AlarmManager` nativo.
  Future<ReminderItem?> cancelReminder(String idOrQuery) async {
    final clean = idOrQuery.trim().replaceFirst(RegExp(r'^#'), '').trim();
    if (clean.isEmpty) {
      throw ArgumentError('Informe o ID ou título do lembrete para cancelar.');
    }

    ReminderItem? target;
    final parsedId = int.tryParse(clean);
    if (parsedId != null) {
      final rows = await _db.query(
        'reminders',
        where: 'id = ?',
        whereArgs: [parsedId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        target = ReminderItem.fromRow(rows.first);
      }
    }

    if (target == null) {
      final pending = await listReminders(onlyPending: true, limit: 100);
      final qLower = clean.toLowerCase();
      for (final item in pending) {
        if (item.title.toLowerCase().contains(qLower)) {
          target = item;
          break;
        }
      }
      if (target == null) {
        final all = await listReminders(onlyPending: false, limit: 100);
        for (final item in all) {
          if (item.title.toLowerCase().contains(qLower)) {
            target = item;
            break;
          }
        }
      }
    }

    if (target == null) return null;

    await _db.update(
      'reminders',
      {'status': 'CANCELLED'},
      where: 'id = ?',
      whereArgs: [target.id],
    );

    try {
      await _channel.invokeMethod<bool>('cancelReminderAlarm', {
        'id': target.id,
      });
    } catch (_) {}

    return ReminderItem(
      id: target.id,
      title: target.title,
      scheduledAt: target.scheduledAt,
      status: 'CANCELLED',
      createdAt: target.createdAt,
    );
  }

  /// Interpreta expressões de lembrete como:
  /// - `"Tomar água daqui 15 minutos"`
  /// - `"18:30:Ligar para o cliente"`
  /// - `"2026-11-23 09:00:Revisar servidor"`
  /// - `"amanhã às 10:00 Enviar relatório"`
  static ParsedReminderDraft? parseReminderSpec(
    String rawSpec, {
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    var body = rawSpec
        .trim()
        .replaceFirst(
          RegExp(
            r'^(?:ultron[,\s]+)?(?:criar\s+lembrete|novo\s+lembrete|agendar\s+lembrete|lembrete|me\s+lembre(?:\s+de)?|lembrar(?:-me)?\s+de)\s*:?\s*',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    if (body.isEmpty) return null;

    // 1. Formato relativo: "daqui a X minutos/horas/segundos" ou "em X min"
    final relMatch = RegExp(
      r'\b(?:daqui(?:\s+a)?|em)\s+(\d+)\s*(seg|segundos?|s|min|minutos?|m|h|horas?)\b',
      caseSensitive: false,
    ).firstMatch(body);
    if (relMatch != null) {
      final amount = int.tryParse(relMatch.group(1)!) ?? 0;
      final unit = relMatch.group(2)!.toLowerCase();
      if (amount > 0) {
        final delta = unit.startsWith('s')
            ? Duration(seconds: amount)
            : unit.startsWith('h')
                ? Duration(hours: amount)
                : Duration(minutes: amount);
        final title = body
            .replaceRange(relMatch.start, relMatch.end, ' ')
            .replaceAll(RegExp(r'\s{2,}'), ' ')
            .replaceFirst(RegExp(r'^[-:,\s]+'), '')
            .replaceFirst(RegExp(r'[-:,\s]+$'), '')
            .trim();
        return ParsedReminderDraft(
          title: title.isEmpty ? 'Lembrete U.L.T.R.O.N.' : title,
          scheduledAt: ref.add(delta),
        );
      }
    }

    // 2. Formato estruturado de tag: "YYYY-MM-DD HH:MM:Título" ou "HH:MM:Título"
    final isoTagMatch = RegExp(
      r'^(\d{4})-(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})\s*[:\-]\s*(.+)$',
    ).firstMatch(body);
    if (isoTagMatch != null) {
      final y = int.parse(isoTagMatch.group(1)!);
      final m = int.parse(isoTagMatch.group(2)!);
      final d = int.parse(isoTagMatch.group(3)!);
      final hh = int.parse(isoTagMatch.group(4)!).clamp(0, 23);
      final mm = int.parse(isoTagMatch.group(5)!).clamp(0, 59);
      final title = isoTagMatch.group(6)!.trim();
      if (title.isNotEmpty) {
        return ParsedReminderDraft(
          title: title,
          scheduledAt: DateTime(y, m, d, hh, mm),
        );
      }
    }

    final hmTagMatch = RegExp(
      r'^(\d{1,2}):(\d{2})\s*[:\-]\s*(.+)$',
    ).firstMatch(body);
    if (hmTagMatch != null) {
      final hh = int.parse(hmTagMatch.group(1)!).clamp(0, 23);
      final mm = int.parse(hmTagMatch.group(2)!).clamp(0, 59);
      final title = hmTagMatch.group(3)!.trim();
      var scheduled = DateTime(ref.year, ref.month, ref.day, hh, mm);
      if (!scheduled.isAfter(ref)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }
      if (title.isNotEmpty) {
        return ParsedReminderDraft(
          title: title,
          scheduledAt: scheduled,
        );
      }
    }

    // 3. Data + Hora natural ("amanhã às 14:00 Comprar café", "hoje às 19h Treino")
    var targetDate = DateTime(ref.year, ref.month, ref.day);
    var dateMatched = false;

    final isoDate = RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b').firstMatch(body);
    if (isoDate != null) {
      targetDate = DateTime(
        int.parse(isoDate.group(1)!),
        int.parse(isoDate.group(2)!),
        int.parse(isoDate.group(3)!),
      );
      body = body.replaceRange(isoDate.start, isoDate.end, ' ');
      dateMatched = true;
    } else {
      final brDate =
          RegExp(r'\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b').firstMatch(body);
      if (brDate != null) {
        final d = int.parse(brDate.group(1)!);
        final m = int.parse(brDate.group(2)!);
        var y = ref.year;
        if (brDate.group(3) != null) {
          final py = int.parse(brDate.group(3)!);
          y = py < 100 ? 2000 + py : py;
        }
        targetDate = DateTime(y, m, d);
        body = body.replaceRange(brDate.start, brDate.end, ' ');
        dateMatched = true;
      } else if (RegExp(r'\bdepois\s+de\s+amanh[aã]\b', caseSensitive: false)
          .hasMatch(body)) {
        targetDate = targetDate.add(const Duration(days: 2));
        body = body.replaceAll(
          RegExp(r'(?:para\s+)?depois\s+de\s+amanh[aã]', caseSensitive: false),
          ' ',
        );
        dateMatched = true;
      } else if (RegExp(r'\bamanh[aã]\b', caseSensitive: false)
          .hasMatch(body)) {
        targetDate = targetDate.add(const Duration(days: 1));
        body = body.replaceAll(
          RegExp(r'(?:para\s+)?amanh[aã]', caseSensitive: false),
          ' ',
        );
        dateMatched = true;
      } else if (RegExp(r'\bhoje\b', caseSensitive: false).hasMatch(body)) {
        body = body.replaceAll(
          RegExp(r'(?:para\s+)?hoje', caseSensitive: false),
          ' ',
        );
        dateMatched = true;
      }
    }

    int? hour;
    var minute = 0;
    final timeMatch = RegExp(
      r'(?:(?:^|\s)(?:para\s+)?(?:[àa]s?|as)\s+|\b)(\d{1,2})(?:[:h](\d{2})|h)(?:\s*h(?:oras?)?)?(?=\s|$)',
      caseSensitive: false,
    ).firstMatch(body);
    if (timeMatch != null) {
      final h = int.tryParse(timeMatch.group(1)!);
      final m =
          timeMatch.group(2) != null ? int.tryParse(timeMatch.group(2)!) : 0;
      if (h != null && h >= 0 && h <= 23 && m != null && m >= 0 && m <= 59) {
        hour = h;
        minute = m;
        body = body.replaceRange(timeMatch.start, timeMatch.end, ' ');
      }
    }

    DateTime scheduled;
    if (hour != null) {
      scheduled = DateTime(
        targetDate.year,
        targetDate.month,
        targetDate.day,
        hour,
        minute,
      );
      if (!dateMatched && !scheduled.isAfter(ref)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }
    } else if (dateMatched) {
      scheduled = DateTime(
        targetDate.year,
        targetDate.month,
        targetDate.day,
        9,
        0,
      );
    } else {
      scheduled = ref.add(const Duration(minutes: 30));
    }

    final cleanTitle = body
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceFirst(RegExp(r'^(?:de|para|que)\s+', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^[-:,\s]+'), '')
        .replaceFirst(RegExp(r'[-:,\s]+$'), '')
        .trim();
    if (cleanTitle.isEmpty) return null;

    return ParsedReminderDraft(
      title: cleanTitle,
      scheduledAt: scheduled,
    );
  }

  Future<void> close() async {
    if (_db.isOpen) {
      await _db.close();
    }
    if (identical(_sharedInstance, this)) {
      _sharedInstance = null;
    }
  }
}
