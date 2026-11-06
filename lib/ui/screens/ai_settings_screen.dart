import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/ai_provider_service.dart';
import '../../services/device_control_service.dart';
import '../../services/fish_audio_tts.dart';
import '../../services/voice_service.dart';
import '../theme.dart';

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key, AiProviderStore? store}) : _store = store;

  final AiProviderStore? _store;

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {

  late final AiProviderStore _store = widget._store ?? AiProviderStore();
  final _deviceService = DeviceControlService();
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _url = TextEditingController(text: 'https://api.groq.com/openai/v1');
  final _model = TextEditingController(text: 'openai/gpt-oss-120b');
  final _key = TextEditingController();
  final _fishKey = TextEditingController();
  final _fishVoice = TextEditingController();

  List<AiProviderConfig> _providers = const [];
  List<String> _fetchedModels = const [];
  FreeProviderPreset _selectedPreset = FreeProviderPreset.catalog[1];
  bool _loading = true;
  bool _fetchingModels = false;
  bool _savingFish = false;
  bool _fishConfigured = false;
  String? _testingProviderId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _model.dispose();
    _key.dispose();
    _fishKey.dispose();
    _fishVoice.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final list = await _store.load();
    final fish = await FishAudioTts().loadConfig();
    if (!mounted) return;
    setState(() {
      _providers = list;
      _fishKey.text = fish.apiKey;
      _fishVoice.text = fish.voiceId;
      _fishConfigured = fish.isConfigured;
      _loading = false;
    });
  }

  Future<void> _saveFishVoice() async {
    HapticFeedback.mediumImpact();
    setState(() => _savingFish = true);
    final fish = FishAudioTts();
    await fish.saveConfig(apiKey: _fishKey.text, voiceId: _fishVoice.text);
    await fish.dispose();
    if (!mounted) return;
    setState(() {
      _fishConfigured =
          _fishKey.text.trim().isNotEmpty && _fishVoice.text.trim().isNotEmpty;
      _savingFish = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _fishConfigured
              ? 'Voz Fish Audio salva. O Ultron vai usar essa voz.'
              : 'Dados incompletos. Sem chave e ID o Ultron usa o TTS local.',
        ),
      ),
    );
  }

  Future<void> _testFishVoice() async {
    HapticFeedback.selectionClick();
    final voice = VoiceService();
    await voice.preview();
    await voice.dispose();
  }

  Future<void> _persist(List<AiProviderConfig> next) async {
    final normalized = [
      for (var i = 0; i < next.length; i++) next[i].copyWith(priority: i),
    ];
    await _store.save(normalized);
    if (!mounted) return;
    setState(() => _providers = normalized);
  }

  void _applyFreePreset(FreeProviderPreset preset) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedPreset = preset;
      _name.text = preset.name;
      _url.text = preset.baseUrl;
      _model.text = preset.defaultModel;
      if (!preset.requiresKey) {
        _key.text = 'free';
      } else if (_key.text.trim() == 'free') {
        _key.clear();
      }
      _fetchedModels = preset.recommendedModels;
    });
  }

  Future<void> _activateZeroKeyFreeNow() async {
    HapticFeedback.mediumImpact();
    final zeroKeyPreset = FreeProviderPreset.catalog.first;
    final existingIdx = _providers.indexWhere(
      (p) => p.baseUrl.toLowerCase().contains('pollinations.ai'),
    );
    List<AiProviderConfig> updated;
    if (existingIdx >= 0) {
      final copy = [..._providers];
      copy[existingIdx] = copy[existingIdx].copyWith(
        enabled: true,
        apiKey: 'free',
      );
      updated = copy;
    } else {
      final added = AiProviderConfig(
        id: 'pollinations_${DateTime.now().microsecondsSinceEpoch}',
        name: zeroKeyPreset.name,
        baseUrl: zeroKeyPreset.baseUrl,
        model: zeroKeyPreset.defaultModel,
        apiKey: 'free',
        enabled: true,
        priority: _providers.length,
      );
      updated = [..._providers, added];
    }
    await _persist(updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '⚡ IA Grátis Sem Chave (Pollinations AI) ativada na fila de failover!',
          style: TextStyle(fontSize: 13),
        ),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openKeyPage(FreeProviderPreset preset) async {
    HapticFeedback.lightImpact();
    try {
      await _deviceService.openUrl(preset.getKeyUrl);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: preset.getKeyUrl));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Link copiado: ${preset.getKeyUrl}',
            style: const TextStyle(fontSize: 13),
          ),
        ),
      );
    }
  }

  Future<void> _fetchModelsFromApi() async {
    final baseUrl = _url.text.trim();
    final apiKey = _key.text.trim();
    final isPollinations = baseUrl.toLowerCase().contains('pollinations.ai');
    if (baseUrl.isEmpty || (!isPollinations && apiKey.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Preencha a URL Base e a Chave da API primeiro para buscar os modelos ao vivo.',
            style: TextStyle(fontSize: 13),
          ),
        ),
      );
      return;
    }
    setState(() => _fetchingModels = true);
    try {
      final temp = AiProviderConfig(
        id: 'temp',
        name: _name.text.trim().isEmpty ? 'Temp' : _name.text.trim(),
        baseUrl: baseUrl,
        model: _model.text.trim(),
        apiKey: apiKey.isEmpty ? 'free' : apiKey,
      );
      final models = await temp.fetchAvailableModels();
      if (!mounted) return;
      setState(() {
        _fetchedModels = models;
        if (models.isNotEmpty && !models.contains(_model.text.trim())) {
          _model.text = models.first;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${models.length} modelos ativos carregados do provedor!',
            style: const TextStyle(fontSize: 13),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao listar modelos: $e',
            style: const TextStyle(fontSize: 13),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _fetchingModels = false);
    }
  }

  Future<void> _testProvider(AiProviderConfig provider) async {
    setState(() => _testingProviderId = provider.id);
    try {
      final res = await provider.testConnection();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Conectado ($res)', style: const TextStyle(fontSize: 13)),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Falha: $e', style: const TextStyle(fontSize: 13)),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _testingProviderId = null);
    }
  }

  Future<void> _add() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();
    final isKeyless = _url.text.trim().toLowerCase().contains('pollinations.ai');
    final added = AiProviderConfig(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim(),
      baseUrl: _url.text.trim(),
      model: _model.text.trim(),
      apiKey: isKeyless && _key.text.trim().isEmpty
          ? 'free'
          : _key.text.trim(),
      priority: _providers.length,
    );
    _name.clear();
    _key.clear();
    await _persist([..._providers, added]);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '✅ Provedor "${added.name}" salvo na fila de failover!',
          style: const TextStyle(fontSize: 13),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  InputDecoration _hudInputDecoration(
    String label, {
    String? hint,
    Widget? suffixIcon,
  }) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffixIcon,
        isDense: true,
        filled: true,
        fillColor: AppColors.surface,
        labelStyle: const TextStyle(color: AppColors.muted, fontSize: 13),
        hintStyle: const TextStyle(color: AppColors.subtle, fontSize: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.crimson),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final activeModels = _fetchedModels.isNotEmpty
        ? _fetchedModels
        : _selectedPreset.recommendedModels;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.accent,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CENTRAL DE IA • 100% GRATUITA',
              style: TextStyle(
                color: AppColors.accent,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.3,
              ),
            ),
            Text(
              'Failover Multi-Provedor • Zero-Key & Free Tiers',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                // 1. Instant Zero-Key Hero Banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.surface, AppColors.background],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.crimson.withValues(alpha: 0.5)),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.crimson.withValues(alpha: 0.12),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppColors.accent.withValues(alpha: 0.6),
                              ),
                            ),
                            child: const Text(
                              'DE GRAÇA SEMPRE',
                              style: TextStyle(
                                color: AppColors.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'IA Instantânea Sem Cadastro ou Free Tiers',
                              style: TextStyle(
                                color: AppColors.accent,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'O U.L.T.R.O.N. Mobile já vem com o Pollinations AI (Zero-Key) pré-configurado para responder de graça sem precisar de chave. Para velocidade máxima (2000+ tok/s), adicione chaves gratuitas da Groq, Gemini, OpenRouter (:free) ou Cerebras abaixo!',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.surface,
                            foregroundColor: AppColors.accent,
                            side: const BorderSide(color: AppColors.crimson),
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _activateZeroKeyFreeNow,
                          icon: const Icon(Icons.bolt, size: 16, color: AppColors.accent),
                          label: const Text(
                            'ATIVAR IA GRÁTIS SEM CHAVE AGORA (POLLINATIONS)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 2. Interactive Catalog of 9 Free Providers
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'CATÁLOGO DE PROVEDORES 100% GRATUITOS (9 OPÇÕES)',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    Text(
                      'Deslize ↔',
                      style: TextStyle(color: AppColors.subtle, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 156,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: FreeProviderPreset.catalog.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final preset = FreeProviderPreset.catalog[index];
                      final isSelected = _selectedPreset.id == preset.id;
                      return GestureDetector(
                        onTap: () => _applyFreePreset(preset),
                        child: Container(
                          width: 245,
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.surface
                                : AppColors.background,
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                              color: isSelected ? AppColors.crimson : AppColors.border,
                              width: isSelected ? 1.4 : 1.0,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: preset.requiresKey
                                          ? AppColors.surface
                                          : AppColors.accent.withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(
                                        color: preset.requiresKey
                                            ? AppColors.crimson.withValues(alpha: 0.45)
                                            : AppColors.accent,
                                      ),
                                    ),
                                    child: Text(
                                      preset.badge,
                                      style: TextStyle(
                                        color: preset.requiresKey
                                            ? AppColors.accent
                                            : AppColors.accent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(
                                      Icons.check_circle,
                                      size: 14,
                                      color: AppColors.accent,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                preset.name,
                                style: const TextStyle(
                                  color: AppColors.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Expanded(
                                child: Text(
                                  preset.description,
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 12,
                                    height: 1.25,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => _applyFreePreset(preset),
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 5,
                                        ),
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: AppColors.surface,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                            color: AppColors.crimson.withValues(
                                              alpha: 0.5,
                                            ),
                                          ),
                                        ),
                                        child: const Text(
                                          'USAR PRESET',
                                          style: TextStyle(
                                            color: AppColors.accent,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (preset.requiresKey) ...[
                                    const SizedBox(width: 6),
                                    InkWell(
                                      onTap: () => _openKeyPage(preset),
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.surface,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(color: AppColors.border),
                                        ),
                                        child: const Row(
                                          children: [
                                            Icon(
                                              Icons.key,
                                              size: 10,
                                              color: AppColors.accent,
                                            ),
                                            SizedBox(width: 3),
                                            Text(
                                              'CHAVE GRÁTIS',
                                              style: TextStyle(
                                                color: AppColors.accent,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),

                // 3. Active Providers Queue (Failover Order)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'FILA DE FAILOVER ATIVA (${_providers.length})',
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const Text(
                      'Ordem de prioridade ↓',
                      style: TextStyle(color: AppColors.subtle, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                for (var i = 0; i < _providers.length; i++)
                  Container(
                    key: ValueKey(_providers[i].id),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _providers[i].enabled
                            ? AppColors.crimson.withValues(alpha: 0.45)
                            : AppColors.border,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                i == 0 ? '#1 PRIMÁRIO' : '#${i + 1} BACKUP',
                                style: const TextStyle(
                                  color: AppColors.accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _providers[i].isKeylessProvider
                                    ? AppColors.accent.withValues(alpha: 0.15)
                                    : AppColors.surface,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _providers[i].isKeylessProvider
                                    ? 'SEM CHAVE (GRÁTIS)'
                                    : 'CHAVE AES-GCM',
                                style: TextStyle(
                                  color: _providers[i].isKeylessProvider
                                      ? AppColors.accent
                                      : AppColors.muted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _providers[i].name,
                                style: const TextStyle(
                                  color: AppColors.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Switch(
                              value: _providers[i].enabled,
                              activeThumbColor: AppColors.crimson,
                              onChanged: (v) {
                                final copy = [..._providers];
                                copy[i] = copy[i].copyWith(enabled: v);
                                _persist(copy);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.memory,
                              size: 12,
                              color: AppColors.accent,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${_providers[i].model}  •  ${_providers[i].baseUrl}',
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            InkWell(
                              onTap: _testingProviderId == _providers[i].id
                                  ? null
                                  : () => _testProvider(_providers[i]),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppColors.crimson.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_testingProviderId == _providers[i].id)
                                      const SizedBox(
                                        width: 10,
                                        height: 10,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.accent,
                                        ),
                                      )
                                    else
                                      const Icon(
                                        Icons.bolt,
                                        size: 12,
                                        color: AppColors.accent,
                                      ),
                                    const SizedBox(width: 4),
                                    const Text(
                                      'TESTAR CONEXÃO',
                                      style: TextStyle(
                                        color: AppColors.accent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.arrow_upward,
                                size: 15,
                                color: AppColors.muted,
                              ),
                              onPressed: i == 0
                                  ? null
                                  : () {
                                      final copy = [..._providers];
                                      final item = copy.removeAt(i);
                                      copy.insert(i - 1, item);
                                      _persist(copy);
                                    },
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.arrow_downward,
                                size: 15,
                                color: AppColors.muted,
                              ),
                              onPressed: i == _providers.length - 1
                                  ? null
                                  : () {
                                      final copy = [..._providers];
                                      final item = copy.removeAt(i);
                                      copy.insert(i + 1, item);
                                      _persist(copy);
                                    },
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 16,
                                color: AppColors.accent,
                              ),
                              onPressed: () {
                                final copy = [..._providers]..removeAt(i);
                                _persist(copy);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),

                // 4. Add / Configure Provider Form
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'CONFIGURAR / ADICIONAR PROVEDOR',
                              style: TextStyle(
                                color: AppColors.accent,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                              ),
                            ),
                            if (_selectedPreset.requiresKey)
                              InkWell(
                                onTap: () => _openKeyPage(_selectedPreset),
                                child: const Text(
                                  '🔑 Criar chave grátis ↗',
                                  style: TextStyle(
                                    color: AppColors.accent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _name,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 14,
                          ),
                          decoration: _hudInputDecoration(
                            'Nome do Provedor',
                            hint: 'Ex: Groq Cloud, OpenRouter Free, Gemini...',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Obrigatório'
                              : null,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _url,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 14,
                          ),
                          decoration: _hudInputDecoration(
                            'URL Base (HTTPS)',
                            hint: 'https://api.groq.com/openai/v1',
                          ),
                          validator: (v) {
                            final uri = Uri.tryParse(v?.trim() ?? '');
                            if (uri == null ||
                                uri.scheme != 'https' ||
                                uri.host.isEmpty) {
                              return 'Use uma URL https:// válida';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _key,
                          obscureText: true,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 14,
                          ),
                          decoration: _hudInputDecoration(
                            'Chave da API (ou "free" para Pollinations Sem Chave)',
                            hint: 'gsk_... / AIza... / sk-or-... / free',
                          ),
                          validator: (v) {
                            final isKeyless = _url.text
                                .trim()
                                .toLowerCase()
                                .contains('pollinations.ai');
                            if (!isKeyless && (v == null || v.trim().isEmpty)) {
                              return 'Informe a chave gratuita (ou escolha Pollinations Zero-Key)';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _model,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 14,
                          ),
                          decoration: _hudInputDecoration(
                            'Modelo Ativo',
                            hint: 'openai/gpt-oss-120b',
                            suffixIcon: IconButton(
                              tooltip: 'Buscar modelos ativos da API',
                              onPressed:
                                  _fetchingModels ? null : _fetchModelsFromApi,
                              icon: _fetchingModels
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.accent,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.sync,
                                      size: 16,
                                      color: AppColors.accent,
                                    ),
                            ),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Obrigatório'
                              : null,
                        ),
                        if (activeModels.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          const Text(
                            'MODELOS GRATUITOS RECOMENDADOS (TOQUE PARA SELECIONAR):',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: activeModels
                                .take(10)
                                .map(
                                  (m) => GestureDetector(
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      setState(() => _model.text = m);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _model.text.trim() == m
                                            ? AppColors.crimson
                                            : AppColors.surface,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: _model.text.trim() == m
                                              ? AppColors.crimson
                                              : AppColors.border,
                                        ),
                                      ),
                                      child: Text(
                                        m,
                                        style: TextStyle(
                                          color: _model.text.trim() == m
                                              ? Colors.white
                                              : AppColors.accent,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.crimson,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _add,
                          icon: const Icon(Icons.add_circle_outline, size: 16),
                          label: const Text(
                            'SALVAR PROVEDOR GRATUITO NA FILA',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Voz personalizada (Fish Audio)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _fishConfigured
                          ? AppColors.accent
                          : AppColors.border,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.record_voice_over,
                            size: 18,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'VOZ PERSONALIZADA • FISH AUDIO',
                              style: TextStyle(
                                color: AppColors.accent,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Text(
                              _fishConfigured ? 'ATIVA' : 'TTS LOCAL',
                              style: TextStyle(
                                color: _fishConfigured
                                    ? AppColors.accent
                                    : AppColors.muted,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Cole a chave da API e o ID do modelo criado no fish.audio. '
                        'Sem os dois, o Ultron continua usando o TTS do aparelho.',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _fishKey,
                        obscureText: true,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 14,
                        ),
                        decoration: _hudInputDecoration(
                          'Chave da API Fish Audio',
                          hint: 'cole aqui a API key do fish.audio',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _fishVoice,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 14,
                        ),
                        decoration: _hudInputDecoration(
                          'ID do modelo de voz (reference_id)',
                          hint: 'ex: 7f2c9a...',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.crimson,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: _savingFish ? null : _saveFishVoice,
                              icon: _savingFish
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined, size: 16),
                              label: const Text(
                                'SALVAR VOZ',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.accent,
                              side: const BorderSide(color: AppColors.border),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 11,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: _testFishVoice,
                            icon: const Icon(Icons.play_arrow, size: 16),
                            label: const Text(
                              'TESTAR',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
