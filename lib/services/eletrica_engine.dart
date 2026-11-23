import 'dart:math' as math;

enum MotorTopology {
  partidaDireta,
  reversao,
  estrelaTriangulo,
  sequenciaMotores,
}

enum ElectricalAuditSeverity { error, warning }

class ElectricalAuditIssue {
  const ElectricalAuditIssue({
    required this.code,
    required this.severity,
    required this.message,
  });

  final String code;
  final ElectricalAuditSeverity severity;
  final String message;
}

class ElectricalComponent {
  const ElectricalComponent({
    required this.id,
    required this.type,
    required this.iecSymbol,
    required this.spec,
    required this.terminals,
  });

  final String id;
  final String type;
  final String iecSymbol;
  final String spec;
  final List<String> terminals;
}

class ElectricalWire {
  const ElectricalWire({
    required this.wireNumber,
    required this.fromTerminal,
    required this.toTerminal,
    required this.circuitType,
  });

  final String wireNumber;
  final String fromTerminal;
  final String toTerminal;
  final String circuitType; // 'forca' | 'comando'
}

class MotorSizingResult {
  const MotorSizingResult({
    required this.powerCv,
    required this.powerKw,
    required this.voltageV,
    required this.nominalCurrentA,
    required this.cableSectionMm2,
    required this.cableAmpacityA,
    required this.breakerA,
    required this.contactorModel,
    required this.thermalRelayRangeA,
    required this.calculationNotes,
  });

  final double powerCv;
  final double powerKw;
  final int voltageV;
  final double nominalCurrentA;
  final double cableSectionMm2;
  final double cableAmpacityA;
  final int breakerA;
  final String contactorModel;
  final String thermalRelayRangeA;
  final String calculationNotes;
}

class ElectricalCircuitProject {
  const ElectricalCircuitProject({
    required this.title,
    required this.topology,
    required this.sizing,
    required this.components,
    required this.wires,
    required this.auditIssues,
    required this.inverterParams,
    this.sequenceDelaySeconds = 0,
  });

  final String title;
  final MotorTopology topology;
  final MotorSizingResult sizing;
  final List<ElectricalComponent> components;
  final List<ElectricalWire> wires;
  final List<ElectricalAuditIssue> auditIssues;
  final Map<String, String> inverterParams;
  final int sequenceDelaySeconds;

  bool get hasCriticalErrors =>
      auditIssues.any((i) => i.severity == ElectricalAuditSeverity.error);

  /// Exporta Netlist estruturada em texto para conferência e apoio à montagem no CADe_SIMU.
  String exportNetlist() {
    final sb = StringBuffer()
      ..writeln('# ULTRON_ELETRICA_NETLIST v1.0')
      ..writeln('PROJETO: $title')
      ..writeln('TOPOLOGIA: ${topology.name}')
      ..writeln(
        'MOTOR: ${sizing.powerCv.toStringAsFixed(1)} CV (${sizing.powerKw.toStringAsFixed(2)} kW) · ${sizing.voltageV}V 3~ · In=${sizing.nominalCurrentA.toStringAsFixed(2)}A',
      )
      ..writeln(
        'DIMENSIONAMENTO_NBR5410: Cabo ${sizing.cableSectionMm2}mm2 (${sizing.cableAmpacityA}A) | Disjuntor ${sizing.breakerA}A | Contator ${sizing.contactorModel} | Rele ${sizing.thermalRelayRangeA}A',
      )
      ..writeln()
      ..writeln('[COMPONENTES]');
    for (final c in components) {
      sb.writeln(
        '${c.id} | ${c.type} | IEC:${c.iecSymbol} | ${c.spec} | Pinos:${c.terminals.join(',')}',
      );
    }
    sb
      ..writeln()
      ..writeln('[CONEXOES]');
    for (final w in wires) {
      sb.writeln(
        '${w.wireNumber} (${w.circuitType}): ${w.fromTerminal} -> ${w.toTerminal}',
      );
    }
    if (inverterParams.isNotEmpty) {
      sb
        ..writeln()
        ..writeln('[PARAMETROS_INVERSOR]');
      for (final e in inverterParams.entries) {
        sb.writeln('${e.key} = ${e.value}');
      }
    }
    sb
      ..writeln()
      ..writeln(
        '# Nota transparente: arquivo textual aberto para apoio ao CADe_SIMU; o .cad proprietário binário não é gerado no celular.',
      );
    return sb.toString().trim();
  }

