import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// Estágios hierárquicos de privilégio do U.L.T.R.O.N.:
/// - `locked`: sessão bloqueada
/// - `guarded`: modo coação (Duress PIN)
/// - `basic`: Nível 1 — Senha/PIN (Ultron Base)
/// - `elevated`: Nível 2 — Chave Física NFC (Celular completo, sem Desktop/críticos)
/// - `sovereign`: Nível 3 — Biometria do Dono (Tudo liberado sem fricção, só confirma críticos/autodestrutivos)
enum AccessLevel { locked, guarded, basic, elevated, sovereign }

/// Política para elevação ao nível `sovereign` (KILL_SWITCH, PC_EXEC_TOOL, ações críticas).
enum SovereignAuthPolicy {
  /// Padrão compatível: Biometria forte do aparelho libera `sovereign`.
  biometricOnly,

  /// Autenticação composta (Marco 3 — v1.8.0): exige Biometria + Tag NFC com payload NDEF autenticado.
  biometricPlusNfcNdef,
}

class AuthGate extends ChangeNotifier {
  AuthGate({
    LocalAuthentication? auth,
    SovereignAuthPolicy sovereignPolicy = SovereignAuthPolicy.biometricOnly,
  })  : _auth = auth ?? LocalAuthentication(),
        _sovereignPolicy = sovereignPolicy;

  final LocalAuthentication _auth;
  SovereignAuthPolicy _sovereignPolicy;
  AccessLevel _level = AccessLevel.locked;
  bool _session = false;
  bool _biometricVerified = false;
  bool _nfcNdefVerified = false;

  AccessLevel get level => _level;
  SovereignAuthPolicy get sovereignPolicy => _sovereignPolicy;
  bool get isBiometricVerified => _biometricVerified;
  bool get isNfcNdefVerified => _nfcNdefVerified;
  bool get isAuthenticated => _session;
  bool get isDuressMode => _session && _level == AccessLevel.guarded;
  bool get hasNfcOrHigher =>
      _session &&
      (_level == AccessLevel.elevated || _level == AccessLevel.sovereign);
  bool get hasBiometricAccess => _session && _level == AccessLevel.sovereign;

  void setSovereignPolicy(SovereignAuthPolicy policy) {
    if (_sovereignPolicy == policy) return;
    _sovereignPolicy = policy;
    if (_session &&
        _level == AccessLevel.sovereign &&
        policy == SovereignAuthPolicy.biometricPlusNfcNdef &&
        !(_biometricVerified && _nfcNdefVerified)) {
      _level = AccessLevel.elevated;
    }
    notifyListeners();
  }

  /// Valida estruturalmente se um payload NDEF não é apenas um UID simples clonável,
  /// exigindo formato assinado/criptografado (`ultron://ndef/...` ou token >= 24 chars).
  static bool isValidEncryptedNdefPayload(String rawPayload) {
    final trimmed = rawPayload.trim();
    if (trimmed.length < 24) return false;
    if (RegExp(r'^[0-9A-Fa-f:\-\s]{4,23}$').hasMatch(trimmed)) return false;
    return trimmed.startsWith('ultron://ndef/') ||
        trimmed.startsWith('ULTRON-NDEF:') ||
        trimmed.contains('.');
  }

  static int _rank(AccessLevel lvl) => switch (lvl) {
        AccessLevel.locked => 0,
        AccessLevel.guarded => 1,
        AccessLevel.basic => 2,
        AccessLevel.elevated => 3,
        AccessLevel.sovereign => 4,
      };

  bool satisfies(AccessLevel requiredLevel) {
    if (!_session) return false;
    if (_level == AccessLevel.guarded) {
      return requiredLevel == AccessLevel.guarded;
    }
    return _rank(_level) >= _rank(requiredLevel);
  }

  String get levelBadge => switch (_level) {
        AccessLevel.locked => 'TRAVADO',
        AccessLevel.guarded => 'NÍVEL 1 • PIN',
        AccessLevel.basic => 'NÍVEL 1 • PIN',
        AccessLevel.elevated => _biometricVerified &&
                _sovereignPolicy == SovereignAuthPolicy.biometricPlusNfcNdef
            ? 'NÍVEL 2 • BIO (FALTA NFC)'
            : 'NÍVEL 2 • NFC',
        AccessLevel.sovereign =>
          (_biometricVerified && _nfcNdefVerified)
              ? 'NÍVEL 3 • BIO+NFC'
              : 'NÍVEL 3 • BIO',
      };

  Future<bool> authenticateBiometric() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      if (!supported && !canCheck) return false;
      final ok = await _auth.authenticate(
        localizedReason: 'Autentique para liberar acesso total no U.L.T.R.O.N.',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (ok) {
        _biometricVerified = true;
        if (_sovereignPolicy == SovereignAuthPolicy.biometricPlusNfcNdef &&
            !_nfcNdefVerified) {
          _grantAtLeast(AccessLevel.elevated);
        } else {
          _grant(AccessLevel.sovereign);
        }
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Elevação via payload NFC NDEF criptografado/assinado (mais forte que UID simples).
  /// Em política composta (`biometricPlusNfcNdef`), combina com biometria para atingir `sovereign`.
  Future<bool> authenticateNfcNdef(
    String ndefPayload,
    Future<bool> Function(String payload) verify,
  ) async {
    final trimmed = ndefPayload.trim();
    if (!isValidEncryptedNdefPayload(trimmed)) return false;
    final ok = await verify(trimmed);
    if (!ok) return false;
    _nfcNdefVerified = true;
    if (_sovereignPolicy == SovereignAuthPolicy.biometricPlusNfcNdef &&
        _biometricVerified) {
      _grant(AccessLevel.sovereign);
    } else {
      _grantAtLeast(AccessLevel.elevated);
    }
    return true;
  }

  Future<bool> authenticatePin(
    String pin,
    Future<bool> Function(String) verify,
  ) async {
    if (pin.length < 4 || pin.length > 8) return false;
    final ok = await verify(pin);
    if (ok) _grantAtLeast(AccessLevel.basic);
    return ok;
  }

  Future<bool> authenticateNfc(
    String uidHex,
    Future<bool> Function(String) verify,
  ) async {
    final normalized = uidHex.trim().toUpperCase();
    if (normalized.isEmpty) return false;
    final ok = await verify(normalized);
    if (ok) _grantAtLeast(AccessLevel.elevated);
    return ok;
  }

  Future<List<BiometricType>> biometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return const [];
    }
  }

  void _grant(AccessLevel next) {
    _session = true;
    _level = next;
    notifyListeners();
  }

  void _grantAtLeast(AccessLevel next) {
    if (_session && _level != AccessLevel.guarded && _rank(_level) > _rank(next)) {
      return;
    }
    _grant(next);
  }

  void grantDuress() {
    _session = true;
    _level = AccessLevel.guarded;
    notifyListeners();
  }

  void lock() {
    _session = false;
    _level = AccessLevel.locked;
    _biometricVerified = false;
    _nfcNdefVerified = false;
    notifyListeners();
  }
}
