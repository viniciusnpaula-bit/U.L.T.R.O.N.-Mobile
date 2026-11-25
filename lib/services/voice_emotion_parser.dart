import 'text_normalization.dart';

/// Registros emocionais suportados para modulação leve de pitch/rate no TTS (até ±15%).
enum VoiceEmotion {
  neutro(id: 'neutro', pitchFactor: 1.00, rateFactor: 1.00),
  lamento(id: 'lamento', pitchFactor: 0.90, rateFactor: 0.90),
  encorajador(id: 'encorajador', pitchFactor: 1.08, rateFactor: 1.04),
  alerta(id: 'alerta', pitchFactor: 1.06, rateFactor: 1.12),
  comemorando(id: 'comemorando', pitchFactor: 1.13, rateFactor: 1.08),
  serio(id: 'serio', pitchFactor: 0.88, rateFactor: 0.94),
  duvida(id: 'duvida', pitchFactor: 1.05, rateFactor: 0.96);

  const VoiceEmotion({
    required this.id,
    required this.pitchFactor,
    required this.rateFactor,
  });

  final String id;
  final double pitchFactor;
  final double rateFactor;

  static VoiceEmotion? tryParseTag(String raw) {
    final norm = PtBrTextNormalizer.normalizePhrase(raw);
    return switch (norm) {
      'neutro' || 'neutral' => VoiceEmotion.neutro,
      'lamento' || 'empatia' || 'triste' || 'desculpa' => VoiceEmotion.lamento,
      'encorajador' || 'motivador' || 'positivo' => VoiceEmotion.encorajador,
      'alerta' || 'urgente' || 'aviso' || 'perigo' => VoiceEmotion.alerta,
      'comemorando' || 'feliz' || 'sucesso' || 'celebrando' =>
        VoiceEmotion.comemorando,
      'serio' || 'formal' || 'tecnico' || 'firme' => VoiceEmotion.serio,
      'duvida' || 'curioso' || 'pergunta' || 'incerteza' => VoiceEmotion.duvida,
      _ => null,
    };
  }
}

class VoiceEmotionParseResult {
  const VoiceEmotionParseResult({
    required this.emotion,
    required this.cleanText,
    required this.explicitTag,
  });

  final VoiceEmotion emotion;
  final String cleanText;
  final bool explicitTag;
}

/// Extrai tags emocionais curtas (`[alerta]`, `[serio]`, etc.) no início das
/// respostas do modelo, remove-as do texto exibido/falado e infere nuance local
/// sem gastar chamadas extras de IA.
class VoiceEmotionParser {
  VoiceEmotionParser._();

  static final RegExp _leadingTagRegex = RegExp(
    r'^\s*[\[\(]\s*([A-Za-zÀ-ÿ_ -]{3,20})\s*[\]\)]\s*[:\-]?\s*',
  );

  static VoiceEmotionParseResult parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const VoiceEmotionParseResult(
        emotion: VoiceEmotion.neutro,
        cleanText: '',
        explicitTag: false,
      );
    }

    final match = _leadingTagRegex.firstMatch(trimmed);
    if (match != null) {
      final candidate = match.group(1) ?? '';
      final parsed = VoiceEmotion.tryParseTag(candidate);
      if (parsed != null) {
        final cleaned = trimmed.substring(match.end).trimLeft();
        return VoiceEmotionParseResult(
          emotion: parsed,
          cleanText: cleaned,
          explicitTag: true,
        );
      }
    }

    return VoiceEmotionParseResult(
      emotion: inferNuance(trimmed),
      cleanText: trimmed,
      explicitTag: false,
    );
  }

  /// Remove apenas a tag emocional inicial caso exista, mantendo o texto limpo.
  static String stripTag(String raw) => parse(raw).cleanText;

  /// Leitura determinística de nuances em português (0 ms, sem LLM).
  static VoiceEmotion inferNuance(String text) {
    final norm = PtBrTextNormalizer.normalizePhrase(text);
    if (norm.isEmpty) return VoiceEmotion.neutro;

    if (norm.contains('atencao') ||
        norm.contains('alerta') ||
        norm.contains('critico') ||
        norm.contains('perigo') ||
        norm.contains('bloqueado') ||
        norm.contains('emergencia') ||
        norm.contains('urgente')) {
      return VoiceEmotion.alerta;
    }

    if (norm.contains('sinto muito') ||
        norm.contains('desculpe') ||
        norm.contains('lamento') ||
        norm.contains('infelizmente') ||
        norm.contains('nao consegui') ||
        norm.contains('falhou')) {
      return VoiceEmotion.lamento;
    }

    if (norm.contains('parabens') ||
        norm.contains('excelente') ||
        norm.contains('concluido com sucesso') ||
        norm.contains('perfeito') ||
        norm.contains('conseguimos')) {
      return VoiceEmotion.comemorando;
    }

    if (norm.contains('voce consegue') ||
        norm.contains('vamos la') ||
        norm.contains('bom trabalho') ||
        norm.contains('otimo progresso') ||
        norm.contains('continue assim')) {
      return VoiceEmotion.encorajador;
    }

    if (text.trim().endsWith('?') && text.length < 180) {
      return VoiceEmotion.duvida;
    }

    return VoiceEmotion.neutro;
  }
}
