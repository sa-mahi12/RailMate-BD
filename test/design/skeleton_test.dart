import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/design/motion/reduced_motion.dart';
import 'package:railmate_bd/design/motion/skeleton.dart';

BoxDecoration _decoration(WidgetTester tester) {
  final Container container = tester.widget<Container>(
    find.byType(Container).first,
  );
  return container.decoration! as BoxDecoration;
}

void main() {
  group('SkeletonBlock', () {
    testWidgets('renders a bounded shimmer sweep', (WidgetTester tester) async {
      await tester.pumpWidget(const SkeletonBlock(width: 120, height: 16));
      expect(find.byType(SkeletonBlock), findsOneWidget);
      BoxDecoration decoration = _decoration(tester);
      expect(decoration.gradient, isNotNull);

      // Advance the sweep manually (a repeating controller never settles).
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      decoration = _decoration(tester);
      expect(decoration.gradient, isNotNull);
      final Container container = tester.widget<Container>(
        find.byType(Container).first,
      );
      // Bounded: the requested size is pinned via tight constraints, so the
      // layout cannot jump when real content arrives.
      expect(container.constraints?.maxWidth, 120);
      expect(container.constraints?.maxHeight, 16);
    });

    testWidgets('reduced motion renders a static block', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MotionGate(
          overrideReduced: true,
          child: SkeletonBlock(width: 120, height: 16),
        ),
      );
      await tester.pump();
      final BoxDecoration decoration = _decoration(tester);
      expect(decoration.gradient, isNull);
      expect(decoration.color, isNotNull);
    });
  });
}
