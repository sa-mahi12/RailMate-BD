import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/board/list/cursor_page.dart';
import 'package:railmate_bd/features/board/post/feed_screen.dart';
import 'package:railmate_bd/features/board/post/post.dart';
import 'package:railmate_bd/features/board/post/post_compose_state.dart';
import 'package:railmate_bd/features/board/post/post_delete.dart';
import 'package:railmate_bd/features/board/post/post_engagement.dart';
import 'package:railmate_bd/features/board/post/post_feed_realtime.dart';
import 'package:railmate_bd/features/board/post/post_feed_state.dart';
import 'package:railmate_bd/features/board/ratings/rating.dart';
import 'package:railmate_bd/features/board/ratings/rating_state.dart';
import 'package:railmate_bd/features/board/reactions/reaction.dart';
import 'package:railmate_bd/features/board/reactions/reaction_state.dart';

Post _post(
  String id,
  int minutesAgo, {
  String body = 'body',
  String? imagePath,
}) => Post(
  id: id,
  userId: 'uid1',
  body: '$body $id',
  imagePath: imagePath,
  createdAt: DateTime.utc(
    2026,
    9,
    28,
    12,
    0,
  ).subtract(Duration(minutes: minutesAgo)),
);

/// In-memory `post_reactions` fake keyed by post id (no backend, no fakes
/// leaking across posts).
class _ReactionStore {
  final List<PostReaction> rows;
  _ReactionStore([List<PostReaction>? seed])
    : rows = List<PostReaction>.of(seed ?? <PostReaction>[]);

  Future<List<PostReaction>> fetch(String postId) async =>
      rows.where((r) => r.postId == postId).toList();

  Future<void> upsert({
    required String postId,
    required String userId,
    required ReactionValue reaction,
  }) async {
    rows.removeWhere((r) => r.postId == postId && r.userId == userId);
    rows.add(PostReaction(postId: postId, userId: userId, reaction: reaction));
  }

  Future<void> remove({required String postId, required String userId}) async {
    rows.removeWhere((r) => r.postId == postId && r.userId == userId);
  }
}

/// In-memory `post_ratings` fake keyed by post id.
class _RatingStore {
  final List<PostRating> rows;
  _RatingStore([List<PostRating>? seed])
    : rows = List<PostRating>.of(seed ?? <PostRating>[]);

  Future<List<PostRating>> fetch(String postId) async =>
      rows.where((r) => r.postId == postId).toList();

  Future<void> upsert({
    required String postId,
    required String userId,
    required int stars,
  }) async {
    rows.removeWhere((r) => r.postId == postId && r.userId == userId);
    rows.add(PostRating(postId: postId, userId: userId, stars: stars));
  }

  Future<void> remove({required String postId, required String userId}) async {
    rows.removeWhere((r) => r.postId == postId && r.userId == userId);
  }
}

ReactionState _reactionsFor(_ReactionStore store) => ReactionState(
  fetchReactions: store.fetch,
  upsertReaction: store.upsert,
  deleteReaction: store.remove,
);

RatingState _ratingsFor(_RatingStore store) => RatingState(
  fetchRatings: store.fetch,
  upsertRating: store.upsert,
  deleteRating: store.remove,
);

