import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/main.dart';

void main() {
  testWidgets('app opens the core screen with command input', (tester) async {
    await tester.pumpWidget(const UltronApp());

    expect(find.byType(UltronApp), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Comando…'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
