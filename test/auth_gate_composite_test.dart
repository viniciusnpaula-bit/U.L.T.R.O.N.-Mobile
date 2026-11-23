import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:ultron_mobile/core/security/auth_gate.dart';
import 'package:ultron_mobile/services/audio_vad_buffer.dart';

class _AlwaysOkBiometricAuth extends LocalAuthentication {
  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<bool> get canCheckBiometrics async => true;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<Object> authMessages = const [],
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async =>
      true;
}

void main() {
  group('Marco 3 — Composite AuthGate (Biometria + NFC NDEF)', () {
    test('rejects plain clonable UID in isValidEncryptedNdefPayload', () {
      expect(AuthGate.isValidEncryptedNdefPayload('04:A1:B2:C3:D4'), isFalse);
      expect(AuthGate.isValidEncryptedNdefPayload('short'), isFalse);
      expect(
        AuthGate.isValidEncryptedNdefPayload(
          'ultron://ndef/v1.hmac256.9f8a7b6c5d4e3f2a1b0c',
        ),
        isTrue,
      );
    });

    test('biometricPlusNfcNdef requires both factors to reach sovereign',
        () async {
      final gate = AuthGate(
        auth: _AlwaysOkBiometricAuth(),
        sovereignPolicy: SovereignAuthPolicy.biometricPlusNfcNdef,
      );

      // Step 1: Biometric alone only reaches elevated (pending NFC NDEF)
      final bioOk = await gate.authenticateBiometric();
      expect(bioOk, isTrue);
      expect(gate.level, AccessLevel.elevated);
      expect(gate.isBiometricVerified, isTrue);
      expect(gate.isNfcNdefVerified, isFalse);
      expect(gate.levelBadge, contains('FALTA NFC'));

      // Step 2: Invalid plain UID does not elevate to sovereign
      final badNdef = await gate.authenticateNfcNdef(
        '04A1B2C3',
        (_) async => true,
      );
      expect(badNdef, isFalse);
      expect(gate.level, AccessLevel.elevated);

      // Step 3: Valid signed NDEF payload completes 2FA and grants sovereign
      final ndefOk = await gate.authenticateNfcNdef(
        'ultron://ndef/v1.hmac256.9f8a7b6c5d4e3f2a1b0c',
        (_) async => true,
      );
      expect(ndefOk, isTrue);
      expect(gate.level, AccessLevel.sovereign);
      expect(gate.levelBadge, 'NÍVEL 3 • BIO+NFC');

      // Locking clears both factors
      gate.lock();
      expect(gate.isBiometricVerified, isFalse);
      expect(gate.isNfcNdefVerified, isFalse);
    });
  });

  group('Marco 3 — Acoustic Diagnostics & dBFS metering', () {
    test('computes dBFS noise floor and tracks Whisper latency & KWS FP rate',
        () {
      // Silence -> -60 dB
      final silent = Uint8List(640);
      expect(PcmEnergy.noiseFloorDb(silent), -60.0);

      // Moderate PCM16 tone
      final loud = Uint8List(640);
      final bd = ByteData.sublistView(loud);
      for (var i = 0; i < 640; i += 2) {
        bd.setInt16(i, 4096, Endian.little);
      }
      final loudDb = PcmEnergy.noiseFloorDb(loud);
      expect(loudDb, greaterThan(-25.0));
      expect(loudDb, lessThan(-10.0));

      final tracker = AcousticDiagnosticsTracker(preRollMs: 600);
      tracker.recordPcmNoiseFrame(loud);
      tracker.recordSttLatency(320);
      tracker.recordSttLatency(480);
      tracker.recordKwsTrigger(falsePositive: false);
      tracker.recordKwsTrigger(falsePositive: true);

      final snap = tracker.snapshot();
      expect(snap.preRollMs, 600);
      expect(snap.avgSttLatencyMs, 400);
      expect(snap.sttSampleCount, 2);
      expect(snap.kwsTriggers, 2);
      expect(snap.kwsFalsePositives, 1);
      expect(snap.falsePositiveRate, closeTo(0.5, 0.001));
    });
  });
}
