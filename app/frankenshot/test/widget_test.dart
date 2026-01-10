import 'package:flutter_test/flutter_test.dart';

import 'package:frankenshot/main.dart';

void main() {
  testWidgets('Machine status screen shows feeding state', (WidgetTester tester) async {
    await tester.pumpWidget(const FrankenshotApp());

    expect(find.text('Frankenshot'), findsOneWidget);
    expect(find.text('Feeding'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Current Configuration'), findsOneWidget);
  });

  testWidgets('Pause button toggles feeding state', (WidgetTester tester) async {
    await tester.pumpWidget(const FrankenshotApp());

    expect(find.text('Feeding'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);

    await tester.tap(find.text('Pause'));
    await tester.pump();

    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
  });

  testWidgets('Configuration values are displayed', (WidgetTester tester) async {
    await tester.pumpWidget(const FrankenshotApp());

    expect(find.text('Time Between Balls'), findsOneWidget);
    expect(find.text('3.0 seconds'), findsOneWidget);
    expect(find.text('Speed'), findsOneWidget);
    expect(find.text('Spin'), findsOneWidget);
    expect(find.text('Height'), findsOneWidget);
    expect(find.text('Horizontal'), findsOneWidget);
  });
}
