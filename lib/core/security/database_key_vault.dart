import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores and retrieves the 256-bit hex passphrase used by SQLCipher.
class DatabaseKeyVault {
  DatabaseKeyVault({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _storageKey = 'ultron.db.key.v1';
  static final RegExp _hex64 = RegExp(r'^[0-9a-fA-F]{64}$');

  final FlutterSecureStorage _storage;

  Future<String?> readKey() async {
    final value = await _storage.read(key: _storageKey);
    if (value == null || !_hex64.hasMatch(value.trim())) {
      return null;
    }
    return value.trim().toLowerCase();
  }

  Future<String> getOrCreateKey() async {
    final existing = await readKey();
    if (existing != null) return existing;

    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    final generated = buffer.toString();
    await _storage.write(key: _storageKey, value: generated);
    return generated;
  }

  Future<void> clearKey() => _storage.delete(key: _storageKey);
}
