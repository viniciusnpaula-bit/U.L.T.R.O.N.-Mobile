import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/android_actions_service.dart';
import '../../services/desktop_pairing_service.dart';
import '../../services/device_control_service.dart';
import '../theme/ultron_theme.dart';
import '../widgets/action_confirmation_dialog.dart';

class DesktopPairingScreen extends StatefulWidget {
  const DesktopPairingScreen({
    super.key,
    this.pairingService,
    this.actionsService,
    this.deviceService,
    this.onPairingChanged,
  });

  final DesktopPairingService? pairingService;
  final AndroidActionsService? actionsService;
  final DeviceControlService? deviceService;
  final VoidCallback? onPairingChanged;

  @override
  State<DesktopPairingScreen> createState() => _DesktopPairingScreenState();
}

class _DesktopPairingScreenState extends State<DesktopPairingScreen> {
  late final DesktopPairingService _pairing;
  late final DeviceControlService _deviceService;
  final _urlCtrl = TextEditingController(text: 'http://192.168.1.50:8765');
  final _deviceCtrl = TextEditingController(text: 'galaxy-a34');
  final _secretCtrl = TextEditingController();
  final _cmdCtrl = TextEditingController(text: 'ping');

  bool _allowNonPrivate = false;
  bool _notificationsOptIn = false;
  bool _systemNotificationAccess = false;
  bool _isPaired = false;
  bool _busy = false;
  String _pairedSummary = '';
  String _status = 'Escaneie o QR Code no U.L.T.R.O.N. Desktop para parear.';

  @override
  void initState() {
    super.initState();
    _pairing = widget.pairingService ?? DesktopPairingService();
    _deviceService = widget.deviceService ?? DeviceControlService();
    _load();
  }

  Future<void> _load() async {
    final existing = await _pairing.loadPairing();
    final actions = widget.actionsService;
    final optIn = actions != null
        ? await actions.isNotificationListenerEnabled()
        : false;
    final sysAccess = actions != null
        ? await actions
            .isSystemNotificationAccessGranted()
            .catchError((_) => false)
        : false;
    if (!mounted) return;
    setState(() {
      if (existing != null) {
        _isPaired = true;
        _pairedSummary = '${existing.deviceId} • ${existing.baseUrl}';
        _urlCtrl.text = existing.baseUrl;
        _deviceCtrl.text = existing.deviceId;
        _allowNonPrivate = existing.allowNonPrivateHost;
        _status = 'Desktop pareado e pronto para comandos na rede local.';
      } else {
        _isPaired = false;
        _pairedSummary = '';
      }
      _notificationsOptIn = optIn;
      _systemNotificationAccess = sysAccess;
    });
  }

