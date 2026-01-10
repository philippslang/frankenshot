import 'package:flutter_test/flutter_test.dart';

import 'package:frankenshot/main.dart';

void main() {
  testWidgets('Machine status screen shows initial state', (WidgetTester tester) async {
    await tester.pumpWidget(const FrankenshotApp());

    expect(find.text('Frankenshot'), findsOneWidget);
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Current Configuration'), findsOneWidget);
  });

  testWidgets('Current configuration shows dashes when no list selected', (WidgetTester tester) async {
    await tester.pumpWidget(const FrankenshotApp());

    // Current config card always visible with dash placeholders
    expect(find.text('Current Configuration'), findsOneWidget);
    expect(find.text('-'), findsNWidgets(5)); // All 5 values show dash
  });

  testWidgets('Configuration lists are displayed with Run buttons', (WidgetTester tester) async {
    await tester.pumpWidget(const FrankenshotApp());

    // Scroll down to see config lists
    await tester.scrollUntilVisible(find.text('Warm Up'), 100);

    expect(find.text('Configuration Lists'), findsOneWidget);
    expect(find.text('Warm Up'), findsOneWidget);
    expect(find.text('Topspin Practice'), findsOneWidget);
    expect(find.text('Run'), findsNWidgets(2));
  });

  testWidgets('Selecting a config list populates current configuration', (WidgetTester tester) async {
    await tester.pumpWidget(const FrankenshotApp());

    // No index shown yet
    expect(find.text('1/3'), findsNothing);

    // Scroll and tap Run button on first config list
    await tester.scrollUntilVisible(find.text('Warm Up'), 100);
    await tester.tap(find.text('Run').first);
    await tester.pump();

    // Should show "Running" chip instead of Run button
    expect(find.text('Running'), findsOneWidget);

    // Scroll back up to see the index
    await tester.scrollUntilVisible(find.text('Current Configuration'), -100);
    expect(find.text('1/3'), findsOneWidget);
  });

  testWidgets('Pause/Resume toggles at any time', (WidgetTester tester) async {
    await tester.pumpWidget(const FrankenshotApp());

    // Initially paused
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);

    // Tap Resume (no config selected)
    await tester.tap(find.text('Resume'));
    await tester.pump();

    expect(find.text('Feeding'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);

    // Tap Pause
    await tester.tap(find.text('Pause'));
    await tester.pump();

    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
  });

  testWidgets('Manual feed button hidden when feeding', (WidgetTester tester) async {
    await tester.pumpWidget(const FrankenshotApp());

    // Manual feed visible when paused
    expect(find.text('Manual Feed'), findsOneWidget);

    // Start feeding
    await tester.tap(find.text('Resume'));
    await tester.pump();

    // Hidden when feeding
    expect(find.text('Manual Feed'), findsNothing);
  });

  testWidgets('Can navigate to create new config list', (WidgetTester tester) async {
    await tester.pumpWidget(const FrankenshotApp());

    // Scroll to and tap the add button
    await tester.scrollUntilVisible(find.byTooltip('Create new list'), 100);
    await tester.tap(find.byTooltip('Create new list'));
    await tester.pumpAndSettle();

    // Should see the editor screen
    expect(find.text('New Configuration List'), findsOneWidget);
    expect(find.text('List Name'), findsOneWidget);
  });
}
