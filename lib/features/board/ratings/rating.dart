/// Board rating model (packet A08, requirement R-07).
///
/// Mirrors `public.post_ratings(post_id, user_id, stars, created_at)` with
/// `PK(post_id, user_id)` = one rating per user/post and
/// `CHECK (stars BETWEEN 1 AND 5)`.
/// Pure Dart: no Flutter, no Supabase, no I/O. Server access is injected
/// by the rating state; this file only shapes data and validates stars.
///
/// RLS (see `supabase/migrations/20260927000002_rls.sql`, read-only here):
/// `ratings_read` (public select), `ratings_insert_own`,
/// `ratings_update_own`, `ratings_delete_own` (owner writes only).
class PostRating {
  /// Star bounds (`post_ratings.stars` check constraint).
  static const int minStars = 1;

  /// Star bounds (`post_ratings.stars` check constraint).
  static const int maxStars = 5;

  /// Row post (`post_ratings.post_id`).
  final String postId;

  /// Row author (`post_ratings.user_id`).
  final String userId;

  /// Row stars (`post_ratings.stars`, 1..5).
  final int stars;

  const PostRating({
    required this.postId,
    required this.userId,
    required this.stars,
  });

  /// Returns an error message when [stars] is out of range, else null.
  static String? validateStars(int? stars) {
    if (stars == null || stars < minStars || stars > maxStars) {
      return 'Pick $minStars–$maxStars stars.';
    }
    return null;
  }

  /// Builds a rating, throwing [ArgumentError] on invalid stars/ids.
  factory PostRating.create({
    required String postId,
    required String userId,
    required int stars,
  }) {
    final error = validateStars(stars);
    if (error != null) throw ArgumentError(error);
    if (postId.isEmpty || userId.isEmpty) {
      throw ArgumentError('postId and userId must both be non-empty.');
    }
    return PostRating(postId: postId, userId: userId, stars: stars);
  }

  /// Parses one `public.post_ratings` row map. Throws [ArgumentError]
  /// on missing ids or out-of-range stars.
  factory PostRating.fromMap(Map<String, dynamic> map) {
    final postId = (map['post_id'] ?? '').toString();
    final userId = (map['user_id'] ?? '').toString();
    final raw = map['stars'];
    final stars = raw is int ? raw : int.tryParse('$raw');
    final error = validateStars(stars);
    if (postId.isEmpty || userId.isEmpty || error != null) {
      throw ArgumentError('Invalid post_ratings row: $map');
    }
    return PostRating(postId: postId, userId: userId, stars: stars!);
  }

  /// Upsert payload for `public.post_ratings` (PK covers post+user).
  Map<String, dynamic> toUpsertMap() => <String, dynamic>{
    'post_id': postId,
    'user_id': userId,
    'stars': stars,
  };
}
