import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/design/motion/fade_slide_in.dart';
import 'package:railmate_bd/design/motion/reduced_motion.dart';

const Widget _child = Text('hello', textDirection: TextDirection.ltr);

Widget _host({bool reduced = false}) {
  return MotionGate(
    overrideReduced: reduced ? true : null,
    child: const Directionality(
      textDirection: TextDirection.ltr,
      child: FadeSlideIn(delay: Duration(milliseconds: 50), child: _child),
    ),
  );
}

void main() {
  group('FadeSlideIn', () {
    testWidgets('starts hidden then settles on the final state', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host());
      AnimatedOpacity opacity = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(opacity.opacity, 0.0);
      expect(find.text('hello'), findsOneWidget);

      await tester.pumpAndSettle();
      opacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(opacity.opacity, 1.0);
      expect(find.text('hello'), findsOneWidget);
    });

    testWidgets('supports entrance scale', (WidgetTester tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: FadeSlideIn(beginScale: 0.94, child: _child),
        ),
      );
      expect(find.byType(AnimatedScale), findsOneWidget);
      await tester.pumpAndSettle();
      final AnimatedScale scale = tester.widget<AnimatedScale>(
        find.byType(AnimatedScale),
      );
      expect(scale.scale, 1.0);
    });

    testWidgets('reduced motion renders the final state immediately', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(reduced: true));
      expect(find.byType(AnimatedOpacity), findsNothing);
      expect(find.byType(AnimatedScale), findsNothing);
      expect(find.text('hello'), findsOneWidget);
      // Even a settle pass must not introduce wrappers.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('hello'), findsOneWidget);
    });
  });
}
