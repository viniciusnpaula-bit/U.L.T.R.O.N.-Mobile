import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

enum AccessLevel { locked, guarded, session }

class AuthGate extends ChangeNotifier {
  AuthGate({LocalAuthentication? auth}) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;
  AccessLevel _level = AccessLevel.locked;
  bool _session = false;

  AccessLevel get level => _level;
  bool get isAuthenticated => _session;

  Future<bool> authenticateBiometric() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported && !(await _auth.canCheckBiometrics)) return false;

      final ok = await _auth.authenticate(
        localizedReason: 'Autentique para acessar o U.L.T.R.O.N.',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (ok) _grant();
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticatePin(
    String pin,
    Future<bool> Function(String) verify,
  ) async {
    if (pin.length < 4 || pin.length > 8) return false;
    final ok = await verify(pin);
    if (ok) _grant();
    return ok;
  }

  void _grant() {
    _session = true;
    _level = AccessLevel.session;
    notifyListeners();
  }

  void lock() {
    _session = false;
    _level = AccessLevel.locked;
    notifyListeners();
  }
}
