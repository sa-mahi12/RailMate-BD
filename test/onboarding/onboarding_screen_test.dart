import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/design/motion/reduced_motion.dart';
import 'package:railmate_bd/features/onboarding/onboarding_screen.dart';

Widget _host({
  required VoidCallback onFinished,
  bool reduced = false,
  TextScaler textScaler = TextScaler.noScaling,
  Key? key,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: textScaler),
      child: MotionGate(
        overrideReduced: reduced,
        child: OnboardingScreen(key: key, onFinished: onFinished),
      ),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
}

void main() {
  group('OnboardingScreen', () {
    testWidgets('exposes the stable gate route name', (
      WidgetTester tester,
    ) async {
      expect(OnboardingScreen.routeName, '/onboarding');
    });

    testWidgets('first page shows spec copy and honest demo notice', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(onFinished: () {}));
      await _settle(tester);

      expect(
        find.text('Plan train journeys with less friction'),
        findsOneWidget,
      );
      expect(find.textContaining('compare demo schedules'), findsOneWidget);
      expect(
        find.textContaining('Not an official rail service'),
        findsOneWidget,
      );
      // Page 2 copy must not be rendered while page 1 is current.
      expect(find.text('Pick seats for everyone'), findsNothing);
    });

    testWidgets('Next advances through all pages and swaps the button label', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(onFinished: () {}));
      await _settle(tester);
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Get Started'), findsNothing);

      await tester.tap(find.text('Next'));
      await _settle(tester);
      expect(find.text('Pick seats for everyone'), findsOneWidget);
      expect(find.textContaining('add passenger details'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await _settle(tester);
      expect(find.text('Tickets, bookings and travel tips'), findsOneWidget);
      expect(find.textContaining('demonstration tickets'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
    });

    testWidgets('horizontal swipe advances the pages', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(onFinished: () {}));
      await _settle(tester);

      await tester.fling(
        find.text('Plan train journeys with less friction'),
        const Offset(-300, 0),
        1200,
      );
      await _settle(tester);
      expect(find.text('Pick seats for everyone'), findsOneWidget);

      await tester.fling(
        find.text('Pick seats for everyone'),
        const Offset(-300, 0),
        1200,
      );
      await _settle(tester);
      expect(find.text('Tickets, bookings and travel tips'), findsOneWidget);
    });

    testWidgets('page indicator tracks the current page', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(onFinished: () {}));
      await _settle(tester);

      expect(find.bySemanticsLabel('Page 1 of 3'), findsOneWidget);
      expect(find.bySemanticsLabel('Page 2 of 3'), findsNothing);

      await tester.tap(find.text('Next'));
      await _settle(tester);
      expect(find.bySemanticsLabel('Page 2 of 3'), findsOneWidget);
      expect(find.bySemanticsLabel('Page 1 of 3'), findsNothing);

      await tester.tap(find.text('Next'));
      await _settle(tester);
      expect(find.bySemanticsLabel('Page 3 of 3'), findsOneWidget);
    });

    testWidgets('tapping a dot jumps straight to that page', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(onFinished: () {}));
      await _settle(tester);

      await tester.tap(find.bySemanticsLabel('Go to page 3'));
      await _settle(tester);
      expect(find.text('Tickets, bookings and travel tips'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
    });

    testWidgets('Skip calls onFinished exactly once', (
      WidgetTester tester,
    ) async {
      int finished = 0;
      await tester.pumpWidget(_host(onFinished: () => finished++));
      await _settle(tester);

      await tester.tap(find.text('Skip'));
      await _settle(tester);
      expect(finished, 1);
    });

    testWidgets('Skip is hidden but inert on the final page', (
      WidgetTester tester,
    ) async {
      int finished = 0;
      await tester.pumpWidget(_host(onFinished: () => finished++));
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Go to page 3'));
      await _settle(tester);

      final Finder skipButton = find.widgetWithText(TextButton, 'Skip');
      expect(skipButton, findsOneWidget);
      expect(
        tester
            .widgetList<AnimatedOpacity>(
              find.ancestor(
                of: skipButton,
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .every((AnimatedOpacity fade) => fade.opacity == 0.0),
        isTrue,
        reason: 'Skip must be faded out on the final page',
      );

      await tester.tap(skipButton, warnIfMissed: false);
      await tester.pump();
      expect(finished, 0, reason: 'faded Skip must stay inert');
    });

    testWidgets('Get Started on the last page calls onFinished exactly once', (
      WidgetTester tester,
    ) async {
      int finished = 0;
      await tester.pumpWidget(_host(onFinished: () => finished++));
      await _settle(tester);

      await tester.tap(find.text('Next'));
      await _settle(tester);
      await tester.tap(find.text('Next'));
      await _settle(tester);

      await tester.tap(find.text('Get Started'));
      await _settle(tester);
      expect(finished, 1);
    });

    testWidgets('reduced motion renders final state with no entrance '
        'animations', (WidgetTester tester) async {
      await tester.pumpWidget(_host(onFinished: () {}, reduced: true));
      // One pump only: entrances must already be in their final state.
      await tester.pump();
      expect(
        find.text('Plan train journeys with less friction'),
        findsOneWidget,
      );
      expect(find.byType(AnimatedOpacity), findsNothing);
    });

    testWidgets('reduced motion still honours Skip and Get Started', (
      WidgetTester tester,
    ) async {
      int finished = 0;
      await tester.pumpWidget(
        _host(onFinished: () => finished++, reduced: true),
      );
      await tester.pump();

      await tester.tap(find.text('Skip'));
      await tester.pump();
      expect(finished, 1);

      await tester.tap(find.bySemanticsLabel('Go to page 3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get Started'));
      await tester.pump();
      expect(finished, 2);
    });

    testWidgets('full motion run builds entrance animations and reveals copy', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(onFinished: () {}));
      await tester.pump();
      expect(find.byType(AnimatedOpacity), findsWidgets);

      await _settle(tester);
      expect(find.textContaining('compare demo schedules'), findsOneWidget);
    });

    testWidgets('no overflow at 1.3 and 1.5 text scale', (
      WidgetTester tester,
    ) async {
      for (final double scale in <double>[1.3, 1.5]) {
        // A fresh key per scale forces a new State so every run starts on
        // page 1 instead of inheriting the previous run's page index.
        await tester.pumpWidget(
          _host(
            onFinished: () {},
            textScaler: TextScaler.linear(scale),
            key: ValueKey<String>('scale-$scale'),
          ),
        );
        await _settle(tester);
        expect(
          tester.takeException(),
          isNull,
          reason: 'overflow at text scale $scale',
        );

        await tester.tap(find.text('Next'));
        await _settle(tester);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Next'));
        await _settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Tickets, bookings and travel tips'), findsOneWidget);
      }
    });

    testWidgets('hero illustration carries a semantic image label', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(onFinished: () {}));
      await _settle(tester);

      expect(find.bySemanticsLabel(RegExp('demo rail route')), findsOneWidget);
      handle.dispose();
    });
  });
}
