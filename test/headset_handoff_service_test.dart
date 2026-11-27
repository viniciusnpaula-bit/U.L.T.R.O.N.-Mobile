import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ultron_mobile/core/security/action_gate.dart';
import 'package:ultron_mobile/core/security/auth_gate.dart';
import 'package:ultron_mobile/services/audit_log_service.dart';
import 'package:ultron_mobile/services/desktop_command_listener.dart';
import 'package:ultron_mobile/services/desktop_pairing_service.dart';
import 'package:ultron_mobile/services/device_control_service.dart';
import 'package:ultron_mobile/services/headset_handoff_service.dart';
import 'package:ultron_mobile/services/obsidian_service.dart';
import 'package:ultron_mobile/services/spotify_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late _MemorySecureStorage storage;
  late DateTime currentNow;
  late AuditLogService audit;

  setUp(() async {
    storage = _MemorySecureStorage();
    currentNow = DateTime(2026, 11, 27, 0, 10);
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, singleInstance: false),
    );
    audit = await AuditLogService.open(database: db);
  });

  tearDown(() async {
    await audit.close();
  });

  Future<SpotifyService> buildConnectedSpotify({
    required List<Map<String, dynamic>> devicesBeforeWake,
    List<Map<String, dynamic>>? devicesAfterWake,
    List<String>? requestLog,
    Map<String, dynamic>? lastTransferBody,
  }) async {
    await storage.write(
      key: SpotifyService.clientIdStorageKey,
      value: 'client_handoff',
    );
    await storage.write(
      key: SpotifyService.accessTokenStorageKey,
      value: 'tok_handoff',
    );
    await storage.write(
      key: SpotifyService.expiresAtStorageKey,
      value: currentNow
          .add(const Duration(hours: 1))
          .millisecondsSinceEpoch
          .toString(),
    );

    var deviceCalls = 0;
    return SpotifyService(
      storage: storage,
      now: () => currentNow,
      httpHandler: (method, uri, {headers = const {}, body}) async {
        requestLog?.add('$method ${uri.path}');
        if (method == 'GET' && uri.path == '/v1/me/player/devices') {
          deviceCalls++;
          final list = (deviceCalls > 1 && devicesAfterWake != null)
              ? devicesAfterWake
              : devicesBeforeWake;
          return SpotifyHttpResponse(
            statusCode: 200,
            body: jsonEncode({'devices': list}),
          );
        }
        if (method == 'PUT' && uri.path == '/v1/me/player') {
          if (lastTransferBody != null && body != null) {
            final parsed = jsonDecode(body) as Map<String, dynamic>;
            lastTransferBody
              ..clear()
              ..addAll(parsed);
          }
          return const SpotifyHttpResponse(statusCode: 204, body: '');
        }
        return const SpotifyHttpResponse(statusCode: 404, body: '');
      },
    );
  }

  group('SpotifyService Connect devices & transfer', () {
    test('lists Connect devices and transfers playback to Smartphone with play=true',
        () async {
      final transferPayload = <String, dynamic>{};
      final sp = await buildConnectedSpotify(
        devicesBeforeWake: const [
          {
            'id': 'pc_dev_1',
            'name': 'DESKTOP-ULTRON',
            'type': 'Computer',
            'is_active': true,
            'is_restricted': false,
            'volume_percent': 75,
          },
          {
            'id': 'phone_dev_2',
            'name': 'Galaxy A34',
            'type': 'Smartphone',
            'is_active': false,
            'is_restricted': false,
            'volume_percent': 60,
          },
        ],
        lastTransferBody: transferPayload,
      );

      final devices = await sp.listDevices();
      expect(devices.length, 2);
      expect(devices.first.isComputer, isTrue);
      expect(devices.last.isMobile, isTrue);

      final moved = await sp.transferPlayback(
        targetType: 'Smartphone',
        play: true,
      );
      expect(moved.id, 'phone_dev_2');
      expect(moved.name, 'Galaxy A34');
      expect(transferPayload['device_ids'], ['phone_dev_2']);
      expect(transferPayload['play'], isTrue);
    });
  });

  group('HeadsetHandoffService (Permutação do Fone)', () {
    test(
        'auto mode (BT disconnected): disconnects PC dongle, prompts double-click, waits for BT, wakes Spotify and transfers playback to Smartphone',
        () async {
      final transferPayload = <String, dynamic>{};
      final spotify = await buildConnectedSpotify(
        // Simula celular dormindo na 1ª tentativa e acordando após openSpotifyApp()
        devicesBeforeWake: const [
          {
            'id': 'pc_1',
            'name': 'DESKTOP-ULTRON',
            'type': 'Computer',
            'is_active': true,
          },
        ],
        devicesAfterWake: const [
          {
            'id': 'pc_1',
            'name': 'DESKTOP-ULTRON',
            'type': 'Computer',
            'is_active': true,
          },
          {
            'id': 'mobile_1',
            'name': 'Galaxy S24',
            'type': 'Smartphone',
            'is_active': false,
          },
        ],
        lastTransferBody: transferPayload,
      );

      String? sentDirection;
      String? spokenPrompt;
      var openedSpotify = 0;

      final handoff = HeadsetHandoffService(
        getBluetoothSnapshot: () async =>
            const BluetoothAudioSnapshot(connected: false),
        waitForBluetoothAudio: ({
          required String preferredName,
          required Duration timeout,
        }) async =>
            const BluetoothAudioSnapshot(
          connected: true,
          devices: ['Attack Shark L30 Pro'],
          primaryDevice: 'Attack Shark L30 Pro',
          matchedPreferred: true,
          elapsedMs: 1400,
        ),
        getSpotifyService: () => spotify,
        triggerDesktopSkill: ({
          required String direction,
          required String headsetName,
        }) async {
          sentDirection = direction;
          return const DesktopCommandResult(sent: true, statusCode: 200);
        },
        hasDesktopPaired: () async => true,
        openSpotifyApp: () async {
          openedSpotify++;
        },
        resumeLocalMedia: () async => true,
        delay: (_) async {},
      );

      final res = await handoff.execute(
        direction: HandoffDirection.auto,
        onProgressSpeak: (msg) => spokenPrompt = msg,
      );

      expect(res.ok, isTrue);
      expect(res.direction, HandoffDirection.toMobile);
      expect(sentDirection, 'to_mobile');
      expect(spokenPrompt, contains('dois cliques'));
      expect(res.bluetoothConnected, isTrue);
      expect(res.bluetoothDeviceName, 'Attack Shark L30 Pro');
      expect(openedSpotify, 1);
      expect(res.spotifyTransferred, isTrue);
      expect(res.spotifyDeviceName, 'Galaxy S24');
      expect(transferPayload['device_ids'], ['mobile_1']);
      expect(transferPayload['play'], isTrue);
    });

    test(
        'auto mode (BT already connected): hands back to PC dongle and transfers Spotify Connect to Computer',
        () async {
      final transferPayload = <String, dynamic>{};
      final spotify = await buildConnectedSpotify(
        devicesBeforeWake: const [
          {
            'id': 'pc_1',
            'name': 'DESKTOP-ULTRON',
            'type': 'Computer',
            'is_active': false,
          },
          {
            'id': 'mobile_1',
            'name': 'Galaxy S24',
            'type': 'Smartphone',
            'is_active': true,
          },
        ],
        lastTransferBody: transferPayload,
      );

      String? sentDirection;
      final handoff = HeadsetHandoffService(
        getBluetoothSnapshot: () async => const BluetoothAudioSnapshot(
          connected: true,
          devices: ['Attack Shark L30 Pro'],
          primaryDevice: 'Attack Shark L30 Pro',
        ),
        waitForBluetoothAudio: ({
          required String preferredName,
          required Duration timeout,
        }) async =>
            const BluetoothAudioSnapshot(connected: false),
        getSpotifyService: () => spotify,
        triggerDesktopSkill: ({
          required String direction,
          required String headsetName,
        }) async {
          sentDirection = direction;
          return const DesktopCommandResult(sent: true, statusCode: 200);
        },
        hasDesktopPaired: () async => true,
        openSpotifyApp: () async {},
        resumeLocalMedia: () async => false,
        delay: (_) async {},
      );

      final res = await handoff.execute(direction: HandoffDirection.auto);

      expect(res.ok, isTrue);
      expect(res.direction, HandoffDirection.toDesktop);
      expect(sentDirection, 'to_desktop');
      expect(res.spotifyTransferred, isTrue);
      expect(res.spotifyDeviceName, 'DESKTOP-ULTRON');
      expect(transferPayload['device_ids'], ['pc_1']);
    });

    test('fromDesktop=true skips calling PC_RUN_SKILL back (prevents loop)',
        () async {
      final spotify = await buildConnectedSpotify(
        devicesBeforeWake: const [
          {
            'id': 'mobile_1',
            'name': 'Galaxy S24',
            'type': 'Smartphone',
            'is_active': false,
          },
        ],
      );

      var pcTriggerCalls = 0;
      final handoff = HeadsetHandoffService(
        getBluetoothSnapshot: () async => const BluetoothAudioSnapshot(
          connected: true,
          devices: ['Attack Shark L30 Pro'],
          primaryDevice: 'Attack Shark L30 Pro',
        ),
        waitForBluetoothAudio: ({
          required String preferredName,
          required Duration timeout,
        }) async =>
            const BluetoothAudioSnapshot(connected: true),
        getSpotifyService: () => spotify,
        triggerDesktopSkill: ({
          required String direction,
          required String headsetName,
        }) async {
          pcTriggerCalls++;
          return const DesktopCommandResult(sent: true, statusCode: 200);
        },
        hasDesktopPaired: () async => true,
        openSpotifyApp: () async {},
        resumeLocalMedia: () async => true,
        delay: (_) async {},
      );

      final res = await handoff.execute(
        direction: HandoffDirection.toMobile,
        fromDesktop: true,
      );

      expect(res.ok, isTrue);
      expect(pcTriggerCalls, 0);
      expect(res.spotifyTransferred, isTrue);
    });
  });

  group('Natural voice triggers, Obsidian skill seed & Desktop inbound', () {
    test(
        'recognizes "Permute a conexão do fone" and "Troque a conexão do fone" via DeviceControlService',
        () async {
      final calls = <HandoffDirection>[];
      final spotify = await buildConnectedSpotify(
        devicesBeforeWake: const [
          {
            'id': 'mobile_1',
            'name': 'Galaxy S24',
            'type': 'Smartphone',
            'is_active': false,
          },
          {
            'id': 'pc_1',
            'name': 'DESKTOP-ULTRON',
            'type': 'Computer',
            'is_active': true,
          },
        ],
      );

      final device = DeviceControlService(
        storage: storage,
        auditLogProvider: () async => audit,
        spotifyProvider: () => spotify,
        headsetHandoffProvider: () => HeadsetHandoffService(
          getBluetoothSnapshot: () async =>
              const BluetoothAudioSnapshot(connected: false),
          waitForBluetoothAudio: ({
            required String preferredName,
            required Duration timeout,
          }) async =>
              const BluetoothAudioSnapshot(
            connected: true,
            devices: ['Attack Shark L30 Pro'],
            primaryDevice: 'Attack Shark L30 Pro',
          ),
          getSpotifyService: () => spotify,
          triggerDesktopSkill: ({
            required String direction,
            required String headsetName,
          }) async {
            calls.add(HandoffDirection.parse(direction));
            return const DesktopCommandResult(sent: true, statusCode: 200);
          },
          hasDesktopPaired: () async => true,
          openSpotifyApp: () async {},
          resumeLocalMedia: () async => true,
          delay: (_) async {},
        ),
      );

      final r1 = await device.tryExecuteNaturalCommand(
        'Permute a conexão do fone',
      );
      expect(r1, isNotNull);
      expect(r1!.handled, isTrue);
      expect(r1.message, contains('Permutação do Fone'));

      final r2 = await device.tryExecuteNaturalCommand(
        'Ultron, troque a conexão do fone pro pc',
      );
      expect(r2, isNotNull);
      expect(r2!.handled, isTrue);
      expect(calls, [HandoffDirection.toMobile, HandoffDirection.toDesktop]);
    });

    test(
        'seeds permutacao_do_fone.md in Obsidian vault and executes via DesktopCommandListener RUN_SKILL without loop',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('ultron_handoff_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final vault = ObsidianService(tempDir);
      await vault.initialize();
      final skill = await vault.findSkill('permutação do fone');
      expect(skill, isNotNull);
      expect(skill!.id, 'permutacao_do_fone');
      expect(skill.title, 'Permutação do Fone');
      expect(skill.content, contains('[ACTION:HEADSET_HANDOFF:auto]'));

      final spotify = await buildConnectedSpotify(
        devicesBeforeWake: const [
          {
            'id': 'mobile_1',
            'name': 'Galaxy S24',
            'type': 'Smartphone',
            'is_active': false,
          },
        ],
      );

      var pcTriggerCalls = 0;
      final authGate = AuthGate(auth: _FakeLocalAuth());
      await authGate.authenticateBiometric();
      final device = DeviceControlService(
        storage: storage,
        authGate: authGate,
        auditLogProvider: () async => audit,
        obsidianProvider: () async => vault,
        spotifyProvider: () => spotify,
        headsetHandoffProvider: () => HeadsetHandoffService(
          getBluetoothSnapshot: () async => const BluetoothAudioSnapshot(
            connected: true,
            devices: ['Attack Shark L30 Pro'],
            primaryDevice: 'Attack Shark L30 Pro',
          ),
          waitForBluetoothAudio: ({
            required String preferredName,
            required Duration timeout,
          }) async =>
              const BluetoothAudioSnapshot(
            connected: true,
            devices: ['Attack Shark L30 Pro'],
            primaryDevice: 'Attack Shark L30 Pro',
          ),
          getSpotifyService: () => spotify,
          triggerDesktopSkill: ({
            required String direction,
            required String headsetName,
          }) async {
            pcTriggerCalls++;
            return const DesktopCommandResult(sent: true, statusCode: 200);
          },
          hasDesktopPaired: () async => true,
          openSpotifyApp: () async {},
          resumeLocalMedia: () async => true,
          delay: (_) async {},
        ),
      );

      final listener = DesktopCommandListener(
        pairingService: DesktopPairingService(storage: storage),
        deviceService: device,
        authGate: authGate,
        now: () => currentNow,
      );
      const config = DesktopPairingConfig(
        baseUrl: 'http://192.168.1.10:8765',
        sharedSecret: 'secret_key_123456',
        deviceId: 'phone_1',
      );
      final payload = jsonEncode({
        'command_id': 'cmd_handoff_1',
        'device_id': 'phone_1',
        'command': 'RUN_SKILL',
        'args': {'skill': 'permutacao_do_fone', 'direction': 'to_mobile'},
        'timestamp': currentNow.millisecondsSinceEpoch.toString(),
        'nonce': 'nonce_handoff_1',
      });

      final res = await listener.handleVerifiedEnvelope(
        rawBody: payload,
        config: config,
        headerTimestamp: currentNow.millisecondsSinceEpoch.toString(),
        headerNonce: 'nonce_handoff_1',
      );

      expect(res, isNotNull);
      expect(res!.ok, isTrue);
      expect(res.status, 'executed');
      expect(pcTriggerCalls, 0);
      expect(res.message, contains('Permutação do Fone'));
    });

    test('ActionGate classifies HEADSET_HANDOFF and SPOTIFY_TRANSFER as safe',
        () {
      const gate = ActionGate();
      final h = gate.simulate('[ACTION:HEADSET_HANDOFF:auto]');
      expect(h.actionCode, 'HEADSET_HANDOFF');
      expect(h.riskLevel, RiskLevel.safe);

      final t = gate.simulate('[ACTION:SPOTIFY_TRANSFER:smartphone]');
      expect(t.actionCode, 'SPOTIFY_TRANSFER');
      expect(t.riskLevel, RiskLevel.safe);
    });
  });
}

class _FakeLocalAuth extends LocalAuthentication {
  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<bool> get canCheckBiometrics async => true;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<Object> authMessages = const <Object>[],
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async =>
      true;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async =>
      const [BiometricType.fingerprint];
}

class _MemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> _data = {};

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
      _data[key];

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
      _data.remove(key);
    } else {
      _data[key] = value;
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
    _data.remove(key);
  }
}
