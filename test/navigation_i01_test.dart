import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/app/app.dart';

void main() {
  testWidgets('app boots to Home tab; each tab shows its screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const RailMateApp());
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsWidgets); // Home tab root rendered
    await tester.tap(find.text('My Trips').last);
    await tester.pumpAndSettle();
    expect(find.text('Setup required'), findsOneWidget);
    await tester.tap(find.text('Board').last);
    await tester.pumpAndSettle();
    expect(find.text('Journey Board'), findsOneWidget);
    await tester.tap(find.text('Guide').last);
    await tester.pumpAndSettle();
    // GuideListScreen header renders without backend.
    expect(find.text('Guide'), findsWidgets);
  });

  testWidgets('unknown route shows error screen', (WidgetTester tester) async {
    await tester.pumpWidget(const RailMateApp());
    await tester.pumpAndSettle();
    final NavigatorState nav = tester.state(find.byType(Navigator).first);
    nav.pushNamed('/no-such-route-xyz');
    await tester.pumpAndSettle();
    expect(find.textContaining('Unknown route'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_left).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Unknown route'), findsNothing); // popped clean
  });
}