  /// Gera diagrama esquemático simplificado em SVG (símbolos IEC) para preview/cofre.
  String exportIecSvg() {
    final height = 140 + (components.length * 46);
    final sb = StringBuffer()
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" width="520" height="$height" viewBox="0 0 520 $height">',
      )
      ..writeln(
        '  <rect width="100%" height="100%" fill="#0C0406" stroke="#51080D" stroke-width="2"/>',
      )
      ..writeln(
        '  <text x="16" y="28" fill="#E50914" font-family="monospace" font-size="14" font-weight="bold">${_escapeXml(title)}</text>',
      )
      ..writeln(
        '  <text x="16" y="48" fill="#FFA0A0" font-family="monospace" font-size="11">'
        '${sizing.powerCv.toStringAsFixed(1)} CV / ${sizing.voltageV}V · In=${sizing.nominalCurrentA.toStringAsFixed(2)}A · Cabo ${sizing.cableSectionMm2}mm2 · Q=${sizing.breakerA}A</text>',
      )
      ..writeln(
        '  <line x1="16" y1="60" x2="504" y2="60" stroke="#51080D" stroke-width="1"/>',
      );

    for (var i = 0; i < components.length; i++) {
      final c = components[i];
      final y = 84 + (i * 44);
      sb
        ..writeln(
          '  <rect x="24" y="$y" width="90" height="30" rx="4" fill="#210407" stroke="#E50914" stroke-width="1.2"/>',
        )
        ..writeln(
          '  <text x="69" y="${y + 19}" text-anchor="middle" fill="#FFFFFF" font-family="monospace" font-size="11" font-weight="bold">${_escapeXml(c.id)} (${_escapeXml(c.iecSymbol)})</text>',
        )
        ..writeln(
          '  <text x="128" y="${y + 13}" fill="#EADCDD" font-family="monospace" font-size="10">${_escapeXml(c.type)} — ${_escapeXml(c.spec)}</text>',
        )
        ..writeln(
          '  <text x="128" y="${y + 27}" fill="#A89698" font-family="monospace" font-size="9">Terminais: ${_escapeXml(c.terminals.join(', '))}</text>',
        );
      if (i < components.length - 1) {
        sb.writeln(
          '  <line x1="69" y1="${y + 30}" x2="69" y2="${y + 44}" stroke="#5CE69C" stroke-width="1.5"/>',
        );
      }
    }

    sb
      ..writeln(
        '  <text x="16" y="${height - 14}" fill="#8A7A7C" font-family="monospace" font-size="9">'
        'Auditoria estrutural: ${auditIssues.isEmpty ? 'OK (0 erros)' : '${auditIssues.length} alerta(s)'} · Sem simulação elétrica SPICE</text>',
      )
      ..writeln('</svg>');
    return sb.toString().trim();
  }

  String formatTechnicalSummary() {
    final auditText = auditIssues.isEmpty
        ? '✅ Auditoria estrutural: 0 erros (alimentação de bobinas, proteção e intertravamento verificados).'
        : auditIssues
            .map(
              (i) =>
                  '${i.severity == ElectricalAuditSeverity.error ? '🚨' : '⚠️'} [${i.code}] ${i.message}',
            )
            .join('\n');

    final invText = inverterParams.isEmpty
        ? ''
        : '\n\n🎛️ **Parâmetros de Inversor:**\n${inverterParams.entries.map((e) => '• `${e.key}`: ${e.value}').join('\n')}';

    return '⚡ **$title** (${topology.name})\n'
        '• **Motor:** ${sizing.powerCv.toStringAsFixed(1)} CV (${sizing.powerKw.toStringAsFixed(2)} kW) · ${sizing.voltageV}V 3~ · **In = ${sizing.nominalCurrentA.toStringAsFixed(2)} A**\n'
        '• **Cabo (NBR 5410 B1 PVC):** ${sizing.cableSectionMm2} mm² (ampacidade ${sizing.cableAmpacityA} A)\n'
        '• **Proteção / Manobra:** Disjuntor **${sizing.breakerA} A** · Contator **${sizing.contactorModel}** · Relé Térmico **${sizing.thermalRelayRangeA} A**\n'
        '• **Memória de cálculo:** ${sizing.calculationNotes}\n'
        '• **Componentes:** ${components.map((c) => c.id).join(', ')} (${wires.length} conexões)\n'
        '$auditText$invText\n\n'
        '_Escopo honesto: verificação estrutural + Netlist/SVG IEC gerados localmente; o formato `.cad` binário proprietário do CADe_SIMU não é gerado nem simulado eletricamente no celular._';
  }

  static String _escapeXml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

