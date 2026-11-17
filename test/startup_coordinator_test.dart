import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/services/startup_coordinator.dart';

void main() {
  test('executes boot stages in strict order until ready', () async {
    final log = <String>[];
    final coordinator = StartupCoordinator(
      initVault: () async => log.add('vault'),
      initAiProviders: () async => log.add('aiProviders'),
      initAudio: () async => log.add('audio'),
      loadShader: () async {
        log.add('shader');
        return null;
      },
    );

    final observedStages = <BootStage>[coordinator.stage];
    coordinator.addListener(() {
      observedStages.add(coordinator.stage);
    });

    final ok = await coordinator.start();
    expect(ok, isTrue);
    expect(log, ['vault', 'aiProviders', 'audio', 'shader']);
    expect(coordinator.stage, BootStage.ready);
    expect(coordinator.isReady, isTrue);
    expect(coordinator.progress, 1.0);
    expect(coordinator.error, isNull);
    expect(
      observedStages,
      containsAllInOrder([
        BootStage.vault,
        BootStage.aiProviders,
        BootStage.audio,
        BootStage.shader,
        BootStage.ready,
      ]),
    );
  });

  test('start is idempotent when called concurrently or after ready', () async {
    var vaultCalls = 0;
    final gate = Completer<void>();
    final coordinator = StartupCoordinator(
      initVault: () async {
        vaultCalls += 1;
        await gate.future;
      },
      initAiProviders: () async {},
      initAudio: () async {},
      loadShader: () async => null,
    );

    final f1 = coordinator.start();
    final f2 = coordinator.start();
    gate.complete();

    expect(await Future.wait([f1, f2]), [true, true]);
    expect(vaultCalls, 1);

    expect(await coordinator.start(), isTrue);
    expect(vaultCalls, 1);
  });

  test('halts at failing stage without advancing to ready and recovers on retry', () async {
    var attempts = 0;
    final log = <String>[];
    final coordinator = StartupCoordinator(
      initVault: () async {
        attempts += 1;
        log.add('vault:$attempts');
        if (attempts == 1) {
          throw StateError('Falha ao abrir cofre');
        }
      },
      initAiProviders: () async => log.add('aiProviders'),
      initAudio: () async => log.add('audio'),
      loadShader: () async => null,
    );

    final firstOk = await coordinator.start();
    expect(firstOk, isFalse);
    expect(coordinator.stage, BootStage.vault);
    expect(coordinator.isReady, isFalse);
    expect(coordinator.error, contains('Falha ao abrir cofre'));
    expect(log, ['vault:1']);

    final retryOk = await coordinator.start();
    expect(retryOk, isTrue);
    expect(coordinator.stage, BootStage.ready);
    expect(coordinator.error, isNull);
    expect(log, ['vault:1', 'vault:2', 'aiProviders', 'audio']);
  });
}
