import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/design/motion/reduced_motion.dart';

Widget _probe() {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Builder(
      builder: (BuildContext context) {
        final bool reduced = ReducedMotion.isReduced(context);
        return Text(
          reduced ? 'reduced' : 'full',
          textDirection: TextDirection.ltr,
        );
      },
    ),
  );
}

void main() {
  group('ReducedMotion / MotionGate', () {
    testWidgets('defaults to full motion when system allows it', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(MotionGate(child: _probe()));
      expect(find.text('full'), findsOneWidget);
    });

    testWidgets('override forces reduced branch', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MotionGate(overrideReduced: true, child: _Probe()),
      );
      expect(find.text('reduced'), findsOneWidget);
    });

    testWidgets('override can force full motion', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MotionGate(overrideReduced: false, child: _Probe()),
        ),
      );
      expect(find.text('full'), findsOneWidget);
    });

    testWidgets('follows system disableAnimations when override is null', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MotionGate(child: _probe()),
        ),
      );
      expect(find.text('reduced'), findsOneWidget);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: MotionGate(child: _probe()),
        ),
      );
      expect(find.text('full'), findsOneWidget);
    });

    testWidgets('notifies dependents when the branch flips', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MotionGate(overrideReduced: false, child: _Probe()),
      );
      expect(find.text('full'), findsOneWidget);
      await tester.pumpWidget(
        const MotionGate(overrideReduced: true, child: _Probe()),
      );
      expect(find.text('reduced'), findsOneWidget);
    });
  });
}

class _Probe extends StatelessWidget {
  const _Probe();

  @override
  Widget build(BuildContext context) {
    final bool reduced = ReducedMotion.isReduced(context);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text(
        reduced ? 'reduced' : 'full',
        textDirection: TextDirection.ltr,
      ),
    );
  }
}
