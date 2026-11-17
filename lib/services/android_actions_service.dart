import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/security/auth_gate.dart';
import '../ui/widgets/action_confirmation_dialog.dart';

enum TileLaunchAction { none, quickCommand, listenVoice }

class AndroidNotificationSummary {
  const AndroidNotificationSummary({
    required this.packageName,
    required this.title,
    required this.text,
    required this.postedAtMs,
  });

  final String packageName;
  final String title;
  final String text;
  final int postedAtMs;

  factory AndroidNotificationSummary.fromMap(Map<Object?, Object?> map) =>
      AndroidNotificationSummary(
        packageName: (map['packageName'] as String? ?? '').trim(),
        title: (map['title'] as String? ?? '').trim(),
        text: (map['text'] as String? ?? '').trim(),
        postedAtMs: (map['postedAtMs'] as num?)?.toInt() ?? 0,
      );
}

abstract interface class AndroidActionsBridge {
  Future<TileLaunchAction> consumePendingTileAction();
  Future<bool> isNotificationAccessGranted();
  Future<void> openNotificationAccessSettings();
  Future<List<AndroidNotificationSummary>> readRecentNotifications();
}

class MethodChannelAndroidActionsBridge implements AndroidActionsBridge {
  MethodChannelAndroidActionsBridge({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel(
              'com.viniciusnpaula.ultron_mobile/android_actions',
            );

  final MethodChannel _channel;

  @override
  Future<TileLaunchAction> consumePendingTileAction() async {
    final raw =
        await _channel.invokeMethod<String>('consumePendingTileAction');
    return switch (raw) {
      'listen_voice' => TileLaunchAction.listenVoice,
      'quick_command' => TileLaunchAction.quickCommand,
      _ => TileLaunchAction.none,
    };
  }

  @override
  Future<bool> isNotificationAccessGranted() async {
    final granted =
        await _channel.invokeMethod<bool>('isNotificationAccessGranted');
    return granted ?? false;
  }

  @override
  Future<void> openNotificationAccessSettings() =>
      _channel.invokeMethod<void>('openNotificationAccessSettings');

  @override
  Future<List<AndroidNotificationSummary>> readRecentNotifications() async {
    final list = await _channel.invokeListMethod<Object?>(
      'readRecentNotifications',
    );
    if (list == null) return const [];
    return list
        .whereType<Map<Object?, Object?>>()
        .map(AndroidNotificationSummary.fromMap)
        .toList();
  }
}

/// Fail-closed gatekeeper for Android Quick Settings Tile launches and
/// opt-in Notification Listener access.
class AndroidActionsService {
  AndroidActionsService({
    required AuthGate gate,
    AndroidActionsBridge? bridge,
    FlutterSecureStorage? storage,
  })  : _gate = gate,
        _bridge = bridge ?? MethodChannelAndroidActionsBridge(),
        _storage = storage ?? const FlutterSecureStorage();

  static const _notificationsOptInKey =
      'ultron.android.notifications_opt_in.v1';

  final AuthGate _gate;
  final AndroidActionsBridge _bridge;
  final FlutterSecureStorage _storage;

  Future<bool> isNotificationListenerEnabled() async {
    final raw = await _storage.read(key: _notificationsOptInKey);
    return raw == 'true';
  }

  /// Toggles opt-in for Notification Listener. Enabling is fail-closed: it
  /// requires an unlocked [AuthGate] and an explicit [confirm] approval.
  Future<bool> setNotificationListenerOptIn(
    bool enabled, {
    required ConfirmationGate confirm,
  }) async {
    if (!enabled) {
      await _storage.write(key: _notificationsOptInKey, value: 'false');
      return false;
    }
    if (!_gate.isAuthenticated) {
      return false;
    }
    final allowed = await confirm(
      const ActionConfirmationRequest(
        title: 'Ativar leitura de notificações',
        description:
            'O U.L.T.R.O.N. poderá consultar notificações recentes apenas quando você estiver autenticado e solicitar leitura.',
        actionLabel: 'Ativar',
        danger: true,
      ),
    );
    if (!allowed || !_gate.isAuthenticated) {
      return false;
    }
    await _storage.write(key: _notificationsOptInKey, value: 'true');
    return true;
  }

  Future<bool> isSystemNotificationAccessGranted() =>
      _bridge.isNotificationAccessGranted();

  Future<void> openSystemNotificationSettings() {
    if (!_gate.isAuthenticated) {
      throw StateError('Sessão bloqueada.');
    }
    return _bridge.openNotificationAccessSettings();
  }

  Future<List<AndroidNotificationSummary>> readRecentNotifications() async {
    if (!_gate.isAuthenticated) {
      throw StateError('Sessão bloqueada: desbloqueie antes de ler notificações.');
    }
    if (!await isNotificationListenerEnabled()) {
      throw StateError(
        'Leitura de notificações desativada por padrão (opt-in requerido).',
      );
    }
    if (!await _bridge.isNotificationAccessGranted()) {
      throw StateError('Permissão de acesso a notificações não concedida no Android.');
    }
    return _bridge.readRecentNotifications();
  }

  /// Consumes a pending Quick Settings Tile launch intent ONLY after
  /// [AuthGate.isAuthenticated] is `true`.
  Future<TileLaunchAction> consumeTileActionIfAuthenticated() async {
    if (!_gate.isAuthenticated) {
      return TileLaunchAction.none;
    }
    return _bridge.consumePendingTileAction();
  }
}
