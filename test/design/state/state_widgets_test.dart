import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/design/motion/reduced_motion.dart';
import 'package:railmate_bd/design/state/state.dart';

/// Hosts a state with bounded space. [pumpSized] resolves the entrance
/// animation; without it tests observe the pre-entrance (hidden) frame.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool reduced = false,
  bool settle = false,
  EdgeInsets padding = const EdgeInsets.all(16),
}) async {
  await tester.pumpWidget(
    MotionGate(
      overrideReduced: reduced ? true : null,
      child: MaterialApp(
        home: Scaffold(
          body: Padding(padding: padding, child: child),
        ),
      ),
    ),
  );
  if (settle && !reduced) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  group('EmptyState', () {
    testWidgets('renders the caller title, message and action', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await _pump(
        tester,
        EmptyState(
          title: 'No bookings yet',
          message:
              'Search for a journey and confirmed demo tickets will appear '
              'here.',
          icon: Icons.confirmation_number_outlined,
          actionLabel: 'Find a train',
          onAction: () => taps++,
        ),
        settle: true,
      );

      expect(find.text('No bookings yet'), findsOneWidget);
      expect(
        find.text(
          'Search for a journey and confirmed demo tickets will appear here.',
        ),
        findsOneWidget,
      );
      expect(find.text('Find a train'), findsOneWidget);
      expect(find.byIcon(Icons.confirmation_number_outlined), findsOneWidget);

      await tester.tap(find.text('Find a train'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('renders no action when no label is supplied', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const EmptyState(
          title: 'No posts yet',
          message: 'Share a station or travel tip with the demo community.',
        ),
        settle: true,
      );
      expect(find.text('No posts yet'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('never invents copy: no generic fallback strings', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const EmptyState(title: 'Nothing here', message: 'Real copy.'),
        settle: true,
      );
      // Exactly the two supplied strings, nothing more.
      final Iterable<Text> texts = tester.widgetList<Text>(find.byType(Text));
      expect(texts.map((Text t) => t.data), <String>[
        'Nothing here',
        'Real copy.',
      ]);
    });

    testWidgets('inline mode sits in a token card surface', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const EmptyState(
          title: 'No demo services on this route/date',
          message: 'Try another date or route.',
          centered: false,
        ),
        settle: true,
      );
      expect(find.byType(StateCard), findsOneWidget);
      expect(find.text('No demo services on this route/date'), findsOneWidget);
    });
  });

  group('ErrorState', () {
    testWidgets('shows the human message and a Retry action', (
      WidgetTester tester,
    ) async {
      int retries = 0;
      await _pump(
        tester,
        ErrorState(
          title: 'Could not load bookings',
          message: 'You appear to be offline. Check your connection and retry.',
          onRetry: () => retries++,
        ),
        settle: true,
      );

      expect(find.text('Could not load bookings'), findsOneWidget);
      expect(
        find.text('You appear to be offline. Check your connection and retry.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retries, 1);
    });

    testWidgets('honours a custom retry label', (WidgetTester tester) async {
      await _pump(
        tester,
        ErrorState(
          message: 'Your session expired. Sign in again to continue.',
          retryLabel: 'Sign in again',
          onRetry: () {},
        ),
        settle: true,
      );
      expect(find.text('Sign in again'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('omits Retry for a read-only failure', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const ErrorState(message: 'You do not have access to this journey.'),
        settle: true,
      );
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('renders only the caller message, never a raw exception', (
      WidgetTester tester,
    ) async {
      const String mapped =
          'Booking failed: those seats were taken a moment ago.';
      await _pump(
        tester,
        const ErrorState(
          title: 'Booking failed',
          message: mapped,
          icon: Icons.event_seat_outlined,
        ),
        settle: true,
      );
      final Iterable<String> strings = tester
          .widgetList<Text>(find.byType(Text))
          .map((Text t) => t.data ?? '');
      expect(strings, containsAll(<String>['Booking failed', mapped]));
      expect(strings.any((String s) => s.contains('Exception')), isFalse);
    });
  });

  group('SuccessState', () {
    testWidgets('confirms a booking with the caller message', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const SuccessState(
          title: 'Booking confirmed',
          message: 'Your demonstration ticket is ready.',
        ),
        settle: true,
      );
      expect(find.text('Booking confirmed'), findsOneWidget);
      expect(find.text('Your demonstration ticket is ready.'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('optional follow-up action fires immediately', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await _pump(
        tester,
        SuccessState(
          title: 'Email verified',
          message: 'Your account is now verified.',
          actionLabel: 'Done',
          onAction: () => taps++,
        ),
        settle: true,
      );
      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(taps, 1);
    });
  });

  group('reduced motion', () {
    testWidgets('states render in their final state with no entrance', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const SuccessState(
          title: 'Cancellation complete',
          message: 'The demonstration booking was cancelled.',
        ),
        reduced: true,
      );
      expect(find.byType(StateEntrance), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(StateEntrance),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
      expect(find.text('Cancellation complete'), findsOneWidget);
    });

    testWidgets('no animation work is scheduled under reduced motion', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        ErrorState(message: 'Upload failed. Try again.', onRetry: () {}),
        reduced: true,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.descendant(
          of: find.byType(StateEntrance),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
      expect(find.text('Upload failed. Try again.'), findsOneWidget);
    });
  });

  group('entrance', () {
    testWidgets('states fade in over a short bounded window', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const EmptyState(
          title: 'No posts yet',
          message: 'Share a station or travel tip with the demo community.',
        ),
      );
      // The first frame is the pre-entrance hidden state.
      final Finder opacityFinder = find.descendant(
        of: find.byType(StateEntrance),
        matching: find.byType(Opacity),
      );
      expect(tester.widget<Opacity>(opacityFinder).opacity, 0.0);

      // Bounded: settled well inside the 450 ms slow budget.
      await tester.pumpAndSettle();
      expect(tester.widget<Opacity>(opacityFinder).opacity, 1.0);
    });

    testWidgets('content is present during the entrance', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const SuccessState(
          title: 'Post published',
          message: 'Your station tip is on the board.',
        ),
      );
      expect(find.text('Post published'), findsOneWidget);
    });
  });

  group('accessibility', () {
    testWidgets('the action is exposed as a semantic button', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pump(
        tester,
        ErrorState(
          message: 'Rate limit reached. Wait a moment and retry.',
          onRetry: () {},
        ),
        settle: true,
      );
      expect(find.bySemanticsLabel('Retry'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the state block is a live region', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pump(
        tester,
        const SuccessState(
          title: 'Key saved',
          message: 'Your OpenRouter key is stored on this device only.',
        ),
        settle: true,
      );
      final SemanticsNode node = tester.getSemantics(find.byType(SuccessState));
      expect(node.flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });
  });

  group('StateLayout', () {
    testWidgets('inline layout keeps text on the start edge', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const StateLayout(
          icon: Icons.inbox_outlined,
          title: 'Nothing scheduled',
          message: 'Confirmed demonstration journeys appear here.',
          accent: Colors.teal,
          centered: false,
        ),
        settle: true,
      );
      final Text title = tester.widget<Text>(find.text('Nothing scheduled'));
      expect(title.textAlign, TextAlign.start);
    });
  });
}
