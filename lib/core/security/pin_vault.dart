import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum PinAuthMode { denied, normal, duress }

class NfcTagEntry {
  const NfcTagEntry({
    required this.id,
    required this.label,
    required this.uidSuffix,
    required this.addedAtMs,
  });

  final String id;
  final String label;
  final String uidSuffix;
  final int addedAtMs;
}

/// Salted PBKDF2-HMAC-SHA256 verifier. The PIN and NFC tag UIDs are never stored
/// in plaintext; only salted hashes live in Android's secure storage (Keystore-backed).
class PinVault {
  PinVault({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _key = 'ultron.pin.v1';
  static const _duressKey = 'ultron.pin.duress.v1';
  static const _nfcKey = 'ultron.nfc.tags.v1';
  static const _lockKey = 'ultron.pin.lock.v1';
  static const _iterations = 120000;

  /// Wrong PINs allowed before the first wait.
  static const freeAttempts = 5;
  static const _baseDelay = Duration(seconds: 30);
  static const _maxDelay = Duration(minutes: 15);

  Future<bool> get hasPin async => (await _storage.read(key: _key)) != null;
  Future<bool> get hasDuressPin async =>
      (await _storage.read(key: _duressKey)) != null;

  /// No wait until [freeAttempts], then 30s doubling up to 15 minutes.
  static Duration lockDelay(int failures) {
    if (failures <= freeAttempts) return Duration.zero;
    final step = (failures - freeAttempts).clamp(1, 10).toInt();
    final seconds = _baseDelay.inSeconds << (step - 1);
    return Duration(seconds: min(seconds, _maxDelay.inSeconds));
  }

  Future<Duration> lockRemaining() async {
    final lock = await _readLock();
    final until = DateTime.fromMillisecondsSinceEpoch(lock['until'] as int? ?? 0);
    final left = until.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  Future<int> failureCount() async =>
      (await _readLock())['failures'] as int? ?? 0;

  /// Counts the failure, stores the wait it bought and returns it.
  Future<Duration> registerFailure() async {
    final failures = ((await _readLock())['failures'] as int? ?? 0) + 1;
    final delay = lockDelay(failures);
    await _storage.write(
      key: _lockKey,
      value: jsonEncode({
        'failures': failures,
        'until': DateTime.now().add(delay).millisecondsSinceEpoch,
      }),
    );
    return delay;
  }

  Future<void> resetFailures() => _storage.delete(key: _lockKey);

  Future<void> setPin(String pin) async {
    if (await _matchesStoredKey(_duressKey, pin)) {
      throw ArgumentError(
        'O PIN principal não pode ser igual ao PIN de Coação.',
      );
    }
    final salt = _randomSalt();
    final hash = await _derive(pin, salt);
    await _storage.write(
      key: _key,
      value: jsonEncode({
        'salt': base64Encode(salt),
        'hash': base64Encode(hash),
        'iterations': _iterations,
      }),
    );
    await resetFailures();
  }

  Future<void> setDuressPin(String pin) async {
    final clean = pin.trim();
    if (!RegExp(r'^\d{4,8}$').hasMatch(clean)) {
      throw ArgumentError(
        'O PIN de Coação deve ter entre 4 e 8 dígitos numéricos.',
      );
    }
    if (await _matchesStoredKey(_key, clean)) {
      throw ArgumentError(
        'O PIN de Coação não pode ser igual ao PIN principal.',
      );
    }
    final salt = _randomSalt();
    final hash = await _derive(clean, salt);
    await _storage.write(
      key: _duressKey,
      value: jsonEncode({
        'salt': base64Encode(salt),
        'hash': base64Encode(hash),
        'iterations': _iterations,
      }),
    );
  }

  Future<void> clearDuressPin() => _storage.delete(key: _duressKey);

  static String normalizeNfcUid(String raw) =>
      raw.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();

  Future<bool> get hasNfcKey async => (await listNfcTags()).isNotEmpty;

  Future<List<Map<String, dynamic>>> _readNfcRecords() async {
    final raw = await _storage.read(key: _nfcKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<NfcTagEntry>> listNfcTags() async {
    final records = await _readNfcRecords();
    return records
        .map(
          (r) => NfcTagEntry(
            id: (r['id'] as String? ?? '').trim(),
            label: (r['label'] as String? ?? 'Chave NFC').trim(),
            uidSuffix: (r['suffix'] as String? ?? '****').trim(),
            addedAtMs: (r['addedAtMs'] as num?)?.toInt() ?? 0,
          ),
        )
        .where((e) => e.id.isNotEmpty)
        .toList();
  }

  Future<NfcTagEntry> addNfcTag(
    String rawUid, {
    String label = 'Chave NFC',
  }) async {
    final uid = normalizeNfcUid(rawUid);
    if (uid.length < 8) {
      throw ArgumentError('UID NFC inválido ou muito curto.');
    }
    final cleanLabel = label.trim().isEmpty ? 'Chave NFC' : label.trim();
    final salt = _randomSalt();
    final hash = await _derive(uid, salt);
    final suffix = uid.length >= 4 ? uid.substring(uid.length - 4) : uid;
    final id = 'nfc_${DateTime.now().millisecondsSinceEpoch}_${salt[0].toRadixString(16)}';
    final addedAtMs = DateTime.now().millisecondsSinceEpoch;

    final existing = await _readNfcRecords();
    final updated = <Map<String, dynamic>>[];
    for (final rec in existing) {
      // Substitui se a mesma tag fisica ja estava cadastrada.
      try {
        final s = base64Decode(rec['salt'] as String);
        final expected = base64Decode(rec['hash'] as String);
        final iters = (rec['iterations'] as int?) ?? _iterations;
        final actual = await _derive(uid, s, iterations: iters);
        if (_constantTimeEquals(actual, expected)) continue;
      } catch (_) {}
      updated.add(rec);
    }

    updated.add(<String, dynamic>{
      'id': id,
      'label': cleanLabel,
      'suffix': suffix,
      'addedAtMs': addedAtMs,
      'salt': base64Encode(salt),
      'hash': base64Encode(hash),
      'iterations': _iterations,
    });

    await _storage.write(key: _nfcKey, value: jsonEncode(updated));
    return NfcTagEntry(
      id: id,
      label: cleanLabel,
      uidSuffix: suffix,
      addedAtMs: addedAtMs,
    );
  }

  Future<void> removeNfcTag(String id) async {
    final existing = await _readNfcRecords();
    final remaining = existing.where((r) => r['id'] != id).toList();
    if (remaining.isEmpty) {
      await clearNfcTags();
    } else {
      await _storage.write(key: _nfcKey, value: jsonEncode(remaining));
    }
  }

  Future<void> clearNfcTags() => _storage.delete(key: _nfcKey);

  Future<bool> verifyNfcTag(String rawUid) async {
    if (await lockRemaining() > Duration.zero) return false;
    final uid = normalizeNfcUid(rawUid);
    if (uid.length < 8) {
      await registerFailure();
      return false;
    }
    final records = await _readNfcRecords();
    if (records.isEmpty) return false;
    for (final rec in records) {
      try {
        final salt = base64Decode(rec['salt'] as String);
        final expected = base64Decode(rec['hash'] as String);
        final iterations = (rec['iterations'] as int?) ?? _iterations;
        final actual = await _derive(uid, salt, iterations: iterations);
        if (_constantTimeEquals(actual, expected)) {
          await resetFailures();
          return true;
        }
      } catch (_) {}
    }
    await registerFailure();
    return false;
  }

  Future<bool> _matchesStoredKey(String storageKey, String pin) async {
    final raw = await _storage.read(key: storageKey);
    if (raw == null) return false;
    final Map<String, dynamic> data;
    final Uint8List salt;
    final Uint8List expected;
    final int iterations;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>;
      salt = base64Decode(data['salt'] as String);
      expected = base64Decode(data['hash'] as String);
      iterations = (data['iterations'] as int?) ?? _iterations;
    } catch (_) {
      return false;
    }
    final actual = await _derive(pin, salt, iterations: iterations);
    return _constantTimeEquals(actual, expected);
  }

  Future<PinAuthMode> verifyWithDuress(String pin) async {
    if (await lockRemaining() > Duration.zero) return PinAuthMode.denied;
    if (await _matchesStoredKey(_key, pin)) {
      await resetFailures();
      return PinAuthMode.normal;
    }
    if (await _matchesStoredKey(_duressKey, pin)) {
      await resetFailures();
      return PinAuthMode.duress;
    }
    await registerFailure();
    return PinAuthMode.denied;
  }

  Future<bool> verify(String pin) async {
    final mode = await verifyWithDuress(pin);
    return mode == PinAuthMode.normal;
  }

  Future<void> clear() => _storage.delete(key: _key);

  Future<Map<String, dynamic>> _readLock() async {
    try {
      final raw = await _storage.read(key: _lockKey);
      if (raw == null) return const {};
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      // A corrupted record must not brick the gate.
      return const {};
    }
  }

  static Future<List<int>> _derive(
    String pin,
    List<int> salt, {
    int iterations = _iterations,
  }) =>
      Isolate.run(() => pbkdf2(utf8.encode(pin), salt, iterations, 32));

  static Uint8List _randomSalt() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// PBKDF2-HMAC-SHA256 (RFC 8018) for a single block, so [length] must be <= 32.
List<int> pbkdf2(List<int> password, List<int> salt, int iterations, int length) {
  final hmac = Hmac(sha256, password);
  final firstBlock = <int>[...salt, 0, 0, 0, 1];
  var block = hmac.convert(firstBlock).bytes;
  final result = List<int>.from(block);
  for (var i = 1; i < iterations; i++) {
    block = hmac.convert(block).bytes;
    for (var j = 0; j < result.length; j++) {
      result[j] ^= block[j];
    }
  }
  return result.sublist(0, length);
}