  Future<void> _applyPairingUri(String rawUri) async {
    try {
      final config = await _pairing.pairFromUri(
        rawUri,
        allowNonPrivateHost: _allowNonPrivate,
        onConfigureKillSwitch: (baseUrl, secret, {bool allowNonPrivateHost = false}) async {
          await _deviceService.savePcKillSwitchUrl(
            baseUrl,
            allowNonPrivateHost: allowNonPrivateHost,
          );
          await _deviceService.savePcLanSecret(secret);
        },
      );
      _secretCtrl.clear();
      widget.onPairingChanged?.call();
      if (!mounted) return;
      setState(() {
        _isPaired = true;
        _pairedSummary = '${config.deviceId} • ${config.baseUrl}';
        _urlCtrl.text = config.baseUrl;
        _deviceCtrl.text = config.deviceId;
        _allowNonPrivate = config.allowNonPrivateHost;
        _status = '✅ Pareado com ${config.baseUrl} (${config.deviceId})! '
            'Kill Switch LAN também sincronizado.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = '⚠️ Falha ao parear via link/QR: $e');
    }
  }

  Future<void> _scanQrCode() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'Abrindo câmera para ler o QR Code do Desktop...';
    });
    try {
      final scanned = await _deviceService.scanPairingQr();
      if (!mounted) return;
      if (scanned == null || scanned.trim().isEmpty) {
        setState(() => _status = 'Leitura de QR Code cancelada.');
        return;
      }
      await _applyPairingUri(scanned);
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _status = '⚠️ ${e.message ?? e.code}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = '⚠️ Erro ao ler QR Code: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pastePairingLink() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final clip = await Clipboard.getData('text/plain');
      final text = clip?.text?.trim() ?? '';
      if (!mounted) return;
      if (text.isEmpty) {
        setState(() => _status = 'Área de transferência vazia.');
        return;
      }
      await _applyPairingUri(text);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _disconnect() async {
    await _pairing.clearPairing();
    _secretCtrl.clear();
    widget.onPairingChanged?.call();
    if (!mounted) return;
    setState(() {
      _isPaired = false;
      _pairedSummary = '';
      _status = 'Pareamento Desktop removido.';
    });
  }

  Future<void> _savePairing() async {
    try {
      final existing = await _pairing.loadPairing();
      final secret = _secretCtrl.text.trim().isNotEmpty
          ? _secretCtrl.text.trim()
          : (existing?.sharedSecret ?? '');
      final config = DesktopPairingConfig(
        baseUrl: _urlCtrl.text.trim(),
        deviceId: _deviceCtrl.text.trim(),
        sharedSecret: secret,
        allowNonPrivateHost: _allowNonPrivate,
      );
      await _pairing.savePairing(config);
      _secretCtrl.clear();
      widget.onPairingChanged?.call();
      if (!mounted) return;
      setState(() {
        _isPaired = true;
        _pairedSummary = '${config.deviceId} • ${config.baseUrl}';
        _status = 'Pareamento Desktop salvo com segurança.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Erro ao salvar pareamento: $e');
    }
  }

  Future<void> _sendTestCommand([String? overrideCommand]) async {
    final raw = (overrideCommand ?? _cmdCtrl.text).trim();
    if (raw.isEmpty) return;
    final parsed = DesktopPairingService.parsePcCommandInput(raw);
    if (parsed == null) {
      setState(() {
        _status =
            'Comando não reconhecido. Use: ping, abrir <app>, midia <acao>, copiar <texto>, colar, skill <nome>, termico, energia, volume_app, travados, backup, limpar_disco, ejetar_usb ou tool <nome>.';
      });
      return;
    }
    final command = parsed.command;
    final args = parsed.args;
    final result = await _pairing.sendCommand(
      command: command,
      args: args,
      confirm: (req) => showActionConfirmationDialog(context, req),
    );
    if (!mounted) return;
    setState(() {
      if (result.deniedByUser) {
        _status = 'Envio cancelado pelo usuário.';
      } else if (result.sent) {
        final sigNote =
            result.verifiedSignature ? ' • HMAC verificado' : '';
        final bodyNote = (result.responseBody ?? '').trim().isNotEmpty
            ? '\n${result.responseBody}'
            : '';
        _status =
            '✅ Comando "$command" OK (HTTP ${result.statusCode}$sigNote).$bodyNote';
      } else {
        _status = 'Falha no envio ($command): ${result.error}';
      }
    });
  }

  Future<void> _toggleNotifications(bool value) async {
    final actions = widget.actionsService;
    if (actions == null) return;
    final enabled = await actions.setNotificationListenerOptIn(
      value,
      confirm: (req) => showActionConfirmationDialog(context, req),
    );
    if (!mounted) return;
    setState(() => _notificationsOptIn = enabled);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _deviceCtrl.dispose();
    _secretCtrl.dispose();
    _cmdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = UltronTheme.accentOf(context);
    final onAccent = UltronTheme.onAccentFor(accent);
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      appBar: AppBar(title: const Text('Parear com U.L.T.R.O.N. Desktop')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF111114),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isPaired
                    ? accent.withValues(alpha: 0.7)
                    : Colors.white24,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _isPaired ? Icons.link : Icons.link_off,
                      color: _isPaired
                          ? const Color(0xFF22C55E)
                          : const Color(0xFF9A9AA3),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isPaired
                            ? 'Conectado ao Desktop'
                            : 'Nenhum Desktop pareado',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_pairedSummary.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    _pairedSummary,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  _status,
                  style: const TextStyle(color: Color(0xFF9A9AA3), fontSize: 13),
                ),
                if (_isPaired) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : () => _sendTestCommand('ping'),
                          icon: const Icon(Icons.wifi_tethering, size: 18),
                          label: const Text('Testar conexão'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _busy ? null : _disconnect,
                        icon: const Icon(Icons.link_off, size: 18),
                        label: const Text('Desconectar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final quick in const <(String, String)>[
                        ('🌡️ Térmico', 'termico'),
                        ('⚡ Energia Alta', 'energia high_performance'),
                        ('🔊 Volumes Apps', 'volume_app listar'),
                        ('🧊 Fechar Travados', 'travados'),
                        ('💾 Backup', 'backup'),
                        ('🧹 Limpar Disco', 'limpar_disco'),
                        ('⏏️ Ejetar USB', 'ejetar_usb'),
                      ])
                        ActionChip(
                          label: Text(
                            quick.$1,
                            style: const TextStyle(fontSize: 11),
                          ),
                          onPressed: _busy
                              ? null
                              : () => _sendTestCommand(quick.$2),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No computador, abra o U.L.T.R.O.N. Desktop, clique em "parear celular" na barra superior e aponte a câmera:',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _scanQrCode,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: onAccent,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('ESCANEAR QR CODE DO DESKTOP'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pastePairingLink,
            icon: const Icon(Icons.content_paste_go),
            label: const Text('Colar link de pareamento (ultron://pair)'),
          ),
          if (widget.actionsService != null) ...[
            const Divider(height: 28),
            SwitchListTile(
              value: _notificationsOptIn,
              onChanged: _toggleNotifications,
              title: const Text('Leitura de notificações (opt-in)'),
              subtitle: Text(
                _systemNotificationAccess
                    ? 'Permissão Android concedida'
                    : 'Permissão Android pendente',
              ),
            ),
            TextButton(
              onPressed: () =>
                  widget.actionsService!.openSystemNotificationSettings(),
              child: const Text('Abrir configurações de acesso a notificações'),
            ),
          ],
          const Divider(height: 28),
          ExpansionTile(
            title: const Text('Configuração manual (avançado)'),
            tilePadding: EdgeInsets.zero,
            children: [
              TextField(
                controller: _urlCtrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'URL LAN do Desktop',
                  hintText: 'http://192.168.1.50:8765',
                ),
              ),
              TextField(
                controller: _deviceCtrl,
                decoration: const InputDecoration(labelText: 'ID deste aparelho'),
              ),
              TextField(
                controller: _secretCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Segredo HMAC compartilhado',
                ),
              ),
              SwitchListTile(
                value: _allowNonPrivate,
                onChanged: (v) => setState(() => _allowNonPrivate = v),
                title: const Text('Permitir host fora da rede privada'),
              ),
              FilledButton(
                onPressed: _savePairing,
                child: const Text('Salvar pareamento'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cmdCtrl,
                decoration: const InputDecoration(labelText: 'Comando remoto'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _sendTestCommand(),
                child: const Text('Enviar comando com confirmação'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
