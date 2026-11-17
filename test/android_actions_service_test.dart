import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/core/security/auth_gate.dart';
import 'package:ultron_mobile/services/android_actions_service.dart';

class _InMemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> data = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    data.remove(key);
  }
}

class _FakeBridge implements AndroidActionsBridge {
  TileLaunchAction pendingAction = TileLaunchAction.none;
  bool systemAccessGranted = true;
  int readCalls = 0;
  int consumeCalls = 0;

  @override
  Future<TileLaunchAction> consumePendingTileAction() async {
    consumeCalls += 1;
    final current = pendingAction;
    pendingAction = TileLaunchAction.none;
    return current;
  }

  @override
  Future<bool> isNotificationAccessGranted() async => systemAccessGranted;

  @override
  Future<void> openNotificationAccessSettings() async {}

  @override
  Future<List<AndroidNotificationSummary>> readRecentNotifications() async {
    readCalls += 1;
    return const [
      AndroidNotificationSummary(
        packageName: 'com.whatsapp',
        title: 'Contato',
        text: 'Mensagem de teste',
        postedAtMs: 1000,
      ),
    ];
  }
}

void main() {
  test('notification listener defaults to disabled (fail-closed) and requires explicit opt-in', () async {
    final gate = AuthGate();
    await gate.authenticatePin('1234', (_) async => true);
    final bridge = _FakeBridge();
    final service = AndroidActionsService(
      gate: gate,
      bridge: bridge,
      storage: _InMemorySecureStorage(),
    );

    expect(await service.isNotificationListenerEnabled(), isFalse);
    await expectLater(
      service.readRecentNotifications(),
      throwsStateError,
    );
    expect(bridge.readCalls, 0);

    // Denied confirmation keeps listener disabled
    expect(
      await service.setNotificationListenerOptIn(
        true,
        confirm: (_) async => false,
      ),
      isFalse,
    );
    expect(await service.isNotificationListenerEnabled(), isFalse);

    // Approved confirmation enables listener
    expect(
      await service.setNotificationListenerOptIn(
        true,
        confirm: (_) async => true,
      ),
      isTrue,
    );
    expect(await service.isNotificationListenerEnabled(), isTrue);

    final notes = await service.readRecentNotifications();
    expect(notes, hasLength(1));
    expect(bridge.readCalls, 1);
  });

  test('refuses notification reading and tile actions while AuthGate is locked', () async {
    final gate = AuthGate();
    final bridge = _FakeBridge()..pendingAction = TileLaunchAction.listenVoice;
    final storage = _InMemorySecureStorage();
    final service = AndroidActionsService(
      gate: gate,
      bridge: bridge,
      storage: storage,
    );

    // Cannot opt-in while locked
    expect(
      await service.setNotificationListenerOptIn(
        true,
        confirm: (_) async => true,
      ),
      isFalse,
    );

    // Refuses tile action while locked (does not trigger or lose pending intent)
    final lockedTile = await service.consumeTileActionIfAuthenticated();
    expect(lockedTile, TileLaunchAction.none);
    expect(bridge.consumeCalls, 0);

    await expectLater(service.readRecentNotifications(), throwsStateError);
    expect(bridge.readCalls, 0);

    // Unlock -> now tile action is consumed
    await gate.authenticatePin('1234', (_) async => true);
    final unlockedTile = await service.consumeTileActionIfAuthenticated();
    expect(unlockedTile, TileLaunchAction.listenVoice);
    expect(bridge.consumeCalls, 1);
  });
}
