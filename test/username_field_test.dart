import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/auth/auth_theme.dart';
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
    testWidgets(
      'available note sits under the field and keeps the text visible',
      (WidgetTester tester) async {
        final _RecordingChecker fake = _RecordingChecker(taken: false);
        await tester.pumpWidget(
          _host(UsernameField(checker: fake.checker, debounce: Duration.zero)),
        );

        await tester.enterText(find.byType(TextField), 'sanjida_mahu');
        await tester.pumpAndSettle();

        expect(fake.calls, 1);
        // Regression: an expanding suffix used to squeeze the text area to
        // zero width, so the typed value was invisible on the device.
        expect(find.text('sanjida_mahu'), findsOneWidget);
        expect(
          tester.getSize(find.byType(EditableText)).width,
          greaterThan(80),
        );

        // Availability is reported below the input, in small type - not inside
        // the box on top of what the user typed.
        expect(find.text('Username is available.'), findsOneWidget);
        expect(find.text('Available'), findsNothing);
        expect(
          tester.getTopLeft(find.text('Username is available.')).dy,
          greaterThan(tester.getBottomLeft(find.byType(EditableText)).dy),
        );
        final Text helper = tester.widget<Text>(
          find.text('Username is available.'),
        );
        expect(helper.style?.fontSize, 12);
        expect(helper.style?.color, kAuthGreen);
      },
    );

    testWidgets('idle helper explains the username rule', (
      WidgetTester tester,
    ) async {
      final _RecordingChecker fake = _RecordingChecker(taken: false);
      await tester.pumpWidget(
        _host(UsernameField(checker: fake.checker, debounce: Duration.zero)),
      );

      expect(
        find.text('3-20 characters: lowercase letters, numbers or _.'),
        findsOneWidget,
      );
      expect(fake.calls, 0);
    });

    testWidgets('taken username shows the taken message and no note', (
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
      expect(find.text('Username is available.'), findsNothing);
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
      expect(find.text('Username is available.'), findsNothing);
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

    testWidgets('a query that never answers times out into a retry hint', (
      WidgetTester tester,
    ) async {
      // A half-open connection must not leave the form "checking" forever,
      // because the register screen blocks submit while a check is in flight.
      final UsernameAvailabilityChecker hanging = UsernameAvailabilityChecker(
        existsQuery: (_) => Completer<bool>().future,
      );
      await tester.pumpWidget(
        _host(UsernameField(checker: hanging, debounce: Duration.zero)),
      );

      await tester.enterText(find.byType(TextField), 'sanjida_mahu');
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.text('Could not check availability — retry.'),
        findsOneWidget,
      );
      expect(find.text('sanjida_mahu'), findsOneWidget);
    });
  });
}
