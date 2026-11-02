import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// PIN and biometric authentication backed by Android's secure storage/system prompt.
class UltronAuthService {
  UltronAuthService({FlutterSecureStorage? storage, LocalAuthentication? auth})
      : _storage = storage ?? const FlutterSecureStorage(),
        _auth = auth ?? LocalAuthentication();

  final FlutterSecureStorage _storage;
  final LocalAuthentication _auth;
  static const _saltKey = 'ultron.auth.pin.salt';
  static const _hashKey = 'ultron.auth.pin.hash';

  Future<bool> hasPin() async => (await _storage.read(key: _hashKey)) != null;

  Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      throw ArgumentError('O PIN deve conter de 4 a 8 dígitos.');
    }
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    await _storage.write(key: _saltKey, value: base64Encode(salt));
    await _storage.write(key: _hashKey, value: _digest(pin, salt));
  }

  Future<bool> verifyPin(String pin) async {
    final encodedSalt = await _storage.read(key: _saltKey);
    final expected = await _storage.read(key: _hashKey);
    if (encodedSalt == null || expected == null) return false;
    return _digest(pin, base64Decode(encodedSalt)) == expected;
  }

  String _digest(String pin, List<int> salt) =>
      sha256.convert([...salt, ...utf8.encode(pin)]).toString();

  Future<bool> canUseBiometrics() async {
    try {
      return await _auth.isDeviceSupported() &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateBiometric() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Autentique para acessar o U.L.T.R.O.N.',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
