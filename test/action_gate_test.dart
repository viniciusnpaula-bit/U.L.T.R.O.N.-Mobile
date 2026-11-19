import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/core/security/action_gate.dart';

void main() {
  const gate = ActionGate();

  group('ActionGate Risk Classification', () {
    test(
        'classifies KILL_SWITCH and CLEAR_HISTORY as critical risk requiring confirmation',
        () {
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

    test(
        'classifies WHATSAPP, SMS, REPLY_MESSAGE, DIAL, and PC_RUN_SKILL as sensitive requiring confirmation',
        () {
      final waSim = gate.simulate('[ACTION:WHATSAPP:Carlos:Chegando]');
      expect(waSim.riskLevel, RiskLevel.sensitive);
      expect(waSim.requiresConfirmation, isTrue);
      expect(waSim.targetResource, contains('Carlos'));

      final smsSim = gate.simulate('[ACTION:SMS:1199999999:Teste]');
      expect(smsSim.riskLevel, RiskLevel.sensitive);
      expect(smsSim.requiresConfirmation, isTrue);

      final replySim = gate.simulate('[ACTION:REPLY_MESSAGE:ultimo:OK]');
      expect(replySim.riskLevel, RiskLevel.sensitive);
      expect(replySim.requiresConfirmation, isTrue);
      expect(replySim.canDegradeToOffline, isFalse);

      final dialSim = gate.simulate('[ACTION:DIAL:11999999999]');
      expect(dialSim.riskLevel, RiskLevel.sensitive);
      expect(dialSim.requiresConfirmation, isTrue);

      final pcSkillSim = gate.simulate('PC_RUN_SKILL:backup');
      expect(pcSkillSim.riskLevel, RiskLevel.sensitive);
      expect(pcSkillSim.requiresConfirmation, isTrue);

      final pcPingSim = gate.simulate('PING');
      expect(pcPingSim.riskLevel, RiskLevel.safe);
      expect(pcPingSim.requiresConfirmation, isFalse);

      final createEventSim = gate.simulate('CREATE_EVENT:Daily:20/11 09:00');
      expect(createEventSim.riskLevel, RiskLevel.sensitive);
      expect(createEventSim.requiresConfirmation, isTrue);

      final readCalSim = gate.simulate('READ_CALENDAR');
      expect(readCalSim.riskLevel, RiskLevel.safe);
      expect(readCalSim.requiresConfirmation, isFalse);

      final httpPostSim = gate.simulate(
          '[ACTION:HTTP_POST:http://192.168.1.50:8123/api/webhook/luz|{"on":true}]');
      expect(httpPostSim.riskLevel, RiskLevel.sensitive);
      expect(httpPostSim.requiresConfirmation, isTrue);

      final httpGetLanSim = gate
          .simulate('[ACTION:HTTP_GET:http://192.168.1.50:8123/api/states]');
      expect(httpGetLanSim.riskLevel, RiskLevel.safe);
      expect(httpGetLanSim.requiresConfirmation, isFalse);

      final httpGetPublicSim =
          gate.simulate('[ACTION:HTTP_GET:https://example.com/hook]');
      expect(httpGetPublicSim.riskLevel, RiskLevel.sensitive);
      expect(httpGetPublicSim.requiresConfirmation, isTrue);
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
    test(
        'generates valid and reproducible HMAC-SHA256 signature and rejects empty secret',
        () {
      const payload = '{"command":"LOCK_WORKSTATION","source":"ULTRON_MOBILE"}';
      final sig1 = ActionGate.signPayload(payload, secret: 'custom-lan-secret');
      final sig2 = ActionGate.signPayload(payload, secret: 'custom-lan-secret');
      expect(sig1, sig2);
      expect(sig1.length, 64); // SHA-256 hex string

      // Modifying the payload changes the signature
      final sig3 =
          ActionGate.signPayload('$payload ', secret: 'custom-lan-secret');
      expect(sig1, isNot(equals(sig3)));

      // Empty secret fails closed
      expect(
        () => ActionGate.signPayload(payload, secret: '   '),
        throwsArgumentError,
      );
    });
  });
}
