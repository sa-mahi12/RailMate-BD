import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/board/post/post.dart';
import 'package:railmate_bd/features/board/post/post_engagement.dart';
import 'package:railmate_bd/features/board/ratings/rating.dart';
import 'package:railmate_bd/features/board/ratings/rating_realtime.dart';
import 'package:railmate_bd/features/board/reactions/reaction.dart';

/// Cross-client live 1-5 star ratings (R-07, 2026-11-14).
///
/// The real [PostEngagement] is driven by an injected broadcast stream — the
/// exact seam the composition root feeds from one `public.post_ratings`
/// channel. Ratings are a *separate* table from reactions, so these tests pin
/// that a peer rating updates the authoritative average/count without a user
/// refresh, that unrelated posts are ignored, that a burst is coalesced, and
/// that an echoed own rating can never double count.
void main() {
  late StreamController<RatingRealtimeEvent> events;
  late List<PostRating> rows;
  late int ratingFetches;
  late int reactionFetches;

  final Post post = Post(
    id: 'p1',
    userId: 'u9',
    body: 'Trip report',
    createdAt: DateTime(2026, 11, 14, 9),
  );

  setUp(() {
    events = StreamController<RatingRealtimeEvent>.broadcast();
    rows = <PostRating>[];
    ratingFetches = 0;
    reactionFetches = 0;
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
              ratingRealtime: withRealtime ? events.stream : null,
              fetchReactions: (String postId) async {
                reactionFetches++;
                return <PostReaction>[];
              },
              upsertReaction: ({
                required String postId,
                required String userId,
                required ReactionValue reaction,
              }) async {},
              deleteReaction: ({
                required String postId,
                required String userId,
              }) async {},
              fetchRatings: (String postId) async {
                ratingFetches++;
                return rows
                    .where((PostRating r) => r.postId == postId)
                    .toList();
              },
              upsertRating:
                  ({
                    required String postId,
                    required String userId,
                    required int stars,
                  }) async {
                    rows.removeWhere(
                      (PostRating r) =>
                          r.postId == postId && r.userId == userId,
                    );
                    rows.add(
                      PostRating(postId: postId, userId: userId, stars: stars),
                    );
                  },
              deleteRating:
                  ({required String postId, required String userId}) async {
                    rows.removeWhere(
                      (PostRating r) =>
                          r.postId == postId && r.userId == userId,
                    );
                  },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('cross-client star ratings', () {
    testWidgets("another client's 5-star rating updates the average", (
      WidgetTester tester,
    ) async {
      await pumpEngagement(tester);
      expect(ratingFetches, 1);
      expect(find.text('No ratings yet'), findsOneWidget);

      rows.add(const PostRating(postId: 'p1', userId: 'u2', stars: 5));
      events.add(
        const RatingRealtimeEvent(
          eventId: 'g1',
          kind: RatingRealtimeKind.insert,
          postId: 'p1',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('5.0 (1)'), findsOneWidget);
      expect(
        ratingFetches,
        2,
        reason: 'the card refetches authoritative rating rows on the event',
      );
      // Ratings must not borrow the reactions channel to update.
      expect(reactionFetches, 1);
    });

    testWidgets('changing 5 -> 2 recomputes the mean on the peer', (
      WidgetTester tester,
    ) async {
      rows.add(const PostRating(postId: 'p1', userId: 'u2', stars: 5));
      await pumpEngagement(tester);
      expect(find.text('5.0 (1)'), findsOneWidget);

      rows
        ..clear()
        ..add(const PostRating(postId: 'p1', userId: 'u2', stars: 2));
      events.add(
        const RatingRealtimeEvent(
          eventId: 'g2',
          kind: RatingRealtimeKind.update,
          postId: 'p1',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2.0 (1)'), findsOneWidget);
    });

    testWidgets('a removed rating drops the count', (
      WidgetTester tester,
    ) async {
      rows
        ..add(const PostRating(postId: 'p1', userId: 'u2', stars: 4))
        ..add(const PostRating(postId: 'p1', userId: 'u3', stars: 2));
      await pumpEngagement(tester);
      expect(find.text('3.0 (2)'), findsOneWidget);

      rows.removeWhere((PostRating r) => r.userId == 'u2');
      events.add(
        const RatingRealtimeEvent(
          eventId: 'g3',
          kind: RatingRealtimeKind.delete,
          postId: 'p1',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2.0 (1)'), findsOneWidget);
    });

    testWidgets('an event for another post is ignored', (
      WidgetTester tester,
    ) async {
      await pumpEngagement(tester);
      final int before = ratingFetches;

      events.add(
        const RatingRealtimeEvent(
          eventId: 'g4',
          kind: RatingRealtimeKind.insert,
          postId: 'p2',
        ),
      );
      await tester.pumpAndSettle();

      expect(ratingFetches, before);
      expect(find.text('No ratings yet'), findsOneWidget);
    });

    testWidgets('own rating plus realtime echo is never double counted', (
      WidgetTester tester,
    ) async {
      await pumpEngagement(tester);

      await tester.tap(find.byTooltip('Rate 5 stars'));
      await tester.pumpAndSettle();
      expect(find.text('5.0 (1)'), findsOneWidget);

      events.add(
        const RatingRealtimeEvent(
          eventId: 'echo-1',
          kind: RatingRealtimeKind.insert,
          postId: 'p1',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('5.0 (1)'), findsOneWidget);
      expect(find.text('5.0 (2)'), findsNothing);
    });

    testWidgets('a burst of peer events is coalesced into few refetches', (
      WidgetTester tester,
    ) async {
      // Slow fetch so the events land while one refetch is in flight.
      final Completer<void> gate = Completer<void>();
      bool gated = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PostEngagement(
              post: post,
              currentUserId: 'u1',
              ratingRealtime: events.stream,
              fetchReactions: (String postId) async => <PostReaction>[],
              upsertReaction: ({
                required String postId,
                required String userId,
                required ReactionValue reaction,
              }) async {},
              deleteReaction: ({
                required String postId,
                required String userId,
              }) async {},
              fetchRatings: (String postId) async {
                ratingFetches++;
                if (!gated) {
                  gated = true;
                  await gate.future;
                }
                return rows
                    .where((PostRating r) => r.postId == postId)
                    .toList();
              },
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
      );
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();
      final int initial = ratingFetches;

      for (var i = 0; i < 5; i++) {
        events.add(
          RatingRealtimeEvent(
            eventId: 'burst-$i',
            kind: RatingRealtimeKind.update,
            postId: 'p1',
          ),
        );
      }
      await tester.pumpAndSettle();

      // Five events must not mean five concurrent fetches; at most the
      // in-flight one plus one queued follow-up.
      expect(ratingFetches - initial, lessThanOrEqualTo(2));
    });

    testWidgets('signed-out readers still see live aggregates', (
      WidgetTester tester,
    ) async {
      await pumpEngagement(tester, currentUserId: null);

      rows.add(const PostRating(postId: 'p1', userId: 'u2', stars: 3));
      events.add(
        const RatingRealtimeEvent(
          eventId: 'g5',
          kind: RatingRealtimeKind.insert,
          postId: 'p1',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('3.0 (1)'), findsOneWidget);
      expect(find.text('Sign in to react or rate.'), findsOneWidget);
    });
  });

  group('lifecycle', () {
    testWidgets('disposing the card cancels its rating subscription', (
      WidgetTester tester,
    ) async {
      await pumpEngagement(tester);
      expect(events.hasListener, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(events.hasListener, isFalse);

      events.add(
        const RatingRealtimeEvent(
          eventId: 'late',
          kind: RatingRealtimeKind.delete,
          postId: 'p1',
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('RatingRealtimeEvent', () {
    test('applies only to its own non-empty post', () {
      const RatingRealtimeEvent event = RatingRealtimeEvent(
        eventId: 'e',
        kind: RatingRealtimeKind.insert,
        postId: 'p1',
      );
      expect(event.appliesTo('p1'), isTrue);
      expect(event.appliesTo('p2'), isFalse);
      expect(event.appliesTo(''), isFalse);
    });
  });
}
