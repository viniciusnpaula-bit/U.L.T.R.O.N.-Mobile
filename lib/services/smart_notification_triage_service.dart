import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'obsidian_service.dart';
import 'text_normalization.dart';

/// Configuração da Triagem Inteligente de Notificações (tempo real + Obsidian).
class NotificationTriageConfig {
  const NotificationTriageConfig({
    this.enabled = false,
    this.saveToObsidian = true,
    this.speakUrgentAlerts = false,
    this.respectNightFocus = true,
    this.urgencyThreshold = 0.70,
    this.monitoredApps = const ['whatsapp', 'telegram', 'email'],
    this.vipContacts = const [],
    this.customKeywords = const [],
    this.mutedSenders = const [],
    this.triagedCount = 0,
  });

  final bool enabled;
  final bool saveToObsidian;
  final bool speakUrgentAlerts;
  final bool respectNightFocus;
  final double urgencyThreshold;
  final List<String> monitoredApps;
  final List<String> vipContacts;
  final List<String> customKeywords;
  final List<String> mutedSenders;
  final int triagedCount;

  NotificationTriageConfig copyWith({
    bool? enabled,
    bool? saveToObsidian,
    bool? speakUrgentAlerts,
    bool? respectNightFocus,
    double? urgencyThreshold,
    List<String>? monitoredApps,
    List<String>? vipContacts,
    List<String>? customKeywords,
    List<String>? mutedSenders,
    int? triagedCount,
  }) =>
      NotificationTriageConfig(
        enabled: enabled ?? this.enabled,
        saveToObsidian: saveToObsidian ?? this.saveToObsidian,
        speakUrgentAlerts: speakUrgentAlerts ?? this.speakUrgentAlerts,
        respectNightFocus: respectNightFocus ?? this.respectNightFocus,
        urgencyThreshold: urgencyThreshold ?? this.urgencyThreshold,
        monitoredApps: monitoredApps ?? this.monitoredApps,
        vipContacts: vipContacts ?? this.vipContacts,
        customKeywords: customKeywords ?? this.customKeywords,
        mutedSenders: mutedSenders ?? this.mutedSenders,
        triagedCount: triagedCount ?? this.triagedCount,
      );

  Map<String, dynamic> toChannelMap() => <String, dynamic>{
        'enabled': enabled,
        'saveToObsidian': saveToObsidian,
        'speakUrgentAlerts': speakUrgentAlerts,
        'respectNightFocus': respectNightFocus,
        'urgencyThreshold': urgencyThreshold,
        'monitoredApps': monitoredApps,
        'vipContacts': vipContacts,
        'customKeywords': customKeywords,
        'mutedSenders': mutedSenders,
      };

