import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/voice_service.dart';

Future<void> showVoiceSelectorSheet(
  BuildContext context, {
  required VoiceService voiceService,
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF14040A),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) => VoiceSelectorSheet(
        voiceService: voiceService,
        onChanged: onChanged,
        scrollController: scrollController,
      ),
    ),
  );
}

class VoiceSelectorSheet extends StatefulWidget {
  const VoiceSelectorSheet({
    super.key,
    required this.voiceService,
    this.onChanged,
    this.scrollController,
  });

  final VoiceService voiceService;
  final VoidCallback? onChanged;
  final ScrollController? scrollController;

  @override
  State<VoiceSelectorSheet> createState() => _VoiceSelectorSheetState();
}

class _VoiceSelectorSheetState extends State<VoiceSelectorSheet> {
  static const _crimson = Color(0xFFE50914);
  static const _rose = Color(0xFFFFA0A0);
  static const _border = Color(0xFF51080D);

  List<TtsVoiceOption> _voices = const [];
  bool _loading = true;
  String? _status;

  @override
  void initState() {
    super.initState();
    _loadVoices();
  }

  Future<void> _loadVoices() async {
    setState(() => _loading = true);
    try {
      await widget.voiceService.initialize();
      final list = await widget.voiceService.listPortugueseVoices();
      if (!mounted) return;
      setState(() {
        _voices = list;
        _loading = false;
        _status = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = 'Não foi possível consultar as vozes do Android: $e';
      });
    }
  }

  Future<void> _selectProfile(VoiceProfile profile) async {
    HapticFeedback.selectionClick();
    await widget.voiceService.setProfile(profile);
    widget.onChanged?.call();
    if (!mounted) return;
    setState(() {});
    unawaited(widget.voiceService.preview().catchError((_) {}));
  }

  Future<void> _selectVoice(TtsVoiceOption option) async {
    HapticFeedback.selectionClick();
    await widget.voiceService.setPreferredVoice(option);
    widget.onChanged?.call();
    if (!mounted) return;
    setState(() {});
    unawaited(widget.voiceService.preview().catchError((_) {}));
  }

  @override
  Widget build(BuildContext context) {
    final activeVoice =
        widget.voiceService.activeVoiceName ?? 'Padrão do sistema';
    final currentProfile = widget.voiceService.profile;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: ListView(
        controller: widget.scrollController,
        children: [
          Row(
            children: [
              const Icon(Icons.record_voice_over, color: _crimson, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'VOZ DO U.L.T.R.O.N.',
                  style: TextStyle(
                    color: _crimson,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Recarregar vozes',
                onPressed: _loadVoices,
                icon: const Icon(Icons.refresh, color: _rose, size: 18),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF2E0305),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Voz ativa: $activeVoice',
                  style: const TextStyle(
                    color: Color(0xFFF0E6E7),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Timbre: ${currentProfile.label} (Tom ${currentProfile.pitch} • Velocidade ${currentProfile.rate})',
                  style: const TextStyle(color: _rose, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '1. TIMBRE E RITMO',
            style: TextStyle(
              color: _rose,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.9,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final prof in VoiceProfile.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: OutlinedButton(
                      onPressed: () => _selectProfile(prof),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: currentProfile == prof
                            ? _crimson
                            : const Color(0xFF2E0305),
                        foregroundColor:
                            currentProfile == prof ? Colors.black : _rose,
                        side: BorderSide(
                          color: currentProfile == prof ? _crimson : _border,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(
                        prof.label,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => unawaited(
                      widget.voiceService.preview().catchError((_) {})),
                  style: FilledButton.styleFrom(backgroundColor: _crimson),
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text(
                    'TESTAR VOZ',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () =>
                    unawaited(widget.voiceService.stop().catchError((_) {})),
                icon: const Icon(Icons.stop, size: 16, color: _rose),
                label: const Text(
                  'CALAR',
                  style: TextStyle(fontSize: 11, color: _rose),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '2. VOZES PORTUGUÊS INSTALADAS (${_voices.length})',
            style: const TextStyle(
              color: _rose,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.9,
            ),
          ),
          const SizedBox(height: 6),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_status != null)
            Text(
              _status!,
              style: const TextStyle(color: _rose, fontSize: 11),
            )
          else if (_voices.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Nenhuma voz pt-BR foi retornada pelo motor TTS do Android. Verifique Configurações do Android → Conversão de texto em voz (Google TTS).',
                style: TextStyle(color: Color(0xFFA89698), fontSize: 11),
              ),
            )
          else ...[
            for (final voice in _voices)
              Card(
                color: voice.name == widget.voiceService.activeVoiceName
                    ? const Color(0xFF3E050B)
                    : const Color(0xFF1D0408),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: voice.name == widget.voiceService.activeVoiceName
                        ? _crimson
                        : _border,
                  ),
                ),
                child: ListTile(
                  dense: true,
                  title: Text(
                    voice.name,
                    style: const TextStyle(
                      color: Color(0xFFF0E6E7),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${voice.locale} • ${voice.offline ? 'Offline' : 'Rede'}'
                    '${voice.quality.isEmpty ? '' : ' • ${voice.quality}'}',
                    style: const TextStyle(
                      color: Color(0xFFA89698),
                      fontSize: 10,
                    ),
                  ),
                  trailing: Icon(
                    voice.name == widget.voiceService.activeVoiceName
                        ? Icons.check_circle
                        : Icons.play_circle_outline,
                    color: voice.name == widget.voiceService.activeVoiceName
                        ? _crimson
                        : _rose,
                    size: 20,
                  ),
                  onTap: () => _selectVoice(voice),
                ),
              ),
            if (_voices.length <= 1)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Dica: este aparelho só possui 1 voz PT instalada. Para trocar entre mais vozes masculinas/femininas, baixe pacotes em Configurações do Android → Idioma/TTS → Vozes.',
                  style: TextStyle(color: Color(0xFFA89698), fontSize: 10),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
