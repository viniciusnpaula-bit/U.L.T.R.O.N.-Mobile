import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/security/action_gate.dart';
import 'desktop_pairing_service.dart';
import 'device_control_service.dart';
import 'obsidian_service.dart';
import 'workflow_scheduler_service.dart';

class RemoteSkillEntry {
  const RemoteSkillEntry({
    required this.id,
    required this.title,
    this.description = '',
    this.pinned = false,
    this.source = 'pc_sync',
    this.lastRunAt,
  });

  factory RemoteSkillEntry.fromJson(Map<String, dynamic> json) =>
      RemoteSkillEntry(
        id: (json['id'] as String? ?? '').trim(),
        title: (json['title'] as String? ?? json['id'] as String? ?? '').trim(),
        description: (json['description'] as String? ?? '').trim(),
        pinned: json['pinned'] == true,
        source: (json['source'] as String? ?? 'pc_sync').trim(),
        lastRunAt: json['lastRunAt'] != null
            ? DateTime.tryParse(json['lastRunAt'].toString())
            : null,
      );

  final String id;
  final String title;
  final String description;
  final bool pinned;
  final String source; // pc_sync | favorite
  final DateTime? lastRunAt;

  RemoteSkillEntry copyWith({
    String? title,
    String? description,
    bool? pinned,
    String? source,
    DateTime? lastRunAt,
  }) =>
      RemoteSkillEntry(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        pinned: pinned ?? this.pinned,
        source: source ?? this.source,
        lastRunAt: lastRunAt ?? this.lastRunAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'description': description,
        'pinned': pinned,
        'source': source,
        if (lastRunAt != null) 'lastRunAt': lastRunAt!.toUtc().toIso8601String(),
      };
}

class MobileSkillDescriptor {
  const MobileSkillDescriptor({
    required this.id,
    required this.slug,
    required this.title,
    required this.description,
    required this.actionCount,
    required this.riskLevel,
    required this.requiresConfirmation,
  });

  factory MobileSkillDescriptor.fromMobileSkill(
    MobileSkill skill, {
    ActionGate actionGate = const ActionGate(),
  }) {
    final tags = WorkflowSchedulerService.extractActionTags(skill.content);
    var maxRisk = RiskLevel.safe;
    for (final tag in tags) {
      final level = actionGate.simulate(tag).riskLevel;
      if (level == RiskLevel.critical) {
        maxRisk = RiskLevel.critical;
        break;
      }
      if (level == RiskLevel.sensitive) {
        maxRisk = RiskLevel.sensitive;
      }
    }
    var desc = '';
    for (final line in skill.content.split('\n')) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#') || t.startsWith('[')) continue;
      desc = t;
      break;
    }
    return MobileSkillDescriptor(
      id: skill.id,
      slug: skill.slug,
      title: skill.title,
      description: desc,
      actionCount: tags.length,
      riskLevel: maxRisk,
      requiresConfirmation: maxRisk != RiskLevel.safe,
    );
  }

  final String id;
  final String slug;
  final String title;
  final String description;
  final int actionCount;
  final RiskLevel riskLevel;
  final bool requiresConfirmation;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'slug': slug,
        'title': title,
        'description': description,
        'actionCount': actionCount,
        'riskLevel': riskLevel.name,
        'requiresConfirmation': requiresConfirmation,
      };
}

/// Ponte bidirecional de Skills (Celular ⇄ PC):
/// - Descobre, fixa em 1 toque, salva favoritos e executa skills do Desktop via `PC_LIST_SKILLS` / `PC_RUN_SKILL`.
/// - Expõe e sincroniza o catálogo de skills locais (`Skills/*.md`) para o PC disparar via `RUN_SKILL`.
class SkillBridgeService extends ChangeNotifier {
  SkillBridgeService({
    required DeviceControlService deviceService,
    FlutterSecureStorage? storage,
    DateTime Function()? now,
  })  : _deviceService = deviceService,
        _storage = storage ?? const FlutterSecureStorage(),
        _now = now ?? DateTime.now;

  static const _storageKey = 'ultron.skills.pc_catalog.v1';

  final DeviceControlService _deviceService;
  final FlutterSecureStorage _storage;
  final DateTime Function() _now;

  final Map<String, RemoteSkillEntry> _entries = <String, RemoteSkillEntry>{};
  bool _isSyncing = false;
  DateTime? _lastSyncedAt;
  String? _lastStatusMessage;

  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  String? get lastStatusMessage => _lastStatusMessage;

