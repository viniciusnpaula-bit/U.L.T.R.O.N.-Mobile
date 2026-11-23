import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/core/security/auth_gate.dart';
import 'package:ultron_mobile/core/security/pin_vault.dart';
import 'package:ultron_mobile/services/obsidian_service.dart';

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pbkdf2 PBKDF2-HMAC-SHA256', () {
    // Known vectors: PBKDF2-HMAC-SHA256("password", "salt", c, 32).
    const expected1 =
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b';
    const expected2 =
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43';

    test('matches the published test vectors', () {
      final password = utf8.encode('password');
      final salt = utf8.encode('salt');
      expect(hex(pbkdf2(password, salt, 1, 32)), expected1);
      expect(hex(pbkdf2(password, salt, 2, 32)), expected2);
    });

    test('depends on the salt and stays deterministic otherwise', () {
      final password = utf8.encode('1234');
      final a = pbkdf2(password, utf8.encode('salt-a'), 10, 32);
      final b = pbkdf2(password, utf8.encode('salt-b'), 10, 32);
      final again = pbkdf2(password, utf8.encode('salt-a'), 10, 32);
      expect(a, isNot(equals(b)));
      expect(a, equals(again));
      expect(a.length, 32);
    });
  });

  group('PinVault lockout', () {
    test('does not wait during the free attempts', () {
      for (var failures = 0; failures <= PinVault.freeAttempts; failures++) {
        expect(PinVault.lockDelay(failures), Duration.zero);
      }
    });

    test('waits 30s on the first failure and doubles after it', () {
      expect(PinVault.lockDelay(6), const Duration(seconds: 30));
      expect(PinVault.lockDelay(7), const Duration(seconds: 60));
      expect(PinVault.lockDelay(8), const Duration(seconds: 120));
      expect(PinVault.lockDelay(9), const Duration(seconds: 240));
      expect(PinVault.lockDelay(10), const Duration(minutes: 8));
    });

    test('caps the wait at 15 minutes', () {
      expect(PinVault.lockDelay(11), const Duration(minutes: 15));
      expect(PinVault.lockDelay(1000), const Duration(minutes: 15));
    });
  });

  group('AuthGate Duress & ObsidianService Phase 1', () {
    test('grantDuress sets AccessLevel.guarded and isDuressMode=true', () {
      final gate = AuthGate();
      expect(gate.isAuthenticated, isFalse);
      expect(gate.isDuressMode, isFalse);

      gate.grantDuress();
      expect(gate.isAuthenticated, isTrue);
      expect(gate.isDuressMode, isTrue);
      expect(gate.level, AccessLevel.guarded);

      gate.lock();
      expect(gate.isAuthenticated, isFalse);
      expect(gate.isDuressMode, isFalse);
    });

    test('ObsidianService appends daily note and parses MobileSkill', () async {
      final tempDir = await Directory.systemTemp.createTemp('ultron_vault_');
      try {
        final obsidian = ObsidianService(tempDir);
        final date = DateTime(2026, 11, 3);
        final file = await obsidian.appendDailyNote(date, 'Testar sensores');
        expect(await file.exists(), isTrue);
        final content = await obsidian.readDailyNote(date);
        expect(content, contains('Testar sensores'));

        final skillsDir = Directory('${tempDir.path}/Skills');
        await skillsDir.create(recursive: true);
        await File('${skillsDir.path}/modo_estudo.md').writeAsString(
          '# Modo Estudo\nSilencia notificações e abre timer.\n[ACTION:TIMER:25]\n',
        );

        final skills = await obsidian.listSkills();
        expect(skills.length, 1);
        expect(skills.first.slug, 'modo_estudo');
        expect(skills.first.title, 'Modo Estudo');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('setDuressPin validates 4..8 digits and rejects matching primary PIN',
        () async {
      final storage = _PinTestStorage();
      final vault = PinVault(storage: storage);

      await vault.setPin('1234');
      await expectLater(() => vault.setDuressPin('123'), throwsArgumentError);
      await expectLater(
          () => vault.setDuressPin('123456789'), throwsArgumentError);
      await expectLater(() => vault.setDuressPin('abcd'), throwsArgumentError);
      await expectLater(() => vault.setDuressPin('1234'), throwsArgumentError);

      await vault.setDuressPin('5678');
      expect(await vault.hasDuressPin, isTrue);
      expect(await vault.verifyWithDuress('1234'), PinAuthMode.normal);
      expect(await vault.verifyWithDuress('5678'), PinAuthMode.duress);
      expect(await vault.verifyWithDuress('9999'), PinAuthMode.denied);
    });

    test('PinVault NFC tag enrollment verifies hashed UID and AuthGate elevates PIN -> NFC',
        () async {
      final storage = _PinTestStorage();
      final vault = PinVault(storage: storage);
      final gate = AuthGate();

      await vault.setPin('1234');
      expect(await vault.hasNfcKey, isFalse);

      final added = await vault.addNfcTag('04:A1:B2:C3:D4', label: 'Chaveiro');
      expect(added.label, 'Chaveiro');
      expect(added.uidSuffix, 'C3D4');
      expect(await vault.hasNfcKey, isTrue);

      expect(await vault.verifyNfcTag('04a1b2c3d4'), isTrue);
      expect(await vault.verifyNfcTag('DEADBEEF99'), isFalse);

      await gate.authenticatePin('1234', vault.verify);
      expect(gate.level, AccessLevel.basic);
      expect(gate.hasNfcOrHigher, isFalse);

      final nfcOk = await gate.authenticateNfc('04A1B2C3D4', vault.verifyNfcTag);
      expect(nfcOk, isTrue);
      expect(gate.level, AccessLevel.elevated);
      expect(gate.hasNfcOrHigher, isTrue);
      expect(gate.hasBiometricAccess, isFalse);

      // Re-entering PIN must not downgrade elevated session
      await gate.authenticatePin('1234', vault.verify);
      expect(gate.level, AccessLevel.elevated);

      await vault.removeNfcTag(added.id);
      expect(await vault.hasNfcKey, isFalse);
    });
  });
}

class _PinTestStorage extends FlutterSecureStorage {
  final Map<String, String> _data = <String, String>{};

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
