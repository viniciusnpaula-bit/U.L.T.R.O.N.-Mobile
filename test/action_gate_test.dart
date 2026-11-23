import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/core/security/action_gate.dart';
import 'package:ultron_mobile/core/security/auth_gate.dart';

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

      final metadataAwsSim = gate
          .simulate('[ACTION:HTTP_GET:http://169.254.169.254/latest/meta-data]');
      expect(metadataAwsSim.riskLevel, RiskLevel.critical);
      expect(metadataAwsSim.requiresConfirmation, isTrue);
      expect(ActionGate.isPrivateLanUrl('http://169.254.169.254/latest/meta-data'),
          isFalse);

      final metadataGcpSim = gate.simulate(
          '[ACTION:HTTP_GET:http://metadata.google.internal/computeMetadata/v1]');
      expect(metadataGcpSim.riskLevel, RiskLevel.critical);
      expect(metadataGcpSim.requiresConfirmation, isTrue);

      final metadataPostSim = gate.simulate(
          '[ACTION:HTTP_POST:http://169.254.169.254/latest/api/token|{}]');
      expect(metadataPostSim.riskLevel, RiskLevel.critical);
      expect(metadataPostSim.requiresConfirmation, isTrue);

      expect(ActionGate.isBlockedMetadataHost('169.254.169.254'), isTrue);
      expect(ActionGate.isBlockedMetadataHost('0.0.0.0'), isTrue);
      expect(ActionGate.isBlockedMetadataHost('[fe80::1]'), isTrue);
      expect(ActionGate.isBlockedMetadataHost('192.168.1.50'), isFalse);
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

    test(
        'classifies OBSIDIAN_*, UNDO, REMINDER_*, and CANCEL_EVENT according to Phase 1 security policy',
        () {
      // Read actions -> RiskLevel.safe
      for (final tag in [
        '[ACTION:OBSIDIAN_LIST:Memoria]',
        '[ACTION:OBSIDIAN_READ:Memoria/Operador.md]',
        '[ACTION:OBSIDIAN_STATUS]',
        '[ACTION:REMINDER_LIST]',
      ]) {
        final sim = gate.simulate(tag);
        expect(sim.riskLevel, RiskLevel.safe, reason: tag);
        expect(sim.requiresConfirmation, isFalse, reason: tag);
        expect(sim.canDegradeToOffline, isTrue, reason: tag);
      }

      // Local vault mutations & reminders -> RiskLevel.safe (offline-capable, reversible via UNDO)
      for (final tag in [
        '[ACTION:OBSIDIAN_APPEND:Memoria/Operador.md:Novo item]',
        '[ACTION:OBSIDIAN_TASKS:marcar:1]',
        '[ACTION:UNDO]',
        '[ACTION:REMINDER_CREATE:daqui 15 min:Hidratar]',
        '[ACTION:REMINDER_CANCEL:1]',
      ]) {
        final sim = gate.simulate(tag);
        expect(sim.riskLevel, RiskLevel.safe, reason: tag);
        expect(sim.requiresConfirmation, isFalse, reason: tag);
      }

      // CANCEL_EVENT -> RiskLevel.sensitive requiring confirmation
      final cancelEventSim =
          gate.simulate('[ACTION:CANCEL_EVENT:Reunião Tática]');
      expect(cancelEventSim.actionCode, 'CANCEL_EVENT');
      expect(cancelEventSim.riskLevel, RiskLevel.sensitive);
      expect(cancelEventSim.requiresConfirmation, isTrue);
      expect(cancelEventSim.targetResource, contains('Reunião Tática'));

      // Phase 2: WEATHER, NEWS, WEB_SEARCH, FLOW_LIST, FLOW_RUN -> RiskLevel.safe
      for (final tag in [
        '[ACTION:WEATHER:São Paulo]',
        '[ACTION:NEWS:tecnologia]',
        '[ACTION:WEB_SEARCH:computação quântica]',
        '[ACTION:FLOW_LIST]',
        '[ACTION:FLOW_RUN:rotina_manha]',
      ]) {
        final sim = gate.simulate(tag);
        expect(sim.riskLevel, RiskLevel.safe, reason: tag);
        expect(sim.requiresConfirmation, isFalse, reason: tag);
      }

      // Phase 2: SKILL_CREATE, SKILL_DELETE, FLOW_CREATE, FLOW_SCHEDULE, FLOW_DELETE -> RiskLevel.sensitive
      final skillCreateSim = gate
          .simulate('[ACTION:SKILL_CREATE:modo_tatico|[ACTION:TORCH_ON]]');
      expect(skillCreateSim.riskLevel, RiskLevel.sensitive);
      expect(skillCreateSim.requiresConfirmation, isTrue);

      final skillDeleteSim = gate.simulate('[ACTION:SKILL_DELETE:modo_tatico]');
      expect(skillDeleteSim.riskLevel, RiskLevel.sensitive);
      expect(skillDeleteSim.requiresConfirmation, isTrue);

      // SKILL_DELETE always confirms even in sovereign (Biometric) mode
      final sovereignDeleteDecision = gate.evaluatePrivilege(
        skillDeleteSim,
        AccessLevel.sovereign,
      );
      expect(sovereignDeleteDecision.allowed, isTrue);
      expect(sovereignDeleteDecision.requiresConfirmation, isTrue);

      // Phase 3: SPOTIFY_SEARCH, SPOTIFY_STATE, SPOTIFY_PLAY, SPOTIFY_PLAYLISTS, SPOTIFY_ADD_PLAYLIST -> RiskLevel.safe
      for (final tag in [
        '[ACTION:SPOTIFY_SEARCH:Daft Punk]',
        '[ACTION:SPOTIFY_STATE]',
        '[ACTION:SPOTIFY_PLAY:Starboy]',
        '[ACTION:SPOTIFY_PLAYLISTS]',
        '[ACTION:SPOTIFY_ADD_PLAYLIST:Treino|spotify:track:123]',
      ]) {
        final sim = gate.simulate(tag);
        expect(sim.riskLevel, RiskLevel.safe, reason: tag);
        expect(sim.requiresConfirmation, isFalse, reason: tag);
      }
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

  group('3-Stage Privilege Evaluation (PIN / NFC / Biometric)', () {
    test('PIN (basic) only allows safe local actions', () {
      final safe = gate.evaluatePrivilege(
        gate.simulate('[ACTION:TORCH_ON]'),
        AccessLevel.basic,
      );
      expect(safe.allowed, isTrue);
      expect(safe.requiresConfirmation, isFalse);

      final wa = gate.evaluatePrivilege(
        gate.simulate('[ACTION:WHATSAPP:Carlos:Oi]'),
        AccessLevel.basic,
      );
      expect(wa.allowed, isFalse);
      expect(wa.requiredLevel, AccessLevel.elevated);

      final pc = gate.evaluatePrivilege(
        gate.simulate('PC_OPEN_APP:chrome'),
        AccessLevel.basic,
      );
      expect(pc.allowed, isFalse);
      expect(pc.requiredLevel, AccessLevel.sovereign);

      final ks = gate.evaluatePrivilege(
        gate.simulate('KILL_SWITCH'),
        AccessLevel.basic,
      );
      expect(ks.allowed, isFalse);
      expect(ks.requiredLevel, AccessLevel.sovereign);
    });

    test('NFC (elevated) unlocks mobile sensitive actions but blocks Desktop and critical',
        () {
      final wa = gate.evaluatePrivilege(
        gate.simulate('[ACTION:WHATSAPP:Carlos:Oi]'),
        AccessLevel.elevated,
      );
      expect(wa.allowed, isTrue);
      expect(wa.requiresConfirmation, isTrue);

      final pc = gate.evaluatePrivilege(
        gate.simulate('PC_OPEN_APP:chrome'),
        AccessLevel.elevated,
      );
      expect(pc.allowed, isFalse);
      expect(pc.requiredLevel, AccessLevel.sovereign);

      final pcPing = gate.evaluatePrivilege(
        gate.simulate('PING'),
        AccessLevel.elevated,
      );
      expect(pcPing.allowed, isFalse);
      expect(pcPing.requiredLevel, AccessLevel.sovereign);

      final clear = gate.evaluatePrivilege(
        gate.simulate('CLEAR_HISTORY'),
        AccessLevel.elevated,
      );
      expect(clear.allowed, isFalse);
      expect(clear.requiredLevel, AccessLevel.sovereign);
    });

    test('Biometric (sovereign) skips confirmation on normal/sensitive/Desktop and confirms only critical',
        () {
      final wa = gate.evaluatePrivilege(
        gate.simulate('[ACTION:WHATSAPP:Carlos:Oi]'),
        AccessLevel.sovereign,
      );
      expect(wa.allowed, isTrue);
      expect(wa.requiresConfirmation, isFalse);

      final pc = gate.evaluatePrivilege(
        gate.simulate('PC_OPEN_APP:chrome'),
        AccessLevel.sovereign,
      );
      expect(pc.allowed, isTrue);
      expect(pc.requiresConfirmation, isFalse);

      final ks = gate.evaluatePrivilege(
        gate.simulate('KILL_SWITCH'),
        AccessLevel.sovereign,
      );
      expect(ks.allowed, isTrue);
      expect(ks.requiresConfirmation, isTrue);

      final clear = gate.evaluatePrivilege(
        gate.simulate('CLEAR_HISTORY'),
        AccessLevel.sovereign,
      );
      expect(clear.allowed, isTrue);
      expect(clear.requiresConfirmation, isTrue);
    });

    test(
        'Phase 4 Desktop LAN commands all require AccessLevel.sovereign (Biometric) and PC_EXEC_TOOL confirms on ALTO/CRITICO risk',
        () {
      const desktopCommands = <String>[
        '[ACTION:PC_THERMAL]',
        '[ACTION:PC_POWER_PLAN:high_performance]',
        '[ACTION:PC_APP_VOLUME:spotify:50]',
        '[ACTION:PC_KILL_FROZEN]',
        '[ACTION:PC_BACKUP]',
        '[ACTION:PC_CLEAN_DISK]',
        '[ACTION:PC_EJECT_USB]',
        '[ACTION:PC_EXEC_TOOL:listar_processos|{"limit":5}]',
      ];

      for (final tag in desktopCommands) {
        final sim = gate.simulate(tag);
        expect(gate.requiredLevelFor(sim), AccessLevel.sovereign, reason: tag);

        // Blocked on basic (PIN) and elevated (NFC)
        expect(
          gate.evaluatePrivilege(sim, AccessLevel.basic).allowed,
          isFalse,
          reason: '$tag on basic',
        );
        expect(
          gate.evaluatePrivilege(sim, AccessLevel.elevated).allowed,
          isFalse,
          reason: '$tag on elevated',
        );

        // Allowed on sovereign (Biometric) without extra friction for standard tools
        final sov = gate.evaluatePrivilege(sim, AccessLevel.sovereign);
        expect(sov.allowed, isTrue, reason: '$tag on sovereign');
        expect(sov.requiresConfirmation, isFalse, reason: '$tag frictionless on sovereign');
      }

      // PC_EXEC_TOOL with ALTO or CRITICO risk -> RiskLevel.critical -> requires explicit confirmation even in sovereign mode
      final highRiskTool = gate.simulate(
        '[ACTION:PC_EXEC_TOOL:encerrar_apps_travados|ALTO|{"force":true}]',
      );
      expect(highRiskTool.riskLevel, RiskLevel.critical);
      final sovHigh =
          gate.evaluatePrivilege(highRiskTool, AccessLevel.sovereign);
      expect(sovHigh.allowed, isTrue);
      expect(sovHigh.requiresConfirmation, isTrue);

      final criticalTool = gate.simulate(
        '[ACTION:PC_EXEC_TOOL:format_temp_partition|CRITICO|{}]',
      );
      expect(criticalTool.riskLevel, RiskLevel.critical);
      final sovCrit =
          gate.evaluatePrivilege(criticalTool, AccessLevel.sovereign);
      expect(sovCrit.allowed, isTrue);
      expect(sovCrit.requiresConfirmation, isTrue);

      // Phase 5: create_mini_app is always critical and requires explicit confirmation even in sovereign
      final miniAppSim = gate.simulate(
        '[ACTION:PC_EXEC_TOOL:create_mini_app|{"title":"Conversor Ohm","runtime":"html"}]',
      );
      expect(miniAppSim.riskLevel, RiskLevel.critical);
      expect(miniAppSim.description, contains('Mini-App'));
      expect(
        gate.evaluatePrivilege(miniAppSim, AccessLevel.elevated).allowed,
        isFalse,
      );
      final sovMiniApp =
          gate.evaluatePrivilege(miniAppSim, AccessLevel.sovereign);
      expect(sovMiniApp.allowed, isTrue);
      expect(sovMiniApp.requiresConfirmation, isTrue);
    });
  });
}
