import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/design/motion/pressable.dart';
import 'package:railmate_bd/design/motion/reduced_motion.dart';

void main() {
  group('PressScale', () {
    testWidgets('scales down while pressed and fires onTap on release', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: PressScale(
              onTap: () => taps++,
              child: const Text('go', textDirection: TextDirection.ltr),
            ),
          ),
        ),
      );
      expect(find.byType(AnimatedScale), findsOneWidget);
      AnimatedScale scale = tester.widget<AnimatedScale>(
        find.byType(AnimatedScale),
      );
      expect(scale.scale, 1.0);

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.text('go')),
      );
      await tester.pump();
      scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scale.scale, 0.985);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, 1);
      scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scale.scale, 1.0);
    });

    testWidgets('reduced motion keeps taps with no scale wrapper', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MotionGate(
            overrideReduced: true,
            child: Center(
              child: PressScale(
                onTap: () => taps++,
                child: const Text('go', textDirection: TextDirection.ltr),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(AnimatedScale), findsNothing);
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(taps, 1);
    });
  });
}
