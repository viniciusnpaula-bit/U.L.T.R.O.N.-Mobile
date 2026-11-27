import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:ultron_mobile/core/security/auth_gate.dart';
import 'package:ultron_mobile/models/assistant_persona.dart';
import 'package:ultron_mobile/services/desktop_pairing_service.dart';
import 'package:ultron_mobile/services/device_control_service.dart';
import 'package:ultron_mobile/services/obsidian_service.dart';
import 'package:ultron_mobile/services/skill_bridge_service.dart';
import 'package:ultron_mobile/ui/theme/ultron_theme.dart';
import 'package:ultron_mobile/ui/widgets/skill_bridge_panel.dart';

class _RealHttpOverrides extends HttpOverrides {}

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

class _MemoryStorage extends FlutterSecureStorage {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  HttpOverrides? previousHttpOverrides;

  setUp(() {
    previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = _RealHttpOverrides();
  });

  tearDown(() {
    HttpOverrides.global = previousHttpOverrides;
  });

  group('SkillBridgeService', () {
    test('parses JSON and text PC skill payloads cleanly', () {
      final jsonItems = SkillBridgeService.parsePcSkillsResponse(
        jsonEncode({
          'ok': true,
          'data': {
            'skills': [
              {
                'id': 'modo_trabalho',
                'title': 'Modo Trabalho',
                'description': 'Abre IDE e Docker',
              },
              'backup_rapido',
            ],
          },
        }),
      );
      expect(jsonItems.length, 2);
      expect(jsonItems[0].id, 'modo_trabalho');
      expect(jsonItems[0].description, 'Abre IDE e Docker');
      expect(jsonItems[1].id, 'backup_rapido');

      final textItems = SkillBridgeService.parsePcSkillsResponse(
        '• deploy_prod - Sobe build\n- modo_gamer: Fecha apps em segundo plano',
      );
      expect(textItems.length, 2);
      expect(textItems[0].id, 'deploy_prod');
      expect(textItems[1].id, 'modo_gamer');
    });

    test('refreshes PC skills (with fallback), pins shortcuts, runs PC skills, and syncs Mobile skills',
        () async {
      final commandsReceived = <Map<String, dynamic>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((req) async {
        final raw = await utf8.decoder.bind(req).join();
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        commandsReceived.add(decoded);
        final cmd = decoded['command'] as String? ?? '';
        final args = decoded['args'] as Map<String, dynamic>? ?? {};

        if (cmd == 'PC_LIST_SKILLS') {
          req.response.statusCode = 404;
          req.response.write('unsupported');
        } else if (cmd == 'PC_EXEC_TOOL' && args['tool'] == 'listar_skills') {
          req.response.statusCode = 200;
          req.response.write(jsonEncode({
            'skills': [
              {
                'id': 'modo_trabalho',
                'title': 'Modo Trabalho',
                'description': 'VS Code + Docker',
              },
            ],
          }));
        } else {
          req.response.statusCode = 200;
          req.response.write(jsonEncode({'ok': true, 'executed': cmd}));
        }
        await req.response.close();
      });

      final storage = _MemoryStorage();
      final pairing = DesktopPairingService(storage: storage);
      await pairing.savePairing(
        DesktopPairingConfig(
          baseUrl: 'http://127.0.0.1:${server.port}',
          deviceId: 'galaxy-a34',
          sharedSecret: 'desktop-bridge-secret-32-chars!!',
        ),
      );
      final authGate = AuthGate(auth: _FakeLocalAuth());
      await authGate.authenticateBiometric();

      final deviceService = DeviceControlService(
        storage: storage,
        authGate: authGate,
        desktopPairingProvider: () => pairing,
      );
      final bridge = SkillBridgeService(
        deviceService: deviceService,
        storage: storage,
      );
      addTearDown(bridge.dispose);

      // Pin shortcut before sync
      await bridge.savePinnedPcSkill('Deploy API', description: 'Build + restart');
      expect(bridge.pcSkills.first.id, 'deploy_api');
      expect(bridge.pcSkills.first.pinned, isTrue);

      // Refresh falls back to PC_EXEC_TOOL:listar_skills and preserves pinned
      final list = await bridge.refreshPcSkills();
      expect(list.any((s) => s.id == 'modo_trabalho'), isTrue);
      expect(list.any((s) => s.id == 'deploy_api' && s.pinned), isTrue);

      // Run PC skill by human title
      final runRes = await bridge.runPcSkill('Modo Trabalho');
      expect(runRes.sent, isTrue);
      expect(
        commandsReceived.any(
          (c) =>
              c['command'] == 'PC_RUN_SKILL' &&
              (c['args'] as Map)['skill'] == 'modo_trabalho',
        ),
        isTrue,
      );

      // Sync Mobile skills to PC
      const mobileSkills = [
        MobileSkill(
          id: 'modo_estudo',
          title: 'Modo Estudo',
          content: '# Modo Estudo\nSilencia mídia.\n[ACTION:VOLUME_MUTE]',
        ),
      ];
      final syncRes = await bridge.syncMobileSkillsToPc(mobileSkills);
      expect(syncRes.sent, isTrue);
      final syncCmd = commandsReceived.last;
      expect(syncCmd['command'], 'PC_SYNC_MOBILE_SKILLS');
      expect((syncCmd['args']['skills'] as List).first['slug'], 'modo_estudo');
      expect((syncCmd['args']['skills'] as List).first['riskLevel'], 'safe');

      // Natural language phrases ("ativar skill ... no pc" and "listar skills do pc")
      final natRun = await deviceService.tryExecuteNaturalCommand(
        'ativar skill modo trabalho no pc',
        confirmAction: (_) async => true,
      );
      expect(natRun?.handled, isTrue);
      expect(natRun?.message, contains('modo trabalho'));

      final natList = await deviceService.tryExecuteNaturalCommand(
        'listar skills do pc',
        confirmAction: (_) async => true,
      );
      expect(natList?.handled, isTrue);
    });
  });