  factory NotificationTriageConfig.fromMap(Map<Object?, Object?> map) {
    List<String> parseList(Object? raw, List<String> fallback) {
      if (raw is List) {
        return raw
            .map((e) => e?.toString().trim() ?? '')
            .where((e) => e.isNotEmpty)
            .toList(growable: false);
      }
      return fallback;
    }

    return NotificationTriageConfig(
      enabled: map['enabled'] as bool? ?? false,
      saveToObsidian: map['saveToObsidian'] as bool? ?? true,
      speakUrgentAlerts: map['speakUrgentAlerts'] as bool? ?? false,
      respectNightFocus: map['respectNightFocus'] as bool? ?? true,
      urgencyThreshold:
          ((map['urgencyThreshold'] as num?)?.toDouble() ?? 0.70)
              .clamp(0.35, 0.95),
      monitoredApps: parseList(
        map['monitoredApps'],
        const ['whatsapp', 'telegram', 'email'],
      ),
      vipContacts: parseList(map['vipContacts'], const []),
      customKeywords: parseList(map['customKeywords'], const []),
      mutedSenders: parseList(map['mutedSenders'], const []),
      triagedCount: (map['triagedCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Evento urgente detectado pela triagem em tempo real.
class UrgentNotificationEvent {
  const UrgentNotificationEvent({
    required this.appLabel,
    required this.packageName,
    required this.sender,
    required this.text,
    required this.score,
    required this.reasons,
    required this.timestamp,
    this.saveToObsidian = true,
  });

  final String appLabel;
  final String packageName;
  final String sender;
  final String text;
  final double score;
  final String reasons;
  final DateTime timestamp;
  final bool saveToObsidian;

  factory UrgentNotificationEvent.fromMap(Map<Object?, Object?> map) {
    final tsMs = (map['timestampMs'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    return UrgentNotificationEvent(
      appLabel: (map['appLabel'] as String?) ?? 'App',
      packageName: (map['packageName'] as String?) ?? '',
      sender: (map['sender'] as String?) ?? 'Contato',
      text: (map['text'] as String?) ?? '',
      score: ((map['score'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0),
      reasons: (map['reasons'] as String?) ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(tsMs),
      saveToObsidian: map['saveToObsidian'] as bool? ?? true,
    );
  }
}

/// Resultado determinístico da avaliação de urgência de uma notificação.
class UrgencyEvaluation {
  const UrgencyEvaluation({
    required this.score,
    required this.isUrgent,
    required this.reasons,
    this.suppressedReason,
  });

  final double score;
  final bool isUrgent;
  final List<String> reasons;
  final String? suppressedReason;
}

/// Motor offline de Triagem Inteligente de Notificações (Camada 1 determinística).
///
/// Características:
/// - Reação em tempo real (sem polling a cada 5 min) e sem spaCy/BERT pesado.
/// - Auto-exclusão do próprio pacote U.L.T.R.O.N. (evita loop infinito).
/// - Filtro de ruído (promoções, newsletters, códigos OTP/2FA).
/// - Pontuação composta: palavras-chave PT-BR normalizadas + VIPs + rajada (3+ msgs/60s).
/// - Deduplicação por hash SHA-256 com cooldown configurável.
/// - Respeito ao Foco Noturno (22h-06h), liberando apenas VIPs ou score >= 0.90.
/// - Redação de dados sensíveis antes de qualquer envio eventual à nuvem.
class SmartNotificationTriageService {
  SmartNotificationTriageService({
    this.ownPackageName = 'com.viniciusnpaula.ultron_mobile',
    this.dedupCooldown = const Duration(minutes: 5),
    this.burstWindow = const Duration(seconds: 60),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const List<String> criticalKeywords = <String>[
    'emergencia',
    'socorro',
    'acidente',
    'hospital',
    'urgente',
    'urgencia',
    'imediato',
    'imediatamente',
    'me liga',
    'liga pra mim',
    'liga agora',
    'to na porta',
    'estou na porta',
    'cheguei agora',
    'vazamento',
    'servidor fora',
    'sistema caiu',
    'falha critica',
    'parou tudo',
  ];

  static const List<String> timeSensitiveKeywords = <String>[
    'hoje',
    'agora',
    'prazo',
    'vence',
    'atrasado',
    'reuniao',
    'cancelou',
    'confirmar',
    'pix',
    'boleto',
    'entrega',
    'importante',
  ];

  static const List<String> noisePatterns = <String>[
    'cupom',
    'desconto',
    'oferta',
    'black friday',
    'frete gratis',
    'newsletter',
    'promocao',
    'promocoes',
    'cashback',
    'codigo de verificacao',
    'codigo de seguranca',
    'nao compartilhe',
    'seu codigo e',
    'verification code',
    'one-time password',
  ];

  final String ownPackageName;
  final Duration dedupCooldown;
  final Duration burstWindow;
  final DateTime Function() _now;

  final Map<String, DateTime> _dedupCache = <String, DateTime>{};
  final Map<String, List<DateTime>> _burstHistory = <String, List<DateTime>>{};

  /// Mascara códigos OTP, CPFs e números longos antes de qualquer envio a LLM externo.
  static String redactSensitiveForCloud(String input) {
    var out = input;
    // CPF formato 000.000.000-00
    out = out.replaceAll(RegExp(r'\b\d{3}\.\d{3}\.\d{3}-\d{2}\b'), '[CPF_REDIGIDO]');
    // Números de cartão (13 a 19 dígitos com ou sem espaços/hífens)
    out = out.replaceAll(
      RegExp(r'\b(?:\d[ -]?){13,19}\b'),
      '[CARTAO_REDIGIDO]',
    );
    // Códigos numéricos 4-8 dígitos próximos a palavras de código/token/otp/pin
    out = out.replaceAllMapped(
      RegExp(
        r'(c[oó]digo|token|otp|pin|senha)\s*[:\-]?\s*(\d{4,8})\b',
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}: [CODIGO_REDIGIDO]',
    );
    return out;
  }

  static String resolveCategory(String packageName, String appLabel) {
    final p = packageName.toLowerCase();
    final l = appLabel.toLowerCase();
    if (p.contains('whatsapp') || l.contains('whatsapp')) return 'whatsapp';
    if (p.contains('telegram') || l.contains('telegram')) return 'telegram';
    if (p.contains('.gm') ||
        p.contains('outlook') ||
        p.contains('email') ||
        p.contains('mail') ||
        l.contains('mail')) {
      return 'email';
    }
    if (p.contains('messaging') || l.contains('sms')) return 'sms';
    return l;
  }

  /// Avalia uma notificação recebida e retorna score, motivos e se deve disparar alerta.
  UrgencyEvaluation evaluate({
    required NotificationTriageConfig config,
    required String packageName,
    required String appLabel,
    required String sender,
    required String text,
    bool isNightOverride = false,
  }) {
    if (!config.enabled) {
      return const UrgencyEvaluation(
        score: 0.0,
        isUrgent: false,
        reasons: [],
        suppressedReason: 'disabled',
      );
    }

    // 1. Auto-exclusão obrigatória contra loop de notificações
    if (packageName.trim() == ownPackageName) {
      return const UrgencyEvaluation(
        score: 0.0,
        isUrgent: false,
        reasons: [],
        suppressedReason: 'self_package',
      );
    }

    // 2. Filtro de apps monitorados (WhatsApp, Telegram, E-mail)
    final category = resolveCategory(packageName, appLabel);
    final allowed = config.monitoredApps
        .map(PtBrTextNormalizer.normalizePhrase)
        .toList();
    if (allowed.isNotEmpty &&
        !allowed.contains('all') &&
        !allowed.contains(category)) {
      return const UrgencyEvaluation(
        score: 0.0,
        isUrgent: false,
        reasons: [],
        suppressedReason: 'unmonitored_app',
      );
    }

    final normSender = PtBrTextNormalizer.normalizePhrase(sender);
    final normText = PtBrTextNormalizer.normalizePhrase(text);

    // 3. Remetentes silenciados
    for (final m in config.mutedSenders) {
      final nm = PtBrTextNormalizer.normalizePhrase(m);
      if (nm.isNotEmpty && normSender.contains(nm)) {
        return const UrgencyEvaluation(
          score: 0.0,
          isUrgent: false,
          reasons: [],
          suppressedReason: 'muted_sender',
        );
      }
    }

    // 4. Filtro anti-ruído (promoções, spam e OTP/2FA)
    for (final pattern in noisePatterns) {
      if (normText.contains(pattern)) {
        return const UrgencyEvaluation(
          score: 0.0,
          isUrgent: false,
          reasons: [],
          suppressedReason: 'noise_filtered',
        );
      }
    }

    final now = _now();

    // 5. Deduplicação por hash SHA-256 + cooldown
    final hash = sha256
        .convert(utf8.encode('$packageName|$normSender|$normText'))
        .toString();
    final prevSeen = _dedupCache[hash];
    if (prevSeen != null && now.difference(prevSeen) < dedupCooldown) {
      return const UrgencyEvaluation(
        score: 0.0,
        isUrgent: false,
        reasons: [],
        suppressedReason: 'duplicate',
      );
    }

    // 6. Detecção de rajada (3+ mensagens do mesmo remetente na janela)
    final burstKey = '$packageName|$normSender';
    final history = _burstHistory.putIfAbsent(burstKey, () => <DateTime>[]);
    history.removeWhere((t) => now.difference(t) > burstWindow);
    history.add(now);
    final burstCount = history.length;

    var score = 0.0;
    final reasons = <String>[];

    var isVip = false;
    for (final vip in config.vipContacts) {
      final nv = PtBrTextNormalizer.normalizePhrase(vip);
      if (nv.isNotEmpty && normSender.contains(nv)) {
        isVip = true;
        break;
      }
    }
    if (isVip) {
      score += 0.45;
      reasons.add('VIP');
    }

    for (final kw in config.customKeywords) {
      final nk = PtBrTextNormalizer.normalizePhrase(kw);
      if (nk.isNotEmpty && normText.contains(nk)) {
        score += 0.65;
        reasons.add('palavra:$nk');
        break;
      }
    }

    String? critMatch;
    for (final kw in criticalKeywords) {
      if (normText.contains(kw)) {
        critMatch = kw;
        break;
      }
    }
    if (critMatch != null) {
      score += 0.72;
      reasons.add(critMatch);
    } else {
      for (final kw in timeSensitiveKeywords) {
        if (normText.contains(kw)) {
          score += 0.35;
          reasons.add(kw);
          break;
        }
      }
    }

    if (burstCount >= 3) {
      score += 0.40;
      reasons.add('rajada(${burstCount}x)');
    }

    if (text.contains('!!') || text.contains('??')) {
      score += 0.12;
      reasons.add('enfase');
    }

    final finalScore = score.clamp(0.0, 1.0);
    if (finalScore < config.urgencyThreshold) {
      return UrgencyEvaluation(
        score: finalScore,
        isUrgent: false,
        reasons: reasons,
        suppressedReason: 'below_threshold',
      );
    }

    // 7. Foco Noturno (22h-06h): só fura para VIP ou urgência crítica (>= 0.90)
    final isNight = isNightOverride || now.hour >= 22 || now.hour < 6;
    if (config.respectNightFocus && isNight && !isVip && finalScore < 0.90) {
      return UrgencyEvaluation(
        score: finalScore,
        isUrgent: false,
        reasons: reasons,
        suppressedReason: 'night_focus',
      );
    }

    _dedupCache[hash] = now;
    return UrgencyEvaluation(
      score: finalScore,
      isUrgent: true,
      reasons: reasons,
    );
  }

  /// Grava uma entrada urgente estruturada em `Inbox/Urgencias_AAAA-MM-DD.md` no Obsidian.
  static Future<File> appendUrgentEventToObsidian(
    UrgentNotificationEvent event, {
    ObsidianService? obsidian,
  }) async {
    final vault = obsidian ?? await ObsidianService.openDefaultVault();
    final dt = event.timestamp.toLocal();
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final pct = (event.score * 100).round();
    final relPath = 'Inbox/Urgencias_$y-$m-$d.md';
    final reasonPart =
        event.reasons.trim().isEmpty ? '' : ' (${event.reasons.trim()})';
    final line =
        '- [ ] [$hh:$mm] **${event.appLabel}** · ${event.sender} [$pct%$reasonPart]: ${event.text.trim()}';
    return vault.appendToNote(relPath, line, createIfMissing: true);
  }
}