/// Motor offline de Engenharia Elétrica Industrial (Marco 5 — v2.0.0).
///
/// Fornece tabelas NBR 5410, dimensionamento de proteção/manobra, parâmetros de
/// inversores (WEG CFW500 / Altus AD600M), geração de topologias IEC, auditoria
/// estrutural e exportação Netlist/SVG para a Ponte CADe_SIMU.
class EletricaEngine {
  const EletricaEngine();

  /// Tabela simplificada NBR 5410 (Cobre PVC 70°C, Método B1, 3 condutores carregados).
  static const List<({double mm2, double ampacityA})> nbr5410B1Table = [
    (mm2: 1.5, ampacityA: 15.5),
    (mm2: 2.5, ampacityA: 21.0),
    (mm2: 4.0, ampacityA: 28.0),
    (mm2: 6.0, ampacityA: 36.0),
    (mm2: 10.0, ampacityA: 50.0),
    (mm2: 16.0, ampacityA: 68.0),
    (mm2: 25.0, ampacityA: 89.0),
    (mm2: 35.0, ampacityA: 110.0),
    (mm2: 50.0, ampacityA: 134.0),
    (mm2: 70.0, ampacityA: 171.0),
  ];

  static const List<int> standardBreakersA = [
    6,
    10,
    16,
    20,
    25,
    32,
    40,
    50,
    63,
    80,
    100,
    125,
    160,
  ];

  static const List<({int maxA, String model})> standardContactors = [
    (maxA: 9, model: 'CWM9'),
    (maxA: 12, model: 'CWM12'),
    (maxA: 18, model: 'CWM18'),
    (maxA: 25, model: 'CWM25'),
    (maxA: 32, model: 'CWM32'),
    (maxA: 40, model: 'CWM40'),
    (maxA: 50, model: 'CWM50'),
    (maxA: 65, model: 'CWM65'),
    (maxA: 80, model: 'CWM80'),
    (maxA: 105, model: 'CWM105'),
    (maxA: 150, model: 'CWM150'),
  ];

  static const List<({double minA, double maxA, String label})>
      standardThermalRelays = [
    (minA: 1.2, maxA: 1.8, label: 'RW27 1.2–1.8'),
    (minA: 1.8, maxA: 2.8, label: 'RW27 1.8–2.8'),
    (minA: 2.8, maxA: 4.0, label: 'RW27 2.8–4.0'),
    (minA: 4.0, maxA: 6.3, label: 'RW27 4.0–6.3'),
    (minA: 5.6, maxA: 8.0, label: 'RW27 5.6–8.0'),
    (minA: 7.0, maxA: 10.0, label: 'RW27 7.0–10.0'),
    (minA: 8.0, maxA: 12.5, label: 'RW27 8.0–12.5'),
    (minA: 11.0, maxA: 17.0, label: 'RW27 11–17'),
    (minA: 15.0, maxA: 23.0, label: 'RW27 15–23'),
    (minA: 22.0, maxA: 32.0, label: 'RW27 22–32'),
    (minA: 32.0, maxA: 40.0, label: 'RW67 32–40'),
    (minA: 40.0, maxA: 57.0, label: 'RW67 40–57'),
    (minA: 50.0, maxA: 63.0, label: 'RW67 50–63'),
    (minA: 63.0, maxA: 80.0, label: 'RW67 63–80'),
    (minA: 75.0, maxA: 97.0, label: 'RW117 75–97'),
  ];

