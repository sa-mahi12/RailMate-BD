import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/board/post/post.dart';
import 'package:railmate_bd/features/board/post/post_engagement.dart';
import 'package:railmate_bd/features/board/ratings/rating.dart';
import 'package:railmate_bd/features/board/reactions/reaction.dart';
import 'package:railmate_bd/features/board/reactions/reaction_realtime.dart';

/// Cross-client live reaction counts (teacher final gate, 2026-11-03).
///
/// The REAL [PostEngagement] is driven by an injected broadcast stream — the
/// exact seam the composition root feeds from one `public.post_reactions`
/// channel. Each assertion pins the packet's rule: another client's change
/// updates the count without user refresh, and the count always comes from an
/// authoritative row refetch (never from a locally incremented aggregate), so
/// an echoed own vote can never double count.
void main() {
  late StreamController<ReactionRealtimeEvent> events;
  late List<PostReaction> rows;
  late int fetches;

  final Post post = Post(
    id: 'p1',
    userId: 'u9',
    body: 'Trip report',
    createdAt: DateTime(2026, 11, 3, 9),
  );

  setUp(() {
    events = StreamController<ReactionRealtimeEvent>.broadcast();
    rows = <PostReaction>[];
    fetches = 0;
  });

  tearDown(() async {
    await events.close();
  });

  Future<void> pumpEngagement(
    WidgetTester tester, {
    String? currentUserId = 'u1',
    bool withRealtime = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PostEngagement(
              post: post,
              currentUserId: currentUserId,
              realtime: withRealtime ? events.stream : null,
              fetchReactions: (String postId) async {
                fetches++;
                return rows
                    .where((PostReaction r) => r.postId == postId)
                    .toList();
              },
              upsertReaction:
                  ({
                    required String postId,
                    required String userId,
                    required ReactionValue reaction,
                  }) async {
                    rows.removeWhere(
                      (PostReaction r) =>
                          r.postId == postId && r.userId == userId,
                    );
                    rows.add(
                      PostReaction(
                        postId: postId,
                        userId: userId,
                        reaction: reaction,
                      ),
                    );
                  },
              deleteReaction:
                  ({required String postId, required String userId}) async {
                    rows.removeWhere(
                      (PostReaction r) =>
                          r.postId == postId && r.userId == userId,
                    );
                  },
              fetchRatings: (String postId) async => <PostRating>[],
              upsertRating: ({
                required String postId,
                required String userId,
                required int stars,
              }) async {},
              deleteRating: ({
                required String postId,
                required String userId,
              }) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder likeCount(String label) =>
      find.descendant(of: find.byTooltip('Like'), matching: find.text(label));

  Finder dislikeCount(String label) => find.descendant(
    of: find.byTooltip('Dislike'),
    matching: find.text(label),
  );

  group('external reaction changes', () {
    testWidgets("another client's like updates the count with no refresh", (
      WidgetTester tester,
    ) async {
      await pumpEngagement(tester);
      expect(fetches, 1);
      expect(likeCount('0'), findsOneWidget);

      rows.add(
        const PostReaction(
          postId: 'p1',
          userId: 'u2',
          reaction: ReactionValue.like,
        ),
      );
      events.add(
        const ReactionRealtimeEvent(
          eventId: 'r1',
          kind: ReactionRealtimeKind.insert,
          postId: 'p1',
        ),
      );
      await tester.pumpAndSettle();

      expect(likeCount('1'), findsOneWidget);
      expect(
        fetches,
        2,
        reason: 'the card refetches authoritative rows on the event',
      );
    });

    testWidgets('an update (like -> dislike) moves both counts', (
      WidgetTester tester,
    ) async {
      rows.add(
        const PostReaction(
          postId: 'p1',
          userId: 'u2',
          reaction: ReactionValue.like,
        ),
      );
      await pumpEngagement(tester);
      expect(likeCount('1'), findsOneWidget);

      rows
        ..clear()
        ..add(
          const PostReaction(
            postId: 'p1',
            userId: 'u2',
            reaction: ReactionValue.dislike,
          ),
        );
      events.add(
        const ReactionRealtimeEvent(
          eventId: 'r2',
          kind: ReactionRealtimeKind.update,
          postId: 'p1',
        ),
      );
      await tester.pumpAndSettle();

      expect(likeCount('0'), findsOneWidget);
      expect(dislikeCount('1'), findsOneWidget);
    });

    testWidgets('a delete removes the count', (WidgetTester tester) async {
      rows.add(
        const PostReaction(
          postId: 'p1',
          userId: 'u2',
          reaction: ReactionValue.like,
        ),
      );
      await pumpEngagement(tester);
      expect(likeCount('1'), findsOneWidget);

      rows.clear();
      events.add(
        const ReactionRealtimeEvent(
          eventId: 'r3',
          kind: ReactionRealtimeKind.delete,
          postId: 'p1',
        ),
      );
      await tester.pumpAndSettle();

      expect(likeCount('0'), findsOneWidget);
    });

    testWidgets('an event for another post is ignored', (
      WidgetTester tester,
    ) async {
      await pumpEngagement(tester);
      final int before = fetches;

      events.add(
        const ReactionRealtimeEvent(
          eventId: 'r4',
          kind: ReactionRealtimeKind.insert,
          postId: 'p2',
        ),
      );
      await tester.pumpAndSettle();

      expect(fetches, before);
      expect(likeCount('0'), findsOneWidget);
    });

    testWidgets('own vote plus realtime echo is never double counted', (
      WidgetTester tester,
    ) async {
      await pumpEngagement(tester);

      await tester.tap(find.byTooltip('Like'));
      await tester.pumpAndSettle();
      expect(likeCount('1'), findsOneWidget);

      // The server echoes the same row back through the shared channel.
      events.add(
        const ReactionRealtimeEvent(
          eventId: 'echo-1',
          kind: ReactionRealtimeKind.insert,
          postId: 'p1',
        ),
      );
      await tester.pumpAndSettle();

      expect(likeCount('1'), findsOneWidget);
      expect(likeCount('2'), findsNothing);
    });

    testWidgets('signed-out readers see live counts but cannot vote', (
      WidgetTester tester,
    ) async {
      await pumpEngagement(tester, currentUserId: null);

      rows.add(
        const PostReaction(
          postId: 'p1',
          userId: 'u2',
          reaction: ReactionValue.like,
        ),
      );
      events.add(
        const ReactionRealtimeEvent(
          eventId: 'r5',
          kind: ReactionRealtimeKind.insert,
          postId: 'p1',
        ),
      );
      await tester.pumpAndSettle();

      expect(likeCount('1'), findsOneWidget);
      expect(find.text('Sign in to react or rate.'), findsOneWidget);
    });
  });

  group('lifecycle', () {
    testWidgets('disposing the card cancels its subscription', (
      WidgetTester tester,
    ) async {
      await pumpEngagement(tester);
      expect(events.hasListener, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(events.hasListener, isFalse);

      events.add(
        const ReactionRealtimeEvent(
          eventId: 'late',
          kind: ReactionRealtimeKind.delete,
          postId: 'p1',
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
