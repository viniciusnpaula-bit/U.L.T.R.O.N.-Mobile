import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/ai_provider_service.dart';
import '../../services/app_update_service.dart';
import 'update_screen.dart';

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  static const _crimson = Color(0xFFFF1A24);
  static const _rose = Color(0xFFFF8088);
  static const _border = Color(0xFF2E0306);
  static const _card = Color(0xFF0E0002);
  static const _inputBg = Color(0xFF160004);

  final store = AiProviderStore();
  final updateService = AppUpdateService();
  final name = TextEditingController(text: 'Groq (Native Llama)');
  final url = TextEditingController(text: 'https://api.groq.com/openai/v1');
  final model = TextEditingController(text: 'llama-3.3-70b-versatile');
  final key = TextEditingController();

  List<AiProviderConfig> providers = [];
  bool busy = false;
  bool showKey = false;
  String providerPreset = 'Groq';
  String status = 'Chaves ficam no armazenamento seguro do Android.';
  String installedVersion = '…';
  UpdateInfo? latestUpdate;
  bool checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadVersion();
  }

  @override
  void dispose() {
    name.dispose();
    url.dispose();
    model.dispose();
    key.dispose();
    super.dispose();
  }

  void _selectPreset(String value) {
    setState(() => providerPreset = value);
    if (value == 'Groq') {
      name.text = 'Groq (Native Llama)';
      url.text = 'https://api.groq.com/openai/v1';
      model.text = 'llama-3.3-70b-versatile';
    } else {
      name.text = 'OpenAI-Compatible';
      url.text = 'https://api.openai.com/v1';
      model.text = 'gpt-4o-mini';
    }
  }

  Future<void> _load() async {
    providers = await store.load();
    if (mounted) setState(() {});
  }

  Future<void> _loadVersion() async {
    try {
      final v = await updateService.currentVersion();
      if (mounted) setState(() => installedVersion = 'v$v');
    } catch (_) {}
  }

  Future<void> _checkGitHubRelease() async {
    HapticFeedback.lightImpact();
    setState(() => checkingUpdate = true);
    try {
      final current = await updateService.currentVersion();
      final latest = await updateService.check();
      if (!mounted) return;
      setState(() {
        installedVersion = 'v$current';
        if (latest != null && AppUpdateService.isNewer(latest.version, current)) {
          latestUpdate = latest;
          status = 'Nova release encontrada: ${latest.version}';
        } else {
          latestUpdate = null;
          status = 'Versão atual ($installedVersion) já é a mais recente.';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => status = 'Falha ao consultar GitHub Releases: $e');
      }
    } finally {
      if (mounted) setState(() => checkingUpdate = false);
    }
  }

  Future<void> _save() async {
    if (name.text.trim().isEmpty ||
        url.text.trim().isEmpty ||
        model.text.trim().isEmpty ||
        key.text.trim().isEmpty) {
      setState(() => status = 'Preencha nome, URL, modelo e chave.');
      return;
    }
    final base = url.text.trim();
    final parsed = Uri.tryParse(base);
    if (parsed == null || parsed.scheme != 'https' || parsed.host.isEmpty) {
      setState(() => status = 'Use uma URL https válida.');
      return;
    }
    if (providerPreset == 'Groq' &&
        !base.startsWith('https://api.groq.com/')) {
      setState(
        () => status =
            'Para uma chave Groq, selecione Groq e use o endpoint da Groq.',
      );
      return;
    }
    if (providerPreset == 'OpenAI' &&
        !base.startsWith('https://api.openai.com/')) {
      setState(
        () => status =
            'Para uma chave OpenAI, selecione OpenAI e use o endpoint da OpenAI.',
      );
      return;
    }
    final p = AiProviderConfig(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.text.trim(),
      baseUrl: base,
      model: model.text.trim(),
      apiKey: key.text.trim(),
      priority: providers.length,
    );
    providers = [...providers, p];
    await store.save(providers);
    key.clear();
    HapticFeedback.mediumImpact();
    setState(() => status = 'Provedor salvo com segurança no Keystore.');
  }

  Future<void> _test(AiProviderConfig p) async {
    setState(() {
      busy = true;
      status = 'Testando conexão com ${p.name}…';
    });
    try {
      final answer = await AiFailover(store: store).test(p);
      setState(() => status = 'Conexão OK (${p.name}): $answer');
    } catch (e) {
      setState(() => status = 'Falha (${p.name}): $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _delete(AiProviderConfig p) async {
    providers.removeWhere((x) => x.id == p.id);
    await store.save(providers);
    setState(() => status = 'Provedor ${p.name} removido.');
  }

  Future<void> _toggle(AiProviderConfig p) async {
    HapticFeedback.selectionClick();
    providers = providers
        .map(
          (x) => x.id == p.id
              ? AiProviderConfig(
                  id: x.id,
                  name: x.name,
                  baseUrl: x.baseUrl,
                  model: x.model,
                  apiKey: x.apiKey,
                  enabled: !x.enabled,
                  priority: x.priority,
                )
              : x,
        )
        .toList();
    await store.save(providers);
    setState(() {});
  }

  InputDecoration _hudInput(String label, {String? hint, Widget? suffixIcon}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
        hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 11),
        filled: true,
        fillColor: _inputBg,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _crimson),
        ),
        suffixIcon: suffixIcon,
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF0A0002),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.only(bottom: 10),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: _border)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        child: const Row(
                          children: [
                            Icon(Icons.arrow_back, size: 15, color: _crimson),
                            SizedBox(width: 4),
                            Text(
                              'VOLTAR',
                              style: TextStyle(
                                color: _crimson,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Row(
                        children: [
                          Icon(Icons.settings, size: 14, color: Colors.white),
                          SizedBox(width: 6),
                          Text(
                            'CENTRAL DE CONFIGURAÇÕES',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    children: [
                      // Section 1 Header: AI Providers (Failover)
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.memory, size: 14, color: _rose),
                              SizedBox(width: 6),
                              Text(
                                'PROVEDORES DE IA (FAILOVER)',
                                style: TextStyle(
                                  color: _rose,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'ORDEM POR PRIORIDADE',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Status Banner
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF180004),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _crimson.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          status,
                          style: const TextStyle(
                            color: _rose,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Configured Providers List
                      if (providers.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _border),
                          ),
                          child: const Text(
                            'Nenhum provedor cadastrado ainda. Adicione sua chave Groq ou OpenAI abaixo.',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      for (final p in providers)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '#${p.priority + 1} ${p.name}',
                                      style: const TextStyle(
                                        color: Color(0xFFE2E8F0),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () => _toggle(p),
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: p.enabled
                                            ? const Color(0x3310B981)
                                            : const Color(0xFF200004),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: p.enabled
                                              ? const Color(0x6610B981)
                                              : _border,
                                        ),
                                      ),
                                      child: Text(
                                        p.enabled ? 'ATIVO' : 'INATIVO',
                                        style: TextStyle(
                                          color: p.enabled
                                              ? const Color(0xFF34D399)
                                              : const Color(0xFF64748B),
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'MODELO: ${p.model}\nENDPOINT: ${p.baseUrl}',
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 10,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    onPressed: busy ? null : () => _test(p),
                                    icon: const Icon(
                                      Icons.wifi_tethering,
                                      size: 14,
                                      color: _crimson,
                                    ),
                                    label: const Text(
                                      'TESTAR',
                                      style: TextStyle(
                                        color: _crimson,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _delete(p),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 14,
                                      color: Color(0xFFFB7185),
                                    ),
                                    label: const Text(
                                      'REMOVER',
                                      style: TextStyle(
                                        color: Color(0xFFFB7185),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                      // Add Provider Card
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ADICIONAR PROVEDOR (CHAT COMPLETIONS)',
                              style: TextStyle(
                                color: _rose,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              initialValue: providerPreset,
                              dropdownColor: const Color(0xFF160004),
                              style: const TextStyle(
                                color: Color(0xFFE2E8F0),
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
                              decoration: _hudInput('Preset do Provedor'),
                              items: const [
                                DropdownMenuItem(
                                  value: 'Groq',
                                  child: Text('Groq (Llama / Fast Inference)'),
                                ),
                                DropdownMenuItem(
                                  value: 'OpenAI',
                                  child: Text('OpenAI-Compatible'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) _selectPreset(v);
                              },
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: name,
                              style: const TextStyle(fontSize: 11),
                              decoration: _hudInput('Nome do provedor'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: url,
                              keyboardType: TextInputType.url,
                              style: const TextStyle(fontSize: 11),
                              decoration: _hudInput(
                                'URL base',
                                hint: 'https://api.groq.com/openai/v1',
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: model,
                              style: const TextStyle(fontSize: 11),
                              decoration: _hudInput('Modelo'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: key,
                              obscureText: !showKey,
                              style: const TextStyle(fontSize: 11),
                              decoration: _hudInput(
                                'API Key',
                                hint: 'Cole sua chave...',
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    showKey
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    size: 16,
                                    color: const Color(0xFF94A3B8),
                                  ),
                                  onPressed: () =>
                                      setState(() => showKey = !showKey),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _save,
                                style: FilledButton.styleFrom(
                                  backgroundColor: _crimson,
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: const Icon(Icons.add, size: 15),
                                label: const Text(
                                  'SALVAR PROVEDOR NO COFRE',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Section 2: GitHub Releases Updater
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Row(
                                  children: [
                                    Icon(
                                      Icons.cloud_download_outlined,
                                      size: 14,
                                      color: _rose,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'ATUALIZADOR GITHUB',
                                      style: TextStyle(
                                        color: _rose,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  'VERSÃO ATUAL: $installedVersion',
                                  style: const TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Repositório: viniciusnpaula-bit/U.L.T.R.O.N.-Mobile',
                              style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (latestUpdate != null)
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF180004),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _crimson.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '✓ Nova Versão Encontrada: ${latestUpdate!.version}',
                                      style: const TextStyle(
                                        color: Color(0xFF34D399),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      latestUpdate!.name,
                                      style: const TextStyle(
                                        color: Color(0xFFCBD5E1),
                                        fontSize: 10,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton(
                                        onPressed: () =>
                                            Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const UpdateScreen(),
                                          ),
                                        ),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: _crimson,
                                          foregroundColor: Colors.black,
                                        ),
                                        child: const Text(
                                          'ABRIR INSTALADOR DE RELEASE',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: checkingUpdate
                                          ? null
                                          : _checkGitHubRelease,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: _crimson,
                                        backgroundColor:
                                            const Color(0xFF1E0004),
                                        side: BorderSide(
                                          color:
                                              _crimson.withValues(alpha: 0.35),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                      icon: const Icon(Icons.refresh, size: 13),
                                      label: Text(
                                        checkingUpdate
                                            ? 'CONSULTANDO GITHUB API...'
                                            : 'VERIFICAR RELEASES NO GITHUB',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Section 3: Android Preferences (A34 5G)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _border),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PREFERÊNCIAS ANDROID (A34 5G)',
                              style: TextStyle(
                                color: _rose,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Síntese de Voz Robótica (TTS):',
                                  style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 10,
                                  ),
                                ),
                                Text(
                                  'Pitch 0.55 Ativo',
                                  style: TextStyle(
                                    color: Color(0xFF34D399),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Vault Obsidian Vinculado:',
                                  style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 10,
                                  ),
                                ),
                                Text(
                                  'Documents/ULTRON-Vault',
                                  style: TextStyle(
                                    color: Color(0xFFCBD5E1),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A0003),
                      foregroundColor: const Color(0xFFCBD5E1),
                      side: const BorderSide(color: _border),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'SALVAR E VOLTAR AO NÚCLEO',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