  /// Dimensiona motor trifásico (NBR 5410) com memória de cálculo.
  MotorSizingResult sizeThreePhaseMotor({
    required double powerCv,
    int voltageV = 380,
    double efficiency = 0.86,
    double powerFactor = 0.85,
  }) {
    final safeCv = powerCv.clamp(0.25, 100.0);
    final safeV = (voltageV == 220 || voltageV == 380 || voltageV == 440)
        ? voltageV
        : 380;
    final powerKw = safeCv * 0.7355;
    final powerW = powerKw * 1000.0;
    final nominalA = powerW / (math.sqrt(3) * safeV * efficiency * powerFactor);
    final designA = nominalA * 1.25; // Fator de dimensionamento de cabo/proteção

    final cable = nbr5410B1Table.firstWhere(
      (c) => c.ampacityA >= designA,
      orElse: () => nbr5410B1Table.last,
    );
    final breaker = standardBreakersA.firstWhere(
      (b) => b >= designA && b <= cable.ampacityA * 1.15,
      orElse: () => standardBreakersA.firstWhere(
        (b) => b >= nominalA * 1.15,
        orElse: () => standardBreakersA.last,
      ),
    );
    final contactor = standardContactors.firstWhere(
      (c) => c.maxA >= nominalA * 1.15,
      orElse: () => standardContactors.last,
    );
    final relay = standardThermalRelays.firstWhere(
      (r) => nominalA >= r.minA && nominalA <= r.maxA,
      orElse: () => (
        minA: nominalA * 0.9,
        maxA: nominalA * 1.15,
        label:
            'Ajuste ${(nominalA * 0.9).toStringAsFixed(1)}–${(nominalA * 1.15).toStringAsFixed(1)}',
      ),
    );

    final notes =
        'In = ${powerW.toStringAsFixed(0)}W / (√3 × ${safeV}V × η=$efficiency × cosφ=$powerFactor) '
        '= ${nominalA.toStringAsFixed(2)}A; Id (1,25×In) = ${designA.toStringAsFixed(2)}A.';

    return MotorSizingResult(
      powerCv: safeCv,
      powerKw: powerKw,
      voltageV: safeV,
      nominalCurrentA: nominalA,
      cableSectionMm2: cable.mm2,
      cableAmpacityA: cable.ampacityA,
      breakerA: breaker,
      contactorModel: contactor.model,
      thermalRelayRangeA: relay.label,
      calculationNotes: notes,
    );
  }

  /// Gera tabela de parametrização básica para inversores WEG CFW500 ou Altus AD600M.
  Map<String, String> buildInverterParams({
    required String inverterModel,
    required MotorSizingResult sizing,
    double accelSec = 5.0,
    double decelSec = 5.0,
  }) {
    final upper = inverterModel.toUpperCase();
    if (upper.contains('AD600') || upper.contains('ALTUS')) {
      return <String, String>{
        'Modelo': 'Altus AD600M',
        'F00.01 (Comando)': 'Terminal / Remoto',
        'F01.01 (Tensão Motor)': '${sizing.voltageV} V',
        'F01.02 (Corrente Nominal)': '${sizing.nominalCurrentA.toStringAsFixed(2)} A',
        'F01.03 (Potência)': '${sizing.powerKw.toStringAsFixed(2)} kW',
        'F02.01 (Rampa Acel.)': '${accelSec.toStringAsFixed(1)} s',
        'F02.02 (Rampa Desac.)': '${decelSec.toStringAsFixed(1)} s',
      };
    }
    return <String, String>{
      'Modelo': 'WEG CFW500',
      'P0100 (Tempo Aceleração)': '${accelSec.toStringAsFixed(1)} s',
      'P0101 (Tempo Desaceleração)': '${decelSec.toStringAsFixed(1)} s',
      'P0133 / P0134 (Freq. Min/Max)': '5.0 Hz / 60.0 Hz',
      'P0400 (Tensão Nominal Motor)': '${sizing.voltageV} V',
      'P0401 (Corrente Nominal Motor)':
          '${sizing.nominalCurrentA.toStringAsFixed(2)} A',
      'P0404 (Potência Motor)': '${sizing.powerKw.toStringAsFixed(2)} kW',
    };
  }

