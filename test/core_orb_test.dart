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

  testWidgets(
      'CoreOrb reuses FragmentShader across multiple frames and disposes cleanly',
      (tester) async {
    final program =
        await FragmentProgram.fromAsset('shaders/crimson_core.frag');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            height: 240,
            child: CoreOrb(
              stage: CoreStage.center,
              shaderProgram: program,
              energy: 0.5,
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.takeException(), isNull);

    // Unmount and dispose cached shader cleanly
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'CoreStarfieldBackdrop renders deep-space starfield behind CoreOrb without throwing',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: Color(0xFF080808),
          body: SizedBox(
            width: 360,
            height: 420,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CoreStarfieldBackdrop(
                  active: true,
                  energy: 0.45,
                  accentColor: Color(0xFFF10D28),
                  starCount: 72,
                ),
                Center(
                  child: SizedBox(
                    width: 220,
                    height: 220,
                    child: CoreOrb(stage: CoreStage.center, energy: 0.45),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 48));
    expect(find.byType(CoreStarfieldBackdrop), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Pause lifecycle and verify clean teardown
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
