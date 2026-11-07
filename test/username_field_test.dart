import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/auth/username/username.dart';
import 'package:railmate_bd/features/auth/username/username_availability.dart';
import 'package:railmate_bd/features/auth/username/username_field.dart';

/// Records query calls so "invalid input never queries" stays provable.
class _RecordingChecker {
  _RecordingChecker({required this.taken});

  final bool taken;
  int calls = 0;

  UsernameAvailabilityChecker get checker => UsernameAvailabilityChecker(
    existsQuery: (String _) async {
      calls++;
      return taken;
    },
  );
}

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

void main() {
  group('UsernameField', () {
    testWidgets('available pill keeps the typed username visible', (
      WidgetTester tester,
    ) async {
      final _RecordingChecker fake = _RecordingChecker(taken: false);
      await tester.pumpWidget(
        _host(UsernameField(checker: fake.checker, debounce: Duration.zero)),
      );

      await tester.enterText(find.byType(TextField), 'sanjida_mahu');
      await tester.pumpAndSettle();

      expect(fake.calls, 1);
      expect(find.text('Available'), findsOneWidget);
      // Regression: an expanding suffix used to squeeze the text area to
      // zero width, so the typed value was invisible on the device.
      expect(find.text('sanjida_mahu'), findsOneWidget);
      expect(tester.getSize(find.byType(EditableText)).width, greaterThan(80));

      // The pill belongs on the trailing edge, not across the middle.
      final double fieldCenter = tester.getCenter(find.byType(TextField)).dx;
      final double pillCenter = tester.getCenter(find.text('Available')).dx;
      expect(pillCenter, greaterThan(fieldCenter));
      expect(
        tester.getTopRight(find.text('Available')).dx,
        lessThanOrEqualTo(tester.getTopRight(find.byType(TextField)).dx),
      );
    });

    testWidgets('taken username shows the taken message and no pill', (
      WidgetTester tester,
    ) async {
      final _RecordingChecker fake = _RecordingChecker(taken: true);
      await tester.pumpWidget(
        _host(UsernameField(checker: fake.checker, debounce: Duration.zero)),
      );

      await tester.enterText(find.byType(TextField), 'uiprobe2026');
      await tester.pumpAndSettle();

      expect(
        find.text('That username is taken — try another.'),
        findsOneWidget,
      );
      expect(find.text('Available'), findsNothing);
      expect(find.text('uiprobe2026'), findsOneWidget);
    });

    testWidgets('invalid format is explained without a server query', (
      WidgetTester tester,
    ) async {
      final _RecordingChecker fake = _RecordingChecker(taken: false);
      await tester.pumpWidget(
        _host(UsernameField(checker: fake.checker, debounce: Duration.zero)),
      );

      await tester.enterText(find.byType(TextField), 'Bad Name!');
      await tester.pumpAndSettle();

      expect(fake.calls, 0);
      expect(find.text(validateUsername('Bad Name!')!), findsOneWidget);
      expect(find.text('Available'), findsNothing);
    });

    testWidgets('status changes are reported to the parent form', (
      WidgetTester tester,
    ) async {
      final _RecordingChecker fake = _RecordingChecker(taken: false);
      final List<UsernameAvailability> seen = <UsernameAvailability>[];
      await tester.pumpWidget(
        _host(
          UsernameField(
            checker: fake.checker,
            debounce: Duration.zero,
            onStatusChanged: seen.add,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'sanjida_mahu');
      await tester.pumpAndSettle();

      expect(seen, contains(UsernameAvailability.checking));
      expect(seen.last, UsernameAvailability.available);
    });
  });
}
