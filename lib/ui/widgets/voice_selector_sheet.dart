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
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.78,
        minChildSize: 0.45,
        maxChildSize: 0.94,
        expand: false,
        builder: (_, scrollController) => VoiceSelectorSheet(
          voiceService: voiceService,
          onChanged: onChanged,
          scrollController: scrollController,
        ),
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

  final _fishKeyCtrl = TextEditingController();
  final _fishRefCtrl = TextEditingController();

  List<TtsVoiceOption> _voices = const [];
  bool _loading = true;
  String? _status;

  bool _fishExpanded = false;
  bool _fishEnabled = false;
  bool _fishObscureKey = true;
  bool _fishSaving = false;
  String _fishLanguage = FishAudioConfig.defaultLanguage;
  String _fishModel = FishAudioConfig.defaultModel;
  String? _fishFeedback;
  bool _fishFeedbackIsError = false;

  @override
  void initState() {
    super.initState();
    _syncFishFieldsFromService();
    _loadVoices();
  }

  @override
  void dispose() {
    _fishKeyCtrl.dispose();
    _fishRefCtrl.dispose();
    super.dispose();
  }

  void _syncFishFieldsFromService() {
    final cfg = widget.voiceService.fishConfig;
    _fishEnabled = cfg.enabled;
    _fishKeyCtrl.text = cfg.apiKey;
    _fishRefCtrl.text = cfg.referenceId;
    _fishLanguage = cfg.language;
    _fishModel = cfg.model;
    if (cfg.isActive) {
      _fishExpanded = true;
    }
  }

  Future<void> _loadVoices() async {
    setState(() => _loading = true);
    try {
      await widget.voiceService.initialize();
      final list = await widget.voiceService.listPortugueseVoices();
      if (!mounted) return;
      setState(() {
        _syncFishFieldsFromService();
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
    if (widget.voiceService.isFishAudioActive) {
      final disabledCfg =
          widget.voiceService.fishConfig.copyWith(enabled: false);
      await widget.voiceService.setFishConfig(disabledCfg);
      _fishEnabled = false;
    }
    await widget.voiceService.setPreferredVoice(option);
    widget.onChanged?.call();
    if (!mounted) return;
    setState(() {});
    unawaited(widget.voiceService.preview().catchError((_) {}));
  }

  Future<void> _saveAndTestFish({bool? forceEnabled}) async {
    final apiKey = _fishKeyCtrl.text.trim();
    final refId = _fishRefCtrl.text.trim();
    final nextEnabled = forceEnabled ?? true;

    if (nextEnabled && (apiKey.isEmpty || refId.isEmpty)) {
      setState(() {
        _fishFeedback =
            'Informe a API Key e o Reference ID da voz no Fish Studio.';
        _fishFeedbackIsError = true;
      });
      return;
    }

    HapticFeedback.selectionClick();
    setState(() {
      _fishSaving = true;
      _fishFeedback = null;
    });

    try {
      final next = FishAudioConfig(
        enabled: nextEnabled,
        apiKey: apiKey,
        referenceId: refId,
        language: _fishLanguage,
        model: _fishModel,
      );
      await widget.voiceService.setFishConfig(next);
      _fishEnabled = nextEnabled;
      widget.onChanged?.call();

      if (nextEnabled) {
        await widget.voiceService.preview();
        final err = widget.voiceService.lastFishError;
        if (!mounted) return;
        setState(() {
          _fishSaving = false;
          if (err != null && err.isNotEmpty) {
            _fishFeedback = 'Salvo, mas a API falhou e usou voz offline: $err';
            _fishFeedbackIsError = true;
          } else {
            _fishFeedback = 'Fish Audio ativo ($_fishLanguage • $_fishModel).';
            _fishFeedbackIsError = false;
          }
        });
      } else {
        if (!mounted) return;
        setState(() {
          _fishSaving = false;
          _fishFeedback = 'Fish Audio desativado; usando voz do aparelho.';
          _fishFeedbackIsError = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fishSaving = false;
        _fishFeedback = 'Erro ao salvar Fish Audio: $e';
        _fishFeedbackIsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeVoice = widget.voiceService.activeVoiceLabel;
    final currentProfile = widget.voiceService.profile;
    final fishActive = widget.voiceService.isFishAudioActive;

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
                  fishActive
                      ? 'Reference ID: ${widget.voiceService.fishConfig.shortReferenceId} (fallback: ${widget.voiceService.activeVoiceName ?? "Android"})'
                      : 'Timbre: ${currentProfile.label} (Tom ${currentProfile.pitch} • Velocidade ${currentProfile.rate})',
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
          _buildFishAudioCard(fishActive),
          const SizedBox(height: 14),
          Text(
            '3. VOZES PORTUGUÊS INSTALADAS (${_voices.length})',
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
              _buildLocalVoiceTile(voice, fishActive),
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

  Widget _buildFishAudioCard(bool fishActive) {
    final langCodes =
        FishAudioConfig.supportedLanguages.map((e) => e.code).toList();
    final safeLang = langCodes.contains(_fishLanguage) ? _fishLanguage : 'pt';
    final models = List<String>.from(FishAudioConfig.supportedModels);
    if (!models.contains(_fishModel)) {
      models.insert(0, _fishModel);
    }

    return Material(
      color: const Color(0xFF1D0408),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: fishActive ? _crimson : _border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            key: const ValueKey('fish_audio_header'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _fishExpanded = !_fishExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.graphic_eq,
                    size: 16,
                    color: fishActive ? _crimson : _rose,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '2. FISH STUDIO / FISH AUDIO (API)',
                      style: TextStyle(
                        color: _rose,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.9,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: fishActive ? _crimson : const Color(0xFF2E0305),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      fishActive ? 'ATIVO' : 'API',
                      style: TextStyle(
                        color: fishActive ? Colors.black : _rose,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _fishExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: _rose,
                  ),
                ],
              ),
            ),
          ),
          if (_fishExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(color: _border, height: 12),
                  SwitchListTile.adaptive(
                    key: const ValueKey('fish_enabled_switch'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: _crimson,
                    title: const Text(
                      'Usar voz do Fish Studio (API)',
                      style: TextStyle(
                        color: Color(0xFFF0E6E7),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Com fallback automático para a voz offline se falhar',
                      style: TextStyle(color: Color(0xFFA89698), fontSize: 10),
                    ),
                    value: _fishEnabled,
                    onChanged: (v) async {
                      setState(() => _fishEnabled = v);
                      if (!v) {
                        await _saveAndTestFish(forceEnabled: false);
                      }
                    },
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    key: const ValueKey('fish_api_key_field'),
                    controller: _fishKeyCtrl,
                    obscureText: _fishObscureKey,
                    style:
                        const TextStyle(color: Color(0xFFF0E6E7), fontSize: 12),
                    decoration: InputDecoration(
                      labelText: 'Fish API Key',
                      hintText: 'Bearer token do Fish Audio',
                      labelStyle: const TextStyle(color: _rose, fontSize: 11),
                      hintStyle: const TextStyle(
                        color: Color(0xFF7D6B6D),
                        fontSize: 11,
                      ),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFF14040A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _border),
                      ),
                      suffixIcon: IconButton(
                        tooltip: _fishObscureKey ? 'Mostrar' : 'Ocultar',
                        icon: Icon(
                          _fishObscureKey
                              ? Icons.visibility
                              : Icons.visibility_off,
                          size: 16,
                          color: _rose,
                        ),
                        onPressed: () => setState(
                          () => _fishObscureKey = !_fishObscureKey,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('fish_reference_id_field'),
                    controller: _fishRefCtrl,
                    style:
                        const TextStyle(color: Color(0xFFF0E6E7), fontSize: 12),
                    decoration: InputDecoration(
                      labelText: 'Reference ID (ID da voz no Fish Studio)',
                      hintText: 'Ex.: 933563129e564b19a115bedd57b7406a',
                      labelStyle: const TextStyle(color: _rose, fontSize: 11),
                      hintStyle: const TextStyle(
                        color: Color(0xFF7D6B6D),
                        fontSize: 11,
                      ),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFF14040A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _border),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: const ValueKey('fish_language_dropdown'),
                          value: safeLang,
                          dropdownColor: const Color(0xFF1D0408),
                          style: const TextStyle(
                            color: Color(0xFFF0E6E7),
                            fontSize: 11,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Idioma',
                            labelStyle: const TextStyle(
                              color: _rose,
                              fontSize: 10,
                            ),
                            isDense: true,
                            filled: true,
                            fillColor: const Color(0xFF14040A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          items: [
                            for (final lang
                                in FishAudioConfig.supportedLanguages)
                              DropdownMenuItem(
                                value: lang.code,
                                child: Text(lang.label),
                              ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _fishLanguage = val);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: const ValueKey('fish_model_dropdown'),
                          value: _fishModel,
                          dropdownColor: const Color(0xFF1D0408),
                          style: const TextStyle(
                            color: Color(0xFFF0E6E7),
                            fontSize: 11,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Modelo',
                            labelStyle: const TextStyle(
                              color: _rose,
                              fontSize: 10,
                            ),
                            isDense: true,
                            filled: true,
                            fillColor: const Color(0xFF14040A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          items: [
                            for (final m in models)
                              DropdownMenuItem(
                                value: m,
                                child: Text(m),
                              ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _fishModel = val);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'No Fish Studio (fish.audio), abra a voz desejada (ex.: Ultron), copie o Reference ID da URL/modelo e gere sua API Key nas configurações da conta.',
                    style: TextStyle(color: Color(0xFFA89698), fontSize: 10),
                  ),
                  if (_fishFeedback != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _fishFeedbackIsError
                            ? const Color(0xFF3E050B)
                            : const Color(0xFF122817),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _fishFeedbackIsError
                              ? _crimson
                              : const Color(0xFF4CAF50),
                        ),
                      ),
                      child: Text(
                        _fishFeedback!,
                        style: TextStyle(
                          color: _fishFeedbackIsError
                              ? _rose
                              : const Color(0xFFA5D6A7),
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          key: const ValueKey('fish_save_test_button'),
                          onPressed: _fishSaving
                              ? null
                              : () => _saveAndTestFish(forceEnabled: true),
                          style: FilledButton.styleFrom(
                            backgroundColor: _crimson,
                          ),
                          icon: _fishSaving
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save, size: 15),
                          label: Text(
                            _fishSaving
                                ? 'TESTANDO...'
                                : 'SALVAR E TESTAR FISH',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      if (fishActive) ...[
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _fishSaving
                              ? null
                              : () => _saveAndTestFish(forceEnabled: false),
                          child: const Text(
                            'DESATIVAR',
                            style: TextStyle(fontSize: 10, color: _rose),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLocalVoiceTile(TtsVoiceOption voice, bool fishActive) {
    final isSelected =
        !fishActive && voice.name == widget.voiceService.activeVoiceName;
    final isFallback =
        fishActive && voice.name == widget.voiceService.activeVoiceName;

    return Card(
      color: isSelected ? const Color(0xFF3E050B) : const Color(0xFF1D0408),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: isSelected ? _crimson : _border),
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
          '${voice.quality.isEmpty ? '' : ' • ${voice.quality}'}'
          '${isFallback ? ' • Fallback' : ''}',
          style: const TextStyle(
            color: Color(0xFFA89698),
            fontSize: 10,
          ),
        ),
        trailing: Icon(
          isSelected ? Icons.check_circle : Icons.play_circle_outline,
          color: isSelected ? _crimson : _rose,
          size: 20,
        ),
        onTap: () => _selectVoice(voice),
      ),
    );
  }
}