  /// Monta uma topologia industrial completa e executa auditoria estrutural automática.
  ElectricalCircuitProject buildTopology({
    required MotorTopology topology,
    required double powerCv,
    int voltageV = 380,
    int sequenceDelaySeconds = 8,
    String? inverterModel,
  }) {
    final sizing = sizeThreePhaseMotor(powerCv: powerCv, voltageV: voltageV);
    final components = <ElectricalComponent>[
      ElectricalComponent(
        id: 'Q1',
        type: 'Disjuntor Tripolar',
        iecSymbol: 'QF',
        spec: '${sizing.breakerA}A Curva C/D',
        terminals: const ['1/L1', '3/L2', '5/L3', '2/T1', '4/T2', '6/T3'],
      ),
      const ElectricalComponent(
        id: 'Q2',
        type: 'Disjuntor Comando',
        iecSymbol: 'QF',
        spec: '6A Curva C (24V/220V)',
        terminals: ['1', '2'],
      ),
      const ElectricalComponent(
        id: 'S0',
        type: 'Botoeira Desliga (NF)',
        iecSymbol: 'SB-NF',
        spec: 'Emergência / Parada',
        terminals: ['11', '12'],
      ),
      const ElectricalComponent(
        id: 'S1',
        type: 'Botoeira Liga (NA)',
        iecSymbol: 'SB-NA',
        spec: 'Pulso de Partida',
        terminals: ['13', '14'],
      ),
      ElectricalComponent(
        id: 'FT1',
        type: 'Relé Térmico',
        iecSymbol: 'FR',
        spec: '${sizing.thermalRelayRangeA} A',
        terminals: const ['1', '3', '5', '2', '4', '6', '95', '96'],
      ),
      ElectricalComponent(
        id: 'K1',
        type: 'Contator Principal',
        iecSymbol: 'KM',
        spec: sizing.contactorModel,
        terminals: const ['1', '3', '5', '2', '4', '6', '13', '14', '21', '22', 'A1', 'A2'],
      ),
      ElectricalComponent(
        id: 'M1',
        type: 'Motor Trifásico 3~',
        iecSymbol: 'M3~',
        spec: '${sizing.powerCv.toStringAsFixed(1)} CV ${sizing.voltageV}V',
        terminals: const ['U1', 'V1', 'W1', 'PE'],
      ),
    ];

    final wires = <ElectricalWire>[
      const ElectricalWire(wireNumber: 'F1', fromTerminal: 'L1', toTerminal: 'Q1.1/L1', circuitType: 'forca'),
      const ElectricalWire(wireNumber: 'F2', fromTerminal: 'L2', toTerminal: 'Q1.3/L2', circuitType: 'forca'),
      const ElectricalWire(wireNumber: 'F3', fromTerminal: 'L3', toTerminal: 'Q1.5/L3', circuitType: 'forca'),
      const ElectricalWire(wireNumber: 'F4', fromTerminal: 'Q1.2/T1', toTerminal: 'K1.1', circuitType: 'forca'),
      const ElectricalWire(wireNumber: 'F5', fromTerminal: 'K1.2', toTerminal: 'FT1.1', circuitType: 'forca'),
      const ElectricalWire(wireNumber: 'F6', fromTerminal: 'FT1.2', toTerminal: 'M1.U1', circuitType: 'forca'),
      const ElectricalWire(wireNumber: 'C1', fromTerminal: 'L1', toTerminal: 'Q2.1', circuitType: 'comando'),
      const ElectricalWire(wireNumber: 'C2', fromTerminal: 'Q2.2', toTerminal: 'FT1.95', circuitType: 'comando'),
      const ElectricalWire(wireNumber: 'C3', fromTerminal: 'FT1.96', toTerminal: 'S0.11', circuitType: 'comando'),
      const ElectricalWire(wireNumber: 'C4', fromTerminal: 'S0.12', toTerminal: 'S1.13', circuitType: 'comando'),
      const ElectricalWire(wireNumber: 'C5', fromTerminal: 'S0.12', toTerminal: 'K1.13', circuitType: 'comando'),
    ];

    String title;
    switch (topology) {
      case MotorTopology.partidaDireta:
        title = 'Partida Direta com Selo (${sizing.powerCv.toStringAsFixed(1)} CV)';
        wires.addAll(const [
          ElectricalWire(wireNumber: 'C6', fromTerminal: 'S1.14', toTerminal: 'K1.A1', circuitType: 'comando'),
          ElectricalWire(wireNumber: 'C7', fromTerminal: 'K1.14', toTerminal: 'K1.A1', circuitType: 'comando'),
          ElectricalWire(wireNumber: 'C8', fromTerminal: 'K1.A2', toTerminal: 'N', circuitType: 'comando'),
        ]);
        break;

      case MotorTopology.reversao:
        title = 'Partida com Reversão e Intertravamento (${sizing.powerCv.toStringAsFixed(1)} CV)';
        components.addAll([
          const ElectricalComponent(
            id: 'S2',
            type: 'Botoeira Reverso (NA)',
            iecSymbol: 'SB-NA',
            spec: 'Sentido Anti-Horário',
            terminals: ['13', '14'],
          ),
          ElectricalComponent(
            id: 'K2',
            type: 'Contator Reversão',
            iecSymbol: 'KM',
            spec: sizing.contactorModel,
            terminals: const ['1', '3', '5', '2', '4', '6', '13', '14', '21', '22', 'A1', 'A2'],
          ),
        ]);
        wires.addAll(const [
          ElectricalWire(wireNumber: 'C6', fromTerminal: 'S1.14', toTerminal: 'K2.21', circuitType: 'comando'),
          ElectricalWire(wireNumber: 'C7', fromTerminal: 'K2.22', toTerminal: 'K1.A1', circuitType: 'comando'),
          ElectricalWire(wireNumber: 'C8', fromTerminal: 'K1.A2', toTerminal: 'N', circuitType: 'comando'),
          ElectricalWire(wireNumber: 'C9', fromTerminal: 'S0.12', toTerminal: 'S2.13', circuitType: 'comando'),
          ElectricalWire(wireNumber: 'C10', fromTerminal: 'S2.14', toTerminal: 'K1.21', circuitType: 'comando'),
          ElectricalWire(wireNumber: 'C11', fromTerminal: 'K1.22', toTerminal: 'K2.A1', circuitType: 'comando'),
          ElectricalWire(wireNumber: 'C12', fromTerminal: 'K2.A2', toTerminal: 'N', circuitType: 'comando'),
        ]);
        break;

      case MotorTopology.estrelaTriangulo:
        title = 'Partida Estrela-Triângulo (${sizing.powerCv.toStringAsFixed(1)} CV)';
        components.addAll([
          ElectricalComponent(
            id: 'K2',
            type: 'Contator Triângulo',
            iecSymbol: 'KM',
            spec: sizing.contactorModel,
            terminals: const ['1', '3', '5', '2', '4', '6', '21', '22', 'A1', 'A2'],
          ),
          ElectricalComponent(
            id: 'K3',
            type: 'Contator Estrela',
            iecSymbol: 'KM',
            spec: sizing.contactorModel,
            terminals: const ['1', '3', '5', '2', '4', '6', '21', '22', 'A1', 'A2'],
          ),
          const ElectricalComponent(
            id: 'KT1',
            type: 'Relé Temporizador Estrela-Triângulo',
            iecSymbol: 'KT',
            spec: '0.1–30s (ajuste 6s)',
            terminals: ['A1', 'A2', '15', '16', '18'],
          ),
        ]);
        wires.addAll(const [
          ElectricalWire(wireNumber: 'C6', fromTerminal: 'S1.14', toTerminal: 'K1.A1', circuitType: 'comando'),
          ElectricalWire(wireNumber: 'C7', fromTerminal: 'K1.14', toTerminal: 'KT1.A1', circuitType: 'comando'),
          ElectricalWire(wireNumber: 'C8', fromTerminal: 'KT1.16', toTerminal: 'K2.21', circuitType: 'comando'),
          ElectricalWire(wireNumber: 'C9', fromTerminal: 'K2.22', toTerminal: 'K3.A1', circuitType: 'comando'),
          ElectricalWire(wireNumber: 'C10', fromTerminal: 'KT1.18', toTerminal: 'K3.21', circuitType: 'comando'),
          ElectricalWire(wireNumber: 'C11', fromTerminal: 'K3.22', toTerminal: 'K2.A1', circuitType: 'comando'),
          ElectricalWire(wireNumber: 'C12', fromTerminal: 'K1.A2', toTerminal: 'N', circuitType: 'comando'),
          ElectricalWire(wireNumber: 'C13', fromTerminal: 'K2.A2', toTerminal: 'N', circuitType: 'comando'),
          ElectricalWire(wireNumber: 'C14', fromTerminal: 'K3.A2', toTerminal: 'N', circuitType: 'comando'),
          ElectricalWire(wireNumber: 'C15', fromTerminal: 'KT1.A2', toTerminal: 'N', circuitType: 'comando'),
        ]);
        break;

      case MotorTopology.sequenciaMotores:
        final delay = sequenceDelaySeconds.clamp(1, 300);
        title =
            'Sequência de 2 Motores (${sizing.powerCv.toStringAsFixed(1)} CV · M2 após ${delay}s)';
        components.addAll([
          ElectricalComponent(
            id: 'KT1',
            type: 'Temporizador On-Delay',
            iecSymbol: 'KT',
            spec: 'Ajuste ${delay}s',
            terminals: const ['A1', 'A2', '15', '18'],
          ),
          ElectricalComponent(
            id: 'K2',
            type: 'Contator Motor 2',
            iecSymbol: 'KM',
            spec: sizing.contactorModel,
            terminals: const ['1', '3', '5', '2', '4', '6', 'A1', 'A2'],
          ),
          ElectricalComponent(
            id: 'FT2',
            type: 'Relé Térmico M2',
            iecSymbol: 'FR',
            spec: '${sizing.thermalRelayRangeA} A',
            terminals: const ['1', '3', '5', '2', '4', '6', '95', '96'],
          ),
          ElectricalComponent(
            id: 'M2',
            type: 'Motor Trifásico 2 (3~)',
            iecSymbol: 'M3~',
            spec: '${sizing.powerCv.toStringAsFixed(1)} CV ${sizing.voltageV}V',
            terminals: const ['U1', 'V1', 'W1', 'PE'],
          ),
        ]);
        wires.addAll(const [
          ElectricalWire(wireNumber: 'C6', fromTerminal: 'S1.14', toTerminal: 'K1.A1', circuitType: 'comando'),
          ElectricalWire(wireNumber: 'C7', fromTerminal: 'K1.14', toTerminal: 'KT1.A1', circuitType: 'comando'),
          ElectricalWire(wireNumber: 'C8', fromTerminal: 'KT1.18', toTerminal: 'FT2.95', circuitType: 'comando'),
          ElectricalWire(wireNumber: 'C9', fromTerminal: 'FT2.96', toTerminal: 'K2.A1', circuitType: 'comando'),
          ElectricalWire(wireNumber: 'C10', fromTerminal: 'K1.A2', toTerminal: 'N', circuitType: 'comando'),
          ElectricalWire(wireNumber: 'C11', fromTerminal: 'KT1.A2', toTerminal: 'N', circuitType: 'comando'),
          ElectricalWire(wireNumber: 'C12', fromTerminal: 'K2.A2', toTerminal: 'N', circuitType: 'comando'),
        ]);
        break;
    }

    final issues = auditCircuit(
      topology: topology,
      components: components,
      wires: wires,
    );
    final inv = (inverterModel != null && inverterModel.trim().isNotEmpty)
        ? buildInverterParams(inverterModel: inverterModel, sizing: sizing)
        : const <String, String>{};

    return ElectricalCircuitProject(
      title: title,
      topology: topology,
      sizing: sizing,
      components: components,
      wires: wires,
      auditIssues: issues,
      inverterParams: inv,
      sequenceDelaySeconds: sequenceDelaySeconds,
    );
  }