  List<RemoteSkillEntry> get pcSkills {
    final list = _entries.values.toList(growable: false);
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      if (a.lastRunAt != null && b.lastRunAt != null) {
        final cmp = b.lastRunAt!.compareTo(a.lastRunAt!);
        if (cmp != 0) return cmp;
      } else if (a.lastRunAt != null || b.lastRunAt != null) {
        return a.lastRunAt != null ? -1 : 1;
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return List<RemoteSkillEntry>.unmodifiable(list);
  }

  static String sanitizeSlug(String raw) {
    final normalized = _normalizeLookup(raw).replaceAll(RegExp(r'\s+'), '_');
    return normalized.replaceAll(RegExp(r'[^a-z0-9_\-]'), '');
  }

  static String _normalizeLookup(String raw) => raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[áàâãä]'), 'a')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[íìîï]'), 'i')
      .replaceAll(RegExp(r'[óòôõö]'), 'o')
      .replaceAll(RegExp(r'[úùûü]'), 'u')
      .replaceAll('ç', 'c');

  static String buildDesktopTriggerHint(MobileSkill skill) =>
      'RUN_SKILL:${skill.slug}';

  Future<void> load() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _entries.clear();
      for (final item in decoded.whereType<Map>()) {
        final entry = RemoteSkillEntry.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (entry.id.isNotEmpty) {
          _entries[entry.id] = entry;
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final encoded = jsonEncode(
        _entries.values.map((e) => e.toJson()).toList(growable: false),
      );
      await _storage.write(key: _storageKey, value: encoded);
    } catch (_) {}
  }

  /// Faz parse flexível de payloads JSON ou listas textuais retornadas pelo Desktop.
  static List<RemoteSkillEntry> parsePcSkillsResponse(String? rawBody) {
    final body = (rawBody ?? '').trim();
    if (body.isEmpty) return const <RemoteSkillEntry>[];

    final parsed = <String, RemoteSkillEntry>{};

    void addItem(String rawId, {String? title, String? description}) {
      final id = rawId.trim();
      if (id.isEmpty) return;
      final key = id.toLowerCase();
      final cleanTitle =
          (title != null && title.trim().isNotEmpty) ? title.trim() : id;
      parsed[key] = RemoteSkillEntry(
        id: id,
        title: cleanTitle,
        description: (description ?? '').trim(),
        source: 'pc_sync',
      );
    }

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        final data = map['data'] is Map
            ? Map<String, dynamic>.from(map['data'] as Map)
            : map;
        final rawList = data['skills'] ??
            map['skills'] ??
            data['items'] ??
            data['tools'] ??
            map['tools'];
        if (rawList is List) {
          for (final item in rawList) {
            if (item is String) {
              addItem(item);
            } else if (item is Map) {
              final m = Map<String, dynamic>.from(item);
              final id =
                  (m['id'] ?? m['slug'] ?? m['name'] ?? m['skill'] ?? '')
                      .toString();
              final title = (m['title'] ?? m['label'] ?? m['name'] ?? id)
                  .toString();
              final desc =
                  (m['description'] ?? m['summary'] ?? m['desc'] ?? '')
                      .toString();
              addItem(id, title: title, description: desc);
            }
          }
          return parsed.values.toList(growable: false);
        }
      } else if (decoded is List) {
        for (final item in decoded) {
          if (item is String) {
            addItem(item);
          } else if (item is Map) {
            final m = Map<String, dynamic>.from(item);
            final id = (m['id'] ?? m['slug'] ?? m['name'] ?? '').toString();
            addItem(
              id,
              title: (m['title'] ?? id).toString(),
              description: (m['description'] ?? '').toString(),
            );
          }
        }
        return parsed.values.toList(growable: false);
      }
    } catch (_) {}

    // Fallback para resposta em texto simples ("• modo_dev: abre IDE", etc.)
    for (final line in body.split(RegExp(r'\r?\n'))) {
      final clean = line.trim().replaceFirst(RegExp(r'^[-*•]\s*'), '');
      if (clean.isEmpty) continue;
      final match = RegExp(r'^([a-zA-Z0-9_\-\.]+)\s*(?::|-|—)?\s*(.*)$')
          .firstMatch(clean);
      if (match != null) {
        addItem(match.group(1)!, description: match.group(2));
      }
    }
    return parsed.values.toList(growable: false);
  }

  /// Atualiza o catálogo de skills disponíveis no PC via `PC_LIST_SKILLS`
  /// (com fallback para `PC_EXEC_TOOL:listar_skills`).
  Future<List<RemoteSkillEntry>> refreshPcSkills({
    ActionGateConfirmCallback? confirmAction,
  }) async {
    _isSyncing = true;
    _lastStatusMessage = 'Consultando skills do PC...';
    notifyListeners();

    try {
      var res = await _deviceService.sendDesktopBridgeCommand(
        command: 'PC_LIST_SKILLS',
        args: const <String, dynamic>{},
        confirmAction: confirmAction,
        actor: 'OPERATOR',
      );
      if (!res.sent && res.unsupportedByServer) {
        res = await _deviceService.sendDesktopBridgeCommand(
          command: 'PC_EXEC_TOOL',
          args: const <String, dynamic>{'tool': 'listar_skills'},
          confirmAction: confirmAction,
          actor: 'OPERATOR',
        );
      }

      if (res.deniedByUser) {
        _lastStatusMessage =
            'Consulta bloqueada: requer Biometria (Nível 3) ou aprovação.';
        return pcSkills;
      }
      if (!res.sent) {
        _lastStatusMessage =
            res.error ?? 'Desktop não respondeu (HTTP ${res.statusCode ?? '-'}).';
        return pcSkills;
      }

      final fetched = parsePcSkillsResponse(res.responseBody);
      for (final item in fetched) {
        final prev = _entries[item.id];
        _entries[item.id] = item.copyWith(
          pinned: prev?.pinned ?? false,
          lastRunAt: prev?.lastRunAt,
        );
      }
      _lastSyncedAt = _now();
      _lastStatusMessage = fetched.isEmpty
          ? 'PC conectado, mas nenhuma skill retornada.'
          : '${fetched.length} skill(s) sincronizada(s) do PC.';
      await _persist();
      return pcSkills;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Executa uma skill no PC em 1 toque ou comando de voz (`PC_RUN_SKILL`).
  Future<DesktopCommandResult> runPcSkill(
    String skillQuery, {
    String? argsText,
    ActionGateConfirmCallback? confirmAction,
    String actor = 'OPERATOR',
  }) async {
    final cleanQuery = skillQuery.trim();
    if (cleanQuery.isEmpty) {
      throw ArgumentError('Informe o nome da skill do PC.');
    }

    final resolved = _resolveCachedEntry(cleanQuery);
    final skillId = resolved?.id ?? cleanQuery;
    final args = <String, dynamic>{
      'skill': skillId,
      if (argsText != null && argsText.trim().isNotEmpty)
        'args': argsText.trim(),
    };

    final res = await _deviceService.sendDesktopBridgeCommand(
      command: 'PC_RUN_SKILL',
      args: args,
      confirmAction: confirmAction,
      actor: actor,
    );

    if (res.sent) {
      final now = _now();
      final existing = _entries[skillId];
      _entries[skillId] = (existing ??
              RemoteSkillEntry(
                id: skillId,
                title: resolved?.title ?? cleanQuery,
                source: 'favorite',
              ))
          .copyWith(lastRunAt: now);
      _lastStatusMessage = 'Skill "$skillId" executada no PC.';
      await _persist();
      notifyListeners();
    } else if (!res.deniedByUser) {
      _lastStatusMessage = res.error ?? 'Falha ao executar "$skillId" no PC.';
      notifyListeners();
    }
    return res;
  }

  /// Envia ao Desktop o catálogo de skills locais do celular (`Skills/*.md`).
  Future<DesktopCommandResult> syncMobileSkillsToPc(
    List<MobileSkill> mobileSkills, {
    ActionGateConfirmCallback? confirmAction,
  }) async {
    final descriptors = mobileSkills
        .map((s) => MobileSkillDescriptor.fromMobileSkill(s).toJson())
        .toList(growable: false);
    final res = await _deviceService.sendDesktopBridgeCommand(
      command: 'PC_SYNC_MOBILE_SKILLS',
      args: <String, dynamic>{'skills': descriptors},
      confirmAction: confirmAction,
      actor: 'OPERATOR',
    );
    _lastStatusMessage = res.sent
        ? '${descriptors.length} skill(s) do celular sincronizada(s) com o PC.'
        : (res.error ?? 'Falha ao enviar catálogo do celular ao PC.');
    notifyListeners();
    return res;
  }

  /// Salva ou fixa um atalho rápido de skill do PC (funciona mesmo offline).
  Future<RemoteSkillEntry> savePinnedPcSkill(
    String rawName, {
    String? title,
    String? description,
    bool pinned = true,
  }) async {
    final cleanName = rawName.trim();
    if (cleanName.isEmpty) {
      throw ArgumentError('Nome da skill não pode ser vazio.');
    }
    final slug = sanitizeSlug(cleanName);
    final id = slug.isNotEmpty ? slug : cleanName;
    final prev = _entries[id];
    final entry = RemoteSkillEntry(
      id: id,
      title: (title != null && title.trim().isNotEmpty)
          ? title.trim()
          : (prev?.title ?? cleanName),
      description: (description != null && description.trim().isNotEmpty)
          ? description.trim()
          : (prev?.description ?? 'Atalho rápido Desktop LAN'),
      pinned: pinned,
      source: prev?.source ?? 'favorite',
      lastRunAt: prev?.lastRunAt,
    );
    _entries[id] = entry;
    await _persist();
    notifyListeners();
    return entry;
  }

  Future<void> togglePin(String id) async {
    final existing = _entries[id];
    if (existing == null) return;
    _entries[id] = existing.copyWith(pinned: !existing.pinned);
    await _persist();
    notifyListeners();
  }

  Future<void> removePcSkill(String id) async {
    if (_entries.remove(id) != null) {
      await _persist();
      notifyListeners();
    }
  }

  RemoteSkillEntry? _resolveCachedEntry(String query) {
    if (_entries.containsKey(query)) return _entries[query];
    final normQuery = _normalizeLookup(query);
    final normSlug = sanitizeSlug(query);
    for (final entry in _entries.values) {
      if (_normalizeLookup(entry.id) == normQuery ||
          sanitizeSlug(entry.id) == normSlug ||
          _normalizeLookup(entry.title) == normQuery) {
        return entry;
      }
    }
    for (final entry in _entries.values) {
      if (_normalizeLookup(entry.title).contains(normQuery) ||
          _normalizeLookup(entry.id).contains(normQuery)) {
        return entry;
      }
    }
    return null;
  }
}
