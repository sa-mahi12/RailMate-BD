import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/design/motion/fade_slide_in.dart';
import 'package:railmate_bd/design/motion/reduced_motion.dart';
import 'package:railmate_bd/design/motion/staggered_list.dart';

Widget _text(String value) =>
    Text(value, textDirection: TextDirection.ltr, key: ValueKey<String>(value));

void main() {
  group('StaggeredColumn', () {
    testWidgets('reveals every child', (WidgetTester tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: StaggeredColumn(
            children: <Widget>[_text('a'), _text('b'), _text('c')],
          ),
        ),
      );
      expect(find.byType(FadeSlideIn), findsNWidgets(3));
      await tester.pumpAndSettle();
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
      expect(find.text('c'), findsOneWidget);
      final AnimatedOpacity first = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity).first,
      );
      expect(first.opacity, 1.0);
    });

    testWidgets('reduced motion skips stagger wrappers', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: const MotionGate(
            overrideReduced: true,
            child: StaggeredColumn(
              children: <Widget>[
                Text('a', textDirection: TextDirection.ltr),
                Text('b', textDirection: TextDirection.ltr),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
      expect(find.byType(AnimatedOpacity), findsNothing);
    });
  });

  group('StaggeredList', () {
    testWidgets('builds rows with per-item entrances', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            height: 400,
            child: StaggeredList(
              itemCount: 3,
              itemBuilder: (BuildContext context, int index) =>
                  _text('row$index'),
            ),
          ),
        ),
      );
      expect(find.byType(FadeSlideIn), findsNWidgets(3));
      await tester.pumpAndSettle();
      expect(find.text('row0'), findsOneWidget);
      expect(find.text('row1'), findsOneWidget);
      expect(find.text('row2'), findsOneWidget);
    });
  });
}