  /// Auditoria estrutural de circuito: curto na fonte, bobina aberta, falta de proteção
  /// e falta de intertravamento elétrico em reversão / estrela-triângulo.
  List<ElectricalAuditIssue> auditCircuit({
    required MotorTopology topology,
    required List<ElectricalComponent> components,
    required List<ElectricalWire> wires,
  }) {
    final issues = <ElectricalAuditIssue>[];

    // 1. Curto direto na fonte (L1->L2, L1->L3, L2->L3, L1->N)
    const supplyNodes = {'L1', 'L2', 'L3', 'N'};
    for (final w in wires) {
      final a = w.fromTerminal.trim().toUpperCase();
      final b = w.toTerminal.trim().toUpperCase();
      if (supplyNodes.contains(a) && supplyNodes.contains(b) && a != b) {
        issues.add(
          ElectricalAuditIssue(
            code: 'SHORT_CIRCUIT',
            severity: ElectricalAuditSeverity.error,
            message:
                'Curto-circuito direto na fonte detectado no fio ${w.wireNumber} ($a -> $b).',
          ),
        );
      }
    }

    // 2. Bobinas sem alimentação (todo componente com A1 e A2 precisa dos dois conectados)
    final connected = <String>{};
    for (final w in wires) {
      connected.add(w.fromTerminal.trim().toUpperCase());
      connected.add(w.toTerminal.trim().toUpperCase());
    }
    for (final c in components) {
      final hasCoil = c.terminals.contains('A1') && c.terminals.contains('A2');
      if (!hasCoil) continue;
      final a1Ok = connected.contains('${c.id.toUpperCase()}.A1');
      final a2Ok = connected.contains('${c.id.toUpperCase()}.A2');
      if (!a1Ok || !a2Ok) {
        issues.add(
          ElectricalAuditIssue(
            code: 'OPEN_COIL',
            severity: ElectricalAuditSeverity.error,
            message:
                'Bobina de ${c.id} sem alimentação completa (A1=${a1Ok ? 'OK' : 'ABERTO'}, A2=${a2Ok ? 'OK' : 'ABERTO'}).',
          ),
        );
      }
    }

    // 3. Falta de proteção (motor sem disjuntor QF ou sem relé térmico FR)
    final hasMotor = components.any((c) => c.iecSymbol == 'M3~');
    final hasBreaker = components.any((c) => c.iecSymbol == 'QF');
    final hasThermal = components.any((c) => c.iecSymbol == 'FR');
    if (hasMotor && (!hasBreaker || !hasThermal)) {
      issues.add(
        ElectricalAuditIssue(
          code: 'MISSING_PROTECTION',
          severity: ElectricalAuditSeverity.error,
          message:
              'Motor sem proteção completa (Disjuntor=${hasBreaker ? 'OK' : 'AUSENTE'}, Relé Térmico=${hasThermal ? 'OK' : 'AUSENTE'}).',
        ),
      );
    }

    // 4. Intertravamento obrigatório em Reversão (K1/K2) e Estrela-Triângulo (K2/K3)
    if (topology == MotorTopology.reversao) {
      final hasK1Nf =
          connected.contains('K1.21') && connected.contains('K1.22');
      final hasK2Nf =
          connected.contains('K2.21') && connected.contains('K2.22');
      if (!hasK1Nf || !hasK2Nf) {
        issues.add(
          const ElectricalAuditIssue(
            code: 'MISSING_INTERLOCK',
            severity: ElectricalAuditSeverity.error,
            message:
                'Falta intertravamento elétrico cruzado (NF 21-22) entre K1 e K2 na partida com reversão.',
          ),
        );
      }
    } else if (topology == MotorTopology.estrelaTriangulo) {
      final hasK2Nf =
          connected.contains('K2.21') && connected.contains('K2.22');
      final hasK3Nf =
          connected.contains('K3.21') && connected.contains('K3.22');
      if (!hasK2Nf || !hasK3Nf) {
        issues.add(
          const ElectricalAuditIssue(
            code: 'MISSING_INTERLOCK',
            severity: ElectricalAuditSeverity.error,
            message:
                'Falta intertravamento elétrico cruzado (NF 21-22) entre K2 (Triângulo) e K3 (Estrela).',
          ),
        );
      }
    }

    return issues;
  }

