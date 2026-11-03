import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/board/comments/comment.dart';
import 'package:railmate_bd/features/board/comments/comment_section.dart';
import 'package:railmate_bd/features/board/comments/comment_subscription.dart';

/// Cross-client comment behaviour (teacher final gate, 2026-11-03).
///
/// These tests drive the REAL [CommentSection] with an injected broadcast
/// stream — the same seam the composition root feeds from one Supabase
/// `public.post_comments` channel. They assert that an event changes the open
/// thread WITHOUT calling the fetcher again, which is exactly what "another
/// client's comment appears without refresh" means. No test here calls
/// `load()` after the initial expand to fake liveness.
void main() {
  Comment row(
    String id, {
    String postId = 'p1',
    String body = 'Hello there',
    int minute = 0,
  }) => Comment(
    id: id,
    postId: postId,
    userId: 'u2',
    body: body,
    createdAt: DateTime(2026, 11, 3, 10, minute),
  );

  late StreamController<CommentRealtimeEvent> events;

  setUp(() {
    events = StreamController<CommentRealtimeEvent>.broadcast();
  });

  tearDown(() async {
    await events.close();
  });

  /// Pumps one section and returns a counter of real fetch calls.
  Future<List<int>> pumpSection(
    WidgetTester tester, {
    required List<Comment> rows,
    String postId = 'p1',
    String? currentUserId = 'u1',
    bool withRealtime = true,
  }) async {
    final List<int> fetches = <int>[0];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommentSection(
            postId: postId,
            currentUserId: currentUserId,
            realtime: withRealtime ? events.stream : null,
            fetchComments: ({required String postId}) async {
              fetches[0]++;
              return rows.where((Comment c) => c.postId == postId).toList();
            },
            addComment:
                ({
                  required String postId,
                  required String userId,
                  required String body,
                }) async => Comment(
                  id: 'own-1',
                  postId: postId,
                  userId: userId,
                  body: body,
                  createdAt: DateTime(2026, 11, 3, 11),
                ),
            deleteComment: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fetches;
  }

  Future<void> expand(WidgetTester tester) async {
    await tester.tap(find.text('Comments'));
    await tester.pumpAndSettle();
  }

  group('external comment mutations', () {
    testWidgets('another client\'s insert appears with no reload', (
      WidgetTester tester,
    ) async {
      final List<int> fetches = await pumpSection(
        tester,
        rows: <Comment>[row('c1', body: 'First', minute: 0)],
      );
      await expand(tester);
      expect(find.text('Comments (1)'), findsOneWidget);
      expect(fetches.single, 1, reason: 'only the initial load ran');

      events.add(
        CommentRealtimeEvent(
          eventId: 'e1',
          kind: CommentEventKind.insert,
          comment: row('c2', body: 'From the other client', minute: 5),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('From the other client'), findsOneWidget);
      expect(find.text('Comments (2)'), findsOneWidget);
      expect(
        fetches.single,
        1,
        reason: 'realtime merges the row; it must not re-query',
      );
    });

    testWidgets('another client\'s delete disappears with no reload', (
      WidgetTester tester,
    ) async {
      final List<int> fetches = await pumpSection(
        tester,
        rows: <Comment>[
          row('c1', body: 'Keep me', minute: 0),
          row('c2', body: 'Remove me', minute: 5),
        ],
      );
      await expand(tester);
      expect(find.text('Remove me'), findsOneWidget);

      events.add(
        const CommentRealtimeEvent(
          eventId: 'e2',
          kind: CommentEventKind.delete,
          commentId: 'c2',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Remove me'), findsNothing);
      expect(find.text('Keep me'), findsOneWidget);
      expect(find.text('Comments (1)'), findsOneWidget);
      expect(fetches.single, 1);
    });

    testWidgets('an event for another post is ignored', (
      WidgetTester tester,
    ) async {
      final List<int> fetches = await pumpSection(
        tester,
        rows: <Comment>[row('c1', body: 'Mine', minute: 0)],
      );
      await expand(tester);

      events.add(
        CommentRealtimeEvent(
          eventId: 'e3',
          kind: CommentEventKind.insert,
          comment: row('c9', postId: 'p2', body: 'Other post'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Other post'), findsNothing);
      expect(find.text('Comments (1)'), findsOneWidget);
      expect(fetches.single, 1);
    });

    testWidgets('own insert plus realtime echo is never duplicated', (
      WidgetTester tester,
    ) async {
      await pumpSection(tester, rows: const <Comment>[]);
      await expand(tester);

      await tester.enterText(find.byType(TextField), 'My own note');
      await tester.tap(find.byTooltip('Post comment'));
      await tester.pumpAndSettle();
      expect(find.text('My own note'), findsOneWidget);

      // The server echoes the same row id back through the channel.
      events.add(
        CommentRealtimeEvent(
          eventId: 'echo-1',
          kind: CommentEventKind.insert,
          comment: Comment(
            id: 'own-1',
            postId: 'p1',
            userId: 'u1',
            body: 'My own note',
            createdAt: DateTime(2026, 11, 3, 11),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My own note'), findsOneWidget);
      expect(find.text('Comments (1)'), findsOneWidget);
    });

    testWidgets('nothing is merged before the thread is first loaded', (
      WidgetTester tester,
    ) async {
      await pumpSection(tester, rows: const <Comment>[]);

      // Collapsed, never loaded: an event must NOT invent a count.
      events.add(
        CommentRealtimeEvent(
          eventId: 'e4',
          kind: CommentEventKind.insert,
          comment: row('c5', body: 'Early bird'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Comments'), findsOneWidget);

      await expand(tester);
      expect(find.text('Comment'), findsOneWidget);
    });
  });

  group('lifecycle', () {
    testWidgets('disposing the section cancels its subscription', (
      WidgetTester tester,
    ) async {
      await pumpSection(tester, rows: <Comment>[row('c1')]);
      await expand(tester);
      expect(events.hasListener, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(events.hasListener, isFalse);

      // A late event after disposal must be a no-op, not a crash.
      events.add(
        const CommentRealtimeEvent(
          eventId: 'late',
          kind: CommentEventKind.delete,
          commentId: 'c1',
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('signed-out readers stay read-only while live', (
      WidgetTester tester,
    ) async {
      final List<int> fetches = await pumpSection(
        tester,
        rows: <Comment>[row('c1', body: 'Read only')],
        currentUserId: null,
      );
      await expand(tester);
      expect(find.text('Sign in to join the conversation.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      events.add(
        CommentRealtimeEvent(
          eventId: 'e5',
          kind: CommentEventKind.insert,
          comment: row('c2', body: 'New public row', minute: 3),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('New public row'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(fetches.single, 1);
    });
  });
}