  group('SkillBridgePanel widget', () {
    testWidgets('renders PC & Celular tabs, runs 1-tap PC skill, pins shortcut, and syncs Mobile skills without overflow at 360px',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final storage = _MemoryStorage();
      final bridge = SkillBridgeService(
        deviceService: DeviceControlService(storage: storage),
        storage: storage,
      );
      addTearDown(bridge.dispose);
      await bridge.savePinnedPcSkill(
        'modo_trabalho',
        title: 'Modo Trabalho',
        description: 'Abre VS Code e Docker',
      );

      String? ranPcSkill;
      var syncedMobile = false;
      MobileSkill? ranMobileSkill;

      await tester.pumpWidget(
        MaterialApp(
          theme: UltronTheme.dark(persona: AssistantPersona.ultron),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SkillBridgePanel(
                skillBridge: bridge,
                mobileSkills: const [
                  MobileSkill(
                    id: 'modo_estudo',
                    title: 'Modo Estudo',
                    content: '# Modo Estudo\n[ACTION:VOLUME_MUTE]',
                  ),
                ],
                onRunPcSkill: (id) async => ranPcSkill = id,
                onRefreshPcSkills: () async {},
                onSyncMobileSkillsToPc: () async => syncedMobile = true,
                onExecuteMobileSkill: (s) async => ranMobileSkill = s,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      expect(find.text('Modo Trabalho'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.play_circle_filled_rounded).first);
      await tester.pump();
      expect(ranPcSkill, 'modo_trabalho');

      // Switch to Celular tab
      await tester.tap(find.byKey(const Key('skills_bridge_tab_mobile')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Modo Estudo'), findsOneWidget);
      expect(find.text('SAFE'), findsOneWidget);

      await tester.tap(find.byKey(const Key('skills_bridge_sync_mobile')));
      await tester.pump();
      expect(syncedMobile, isTrue);

      await tester.tap(find.byIcon(Icons.play_arrow_rounded).first);
      await tester.pump();
      expect(ranMobileSkill?.id, 'modo_estudo');
    });
  });
}
