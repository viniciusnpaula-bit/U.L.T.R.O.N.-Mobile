import 'package:flutter/material.dart';

import '../../services/user_preferences_service.dart';
import '../../services/voice_corrections_service.dart';
import '../../services/voice_service.dart';
import '../../services/voice_shortcuts_service.dart';
import '../widgets/voice_selector_sheet.dart';

class MemorySettingsScreen extends StatefulWidget {
  const MemorySettingsScreen({
    super.key,
    this.correctionsService,
    this.shortcutsService,
    this.preferencesService,
    this.voiceService,
  });

  final VoiceCorrectionsService? correctionsService;
  final VoiceShortcutsService? shortcutsService;
  final UserPreferencesService? preferencesService;
  final VoiceService? voiceService;

  @override
  State<MemorySettingsScreen> createState() => _MemorySettingsScreenState();
}

class _MemorySettingsScreenState extends State<MemorySettingsScreen> {
  late final VoiceCorrectionsService _corrections;
  late final VoiceShortcutsService _shortcuts;
  late final UserPreferencesService _preferences;
  late final VoiceService _voiceService;

  List<VoiceCorrection> _correctionRows = const [];
  List<VoiceShortcut> _shortcutRows = const [];
  List<UserPreference> _preferenceRows = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _corrections = widget.correctionsService ?? VoiceCorrectionsService();
    _shortcuts = widget.shortcutsService ?? VoiceShortcutsService();
    _preferences = widget.preferencesService ?? UserPreferencesService();
    _voiceService = widget.voiceService ?? VoiceService();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final corrections = await _corrections.list();
      final shortcuts = await _shortcuts.list();
      final preferences = await _preferences.list();
      if (!mounted) return;
      setState(() {
        _correctionRows = corrections;
        _shortcutRows = shortcuts;
        _preferenceRows = preferences;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Erro ao carregar memória local: $e';
      });
    }
  }

  Future<void> _addCorrectionDialog() async {
    final wrongCtrl = TextEditingController();
    final correctCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF160509),
        title: const Text('Nova correção de voz'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: wrongCtrl,
              decoration:
                  const InputDecoration(labelText: 'Transcrição errada'),
            ),
            TextField(
              controller: correctCtrl,
              decoration: const InputDecoration(labelText: 'Texto correto'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    final wrong = wrongCtrl.text.trim();
    final correct = correctCtrl.text.trim();
    wrongCtrl.dispose();
    correctCtrl.dispose();
    if (confirmed != true || wrong.isEmpty || correct.isEmpty) return;
    try {
      await _corrections.add(wrong, correct);
      await _reload();
    } on ArgumentError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${e.message ?? e}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0002),
      appBar: AppBar(
        title: const Text('Memória & Voz'),
        actions: [
          IconButton(
            tooltip: 'Adicionar correção',
            onPressed: _addCorrectionDialog,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const _SectionHeader(title: 'Voz do U.L.T.R.O.N. (TTS)'),
                    Card(
                      child: ListTile(
                        leading: const Icon(
                          Icons.record_voice_over,
                          color: Color(0xFFE50914),
                        ),
                        title: Text(
                          'Voz: ${_voiceService.activeVoiceName ?? "Padrão do aparelho"}',
                        ),
                        subtitle:
                            Text('Timbre: ${_voiceService.profile.label}'),
                        trailing: FilledButton(
                          onPressed: () async {
                            await showVoiceSelectorSheet(
                              context,
                              voiceService: _voiceService,
                              onChanged: () {
                                if (mounted) setState(() {});
                              },
                            );
                          },
                          child: const Text('Trocar'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionHeader(
                      title: 'Correções de Voz (${_correctionRows.length})',
                    ),
                    if (_correctionRows.isEmpty)
                      const _EmptyHint('Nenhuma correção cadastrada.')
                    else
                      for (final item in _correctionRows)
                        Card(
                          child: ListTile(
                            title: Text(
                                '${item.wrongPhrase} → ${item.correctPhrase}'),
                            trailing: IconButton(
                              tooltip: 'Remover correção',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: item.id == null
                                  ? null
                                  : () async {
                                      await _corrections.remove(item.id!);
                                      await _reload();
                                    },
                            ),
                          ),
                        ),
                    const SizedBox(height: 16),
                    _SectionHeader(
                      title: 'Atalhos por Voz (${_shortcutRows.length})',
                    ),
                    if (_shortcutRows.isEmpty)
                      const _EmptyHint('Nenhum atalho cadastrado.')
                    else
                      for (final item in _shortcutRows)
                        Card(
                          child: ListTile(
                            title: Text(item.triggerPhrase),
                            subtitle: Text(
                              '${item.actionType}'
                              '${item.requiresConfirmation ? ' • exige confirmação' : ''}',
                            ),
                            trailing: IconButton(
                              tooltip: 'Remover atalho',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: item.id == null
                                  ? null
                                  : () async {
                                      await _shortcuts.remove(item.id!);
                                      await _reload();
                                    },
                            ),
                          ),
                        ),
                    const SizedBox(height: 16),
                    _SectionHeader(
                      title: 'Preferências Salvas (${_preferenceRows.length})',
                    ),
                    if (_preferenceRows.isEmpty)
                      const _EmptyHint('Nenhuma preferência salva.')
                    else
                      for (final item in _preferenceRows)
                        Card(
                          child: ListTile(
                            title: Text(item.key),
                            subtitle: Text(item.value),
                            trailing: IconButton(
                              tooltip: 'Remover preferência',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                await _preferences.remove(item.key);
                                await _reload();
                              },
                            ),
                          ),
                        ),
                  ],
                ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFFFFA0A0),
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        message,
        style: const TextStyle(color: Color(0xFF9E6A70)),
      ),
    );
  }
}
