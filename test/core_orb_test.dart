import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/ui/widgets/core_orb.dart';

void main() {
  testWidgets(
      'CoreOrb loads compiled crimson FragmentProgram and renders without throwing',
      (tester) async {
    final program =
        await FragmentProgram.fromAsset('shaders/crimson_core.frag');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            height: 280,
            child: CoreOrb(
              stage: CoreStage.center,
              shaderProgram: program,
              energy: 0.75,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 32));

    expect(find.byType(CoreOrb), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'CoreOrb renders fallback CorePainter safely when shaderProgram is null',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CoreOrb(
            stage: CoreStage.center,
            shaderProgram: null,
            energy: 0.4,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 32));

    expect(find.byType(CoreOrb), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'CoreOrb pauses Ticker when stage is hidden or app lifecycle is paused',
      (tester) async {
    final tickerStates = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoreOrb(
            stage: CoreStage.center,
            onTickerStateChanged: tickerStates.add,
          ),
        ),
      ),
    );
    expect(tickerStates.last, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoreOrb(
            stage: CoreStage.hidden,
            onTickerStateChanged: tickerStates.add,
          ),
        ),
      ),
    );
    expect(tickerStates.last, isFalse);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoreOrb(
            stage: CoreStage.corner,
            onTickerStateChanged: tickerStates.add,
          ),
        ),
      ),
    );
    expect(tickerStates.last, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(tickerStates.last, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tickerStates.last, isTrue);
  });
}
