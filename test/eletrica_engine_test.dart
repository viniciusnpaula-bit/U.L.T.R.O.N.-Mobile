import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/services/device_control_service.dart';
import 'package:ultron_mobile/services/eletrica_engine.dart';
import 'package:ultron_mobile/services/obsidian_service.dart';
import 'package:ultron_mobile/services/slash_command_parser.dart';

void main() {
  const engine = EletricaEngine();

  group('Marco 5 — EletricaEngine (NBR 5410, Inversores, Topologias & Auditoria)',
      () {
    test('sizes three-phase motor accurately with calculation memory', () {
      final s5cv380 = engine.sizeThreePhaseMotor(powerCv: 5.0, voltageV: 380);
      expect(s5cv380.powerKw, closeTo(3.68, 0.05));
      expect(s5cv380.nominalCurrentA, closeTo(7.65, 0.3));
      expect(s5cv380.cableSectionMm2, greaterThanOrEqualTo(1.5));
      expect(s5cv380.breakerA, greaterThanOrEqualTo(10));
      expect(s5cv380.contactorModel, isNotEmpty);
      expect(s5cv380.calculationNotes, contains('In ='));

      final s10cv220 = engine.sizeThreePhaseMotor(powerCv: 10.0, voltageV: 220);
      expect(s10cv220.nominalCurrentA, greaterThan(22.0));
      expect(s10cv220.cableSectionMm2, greaterThanOrEqualTo(6.0));
    });

    test('builds valid topologies with zero audit errors, Netlist and IEC SVG', () {
      for (final topo in MotorTopology.values) {
        final proj = engine.buildTopology(
          topology: topo,
          powerCv: 5.0,
          voltageV: 380,
          sequenceDelaySeconds: 10,
          inverterModel: topo == MotorTopology.reversao ? 'WEG CFW500' : 'Altus AD600M',
        );
        expect(proj.hasCriticalErrors, isFalse, reason: topo.name);
        expect(proj.auditIssues, isEmpty, reason: topo.name);

        final netlist = proj.exportNetlist();
        expect(netlist, contains('[COMPONENTES]'));
        expect(netlist, contains('[CONEXOES]'));
        expect(netlist, contains('[PARAMETROS_INVERSOR]'));

        final svg = proj.exportIecSvg();
        expect(svg, startsWith('<svg'));
        expect(svg, endsWith('</svg>'));
        expect(svg, contains('M3~'));
      }
    });

    test('auditCircuit detects short circuit, open coil, missing protection and missing interlock',
        () {
      const brokenComponents = <ElectricalComponent>[
        ElectricalComponent(
          id: 'K1',
          type: 'Contator',
          iecSymbol: 'KM',
          spec: 'CWM18',
          terminals: ['A1', 'A2', '21', '22'],
        ),
        ElectricalComponent(
          id: 'K2',
          type: 'Contator Reversão',
          iecSymbol: 'KM',
          spec: 'CWM18',
          terminals: ['A1', 'A2', '21', '22'],
        ),
        ElectricalComponent(
          id: 'M1',
          type: 'Motor',
          iecSymbol: 'M3~',
          spec: '5 CV',
          terminals: ['U1', 'V1', 'W1'],
        ),
      ];
      const brokenWires = <ElectricalWire>[
        // Direct short between L1 and L2!
        ElectricalWire(
          wireNumber: 'F0',
          fromTerminal: 'L1',
          toTerminal: 'L2',
          circuitType: 'forca',
        ),
        // K1.A1 connected, but K1.A2 left open (and K2 coil totally open, no interlock)
        ElectricalWire(
          wireNumber: 'C1',
          fromTerminal: 'S1.14',
          toTerminal: 'K1.A1',
          circuitType: 'comando',
        ),
      ];

      final issues = engine.auditCircuit(
        topology: MotorTopology.reversao,
        components: brokenComponents,
        wires: brokenWires,
      );
      final codes = issues.map((i) => i.code).toSet();
      expect(codes, contains('SHORT_CIRCUIT'));
      expect(codes, contains('OPEN_COIL'));
      expect(codes, contains('MISSING_PROTECTION'));
      expect(codes, contains('MISSING_INTERLOCK'));
    });

    test('parses /eletrica command and saves ficha + Netlist + SVG to Memoria/Engenharia/',
        () async {
      final parsed = SlashCommandParser.parse('/eletrica reversao 5 cv 380v cfw500');
      expect(parsed?.command, UltronCommand.eletrica);

      final vaultDir = await Directory.systemTemp.createTemp('ultron_eletrica_');
      addTearDown(() async {
        if (await vaultDir.exists()) await vaultDir.delete(recursive: true);
      });
      final vault = ObsidianService(vaultDir);
      await vault.initialize();

      final device = DeviceControlService(obsidianProvider: () async => vault);
      final res = await device.executeEletricaCommand(
        'reversao 5 cv 380v cfw500',
      );
      expect(res.handled, isTrue);
      expect(res.message, contains('Reversão'));
      expect(res.message, contains('P0401'));
      expect(res.message, contains('Memoria/Engenharia/Projeto_reversao_5_0CV_380V.md'));

      final saved = await vault.readNote(
        'Memoria/Engenharia/Projeto_reversao_5_0CV_380V.md',
      );
      expect(saved, contains('ULTRON_ELETRICA_NETLIST'));
      expect(saved, contains('<svg'));
    });
  });
}
