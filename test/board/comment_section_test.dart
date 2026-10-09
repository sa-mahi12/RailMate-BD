import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/board/comments/comment.dart';
import 'package:railmate_bd/features/board/comments/comment_section.dart';

/// Comment section wiring: the per-post thread UI over injected fakes.
/// State-level rules live in `board_comments_b08_test.dart`; this file pins
/// the consumer contract: collapsed label, expand-to-load, composer gating,
/// delete confirmation, and no raw ids on screen.
void main() {
  Comment row(String id, String userId, String body) => Comment(
    id: id,
    postId: 'p1',
    userId: userId,
    body: body,
    createdAt: DateTime(2026, 10, 4, 10, 0),
  );

  Future<void> pumpSection(
    WidgetTester tester, {
    required List<Comment> rows,
    String? currentUserId,
    Future<Comment> Function({
      required String postId,
      required String userId,
      required String body,
    })?
    add,
    Future<void> Function(String commentId)? remove,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CommentSection(
          postId: 'p1',
          currentUserId: currentUserId,
          fetchComments: ({required String postId}) async => rows,
          addComment:
              add ??
              ({
                required String postId,
                required String userId,
                required String body,
              }) async => row('new', userId, body),
          deleteComment: remove ?? (_) async {},
        ),
      ),
    ),
  );

  Future<void> expand(WidgetTester tester) async {
    await tester.tap(find.text('Comments'));
    await tester.pumpAndSettle();
  }

  group('collapsed section', () {
    testWidgets('shows no invented count before a load', (
      WidgetTester tester,
    ) async {
      await pumpSection(tester, rows: const <Comment>[]);
      expect(find.text('Comments'), findsOneWidget);
      expect(find.textContaining('('), findsNothing);
    });

    testWidgets('expanding loads and shows the count', (
      WidgetTester tester,
    ) async {
      await pumpSection(tester, rows: <Comment>[row('c1', 'u2', 'Nice trip')]);
      await expand(tester);
      expect(find.text('Comments (1)'), findsOneWidget);
      expect(find.text('Nice trip'), findsOneWidget);
    });
  });

  group('thread states', () {
    testWidgets('empty thread is honest', (WidgetTester tester) async {
      await pumpSection(tester, rows: const <Comment>[]);
      await expand(tester);
      expect(find.text('No comments yet'), findsOneWidget);
    });

    testWidgets('load failure offers retry, never zeros', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentSection(
              postId: 'p1',
              currentUserId: 'u1',
              fetchComments: ({required String postId}) async =>
                  throw Exception('down'),
              addComment: ({
                required String postId,
                required String userId,
                required String body,
              }) async => row('new', userId, body),
              deleteComment: (_) async {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('Comments'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load the comments."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('authors read as You/Traveller, never raw ids', (
      WidgetTester tester,
    ) async {
      await pumpSection(
        tester,
        rows: <Comment>[row('c1', 'u1', 'Mine'), row('c2', 'u9', 'Theirs')],
        currentUserId: 'u1',
      );
      await expand(tester);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('Traveller'), findsOneWidget);
      expect(find.text('u1'), findsNothing);
      expect(find.text('u9'), findsNothing);
    });
  });

  group('composer gating', () {
    testWidgets('signed-out readers get rows plus a hint, no composer', (
      WidgetTester tester,
    ) async {
      await pumpSection(
        tester,
        rows: <Comment>[row('c1', 'u2', 'Hello')],
        currentUserId: null,
      );
      await expand(tester);
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('Sign in to join the conversation.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('posting appends the row and clears the field', (
      WidgetTester tester,
    ) async {
      await pumpSection(tester, rows: const <Comment>[], currentUserId: 'u1');
      await expand(tester);
      await tester.enterText(find.byType(TextField), 'Great journey');
      await tester.tap(find.byTooltip('Post comment'));
      await tester.pumpAndSettle();
      expect(find.text('Great journey'), findsOneWidget);
      expect(find.text('Comments (1)'), findsOneWidget);
    });

    testWidgets('empty draft is refused with guidance, not silence', (
      WidgetTester tester,
    ) async {
      var adds = 0;
      await pumpSection(
        tester,
        rows: const <Comment>[],
        currentUserId: 'u1',
        add:
            ({
              required String postId,
              required String userId,
              required String body,
            }) async {
              adds++;
              return row('new', userId, body);
            },
      );
      await expand(tester);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.byTooltip('Post comment'));
      await tester.pumpAndSettle();
      expect(adds, 0);
      expect(
        find.text("Couldn't save that — please try again."),
        findsOneWidget,
      );
    });
  });

  group('delete flow', () {
    testWidgets('own rows offer delete behind a confirmation', (
      WidgetTester tester,
    ) async {
      var deletes = 0;
      await pumpSection(
        tester,
        rows: <Comment>[row('c1', 'u1', 'Mine')],
        currentUserId: 'u1',
        remove: (_) async {
          deletes++;
        },
      );
      await expand(tester);
      await tester.tap(find.byTooltip('Delete comment'));
      await tester.pumpAndSettle();
      expect(find.text('Delete comment?'), findsOneWidget);
      // Backing out keeps the row.
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(deletes, 0);
      expect(find.text('Mine'), findsOneWidget);
      // Confirming removes it.
      await tester.tap(find.byTooltip('Delete comment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(deletes, 1);
      expect(find.text('Mine'), findsNothing);
    });

    testWidgets("others' rows have no delete affordance", (
      WidgetTester tester,
    ) async {
      await pumpSection(
        tester,
        rows: <Comment>[row('c1', 'u2', 'Theirs')],
        currentUserId: 'u1',
      );
      await expand(tester);
      expect(find.byTooltip('Delete comment'), findsNothing);
    });
  });
}
