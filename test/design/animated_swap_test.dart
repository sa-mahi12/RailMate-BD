import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/design/motion/animated_swap.dart';
import 'package:railmate_bd/design/motion/reduced_motion.dart';

Widget _host(String value, {bool reduced = false}) {
  return MotionGate(
    overrideReduced: reduced ? true : null,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: AnimatedSwap(
        child: Text(
          value,
          key: ValueKey<String>(value),
          textDirection: TextDirection.ltr,
        ),
      ),
    ),
  );
}

void main() {
  group('AnimatedSwap', () {
    testWidgets('crossfades between keyed children', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host('A'));
      expect(find.text('A'), findsOneWidget);

      await tester.pumpWidget(_host('B'));
      await tester.pump(const Duration(milliseconds: 60));
      // Mid-transition both old and new are staged by AnimatedSwitcher.
      expect(find.byType(FadeTransition), findsWidgets);
      await tester.pumpAndSettle();
      expect(find.text('B'), findsOneWidget);
      expect(find.text('A'), findsNothing);
    });

    testWidgets('reduced motion swaps instantly with no fade', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host('A', reduced: true));
      await tester.pumpWidget(_host('B', reduced: true));
      await tester.pump();
      expect(find.text('B'), findsOneWidget);
      expect(find.text('A'), findsNothing);
      expect(find.byType(FadeTransition), findsNothing);
    });
  });
}
