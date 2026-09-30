import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/board/list/cursor_paginator.dart';
import 'package:railmate_bd/features/board/post/post.dart';
import 'package:railmate_bd/features/board/post/post_feed_realtime.dart';
import 'package:railmate_bd/features/board/post/post_feed_state.dart';
import 'package:railmate_bd/features/board/ratings/rating.dart';
import 'package:railmate_bd/features/board/ratings/rating_state.dart';
import 'package:railmate_bd/features/board/reactions/reaction.dart';
import 'package:railmate_bd/features/board/reactions/reaction_state.dart';

Post _post(String id, int minutesAgo, {String body = 'body'}) => Post(
  id: id,
  userId: 'uid1',
  body: '$body $id',
  createdAt: DateTime.utc(
    2026,
    9,
    28,
    12,
    0,
  ).subtract(Duration(minutes: minutesAgo)),
);

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  group('F13 realtime channel -> paginator state (fake channel)', () {
    test('insert lands at front; echo duplicate event is dropped', () async {
      final paginator = newPostPaginator(
        ({required int limit, before}) async => <Post>[
          _post('p2', 5),
          _post('p1', 9),
        ],
      );
      await paginator.loadFirst();
      expect(paginator.rows.map((p) => p.id), ['p2', 'p1']);

      final channel = StreamController<BoardPostEvent>();
      final realtime = BoardPostFeedRealtime();
      await realtime.subscribe(
        stream: channel.stream,
        onEvent: (e) => applyPostEventToPaginator(paginator, e),
      );
      expect(realtime.isSubscribed, isTrue);

      channel.add(
        BoardPostEvent(
          eventId: 'evt-1',
          kind: BoardPostEventKind.insert,
          post: _post('p3', 1),
        ),
      );
      await _flush();
      expect(paginator.rows.map((p) => p.id), ['p3', 'p2', 'p1']);
      expect(realtime.lastEventId, 'evt-1');
      expect(realtime.seenEventCount, 1);

      // At-least-once redelivery of the same event id: dropped, no dup row.
      channel.add(
        BoardPostEvent(
          eventId: 'evt-1',
          kind: BoardPostEventKind.insert,
          post: _post('p3', 1),
        ),
      );
      await _flush();
      expect(paginator.rows.map((p) => p.id), ['p3', 'p2', 'p1']);
      expect(realtime.seenEventCount, 1);

      // Empty event ids are dropped without invoking the sink.
      channel.add(
        const BoardPostEvent(
          eventId: '',
          kind: BoardPostEventKind.delete,
          postId: 'p3',
        ),
      );
      await _flush();
      expect(paginator.rows.map((p) => p.id), ['p3', 'p2', 'p1']);

      await realtime.dispose();
      await channel.close();
    });

    test(
      'update replaces in place; unknown update inserts; delete removes',
      () {
        final paginator = CursorPaginator<Post>(
          fetchPage: ({required int limit, before}) async => <Post>[],
          idOf: (p) => p.id,
          createdAtOf: (p) => p.createdAt,
        );
        expect(
          applyPostEventToPaginator(
            paginator,
            BoardPostEvent(
              eventId: 'e1',
              kind: BoardPostEventKind.insert,
              post: _post('p1', 9),
            ),
          ),
          isTrue,
        );
        expect(
          applyPostEventToPaginator(
            paginator,
            BoardPostEvent(
              eventId: 'e2',
              kind: BoardPostEventKind.insert,
              post: _post('p2', 5),
            ),
          ),
          isTrue,
        );
        // Echo of an already-loaded row: no-op, no duplicate.
        expect(
          applyPostEventToPaginator(
            paginator,
            BoardPostEvent(
              eventId: 'e3',
              kind: BoardPostEventKind.insert,
              post: _post('p2', 5),
            ),
          ),
          isFalse,
        );
        expect(paginator.rows.map((p) => p.id), ['p2', 'p1']);

        // Update keeps position, swaps content.
        expect(
          applyPostEventToPaginator(
            paginator,
            BoardPostEvent(
              eventId: 'e4',
              kind: BoardPostEventKind.update,
              post: Post(
                id: 'p1',
                userId: 'uid1',
                body: 'edited body',
                createdAt: DateTime.utc(2026, 9, 28, 11, 51),
              ),
            ),
          ),
          isTrue,
        );
        expect(paginator.rows.map((p) => p.id), ['p2', 'p1']);
        expect(paginator.rows.last.body, 'edited body');

        // Update for an id never loaded: genuinely new here, front-inserts.
        expect(
          applyPostEventToPaginator(
            paginator,
            BoardPostEvent(
              eventId: 'e5',
              kind: BoardPostEventKind.update,
              post: _post('p0', 0),
            ),
          ),
          isTrue,
        );
        expect(paginator.rows.first.id, 'p0');

        // Delete removes the visible row; unknown delete is a no-op.
        expect(
          applyPostEventToPaginator(
            paginator,
            const BoardPostEvent(
              eventId: 'e6',
              kind: BoardPostEventKind.delete,
              postId: 'p2',
            ),
          ),
          isTrue,
        );
        expect(paginator.rows.map((p) => p.id), ['p0', 'p1']);
        expect(
          applyPostEventToPaginator(
            paginator,
            const BoardPostEvent(
              eventId: 'e7',
              kind: BoardPostEventKind.delete,
              postId: 'missing',
            ),
          ),
          isFalse,
        );

        // Deleted ids stay seen: a stale echo-insert cannot resurrect the row.
        expect(
          applyPostEventToPaginator(
            paginator,
            BoardPostEvent(
              eventId: 'e8',
              kind: BoardPostEventKind.insert,
              post: _post('p2', 5),
            ),
          ),
          isFalse,
        );
        expect(paginator.rows.map((p) => p.id), ['p0', 'p1']);
      },
    );

    test('unsubscribe keeps the list non-live (never fake rows)', () async {
      final paginator = newPostPaginator(
        ({required int limit, before}) async => <Post>[_post('p1', 9)],
      );
      await paginator.loadFirst();
      final channel = StreamController<BoardPostEvent>();
      final realtime = BoardPostFeedRealtime();
      await realtime.subscribe(
        stream: channel.stream,
        onEvent: (e) => applyPostEventToPaginator(paginator, e),
      );
      await realtime.unsubscribe();
      expect(realtime.isSubscribed, isFalse);
      channel.add(
        BoardPostEvent(
          eventId: 'late',
          kind: BoardPostEventKind.insert,
          post: _post('p9', 0),
        ),
      );
      await _flush();
      expect(paginator.rows.map((p) => p.id), ['p1']);
      await realtime.dispose();
      await channel.close();
    });

    test('dispose stops delivery; subscribe after dispose throws', () async {
      final paginator = newPostPaginator(
        ({required int limit, before}) async => <Post>[],
      );
      final channel = StreamController<BoardPostEvent>();
      final realtime = BoardPostFeedRealtime();
      await realtime.subscribe(
        stream: channel.stream,
        onEvent: (e) => applyPostEventToPaginator(paginator, e),
      );
      await realtime.dispose();
      expect(realtime.isDisposed, isTrue);
      channel.add(
        BoardPostEvent(
          eventId: 'after',
          kind: BoardPostEventKind.insert,
          post: _post('p1', 0),
        ),
      );
      await _flush();
      expect(paginator.rows, isEmpty);
      await expectLater(
        realtime.subscribe(stream: channel.stream, onEvent: (_) {}),
        throwsStateError,
      );
      await channel.close();
    });

    test('reconnect replays from lastEventId without double-apply', () async {
      final paginator = newPostPaginator(
        ({required int limit, before}) async => <Post>[],
      );
      final first = StreamController<BoardPostEvent>();
      final realtime = BoardPostFeedRealtime();
      await realtime.subscribe(
        stream: first.stream,
        onEvent: (e) => applyPostEventToPaginator(paginator, e),
      );
      first.add(
        BoardPostEvent(
          eventId: 'evt-1',
          kind: BoardPostEventKind.insert,
          post: _post('p1', 5),
        ),
      );
      await _flush();
      expect(realtime.lastEventId, 'evt-1');

      String? factorySaw;
      final second = StreamController<BoardPostEvent>();
      await realtime.reconnect(
        streamFactory: (String? lastId) {
          factorySaw = lastId;
          return second.stream;
        },
        onEvent: (e) => applyPostEventToPaginator(paginator, e),
      );
      expect(factorySaw, 'evt-1');
      // Transport replays evt-1, then delivers evt-2: replay dropped once.
      second.add(
        BoardPostEvent(
          eventId: 'evt-1',
          kind: BoardPostEventKind.insert,
          post: _post('p1', 5),
        ),
      );
      second.add(
        BoardPostEvent(
          eventId: 'evt-2',
          kind: BoardPostEventKind.insert,
          post: _post('p2', 1),
        ),
      );
      await _flush();
      expect(paginator.rows.map((p) => p.id), ['p2', 'p1']);
      await realtime.dispose();
      await first.close();
      await second.close();
    });
  });

  group('F13 realtime into windowed feed keeps newest-first order', () {
    test('insert sorts; update swaps; delete drops', () async {
      final feed = PostFeedState(
        fetchPosts: ({int limit = 20}) async => <Post>[_post('p2', 5)],
      );
      await feed.load();
      applyPostEventToFeed(
        feed,
        BoardPostEvent(
          eventId: 'e1',
          kind: BoardPostEventKind.insert,
          post: _post('p3', 1),
        ),
      );
      applyPostEventToFeed(
        feed,
        BoardPostEvent(
          eventId: 'e2',
          kind: BoardPostEventKind.insert,
          post: _post('p1', 30),
        ),
      );
      expect(feed.posts.map((p) => p.id), ['p3', 'p2', 'p1']);
      // Echo insert of a loaded id: no duplicate.
      applyPostEventToFeed(
        feed,
        BoardPostEvent(
          eventId: 'e3',
          kind: BoardPostEventKind.insert,
          post: _post('p3', 1),
        ),
      );
      expect(feed.posts.map((p) => p.id), ['p3', 'p2', 'p1']);
      applyPostEventToFeed(
        feed,
        const BoardPostEvent(
          eventId: 'e4',
          kind: BoardPostEventKind.delete,
          postId: 'p2',
        ),
      );
      expect(feed.posts.map((p) => p.id), ['p3', 'p1']);
      feed.dispose();
    });
  });

  group('F13 pagination (page size 5, cursor, no duplicates)', () {
    test(
      'overlapping windows dedupe; short window ends; cursor advances',
      () async {
        final snapshot = <Post>[
          for (var i = 10; i >= 1; i--) _post('p$i', 11 - i),
        ];
        final seenLimits = <int>[];
        final seenCursors = <Object?>[];
        var calls = 0;
        final paginator = newPostPaginator(({
          required int limit,
          before,
        }) async {
          seenLimits.add(limit);
          seenCursors.add(before);
          calls++;
          if (calls == 1) return snapshot.sublist(0, 5); // p10..p6
          if (calls == 2) {
            // Overlap: server repeats the anchor row (concurrent read).
            return <Post>[snapshot[4], ...snapshot.sublist(5, 9)]; // p6,p5..p2
          }
          return snapshot.sublist(9, 10); // p1, short -> end
        });

        await paginator.loadFirst();
        expect(seenLimits.single, CursorPaginator.pageSize);
        expect(CursorPaginator.pageSize, 5);
        await paginator.loadNext();
        await paginator.loadNext();
        expect(seenLimits, [5, 5, 5]);
        expect(seenCursors[0], isNull);
        expect(seenCursors[1], isNotNull);
        expect(seenCursors[2], isNotNull);

        final ids = paginator.rows.map((p) => p.id).toList();
        expect(ids, [
          'p10',
          'p9',
          'p8',
          'p7',
          'p6',
          'p5',
          'p4',
          'p3',
          'p2',
          'p1',
        ]);
        expect(ids.toSet().length, ids.length);
        expect(paginator.seenCount, 10);
        expect(paginator.hasMore, isFalse);
      },
    );

    test('loadFirst resets accumulated state', () async {
      final paginator = newPostPaginator(
        ({required int limit, before}) async => <Post>[_post('p1', 5)],
      );
      await paginator.loadFirst();
      paginator.insertRealtime(_post('p9', 0));
      expect(paginator.rows.length, 2);
      await paginator.loadFirst();
      expect(paginator.rows.map((p) => p.id), ['p1']);
      expect(paginator.seenCount, 1);
    });
  });

  group('F13 reactions (server-persisted toggle, authoritative counts)', () {
    ReactionState makeState(List<PostReaction> seed) {
      final store = List<PostReaction>.of(seed);
      return ReactionState(
        fetchReactions: (String postId) async =>
            store.where((r) => r.postId == postId).toList(),
        upsertReaction:
            ({
              required String postId,
              required String userId,
              required ReactionValue reaction,
            }) async {
              store.removeWhere(
                (r) => r.postId == postId && r.userId == userId,
              );
              store.add(
                PostReaction(
                  postId: postId,
                  userId: userId,
                  reaction: reaction,
                ),
              );
            },
        deleteReaction:
            ({required String postId, required String userId}) async {
              store.removeWhere(
                (r) => r.postId == postId && r.userId == userId,
              );
            },
      );
    }

    test('toggle inserts, same-value removes, switch replaces', () async {
      final state = makeState(<PostReaction>[
        const PostReaction(
          postId: 'p1',
          userId: 'other',
          reaction: ReactionValue.like,
        ),
      ]);
      await state.load('p1');
      expect(state.likeCount, 1);
      expect(state.myReaction('me'), isNull);

      expect(
        await state.toggle(
          postId: 'p1',
          userId: 'me',
          value: ReactionValue.like,
        ),
        isTrue,
      );
      expect(state.likeCount, 2);
      expect(state.myReaction('me'), ReactionValue.like);

      // Same value again removes the vote.
      expect(
        await state.toggle(
          postId: 'p1',
          userId: 'me',
          value: ReactionValue.like,
        ),
        isTrue,
      );
      expect(state.likeCount, 1);
      expect(state.myReaction('me'), isNull);

      // Switch replaces (one row per user, never two).
      expect(
        await state.toggle(
          postId: 'p1',
          userId: 'me',
          value: ReactionValue.dislike,
        ),
        isTrue,
      );
      expect(state.likeCount, 1);
      expect(state.dislikeCount, 1);
      expect(
        await state.toggle(
          postId: 'p1',
          userId: 'me',
          value: ReactionValue.like,
        ),
        isTrue,
      );
      expect(state.likeCount, 2);
      expect(state.dislikeCount, 0);
      state.dispose();
    });

    test('refresh replaces rows (reconnect never double-counts)', () async {
      final store = <PostReaction>[
        const PostReaction(
          postId: 'p1',
          userId: 'a',
          reaction: ReactionValue.like,
        ),
      ];
      final state = ReactionState(
        fetchReactions: (String postId) async => List.of(store),
        upsertReaction: ({
          required postId,
          required userId,
          required reaction,
        }) async {},
        deleteReaction: ({required postId, required userId}) async {},
      );
      await state.load('p1');
      expect(state.likeCount, 1);
      await state.refresh();
      expect(state.likeCount, 1);
      state.dispose();
    });

    test('failed toggle keeps the error honestly', () async {
      final state = ReactionState(
        fetchReactions: (String postId) async => <PostReaction>[],
        upsertReaction:
            ({required postId, required userId, required reaction}) async {
              throw Exception('network down');
            },
        deleteReaction: ({required postId, required userId}) async {},
      );
      await state.load('p1');
      expect(
        await state.toggle(
          postId: 'p1',
          userId: 'me',
          value: ReactionValue.like,
        ),
        isFalse,
      );
      expect(state.errorMessage, isNotNull);
      expect(state.likeCount, 0);
      state.dispose();
    });
  });

  group('F13 ratings (server-persisted stars, recomputed aggregates)', () {
    RatingState makeState(List<PostRating> seed) {
      final store = List<PostRating>.of(seed);
      return RatingState(
        fetchRatings: (String postId) async =>
            store.where((r) => r.postId == postId).toList(),
        upsertRating:
            ({
              required String postId,
              required String userId,
              required int stars,
            }) async {
              store.removeWhere(
                (r) => r.postId == postId && r.userId == userId,
              );
              store.add(
                PostRating(postId: postId, userId: userId, stars: stars),
              );
            },
        deleteRating: ({required String postId, required String userId}) async {
          store.removeWhere((r) => r.postId == postId && r.userId == userId);
        },
      );
    }

    test('set replaces my row; average recomputed; clear removes', () async {
      final state = makeState(<PostRating>[
        const PostRating(postId: 'p1', userId: 'a', stars: 5),
        const PostRating(postId: 'p1', userId: 'b', stars: 3),
      ]);
      await state.load('p1');
      expect(state.ratingCount, 2);
      expect(state.averageStars, 4.0);
      expect(state.myStars('me'), isNull);

      expect(
        await state.setStars(postId: 'p1', userId: 'me', stars: 4),
        isTrue,
      );
      expect(state.ratingCount, 3);
      expect(state.averageStars, closeTo(4.0, 1e-9));
      expect(state.myStars('me'), 4);

      // Re-rating replaces (one row per user, count unchanged).
      expect(
        await state.setStars(postId: 'p1', userId: 'me', stars: 2),
        isTrue,
      );
      expect(state.ratingCount, 3);
      expect(state.averageStars, closeTo(10 / 3, 1e-9));

      expect(await state.clear(postId: 'p1', userId: 'me'), isTrue);
      expect(state.ratingCount, 2);
      expect(state.averageStars, 4.0);
      state.dispose();
    });

    test('invalid stars rejected locally without an upsert call', () async {
      var upserts = 0;
      final state = RatingState(
        fetchRatings: (String postId) async => <PostRating>[],
        upsertRating:
            ({required postId, required userId, required stars}) async {
              upserts++;
            },
        deleteRating: ({required postId, required userId}) async {},
      );
      await state.load('p1');
      expect(
        await state.setStars(postId: 'p1', userId: 'me', stars: 0),
        isFalse,
      );
      expect(
        await state.setStars(postId: 'p1', userId: 'me', stars: 6),
        isFalse,
      );
      expect(upserts, 0);
      expect(state.ratingCount, 0);
      state.dispose();
    });
  });
}
