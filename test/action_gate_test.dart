import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/core/security/action_gate.dart';

void main() {
  const gate = ActionGate();

  group('ActionGate Risk Classification', () {
    test('classifies KILL_SWITCH and CLEAR_HISTORY as critical risk requiring confirmation', () {
      final killSwitchSim = gate.simulate('[ACTION:KILL_SWITCH]');
      expect(killSwitchSim.riskLevel, RiskLevel.critical);
      expect(killSwitchSim.requiresConfirmation, isTrue);
      expect(killSwitchSim.canDegradeToOffline, isFalse);

      final lockPcSim = gate.simulate('LOCK_PC');
      expect(lockPcSim.riskLevel, RiskLevel.critical);
      expect(lockPcSim.requiresConfirmation, isTrue);

      final clearSim = gate.simulate('[ACTION:CLEAR_HISTORY]');
      expect(clearSim.riskLevel, RiskLevel.critical);
      expect(clearSim.requiresConfirmation, isTrue);
    });

    test('classifies WHATSAPP, SMS, and REPLY_MESSAGE as sensitive risk', () {
      final waSim = gate.simulate('[ACTION:WHATSAPP:Carlos:Chegando]');
      expect(waSim.riskLevel, RiskLevel.sensitive);
      expect(waSim.requiresConfirmation, isFalse);
      expect(waSim.targetResource, contains('Carlos'));

      final smsSim = gate.simulate('[ACTION:SMS:1199999999:Teste]');
      expect(smsSim.riskLevel, RiskLevel.sensitive);

      final replySim = gate.simulate('[ACTION:REPLY_MESSAGE:ultimo:OK]');
      expect(replySim.riskLevel, RiskLevel.sensitive);
      expect(replySim.canDegradeToOffline, isFalse);
    });

    test('classifies hardware and local note operations as safe risk', () {
      final torchSim = gate.simulate('[ACTION:TORCH_ON]');
      expect(torchSim.riskLevel, RiskLevel.safe);
      expect(torchSim.requiresConfirmation, isFalse);
      expect(torchSim.canDegradeToOffline, isTrue);

      final volSim = gate.simulate('[ACTION:VOLUME_SET:75]');
      expect(volSim.riskLevel, RiskLevel.safe);

      final noteSim = gate.simulate('[ACTION:NOTE:Revisar protocolo]');
      expect(noteSim.riskLevel, RiskLevel.safe);
      expect(noteSim.canDegradeToOffline, isTrue);

      final skillSim = gate.simulate('[ACTION:SKILL:modo_estudo]');
      expect(skillSim.riskLevel, RiskLevel.safe);
    });
  });

  group('ActionGate Cryptographic Signatures', () {
    test('generates valid and reproducible HMAC-SHA256 signature', () {
      const payload = '{"command":"LOCK_WORKSTATION","source":"ULTRON_MOBILE"}';
      final sig1 = ActionGate.signPayload(payload);
      final sig2 = ActionGate.signPayload(payload);
      expect(sig1, sig2);
      expect(sig1.length, 64); // SHA-256 hex string

      // Modifying the payload changes the signature
      final sig3 = ActionGate.signPayload('$payload ');
      expect(sig1, isNot(equals(sig3)));
    });
  });
}
