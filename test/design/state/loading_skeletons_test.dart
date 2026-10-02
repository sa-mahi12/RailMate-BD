import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/design/motion/reduced_motion.dart';
import 'package:railmate_bd/design/motion/skeleton.dart';
import 'package:railmate_bd/design/state/loading_skeletons.dart';

Widget _host(Widget child, {bool reduced = false}) {
  return MotionGate(
    overrideReduced: reduced ? true : null,
    child: Directionality(
      textDirection: TextDirection.ltr,
      // Align without a tight box: each placeholder sizes itself from the
      // constraints it was given, exactly as it will on a real screen.
      child: Align(alignment: Alignment.topLeft, child: child),
    ),
  );
}

void main() {
  group('SkeletonTextLines', () {
    testWidgets('renders one bounded shimmer block per line', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(const SkeletonTextLines(lines: 3, lineHeight: 14)),
      );
      expect(find.byType(SkeletonTextLines), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SkeletonTextLines),
          matching: find.byType(SkeletonBlock),
        ),
        findsNWidgets(3),
      );

      // Bounded sweep: sizes are fixed so nothing jumps when real text lands.
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.descendant(
          of: find.byType(SkeletonTextLines),
          matching: find.byType(SkeletonBlock),
        ),
        findsNWidgets(3),
      );
    });

    testWidgets('final line is shortened so it reads as a paragraph', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(const SkeletonTextLines(lines: 2, lineHeight: 14, width: 300)),
      );
      final Finder bars = find.descendant(
        of: find.byType(SkeletonTextLines),
        matching: find.byType(SkeletonBlock),
      );
      final Size first = tester.getSize(bars.at(0));
      final Size last = tester.getSize(bars.at(1));
      expect(first.width, 300);
      expect(last.width, lessThan(first.width));
    });

    testWidgets('reduced motion still renders static blocks', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(const SkeletonTextLines(lines: 2), reduced: true),
      );
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(SkeletonTextLines),
          matching: find.byType(SkeletonBlock),
        ),
        findsNWidgets(2),
      );
    });
  });

  group('SkeletonCircle / SkeletonCard', () {
    testWidgets('circle is square with a full radius', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(const SkeletonCircle(size: 36)));
      final Size size = tester.getSize(find.byType(SkeletonCircle));
      expect(size.width, 36);
      expect(size.height, 36);
    });

    testWidgets('card keeps the caller-fixed height', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(const SkeletonCard(height: 120)));
      expect(tester.getSize(find.byType(SkeletonCard)).height, 120);
    });
  });

  group('SkeletonRow', () {
    testWidgets('renders a leading circle plus two text lines', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(const SkeletonRow()));
      expect(find.byType(SkeletonCircle), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SkeletonTextLines),
          matching: find.byType(SkeletonBlock),
        ),
        findsNWidgets(2),
      );
    });

    testWidgets('is decorative unless a semantics label is supplied', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(const SkeletonRow()));
      expect(
        find.descendant(
          of: find.byType(SkeletonRow),
          matching: find.bySemanticsLabel('Loading bookings'),
        ),
        findsNothing,
      );

      await tester.pumpWidget(
        _host(const SkeletonRow(semanticsLabel: 'Loading bookings')),
      );
      expect(
        find.descendant(
          of: find.byType(SkeletonRow),
          matching: find.bySemanticsLabel('Loading bookings'),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('SkeletonList', () {
    testWidgets('builds exactly itemCount placeholder rows', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          SkeletonList(
            itemCount: 4,
            itemBuilder: (BuildContext context, int index) =>
                const SkeletonRow(),
          ),
        ),
      );
      expect(find.byType(SkeletonRow), findsNWidgets(4));
    });

    testWidgets('zero items render an empty placeholder, never fake rows', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          SkeletonList(
            itemCount: 0,
            itemBuilder: (BuildContext context, int index) =>
                const SkeletonRow(),
          ),
        ),
      );
      expect(find.byType(SkeletonRow), findsNothing);
    });

    testWidgets('spreads a semantics label over the whole list', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          SkeletonList(
            itemCount: 2,
            semanticsLabel: 'Loading journeys',
            itemBuilder: (BuildContext context, int index) =>
                const SkeletonRow(),
          ),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(SkeletonList),
          matching: find.bySemanticsLabel('Loading journeys'),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}
