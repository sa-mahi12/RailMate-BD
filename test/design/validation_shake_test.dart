import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/design/motion/reduced_motion.dart';
import 'package:railmate_bd/design/motion/validation_shake.dart';

const Widget _child = Text('field', textDirection: TextDirection.ltr);

Widget _host({required int trigger, bool reduced = false}) {
  return MotionGate(
    overrideReduced: reduced ? true : null,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: ValidationShake(shakeTrigger: trigger, child: _child),
    ),
  );
}

void main() {
  group('ValidationShake', () {
    testWidgets('replays one shake per trigger and keeps the child', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(trigger: 0));
      expect(find.text('field'), findsOneWidget);

      await tester.pumpWidget(_host(trigger: 1));
      await tester.pumpAndSettle();
      expect(find.text('field'), findsOneWidget);

      // A second bump replays again without losing the child.
      await tester.pumpWidget(_host(trigger: 2));
      await tester.pumpAndSettle();
      expect(find.text('field'), findsOneWidget);
    });

    testWidgets('imperative shake() completes', (WidgetTester tester) async {
      final GlobalKey<ValidationShakeState> key =
          GlobalKey<ValidationShakeState>();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ValidationShake(key: key, child: _child),
        ),
      );
      // Start the shake without awaiting: the controller future only
      // completes once test frames are pumped below.
      final Future<void> pending = key.currentState!.shake();
      await tester.pumpAndSettle();
      await pending;
      expect(find.text('field'), findsOneWidget);
    });

    testWidgets('reduced motion skips the shake', (WidgetTester tester) async {
      final GlobalKey<ValidationShakeState> key =
          GlobalKey<ValidationShakeState>();
      await tester.pumpWidget(
        MotionGate(
          overrideReduced: true,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ValidationShake(key: key, child: _child),
          ),
        ),
      );
      await key.currentState!.shake();
      await tester.pump();
      expect(find.text('field'), findsOneWidget);
    });
  });
}
