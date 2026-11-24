import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/eletrica_engine.dart';
import '../theme/ultron_theme.dart';

/// Seção Engenharia: dimensionamento elétrico offline (NBR 5410), inversores e topologias IEC.
class EngineeringSection extends StatefulWidget {
  const EngineeringSection({
    super.key,
    required this.onRunSlashCommand,
  });

  final Future<void> Function(String slashCommand) onRunSlashCommand;

  @override
  State<EngineeringSection> createState() => _EngineeringSectionState();
}

class _EngineeringSectionState extends State<EngineeringSection> {
  static const _engine = EletricaEngine();

  final TextEditingController _powerController =
      TextEditingController(text: '5');
  MotorTopology _topology = MotorTopology.partidaDireta;
  int _voltageV = 380;
  String? _inverterModel;
  late ElectricalCircuitProject _project;

  @override
  void initState() {
    super.initState();
    _project = _buildProject();
  }

  @override
  void dispose() {
    _powerController.dispose();
    super.dispose();
  }

  ElectricalCircuitProject _buildProject() {
    final parsed =
        double.tryParse(_powerController.text.replaceAll(',', '.').trim()) ??
            5.0;
    return _engine.buildTopology(
      topology: _topology,
      powerCv: parsed,
      voltageV: _voltageV,
      inverterModel: _inverterModel,
    );
  }

  void _recalculate() {
    setState(() => _project = _buildProject());
  }

