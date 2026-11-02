import 'package:flutter/material.dart';

import '../../services/ai_service.dart';

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key, required this.service});

  final AiService service;

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final name = TextEditingController(text: 'OpenAI Compatible');
  final url = TextEditingController(text: 'https://api.openai.com/v1');
  final model = TextEditingController(text: 'gpt-4o-mini');
  final key = TextEditingController();
  bool enabled = true;
  bool busy = false;
  String status = '';

  Future<void> save() async {
    if (name.text.trim().isEmpty ||
        url.text.trim().isEmpty ||
        model.text.trim().isEmpty) {
      setState(() => status = 'Preencha nome, URL e modelo.');
      return;
    }
    setState(() => busy = true);
    try {
      await widget.service.saveProvider(
        AiProvider(
          name: name.text.trim(),
          baseUrl: url.text.trim(),
          model: model.text.trim(),
          enabled: enabled,
        ),
        key.text.trim(),
      );
      if (mounted) {
        setState(
          () => status =
              'Provedor salvo localmente. API Key armazenada com segurança.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => status = 'Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> test() async {
    setState(() {
      busy = true;
      status = 'Testando conexão real…';
    });
    try {
      final providers = await widget.service.providers();
      final existing =
          providers.where((p) => p.name == name.text.trim()).firstOrNull;
      final provider = AiProvider(
        name: name.text.trim(),
        baseUrl: url.text.trim(),
        model: model.text.trim(),
        enabled: enabled,
      );
      if (key.text.trim().isNotEmpty || existing == null) {
        await widget.service.saveProvider(provider, key.text.trim());
      }
      final result = await widget.service.testProvider(provider);
      if (mounted) setState(() => status = 'Conexão confirmada: $result');
    } catch (e) {
      if (mounted) setState(() => status = 'Falha real de conexão: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    name.dispose();
    url.dispose();
    model.dispose();
    key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const crimson = Color(0xFFE50914);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0002),
      appBar: AppBar(
        title: const Text('CONFIGURAÇÃO DE IA'),
        backgroundColor: const Color(0xFF2E0305),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _field(name, 'Nome do provedor'),
          _field(url, 'URL base (OpenAI Chat Completions)'),
          _field(model, 'Modelo'),
          _field(key, 'API Key (fica no Secure Storage)', secret: true),
          SwitchListTile(
            value: enabled,
            activeThumbColor: crimson,
            title: const Text('Provedor habilitado'),
            onChanged: (v) => setState(() => enabled = v),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy ? null : save,
            child: const Text('Salvar provedor'),
          ),
          OutlinedButton(
            onPressed: busy ? null : test,
            child: const Text('Testar conexão real'),
          ),
          if (busy)
            const Center(child: CircularProgressIndicator(color: crimson)),
          SelectableText(
            status,
            style: const TextStyle(color: Color(0xFFFFA0A0)),
          ),
          const SizedBox(height: 20),
          const Text(
            'Adaptador implementado para APIs compatíveis com OpenAI Chat Completions. Outros formatos exigem adaptador específico.',
            style: TextStyle(color: Colors.white60),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool secret = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          obscureText: secret,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFE50914)),
            ),
          ),
        ),
      );
}
