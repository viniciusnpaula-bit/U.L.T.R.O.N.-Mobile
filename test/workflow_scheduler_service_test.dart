import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ultron_mobile/core/security/auth_gate.dart';
import 'package:ultron_mobile/services/audit_log_service.dart';
import 'package:ultron_mobile/services/workflow_scheduler_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.viniciusnpaula.ultron_mobile/device');
  final calls = <MethodCall>[];
  late Database db;
  late WorkflowSchedulerService scheduler;

  setUp(() async {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });

    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, singleInstance: false),
    );
    scheduler = await WorkflowSchedulerService.open(
      database: db,
      channel: channel,
    );
  });

  tearDown(() async {
    await scheduler.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('creates, lists, schedules, and deletes workflows with AlarmManager calls',
      () async {
    final fixedNow = DateTime(2026, 11, 22, 10, 0);
    final created = await scheduler.createFlow(
      name: 'rotina foco',
      stepsPayload: 'TORCH_OFF -> VOLUME_SET:25 -> SKILL:modo_estudo',
      scheduleSpec: 'diario 07:30',
      now: fixedNow,
    );

    expect(created.name, 'rotina_foco');
    expect(
      created.stepsPayload,
      '[ACTION:TORCH_OFF] [ACTION:VOLUME_SET:25] [ACTION:SKILL:modo_estudo]',
    );
    expect(created.intervalMinutes, 1440);
    expect(calls.last.method, 'scheduleWorkflowAlarm');

    final listed = await scheduler.listFlows();
    expect(listed.length, 1);
    expect(listed.single.name, 'rotina_foco');

    final rescheduled = await scheduler.scheduleFlow(
      nameOrId: 'rotina_foco',
      scheduleSpec: 'a cada 45m',
      now: fixedNow,
    );
    expect(rescheduled.intervalMinutes, 45);
    expect(
      rescheduled.nextRunMs,
      fixedNow.add(const Duration(minutes: 45)).millisecondsSinceEpoch,
    );

    final deleted = await scheduler.deleteFlow('rotina_foco');
    expect(deleted, isNotNull);
    expect(calls.last.method, 'cancelWorkflowAlarm');
    expect(await scheduler.listFlows(), isEmpty);
  });

  test(
      'enforces AuthGate: safe background flows execute, but sensitive/critical background flows are blocked without authorized session',
      () async {
    final fixedNow = DateTime(2026, 11, 22, 12, 0);

    // 1. Safe flow runs even on background trigger
    await scheduler.createFlow(
      name: 'fluxo_seguro',
      stepsPayload: 'TORCH_ON -> VOLUME_SET:40',
      scheduleSpec: 'daqui 5m',
      now: fixedNow,
    );

    final executedSteps = <String>[];
    final safeRes = await scheduler.runFlow(
      'fluxo_seguro',
      isBackgroundTrigger: true,
      executor: (payload, {required isBackgroundTrigger}) async {
        executedSteps.add(payload);
        return ['🔦 Lanterna ligada', '🔊 Volume: 40%'];
      },
    );
    expect(safeRes.executed, isTrue);
    expect(safeRes.blockedByAuthGate, isFalse);
    expect(executedSteps.length, 1);

    // 2. Sensitive flow (WHATSAPP) must NEVER execute silently on background trigger when session is locked or basic (PIN)
    await scheduler.createFlow(
      name: 'fluxo_sensivel',
      stepsPayload: 'TORCH_ON -> WHATSAPP:Carlos:Relatório pronto',
      scheduleSpec: 'daqui 10m',
      now: fixedNow,
    );

    final gate = AuthGate(); // initially locked
    final blockedLocked = await scheduler.runFlow(
      'fluxo_sensivel',
      authGate: gate,
      isBackgroundTrigger: true,
      executor: (payload, {required isBackgroundTrigger}) async {
        executedSteps.add(payload);
        return ['executou indevidamente'];
      },
    );
    expect(blockedLocked.executed, isFalse);
    expect(blockedLocked.blockedByAuthGate, isTrue);
    expect(blockedLocked.message, contains('bloqueado pelo AuthGate'));
    expect(executedSteps.length, 1); // unchanged

    // Even in basic (PIN) session, sensitive flow is blocked by AuthGate
    await gate.authenticatePin('1234', (pin) async => true);
    expect(gate.level, AccessLevel.basic);
    final blockedBasic = await scheduler.runFlow(
      'fluxo_sensivel',
      authGate: gate,
      isBackgroundTrigger: false,
      executor: (payload, {required isBackgroundTrigger}) async {
        executedSteps.add(payload);
        return ['executou indevidamente'];
      },
    );
    expect(blockedBasic.executed, isFalse);
    expect(blockedBasic.blockedByAuthGate, isTrue);

    // 3. NFC (elevated) session is still blocked on background trigger for sensitive flows,
    // and critical flows (KILL_SWITCH) are always blocked on background trigger.
    await gate.authenticateNfc('AA11BB22', (_) async => true);
    expect(gate.level, AccessLevel.elevated);

    final blockedElevatedBg = await scheduler.runFlow(
      'fluxo_sensivel',
      authGate: gate,
      isBackgroundTrigger: true,
      executor: (payload, {required isBackgroundTrigger}) async {
        executedSteps.add(payload);
        return ['executou indevidamente'];
      },
    );
    expect(blockedElevatedBg.executed, isFalse);
    expect(blockedElevatedBg.blockedByAuthGate, isTrue);

    await scheduler.createFlow(
      name: 'fluxo_critico',
      stepsPayload: 'KILL_SWITCH',
    );
    final blockedCriticalBg = await scheduler.runFlow(
      'fluxo_critico',
      authGate: gate,
      isBackgroundTrigger: true,
      executor: (payload, {required isBackgroundTrigger}) async {
        executedSteps.add(payload);
        return ['executou indevidamente'];
      },
    );
    expect(blockedCriticalBg.executed, isFalse);
    expect(blockedCriticalBg.blockedByAuthGate, isTrue);
  });

  test('Marco 2: runFlowWithCheckpoints pauses on uncertain external step and resumes without re-running completed steps',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final scheduler = await WorkflowSchedulerService.open(database: db);
    addTearDown(scheduler.close);

    final flow = await scheduler.createFlow(
      name: 'rotina_campo',
      stepsPayload: 'TORCH_ON -> OPEN_APP:whatsapp -> VOLUME_SET:60',
    );

    final ranTags = <String>[];
    final firstRun = await scheduler.runFlowWithCheckpoints(
      'rotina_campo',
      stepExecutor: (tag, {required isBackgroundTrigger}) async {
        ranTags.add(tag);
        final outcome = AuditLogService.classifyActionOutcome(
          tag,
          succeeded: true,
        );
        return WorkflowStepResult(outcome: outcome, log: 'step:$tag');
      },
    );

    // Step 1 (TORCH_ON) confirmed, Step 2 (OPEN_APP:whatsapp) uncertain -> pauses before Step 3!
    expect(firstRun.executed, isFalse);
    expect(firstRun.pausedForConfirmation, isTrue);
    expect(firstRun.completedSteps, 2);
    expect(firstRun.totalSteps, 3);
    expect(ranTags, ['[ACTION:TORCH_ON]', '[ACTION:OPEN_APP:whatsapp]']);

    final cp = await scheduler.getCheckpoint(flow.id);
    expect(cp, isNotNull);
    expect(cp!.status, 'PAUSED_UNCERTAIN');
    expect(cp.nextStepIndex, 2);

    // Resuming runs ONLY Step 3 without repeating Step 1 or Step 2!
    ranTags.clear();
    final resumed = await scheduler.runFlowWithCheckpoints(
      'rotina_campo',
      stepExecutor: (tag, {required isBackgroundTrigger}) async {
        ranTags.add(tag);
        return WorkflowStepResult(
          outcome: ExecutionOutcome.confirmed,
          log: 'step:$tag',
        );
      },
    );
    expect(resumed.executed, isTrue);
    expect(resumed.pausedForConfirmation, isFalse);
    expect(ranTags, ['[ACTION:VOLUME_SET:60]']);
    expect(await scheduler.getCheckpoint(flow.id), isNull);
  });
}
