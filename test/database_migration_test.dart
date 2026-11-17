import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ultron_mobile/core/security/database_key_vault.dart';
import 'package:ultron_mobile/services/conversation_history.dart';

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

void main() {
  sqfliteFfiInit();

  test('DatabaseKeyVault generates a 64-hex-char key once and reuses it', () async {
    final storage = _InMemorySecureStorage();
    final vault = DatabaseKeyVault(storage: storage);

    final first = await vault.getOrCreateKey();
    expect(first, matches(RegExp(r'^[0-9a-f]{64}$')));

    final second = await vault.getOrCreateKey();
    expect(second, first);

    final vault2 = DatabaseKeyVault(storage: storage);
    expect(await vault2.getOrCreateKey(), first);
  });

  test('migrates legacy v1 plaintext messages to v2 database and removes legacy file after commit', () async {
    final tempDir = await Directory.systemTemp.createTemp('ultron_db_mig_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final legacyPath = p.join(tempDir.path, ConversationHistory.legacyDatabaseName);
    final legacyDb = await databaseFactoryFfi.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onCreate: (db, _) async {
          await db.execute(ConversationHistory.schema.first);
          await db.execute(ConversationHistory.schema[1]);
        },
      ),
    );
    await legacyDb.insert('messages', {
      'conversation_id': 'default',
      'role': 'user',
      'content': 'Oi Ultron',
      'created_at': '2026-11-16T10:00:00.000Z',
    });
    await legacyDb.insert('messages', {
      'conversation_id': 'default',
      'role': 'assistant',
      'content': 'Olá, tudo pronto.',
      'created_at': '2026-11-16T10:00:05.000Z',
    });
    await legacyDb.close();
    expect(await File(legacyPath).exists(), isTrue);

    String? capturedPassword;
    final storage = _InMemorySecureStorage();
    final keyVault = DatabaseKeyVault(storage: storage);

    final history = await ConversationHistory.openWith(
      directoryPath: tempDir.path,
      keyVault: keyVault,
      encryptedOpener: (
        path, {
        String? password,
        int? version,
        onCreate,
        onUpgrade,
      }) async {
        capturedPassword = password;
        return databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: version,
            singleInstance: false,
            onCreate: onCreate,
            onUpgrade: onUpgrade,
          ),
        );
      },
      plaintextOpener: (path, {bool readOnly = true}) =>
          databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          readOnly: readOnly,
          singleInstance: false,
        ),
      ),
    );
    addTearDown(() async => (await history.database).close());

    expect(capturedPassword, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(await File(legacyPath).exists(), isFalse);

    final migrated = await history.messages(conversationId: 'default');
    expect(migrated.map((m) => m.content), ['Oi Ultron', 'Olá, tudo pronto.']);

    final db = await history.database;
    final tables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    ))
        .map((row) => row['name'] as String)
        .toSet();
    expect(
      tables,
      containsAll(<String>[
        'messages',
        'voice_corrections',
        'voice_shortcuts',
        'user_preferences',
      ]),
    );
  });

  test('preserves legacy v1 file if encrypted target fails during migration', () async {
    final tempDir = await Directory.systemTemp.createTemp('ultron_db_fail_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final legacyPath = p.join(tempDir.path, ConversationHistory.legacyDatabaseName);
    final legacyDb = await databaseFactoryFfi.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onCreate: (db, _) async {
          await db.execute(ConversationHistory.schema.first);
        },
      ),
    );
    await legacyDb.insert('messages', {
      'conversation_id': 'default',
      'role': 'user',
      'content': 'Não perca isto',
      'created_at': '2026-11-16T10:00:00.000Z',
    });
    await legacyDb.close();

    await expectLater(
      ConversationHistory.openWith(
        directoryPath: tempDir.path,
        keyVault: DatabaseKeyVault(storage: _InMemorySecureStorage()),
        encryptedOpener: (
          path, {
          String? password,
          int? version,
          onCreate,
          onUpgrade,
        }) async {
          throw StateError('Falha ao abrir banco cifrado');
        },
        plaintextOpener: (path, {bool readOnly = true}) =>
            databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            readOnly: readOnly,
            singleInstance: false,
          ),
        ),
      ),
      throwsStateError,
    );

    expect(await File(legacyPath).exists(), isTrue);
  });
}