  void _copyToClipboard(String content, String label) {
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copiado para a área de transferência.')),
    );
  }

  static String _topologyLabel(MotorTopology t) => switch (t) {
        MotorTopology.partidaDireta => 'Partida direta',
        MotorTopology.reversao => 'Reversão',
        MotorTopology.estrelaTriangulo => 'Estrela-triângulo',
        MotorTopology.sequenciaMotores => 'Sequência 2 motores',
      };

  @override
  Widget build(BuildContext context) {
    final s = _project.sizing;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const UltronSectionLabel('Parâmetros do motor'),
        UltronSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _powerController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _recalculate(),
                      style: UltronTheme.mono.copyWith(
                        color: UltronColors.textPrimary,
                        fontSize: 14,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Potência (CV)',
                        labelStyle: TextStyle(
                          color: UltronColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _voltageV,
                      dropdownColor: UltronColors.surfaceElevated,
                      decoration: const InputDecoration(
                        labelText: 'Tensão trifásica',
                        labelStyle: TextStyle(
                          color: UltronColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 220, child: Text('220 V')),
                        DropdownMenuItem(value: 380, child: Text('380 V')),
                        DropdownMenuItem(value: 440, child: Text('440 V')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        _voltageV = v;
                        _recalculate();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Topologia',
                style: TextStyle(
                  color: UltronColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: MotorTopology.values.map((t) {
                  final selected = _topology == t;
                  return ChoiceChip(
                    label: Text(_topologyLabel(t)),
                    selected: selected,
                    onSelected: (_) {
                      _topology = t;
                      _recalculate();
                    },
                    selectedColor: UltronColors.surfaceElevated,
                    backgroundColor: UltronColors.surface,
                    side: BorderSide(
                      color: selected
                          ? UltronColors.textSecondary
                          : UltronColors.borderSubtle,
                    ),
                    labelStyle: TextStyle(
                      color: selected
                          ? UltronColors.textPrimary
                          : UltronColors.textSecondary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 12,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              const Text(
                'Inversor de frequência (opcional)',
                style: TextStyle(
                  color: UltronColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  (null, 'Nenhum'),
                  ('CFW500', 'WEG CFW500'),
                  ('AD600M', 'Altus AD600M'),
                ].map((opt) {
                  final selected = _inverterModel == opt.$1;
                  return ChoiceChip(
                    label: Text(opt.$2),
                    selected: selected,
                    onSelected: (_) {
                      _inverterModel = opt.$1;
                      _recalculate();
                    },
                    selectedColor: UltronColors.surfaceElevated,
                    backgroundColor: UltronColors.surface,
                    side: BorderSide(
                      color: selected
                          ? UltronColors.textSecondary
                          : UltronColors.borderSubtle,
                    ),
                    labelStyle: TextStyle(
                      color: selected
                          ? UltronColors.textPrimary
                          : UltronColors.textSecondary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 12,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const UltronSectionLabel('Dimensionamento NBR 5410 (Método B1)'),
        UltronSurfaceCard(
          highlighted: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MetricRow(
                label: 'Corrente nominal (In)',
                value: '${s.nominalCurrentA.toStringAsFixed(2)} A',
                accent: UltronColors.crimson,
              ),
              _MetricRow(
                label: 'Potência',
                value:
                    '${s.powerCv.toStringAsFixed(1)} CV (${s.powerKw.toStringAsFixed(2)} kW)',
              ),
              _MetricRow(
                label: 'Condutor cobre PVC',
                value: '${s.cableSectionMm2} mm² (${s.cableAmpacityA} A)',
              ),
              _MetricRow(
                label: 'Disjuntor tripolar',
                value: '${s.breakerA} A',
              ),
              _MetricRow(
                label: 'Contator principal',
                value: s.contactorModel,
              ),
              _MetricRow(
                label: 'Relé térmico',
                value: '${s.thermalRelayRangeA} A',
                isLast: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const UltronSectionLabel('Auditoria estrutural'),
        UltronSurfaceCard(
          child: _project.auditIssues.isEmpty
              ? const Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                      color: UltronColors.positive,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Sem falhas estruturais detectadas (proteção, bobinas e intertravamento conferidos).',
                        style: TextStyle(
                          color: UltronColors.textPrimary,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  children: _project.auditIssues
                      .map(
                        (i) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                i.severity == ElectricalAuditSeverity.error
                                    ? Icons.error_outline_rounded
                                    : Icons.warning_amber_rounded,
                                size: 16,
                                color: i.severity ==
                                        ElectricalAuditSeverity.error
                                    ? UltronColors.crimson
                                    : UltronColors.warning,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${i.code}: ${i.message}',
                                  style: const TextStyle(
                                    color: UltronColors.textPrimary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
        if (_project.inverterParams.isNotEmpty) ...[
          const SizedBox(height: 14),
          const UltronSectionLabel('Parametrização do inversor'),
          UltronSurfaceCard(
            child: Column(
              children: _project.inverterParams.entries
                  .map(
                    (e) => _MetricRow(
                      label: e.key,
                      value: e.value,
                      isLast: e.key == _project.inverterParams.keys.last,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
        const SizedBox(height: 14),
        const UltronSectionLabel('Exportação e Ponte CADe_SIMU'),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    _copyToClipboard(_project.exportNetlist(), 'Netlist IEC'),
                icon: const Icon(Icons.code_rounded, size: 16),
                label: const Text('Copiar Netlist'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    _copyToClipboard(_project.exportIecSvg(), 'Diagrama SVG'),
                icon: const Icon(Icons.schema_outlined, size: 16),
                label: const Text('Copiar SVG'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => widget.onRunSlashCommand(
              '/eletrica ${_topologyLabel(_topology)} ${_powerController.text.trim()}cv ${_voltageV}v${_inverterModel != null ? ' $_inverterModel' : ''}',
            ),
            icon: const Icon(Icons.save_outlined, size: 17),
            label: const Text('Salvar relatório na conversa e Obsidian'),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Escopo técnico: cálculo NBR 5410, auditoria estrutural e exportação aberta Netlist/SVG executados localmente. O arquivo binário .cad proprietário do CADe_SIMU não é gerado no celular.',
          style: TextStyle(
            color: UltronColors.textMuted,
            fontSize: 11,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    this.accent,
    this.isLast = false,
  });

  final String label;
  final String value;
  final Color? accent;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: UltronColors.borderSubtle),
              ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: UltronColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: UltronTheme.mono.copyWith(
              color: accent ?? UltronColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
