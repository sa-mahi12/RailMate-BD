import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/board/ratings/rating.dart';
import 'package:railmate_bd/features/board/ratings/rating_state.dart';
import 'package:railmate_bd/features/board/reactions/reaction.dart';
import 'package:railmate_bd/features/board/reactions/reaction_state.dart';

void main() {
  group('one-vote toggle', () {
    test('insert, remove on same value, replace on switch', () async {
      final server = <PostReaction>[];
      var upserts = 0;
      var deletes = 0;
      final state = ReactionState(
        fetchReactions: (_) async => List.of(server),
        upsertReaction:
            ({
              required String postId,
              required String userId,
              required ReactionValue reaction,
            }) async {
              upserts++;
              server.removeWhere(
                (r) => r.postId == postId && r.userId == userId,
              );
              server.add(
                PostReaction(
                  postId: postId,
                  userId: userId,
                  reaction: reaction,
                ),
              );
            },
        deleteReaction:
            ({required String postId, required String userId}) async {
              deletes++;
              server.removeWhere(
                (r) => r.postId == postId && r.userId == userId,
              );
            },
      );
      await state.load('p1');
      expect(
        await state.toggle(
          postId: 'p1',
          userId: 'u1',
          value: ReactionValue.like,
        ),
        isTrue,
      );
      await state.load('p1');
      expect(upserts, 1);
      expect(state.likeCount, 1);
      expect(state.myReaction('u1'), ReactionValue.like);

      expect(
        await state.toggle(
          postId: 'p1',
          userId: 'u1',
          value: ReactionValue.like,
        ),
        isTrue,
      );
      await state.load('p1');
      expect(deletes, 1);
      expect(state.likeCount, 0);
      expect(state.myReaction('u1'), isNull);

      expect(
        await state.toggle(
          postId: 'p1',
          userId: 'u1',
          value: ReactionValue.like,
        ),
        isTrue,
      );
      expect(
        await state.toggle(
          postId: 'p1',
          userId: 'u1',
          value: ReactionValue.dislike,
        ),
        isTrue,
      );
      await state.load('p1');
      expect(state.likeCount, 0);
      expect(state.dislikeCount, 1);
      expect(server.where((r) => r.userId == 'u1').length, 1);
    });
  });

  group('star range negatives + valid set', () {
    test(
      '0/6 rejected without upsert; create/fromMap throw; 5 works',
      () async {
        var upserts = 0;
        final state = RatingState(
          fetchRatings: (_) async => [],
          upsertRating:
              ({
                required String postId,
                required String userId,
                required int stars,
              }) async {
                upserts++;
              },
          deleteRating: ({
            required String postId,
            required String userId,
          }) async {},
        );
        await state.load('p1');
        expect(
          await state.setStars(postId: 'p1', userId: 'u1', stars: 0),
          isFalse,
        );
        expect(
          await state.setStars(postId: 'p1', userId: 'u1', stars: 6),
          isFalse,
        );
        expect(upserts, 0);
        expect(state.errorMessage, isNotNull);
        expect(
          () => PostRating.create(postId: 'p1', userId: 'u1', stars: 0),
          throwsArgumentError,
        );
        expect(
          () => PostRating.fromMap({
            'post_id': 'p1',
            'user_id': 'u1',
            'stars': 9,
          }),
          throwsArgumentError,
        );
        expect(
          await state.setStars(postId: 'p1', userId: 'u1', stars: 5),
          isTrue,
        );
        expect(upserts, 1);
      },
    );
  });

  group('aggregate recompute, no duplication after refetch', () {
    test('refetch replaces rows; average stable', () async {
      final seed = [
        const PostReaction(
          postId: 'p1',
          userId: 'u1',
          reaction: ReactionValue.like,
        ),
        const PostReaction(
          postId: 'p1',
          userId: 'u2',
          reaction: ReactionValue.like,
        ),
        const PostReaction(
          postId: 'p1',
          userId: 'u3',
          reaction: ReactionValue.dislike,
        ),
      ];
      final reactions = ReactionState(
        fetchReactions: (_) async => List.of(seed),
        upsertReaction: ({
          required String postId,
          required String userId,
          required ReactionValue reaction,
        }) async {},
        deleteReaction: ({
          required String postId,
          required String userId,
        }) async {},
      );
      await reactions.load('p1');
      expect(reactions.likeCount, 2);
      expect(reactions.dislikeCount, 1);
      await reactions.load('p1');
      expect(reactions.likeCount, 2);
      expect(reactions.dislikeCount, 1);

      final ratings = RatingState(
        fetchRatings: (_) async => const [
          PostRating(postId: 'p1', userId: 'u1', stars: 5),
          PostRating(postId: 'p1', userId: 'u2', stars: 3),
        ],
        upsertRating: ({
          required String postId,
          required String userId,
          required int stars,
        }) async {},
        deleteRating: ({
          required String postId,
          required String userId,
        }) async {},
      );
      await ratings.load('p1');
      expect(ratings.averageStars, 4.0);
      expect(ratings.ratingCount, 2);
      expect(ratings.myStars('u1'), 5);
      await ratings.load('p1');
      expect(ratings.averageStars, 4.0);
      expect(ratings.ratingCount, 2);
    });
  });

  group('isolation negatives', () {
    test('empty post id rejected; foreign-post rows filtered', () async {
      var upserts = 0;
      final ratings = RatingState(
        fetchRatings: (_) async => const [
          PostRating(postId: 'p1', userId: 'u1', stars: 5),
          PostRating(postId: 'p2', userId: 'u2', stars: 1),
        ],
        upsertRating:
            ({
              required String postId,
              required String userId,
              required int stars,
            }) async {
              upserts++;
            },
        deleteRating: ({
          required String postId,
          required String userId,
        }) async {},
      );
      expect(
        await ratings.setStars(postId: '', userId: 'u1', stars: 4),
        isFalse,
      );
      expect(upserts, 0);
      await ratings.load('p1');
      expect(ratings.ratingCount, 1);
      expect(ratings.averageStars, 5.0);
    });
  });
}
