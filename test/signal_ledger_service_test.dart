import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/core/security/action_gate.dart';
import 'package:ultron_mobile/models/assistant_persona.dart';
import 'package:ultron_mobile/services/deep_research_service.dart';
import 'package:ultron_mobile/services/signal_ledger_service.dart';
import 'package:ultron_mobile/services/web_info_service.dart';
import 'package:ultron_mobile/services/workflow_scheduler_service.dart';
import 'package:ultron_mobile/ui/theme/ultron_theme.dart';
import 'package:ultron_mobile/ui/widgets/signal_ledger_panel.dart';

void main() {
  group('SignalLedgerService', () {
    test('consolidates DeepResearch, Workflows, Desktop tasks, and ActionGate approvals',
        () async {
      final gate = Completer<void>();
      final deepResearch = DeepResearchService(
        webInfo: WebInfoService(
          httpGetText: (_, {headers = const {}}) async => null,
        ),
        synthesizer: (prompt, _) async {
          await gate.future;
          return '# Relatório\n\nAchado consolidado.';
        },
      );
      final ledger = SignalLedgerService(deepResearch: deepResearch);
      addTearDown(ledger.dispose);

      // 1. In progress: DeepResearch + Workflow + Desktop task
      deepResearch.startResearch('Motor WEG 5cv', saveToObsidian: false);
      ledger.trackWorkflowStarted(flowId: 7, flowName: 'Backup_Noturno', totalSteps: 2);
      final pcId = ledger.recordDesktopTaskDelegated(topic: 'Benchmark LLM local');

      expect(ledger.activeCount, 3);
      expect(ledger.inProgressItems.map((e) => e.source), containsAll([
        SignalSourceKind.deepResearch,
        SignalSourceKind.workflow,
        SignalSourceKind.desktopTask,
      ]));

      // 2. Awaiting approval: paused workflow + ActionGate simulation
      ledger.recordWorkflowResult(
        const WorkflowExecutionResult(
          flowId: 7,
          flowName: 'Backup_Noturno',
          executed: false,
          blockedByAuthGate: false,
          pausedForConfirmation: true,
          completedSteps: 1,
          totalSteps: 2,
          logs: ['Etapa 1 OK'],
          message: 'Pausado aguardando confirmação para WhatsApp.',
        ),
      );
      var approvedCallbackCalled = false;
      final gateId = ledger.registerPendingApproval(
        simulation: const ActionGate().simulate('[ACTION:PC_BACKUP]'),
        onApprove: () async => approvedCallbackCalled = true,
      );
      expect(ledger.pendingApprovalCount, 2);

      // 3. Complete desktop task + resolve approval + complete DeepResearch
      ledger.completeDesktopTask(
        pcId,
        resultSummary: 'Relatório salvo no PC',
        obsidianNotePath: 'Memoria/Pesquisas/benchmark.md',
      );
      final resolved = await ledger.resolveApproval(gateId, approved: true);
      expect(resolved, isTrue);
      expect(approvedCallbackCalled, isTrue);

      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(ledger.activeCount, 0);
      expect(ledger.pendingApprovalCount, 1); // paused workflow remains
      expect(ledger.completedCount, 3);
      expect(
        ledger.completedItems.any(
          (i) => i.obsidianNotePath == 'Memoria/Pesquisas/benchmark.md',
        ),
        isTrue,
      );
    });
  });

  group('SignalLedgerBoard & SummaryCard widgets', () {
    testWidgets('renders 3 tabs, approves pending items, and opens Obsidian note link',
        (tester) async {
      final ledger = SignalLedgerService();
      addTearDown(ledger.dispose);

      var approved = false;
      ledger.recordDesktopTaskDelegated(topic: 'Indexar documentos');
      ledger.registerPendingApproval(
        simulation: const ActionGate().simulate('[ACTION:KILL_SWITCH]'),
        onApprove: () async => approved = true,
      );
      ledger.recordCompletedDelivery(
        id: 'done-1',
        title: 'Pesquisa NBR 5410',
        subtitle: 'Relatório concluído',
        source: SignalSourceKind.deepResearch,
        obsidianNotePath: 'Memoria/Pesquisas/nbr5410.md',
      );

      String? openedPath;
      await tester.pumpWidget(
        MaterialApp(
          theme: UltronTheme.dark(persona: AssistantPersona.jarvis),
          home: Scaffold(
            body: Column(
              children: [
                SignalLedgerSummaryCard(
                  ledger: ledger,
                  onOpenBoard: () {},
                ),
                Expanded(
                  child: SignalLedgerBoard(
                    ledger: ledger,
                    onOpenObsidianNote: (p) async => openedPath = p,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('signal_ledger_summary_card')), findsOneWidget);
      expect(find.byKey(const Key('signal_tab_in_progress')), findsOneWidget);
      expect(find.byKey(const Key('signal_tab_awaiting')), findsOneWidget);
      expect(find.byKey(const Key('signal_tab_completed')), findsOneWidget);

      // Defaults to awaitingApproval tab since pendingApprovalCount > 0
      expect(find.textContaining('KILL_SWITCH'), findsOneWidget);
      await tester.tap(find.text('Aprovar'));
      await tester.pumpAndSettle();
      expect(approved, isTrue);

      // Switch to Concluído tab and tap Obsidian note link
      await tester.tap(find.byKey(const Key('signal_tab_completed')));
      await tester.pumpAndSettle();
      expect(find.text('Memoria/Pesquisas/nbr5410.md'), findsOneWidget);
      await tester.tap(find.text('Memoria/Pesquisas/nbr5410.md'));
      await tester.pumpAndSettle();
      expect(openedPath, 'Memoria/Pesquisas/nbr5410.md');
    });
  });
}
