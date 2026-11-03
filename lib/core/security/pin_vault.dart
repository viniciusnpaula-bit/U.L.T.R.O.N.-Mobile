import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Salted PBKDF2-HMAC-SHA256 verifier. The PIN itself is never stored and the
/// hash lives in Android's secure storage (Keystore-backed).
class PinVault {
  PinVault({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _key = 'ultron.pin.v1';
  static const _lockKey = 'ultron.pin.lock.v1';
  static const _iterations = 120000;

  /// Wrong PINs allowed before the first wait.
  static const freeAttempts = 5;
  static const _baseDelay = Duration(seconds: 30);
  static const _maxDelay = Duration(minutes: 15);

  Future<bool> get hasPin async => (await _storage.read(key: _key)) != null;

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

  Future<bool> verify(String pin) async {
    // The gate refuses while a wait is pending, not only the keypad.
    if (await lockRemaining() > Duration.zero) return false;
    final raw = await _storage.read(key: _key);
    if (raw == null) return false;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final salt = base64Decode(data['salt'] as String);
    final expected = base64Decode(data['hash'] as String);
    final actual = await _derive(pin, salt, iterations: data['iterations'] as int);
    if (!_constantTimeEquals(actual, expected)) {
      await registerFailure();
      return false;
    }
    await resetFailures();
    return true;
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
