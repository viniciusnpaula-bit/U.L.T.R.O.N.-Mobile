import 'package:flutter/material.dart';

import '../../services/android_actions_service.dart';
import '../../services/desktop_pairing_service.dart';
import '../widgets/action_confirmation_dialog.dart';

class DesktopPairingScreen extends StatefulWidget {
  const DesktopPairingScreen({
    super.key,
    this.pairingService,
    this.actionsService,
  });

  final DesktopPairingService? pairingService;
  final AndroidActionsService? actionsService;

  @override
  State<DesktopPairingScreen> createState() => _DesktopPairingScreenState();
}

class _DesktopPairingScreenState extends State<DesktopPairingScreen> {
  late final DesktopPairingService _pairing;
  final _urlCtrl = TextEditingController(text: 'http://192.168.1.50:8765');
  final _deviceCtrl = TextEditingController(text: 'galaxy-a34');
  final _secretCtrl = TextEditingController();
  final _cmdCtrl = TextEditingController(text: 'ping');

  bool _allowNonPrivate = false;
  bool _notificationsOptIn = false;
  bool _systemNotificationAccess = false;
  String _status = 'Pareamento usa HMAC-SHA256 + timestamp + nonce na LAN.';

  @override
  void initState() {
    super.initState();
    _pairing = widget.pairingService ?? DesktopPairingService();
    _load();
  }

  Future<void> _load() async {
    final existing = await _pairing.loadPairing();
    final actions = widget.actionsService;
    final optIn = actions != null
        ? await actions.isNotificationListenerEnabled()
        : false;
    final sysAccess = actions != null
        ? await actions.isSystemNotificationAccessGranted().catchError((_) => false)
        : false;
    if (!mounted) return;
    setState(() {
      if (existing != null) {
        _urlCtrl.text = existing.baseUrl;
        _deviceCtrl.text = existing.deviceId;
        _allowNonPrivate = existing.allowNonPrivateHost;
      }
      _notificationsOptIn = optIn;
      _systemNotificationAccess = sysAccess;
    });
  }

  Future<void> _savePairing() async {
    try {
      final existing = await _pairing.loadPairing();
      final secret = _secretCtrl.text.trim().isNotEmpty
          ? _secretCtrl.text.trim()
          : (existing?.sharedSecret ?? '');
      await _pairing.savePairing(
        DesktopPairingConfig(
          baseUrl: _urlCtrl.text.trim(),
          deviceId: _deviceCtrl.text.trim(),
          sharedSecret: secret,
          allowNonPrivateHost: _allowNonPrivate,
        ),
      );
      _secretCtrl.clear();
      if (!mounted) return;
      setState(() => _status = 'Pareamento Desktop salvo com segurança.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Erro ao salvar pareamento: $e');
    }
  }

  Future<void> _sendTestCommand() async {
    final command = _cmdCtrl.text.trim();
    if (command.isEmpty) return;
    final result = await _pairing.sendCommand(
      command: command,
      confirm: (req) => showActionConfirmationDialog(context, req),
    );
    if (!mounted) return;
    setState(() {
      if (result.deniedByUser) {
        _status = 'Envio cancelado pelo usuário.';
      } else if (result.sent) {
        _status = 'Comando enviado (HTTP ${result.statusCode}).';
      } else {
        _status = 'Falha no envio: ${result.error}';
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
    return Scaffold(
      backgroundColor: const Color(0xFF0A0002),
      appBar: AppBar(title: const Text('Desktop LAN & Ações Android')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Pareamento com U.L.T.R.O.N. Desktop (LAN)'),
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
          const Divider(height: 28),
          TextField(
            controller: _cmdCtrl,
            decoration: const InputDecoration(labelText: 'Comando remoto'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _sendTestCommand,
            child: const Text('Enviar comando com confirmação'),
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
          const SizedBox(height: 12),
          Text(_status, style: const TextStyle(color: Color(0xFFFFA0A0))),
        ],
      ),
    );
  }
}