  /// Interpreta um pedido em português (ex.: `"reversao 5 cv 380v cfw500"`).
  ElectricalCircuitProject designFromNaturalPrompt(String rawPrompt) {
    final lower = rawPrompt.trim().toLowerCase();
    MotorTopology topology = MotorTopology.partidaDireta;
    if (lower.contains('revers')) {
      topology = MotorTopology.reversao;
    } else if (lower.contains('estrela') || lower.contains('triang') || lower.contains('triâng')) {
      topology = MotorTopology.estrelaTriangulo;
    } else if (lower.contains('sequenc') || lower.contains('sequênc') || lower.contains('dois motores') || lower.contains('2 motores')) {
      topology = MotorTopology.sequenciaMotores;
    }

    double powerCv = 5.0;
    final cvMatch =
        RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:cv|hp)\b', caseSensitive: false)
            .firstMatch(lower);
    if (cvMatch != null) {
      powerCv = double.tryParse(cvMatch.group(1)!.replaceAll(',', '.')) ?? 5.0;
    } else {
      final kwMatch =
          RegExp(r'(\d+(?:[.,]\d+)?)\s*kw\b', caseSensitive: false)
              .firstMatch(lower);
      if (kwMatch != null) {
        final kw =
            double.tryParse(kwMatch.group(1)!.replaceAll(',', '.')) ?? 3.7;
        powerCv = kw / 0.7355;
      }
    }

    var voltageV = 380;
    if (lower.contains('220')) {
      voltageV = 220;
    } else if (lower.contains('440')) {
      voltageV = 440;
    }

    var delayS = 8;
    final delayMatch =
        RegExp(r'(\d+)\s*(?:s|seg|segundos?)\b', caseSensitive: false)
            .firstMatch(lower);
    if (delayMatch != null) {
      delayS = int.tryParse(delayMatch.group(1)!) ?? 8;
    }

    String? inverter;
    if (lower.contains('cfw500') || lower.contains('weg')) {
      inverter = 'WEG CFW500';
    } else if (lower.contains('ad600') || lower.contains('altus')) {
      inverter = 'Altus AD600M';
    }

    return buildTopology(
      topology: topology,
      powerCv: powerCv,
      voltageV: voltageV,
      sequenceDelaySeconds: delayS,
      inverterModel: inverter,
    );
  }
}
