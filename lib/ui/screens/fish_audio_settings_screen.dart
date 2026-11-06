import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/fish_audio_service.dart';

class FishAudioSettingsScreen extends StatefulWidget {
  const FishAudioSettingsScreen({super.key, FishAudioService? service})
      : _service = service;

  final FishAudioService? _service;

  @override
  State<FishAudioSettingsScreen> createState() =>
      _FishAudioSettingsScreenState();
}

class _FishAudioSettingsScreenState extends State<FishAudioSettingsScreen> {
  static const _crimson = Color(0xFFE50914);
  static const _rose = Color(0xFFFFA0A0);
  static const _surface = Color(0xFF2E0305);
  static const _border = Color(0xFF51080D);

  late final FishAudioService _service = widget._service ?? FishAudioService();
  final _apiKey = TextEditingController();
  final _referenceId = TextEditingController();
  String _model = FishAudioService.defaultModel;
  bool _enabled = false;
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  bool _showKey = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _apiKey.dispose();
    _referenceId.dispose();
    if (widget._service == null) _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await _service.loadSettings();
      if (!mounted) return;
      setState(() {
        _apiKey.text = settings.apiKey;
        _referenceId.text = settings.referenceId;
        _model = settings.model;
        _enabled = settings.enabled;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Não foi possível carregar as configurações: $error');
    }
  }

  FishAudioSettings get _settings => FishAudioSettings(
        apiKey: _apiKey.text.trim(),
        model: _model,
        referenceId: _referenceId.text.trim(),
        enabled: _enabled,
      );

  Future<bool> _save({bool quiet = false}) async {
    setState(() => _saving = true);
    try {
      await _service.saveSettings(_settings);
      if (!mounted) return;
      if (!quiet) _message('Configurações do Fish Audio salvas com segurança.');
      return true;
    } catch (error) {
      if (mounted) _message('Falha ao salvar: $error');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    if (_apiKey.text.trim().isEmpty) {
      _message('Insira sua API Key antes de testar.');
      return;
    }
    setState(() => _testing = true);
    try {
      final saved = await _save(quiet: true);
      if (!saved) return;
      await _service.testAndPlay();
      if (mounted) _message('Fish Audio respondeu e o áudio foi reproduzido.');
    } catch (error) {
      if (mounted) _message('Teste do Fish Audio falhou: $error');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value, style: const TextStyle(fontSize: 11))),
    );
  }

  InputDecoration _decoration(String label, {String? hint, Widget? suffix}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffix,
        filled: true,
        fillColor: _surface,
        isDense: true,
        labelStyle: const TextStyle(color: Color(0xFFA89698), fontSize: 11),
        hintStyle: const TextStyle(color: Color(0xFF806D70), fontSize: 10),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _crimson),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF0A0002),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0A0002),
          foregroundColor: _crimson,
          title: const Text(
            'FISH AUDIO • VOZ NEURAL',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: _crimson))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _crimson.withValues(alpha: 0.5)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SÍNTESE DE VOZ EM NUVEM',
                          style: TextStyle(
                            color: _rose,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 7),
                        Text(
                          'Quando ativado, o U.L.T.R.O.N. envia o texto da resposta ao Fish Audio e reproduz o MP3 recebido. Se a API falhar, o TTS local do Android assume automaticamente.',
                          style: TextStyle(
                            color: Color(0xFFF0E6E7),
                            fontSize: 11,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Usar Fish Audio nas respostas',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    subtitle: const Text(
                      'Desligado por padrão até você salvar e testar sua chave.',
                      style: TextStyle(color: Color(0xFFA89698), fontSize: 10),
                    ),
                    value: _enabled,
                    activeThumbColor: _crimson,
                    onChanged: (value) => setState(() => _enabled = value),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _apiKey,
                    obscureText: !_showKey,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: _decoration(
                      'API Key do Fish Audio',
                      hint: 'Cole sua chave privada',
                      suffix: IconButton(
                        tooltip: _showKey ? 'Ocultar chave' : 'Mostrar chave',
                        onPressed: () => setState(() => _showKey = !_showKey),
                        icon: Icon(
                          _showKey ? Icons.visibility_off : Icons.visibility,
                          color: _rose,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _model,
                    dropdownColor: _surface,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: _decoration('Modelo de síntese'),
                    items: const [
                      DropdownMenuItem(
                        value: 's2.1-pro-free',
                        child: Text('S2.1 Pro Free • desenvolvedor'),
                      ),
                      DropdownMenuItem(
                        value: 's2.1-pro',
                        child: Text('S2.1 Pro • produção'),
                      ),
                      DropdownMenuItem(
                        value: 's2-pro',
                        child: Text('S2 Pro'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _model = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _referenceId,
                    autocorrect: false,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: _decoration(
                      'ID da voz (opcional)',
                      hint: 'reference_id da voz escolhida no Fish Audio',
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'Deixe o ID da voz vazio para usar a voz padrão do modelo. O ID é o reference_id da biblioteca Fish Audio ou de uma voz sua.',
                    style: TextStyle(
                      color: Color(0xFFA89698),
                      fontSize: 10,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _crimson,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: _saving ? null : () => _save(),
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined, size: 17),
                    label: const Text('SALVAR CONFIGURAÇÕES'),
                  ),
                  const SizedBox(height: 9),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _rose,
                      side: const BorderSide(color: _border),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: _testing || _saving ? null : _test,
                    icon: _testing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _rose,
                            ),
                          )
                        : const Icon(Icons.play_circle_outline, size: 18),
                    label: const Text('TESTAR API E OUVIR A VOZ'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Clipboard.setData(
                      const ClipboardData(text: 'https://fish.audio/'),
                    ),
                    child: const Text(
                      'Copiar endereço do Fish Audio para criar/selecionar uma voz',
                      style: TextStyle(color: _rose, fontSize: 10),
                    ),
                  ),
                ],
              ),
      );
}