void main() {
  group('F13b per-post state isolation (votes never leak across posts)', () {
    test('reaction votes on p1 leave p2 untouched', () async {
      final store = _ReactionStore();
      final a = _reactionsFor(store);
      final b = _reactionsFor(store);
      await a.load('p1');
      await b.load('p2');
      expect(b.likeCount, 0);

      expect(
        await a.toggle(postId: 'p1', userId: 'me', value: ReactionValue.like),
        isTrue,
      );
      expect(a.likeCount, 1);
      expect(a.myReaction('me'), ReactionValue.like);
      expect(b.likeCount, 0);
      expect(b.dislikeCount, 0);
      expect(b.myReaction('me'), isNull);
      a.dispose();
      b.dispose();
    });

    test('ratings on p2 leave p1 untouched', () async {
      final store = _RatingStore([
        const PostRating(postId: 'p1', userId: 'a', stars: 5),
      ]);
      final a = _ratingsFor(store);
      final b = _ratingsFor(store);
      await a.load('p1');
      await b.load('p2');
      expect(a.ratingCount, 1);

      expect(await b.setStars(postId: 'p2', userId: 'me', stars: 4), isTrue);
      expect(b.ratingCount, 1);
      expect(b.myStars('me'), 4);
      expect(a.ratingCount, 1);
      expect(a.averageStars, 5.0);
      expect(a.myStars('me'), isNull);
      a.dispose();
      b.dispose();
    });
  });

  group('F13b engagement widget (rendered per-post votes)', () {
    testWidgets('signed-in user sees aggregates and toggles a vote', (
      tester,
    ) async {
      final reactions = _ReactionStore([
        const PostReaction(
          postId: 'p1',
          userId: 'other',
          reaction: ReactionValue.like,
        ),
      ]);
      final ratings = _RatingStore([
        const PostRating(postId: 'p1', userId: 'other', stars: 5),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PostEngagement(
              post: _post('p1', 5),
              currentUserId: 'me',
              fetchReactions: reactions.fetch,
              upsertReaction: reactions.upsert,
              deleteReaction: reactions.remove,
              fetchRatings: ratings.fetch,
              upsertRating: ratings.upsert,
              deleteRating: ratings.remove,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Authoritative aggregates render (1 like from 'other', avg 5.0).
      expect(find.text('1'), findsOneWidget);
      expect(find.text('5.0 (1)'), findsOneWidget);
      expect(find.text('Sign in to react or rate.'), findsNothing);

      await tester.tap(find.byTooltip('Like'));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byTooltip('Rate 3 stars'));
      await tester.pumpAndSettle();
      expect(find.text('4.0 (2)'), findsOneWidget);
    });

    testWidgets('signed-out user sees read-only aggregates + hint', (
      tester,
    ) async {
      final reactions = _ReactionStore([
        const PostReaction(
          postId: 'p1',
          userId: 'a',
          reaction: ReactionValue.like,
        ),
        const PostReaction(
          postId: 'p1',
          userId: 'b',
          reaction: ReactionValue.like,
        ),
      ]);
      final ratings = _RatingStore([
        const PostRating(postId: 'p1', userId: 'a', stars: 5),
        const PostRating(postId: 'p1', userId: 'b', stars: 3),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PostEngagement(
              post: _post('p1', 5),
              currentUserId: null,
              fetchReactions: reactions.fetch,
              upsertReaction: reactions.upsert,
              deleteReaction: reactions.remove,
              fetchRatings: ratings.fetch,
              upsertRating: ratings.upsert,
              deleteRating: ratings.remove,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Aggregates still load (public read) ...
      expect(find.text('2'), findsOneWidget);
      expect(find.text('4.0 (2)'), findsOneWidget);
      // ... but there is no vote affordance, only the honest hint.
      expect(find.text('Sign in to react or rate.'), findsOneWidget);
      // Signed out: the vote area is an InkWell (P21 replaced the
      // OutlinedButton with an animated container), and no tap target
      // exists when onTap is null.
      expect(
        tester
            .widget<InkWell>(
              find.ancestor(of: find.text('2'), matching: find.byType(InkWell)),
            )
            .onTap,
        isNull,
      );
      final starBtn = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Rate 1 star'),
          matching: find.byType(IconButton),
        ),
      );
      expect(starBtn.onPressed, isNull);

      await tester.tap(find.byTooltip('Like'));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);
      expect(reactions.rows.length, 2);
    });
  });

  group('F13b toggle -> refresh reconcile (authoritative store wins)', () {
    test('reactions converge on the server rows after refresh', () async {
      final store = _ReactionStore();
      final state = _reactionsFor(store);
      await state.load('p1');
      expect(state.likeCount, 0);

      await state.toggle(postId: 'p1', userId: 'me', value: ReactionValue.like);
      expect(state.likeCount, 1);

      // Another client voted on the server behind our back.
      store.rows.add(
        const PostReaction(
          postId: 'p1',
          userId: 'other',
          reaction: ReactionValue.like,
        ),
      );
      await state.refresh();
      expect(state.likeCount, 2);
      expect(state.myReaction('me'), ReactionValue.like);

      // A server-side removal reconciles down too (no stuck optimistic).
      store.rows.removeWhere((r) => r.userId == 'me');
      await state.refresh();
      expect(state.likeCount, 1);
      expect(state.myReaction('me'), isNull);
      state.dispose();
    });

    test('ratings converge on the server rows after refresh', () async {
      final store = _RatingStore();
      final state = _ratingsFor(store);
      await state.load('p1');

      await state.setStars(postId: 'p1', userId: 'me', stars: 4);
      expect(state.averageStars, 4.0);

      store.rows.add(const PostRating(postId: 'p1', userId: 'other', stars: 2));
      await state.refresh();
      expect(state.ratingCount, 2);
      expect(state.averageStars, 3.0);
      state.dispose();
    });
  });

  group('F13b paged feed (5/page, no duplicate rows)', () {
    test('overlapping keyset windows dedupe across pages', () async {
      final snapshot = <Post>[
        for (var i = 10; i >= 1; i--) _post('p$i', 11 - i),
      ];
      var calls = 0;
      Future<List<Post>> fetchPage({
        required int limit,
        PageCursor? before,
      }) async {
        calls++;
        expect(limit, 5);
        if (before == null) return snapshot.sublist(0, 5);
        final idx = snapshot.indexWhere((p) => p.id == before.id);
        final window = snapshot.skip(idx + 1).take(limit).toList();
        // Second page repeats its anchor (concurrent read overlap).
        if (calls == 2) return <Post>[snapshot[idx], ...window];
        return window;
      }

      final feed = PostFeedState(
        fetchPosts: ({int limit = 20}) async => <Post>[],
        fetchPage: fetchPage,
      );
      expect(feed.isPaged, isTrue);
      await feed.load();
      expect(feed.posts.map((p) => p.id), ['p10', 'p9', 'p8', 'p7', 'p6']);
      expect(feed.hasMore, isTrue);

      for (var k = 0; k < 5 && feed.hasMore; k++) {
        await feed.loadMore();
      }
      final ids = feed.posts.map((p) => p.id).toList();
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
      expect(feed.hasMore, isFalse);
      expect(feed.pageError, isNull);
      feed.dispose();
    });

    test(
      'page failure keeps rows, reports pageError, retry continues',
      () async {
        var calls = 0;
        Future<List<Post>> fetchPage({
          required int limit,
          PageCursor? before,
        }) async {
          calls++;
          if (calls == 1) {
            return <Post>[
              _post('p5', 1),
              _post('p4', 2),
              _post('p3', 3),
              _post('p2', 4),
              _post('p1', 5),
            ];
          }
          if (calls == 2) throw Exception('page down');
          return <Post>[];
        }

        final feed = PostFeedState(
          fetchPosts: ({int limit = 20}) async => <Post>[],
          fetchPage: fetchPage,
        );
        await feed.load();
        expect(feed.posts.length, 5);

        await feed.loadMore();
        expect(feed.posts.length, 5);
        expect(feed.pageError, contains('page down'));
        expect(feed.hasMore, isTrue);

        await feed.loadMore();
        expect(feed.pageError, isNull);
        expect(feed.posts.length, 5);
        expect(feed.hasMore, isFalse);
        feed.dispose();
      },
    );

    test('window mode stays window-only (loadMore is a no-op)', () async {
      final feed = PostFeedState(
        fetchPosts: ({int limit = 20}) async => <Post>[_post('p1', 1)],
      );
      await feed.load();
      expect(feed.isPaged, isFalse);
      expect(feed.hasMore, isFalse);
      expect(feed.pageError, isNull);
      expect(feed.isLoadingMore, isFalse);
      await feed.loadMore();
      expect(feed.posts.map((p) => p.id), ['p1']);
      feed.dispose();
    });
  });

  group('F13b realtime merge still works on a paged feed', () {
    test(
      'insert/update/delete merge + notify; later pages never dupe',
      () async {
        final snapshot = <Post>[
          for (var i = 5; i >= 1; i--) _post('p$i', 6 - i),
        ];
        var calls = 0;
        Future<List<Post>> fetchPage({
          required int limit,
          PageCursor? before,
        }) async {
          calls++;
          if (calls == 1) return snapshot.sublist(0, 5);
          // Server snapshot predates the realtime row; overlap the anchor.
          return <Post>[snapshot.last, _post('p0', 60)];
        }

        final feed = PostFeedState(
          fetchPosts: ({int limit = 20}) async => <Post>[],
          fetchPage: fetchPage,
        );
        await feed.load();
        expect(feed.posts.map((p) => p.id), ['p5', 'p4', 'p3', 'p2', 'p1']);

        var notified = 0;
        feed.addListener(() {
          notified++;
        });

        applyPostEventToFeed(
          feed,
          BoardPostEvent(
            eventId: 'e1',
            kind: BoardPostEventKind.insert,
            post: _post('p6', 0),
          ),
        );
        expect(feed.posts.map((p) => p.id), [
          'p6',
          'p5',
          'p4',
          'p3',
          'p2',
          'p1',
        ]);
        expect(notified, 1);

        // Echo of the merged row: no duplicate, no notify.
        applyPostEventToFeed(
          feed,
          BoardPostEvent(
            eventId: 'e2',
            kind: BoardPostEventKind.insert,
            post: _post('p6', 0),
          ),
        );
        expect(feed.posts.length, 6);
        expect(notified, 1);

        applyPostEventToFeed(
          feed,
          BoardPostEvent(
            eventId: 'e3',
            kind: BoardPostEventKind.update,
            post: _post('p5', 9, body: 'edited'),
          ),
        );
        expect(feed.posts.singleWhere((p) => p.id == 'p5').body, 'edited p5');
        expect(notified, 2);

        applyPostEventToFeed(
          feed,
          const BoardPostEvent(
            eventId: 'e4',
            kind: BoardPostEventKind.delete,
            postId: 'p4',
          ),
        );
        expect(feed.posts.map((p) => p.id), ['p6', 'p5', 'p3', 'p2', 'p1']);
        expect(notified, 3);

        await feed.loadMore();
        expect(feed.posts.map((p) => p.id), [
          'p6',
          'p5',
          'p3',
          'p2',
          'p1',
          'p0',
        ]);
        expect(feed.hasMore, isFalse);
        feed.dispose();
      },
    );
  });

  group('F13b orphan follow-up (post delete also removes the image)', () {
    test(
      'cleanupOrphan deletes the linked image with no reserved path',
      () async {
        final compose = PostComposeState();
        compose.createdPost = const Post(
          id: 'r1',
          userId: 'u1',
          body: 'hello',
          imagePath: 'u1/photo.jpg',
        );
        final rows = <String>[];
        final objects = <String>[];
        final ok = await compose.cleanupOrphan(
          deletePost: (String id) async {
            rows.add(id);
          },
          deleteObject: (String path) async {
            objects.add(path);
          },
        );
        expect(ok, isTrue);
        expect(rows, ['r1']);
        expect(objects, ['u1/photo.jpg']);
        compose.dispose();
      },
    );

    test('cleanupOrphan deletes reserved + linked paths once each', () async {
      final compose = PostComposeState();
      compose.createdPost = const Post(
        id: 'r1',
        userId: 'u1',
        body: 'hello',
        imagePath: 'u1/linked.jpg',
      );
      compose.reservedImagePath = 'u1/reserved.jpg';
      final objects = <String>[];
      await compose.cleanupOrphan(
        deletePost: (String id) async {},
        deleteObject: (String path) async {
          objects.add(path);
        },
      );
      expect(objects.toSet(), {'u1/reserved.jpg', 'u1/linked.jpg'});

      // Same path twice collapses to a single delete.
      final repeat = PostComposeState();
      repeat.createdPost = const Post(
        id: 'r2',
        userId: 'u1',
        body: 'hello',
        imagePath: 'u1/same.jpg',
      );
      repeat.reservedImagePath = 'u1/same.jpg';
      final once = <String>[];
      await repeat.cleanupOrphan(
        deletePost: (String id) async {},
        deleteObject: (String path) async {
          once.add(path);
        },
      );
      expect(once, ['u1/same.jpg']);
      compose.dispose();
      repeat.dispose();
    });

    test(
      'deletePostAndImage removes row + object; object failure is best-effort',
      () async {
        final rows = <String>[];
        final objects = <String>[];
        final ok = await deletePostAndImage(
          post: _post('p1', 1, imagePath: 'u1/a.jpg'),
          deletePost: (String id) async {
            rows.add(id);
          },
          deleteObject: (String path) async {
            objects.add(path);
          },
        );
        expect(ok, isTrue);
        expect(rows, ['p1']);
        expect(objects, ['u1/a.jpg']);

        // Text-only post: row delete only, no object call.
        final rows2 = <String>[];
        var objectCalls = 0;
        final ok2 = await deletePostAndImage(
          post: _post('p2', 2),
          deletePost: (String id) async {
            rows2.add(id);
          },
          deleteObject: (String path) async {
            objectCalls++;
          },
        );
        expect(ok2, isTrue);
        expect(rows2, ['p2']);
        expect(objectCalls, 0);

        // Throwing object delete still reports row success.
        final ok3 = await deletePostAndImage(
          post: _post('p3', 3, imagePath: 'u1/missing.jpg'),
          deletePost: (String id) async {},
          deleteObject: (String path) async {
            throw Exception('gone');
          },
        );
        expect(ok3, isTrue);

        // No row id: no-op, no injected calls.
        var rowCalls = 0;
        final ok4 = await deletePostAndImage(
          post: const Post(userId: 'u1', body: 'draft'),
          deletePost: (String id) async {
            rowCalls++;
          },
          deleteObject: (String path) async {},
        );
        expect(ok4, isFalse);
        expect(rowCalls, 0);
      },
    );
  });

  group('F13b feed screen (engagement + pagination trailer)', () {
    testWidgets('cards render per-post engagement from the seams', (
      tester,
    ) async {
      final reactions = _ReactionStore();
      final ratings = _RatingStore();
      final feed = PostFeedState(
        fetchPosts: ({int limit = 20}) async => <Post>[
          _post('p1', 5, body: 'hello'),
          _post('p2', 9, body: 'world'),
        ],
      );
      await feed.load();
      await tester.pumpWidget(
        MaterialApp(
          home: BoardFeedScreen(
            feed: feed,
            currentUserId: 'me',
            fetchReactions: reactions.fetch,
            upsertReaction: reactions.upsert,
            deleteReaction: reactions.remove,
            fetchRatings: ratings.fetch,
            upsertRating: ratings.upsert,
            deleteRating: ratings.remove,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('hello p1'), findsOneWidget);
      expect(find.text('world p2'), findsOneWidget);
      expect(find.byType(PostEngagement), findsNWidgets(2));
      // Window mode: no pagination trailer.
      expect(find.text('Load more'), findsNothing);
      feed.dispose();
    });

    testWidgets('paged feed shows Load more and appends without dupes', (
      tester,
    ) async {
      final snapshot = <Post>[for (var i = 6; i >= 1; i--) _post('p$i', 7 - i)];
      Future<List<Post>> fetchPage({
        required int limit,
        PageCursor? before,
      }) async {
        if (before == null) return snapshot.sublist(0, 5);
        final idx = snapshot.indexWhere((p) => p.id == before.id);
        return snapshot.skip(idx + 1).take(limit).toList();
      }

      final feed = PostFeedState(
        fetchPosts: ({int limit = 20}) async => <Post>[],
        fetchPage: fetchPage,
      );
      await feed.load();
      await tester.pumpWidget(MaterialApp(home: BoardFeedScreen(feed: feed)));
      await tester.pumpAndSettle();
      // No engagement seams: cards render, engagement hidden (old callers).
      expect(find.byType(PostEngagement), findsNothing);
      expect(find.text('Load more'), findsOneWidget);

      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(feed.posts.length, 6);
      final ids = feed.posts.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(find.text('Load more'), findsNothing);
      feed.dispose();
    });
  });
}
