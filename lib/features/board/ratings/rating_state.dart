import 'package:flutter/foundation.dart';

import 'rating.dart';

/// Lifecycle of a rating window load/mutation.
enum RatingStatus { idle, loading, loaded, error }

/// Injected row fetch: returns ALL `public.post_ratings` rows for [postId]
/// visible to the caller (production: hosted Supabase select with
/// `ratings_read`; tests: fake). The returned list is the authoritative
/// source for [averageStars]/[ratingCount] — recomputed, never cached.
typedef FetchRatings = Future<List<PostRating>> Function(String postId);

/// Injected rating upsert: inserts or replaces the caller's row for
/// (`postId`, `userId`) (production: authenticated upsert under
/// `ratings_insert_own` / `ratings_update_own`; tests: fake).
typedef UpsertRatingRow = Future<void> Function({
  required String postId,
  required String userId,
  required int stars,
});

/// Injected rating delete: removes the row for (`postId`, `userId`)
/// (production: authenticated delete under `ratings_delete_own`).
typedef DeleteRatingRow = Future<void> Function({
  required String postId,
  required String userId,
});

/// Per-post rating state (packet A08, R-07).
///
/// One-rating-per-user: [setStars] replaces the caller's existing row;
/// [clear] removes it. Invalid stars (outside 1..5) are rejected locally
/// without calling the injected upsert.
///
/// Aggregates ([ratingCount]/[averageStars]) are always recomputed from
/// [rows]. [load]/[refresh] REPLACES [rows] (reconnect re-fetch
/// invalidates rather than appends), so a refetch can never duplicate or
/// double-count ratings. Nothing here calls Supabase directly.
class RatingState extends ChangeNotifier {
  final FetchRatings fetchRatings;
  final UpsertRatingRow upsertRating;
  final DeleteRatingRow deleteRating;

  /// Post this state is currently showing. Null before the first [load].
  String? postId;

  RatingStatus status = RatingStatus.idle;
  String? errorMessage;
  bool submitting = false;

  /// Authoritative row list for [postId]. Aggregates derive from this.
  List<PostRating> rows = const <PostRating>[];

  RatingState({
    required this.fetchRatings,
    required this.upsertRating,
    required this.deleteRating,
  });

  bool get isLoading => status == RatingStatus.loading;

  /// Number of raters (row count).
  int get ratingCount => rows.length;

  /// Mean of [rows] stars, 0.0 when there are no ratings.
  double get averageStars {
    if (rows.isEmpty) return 0.0;
    var sum = 0;
    for (final r in rows) {
      sum += r.stars;
    }
    return sum / rows.length;
  }

  /// The caller's current stars, or null when they have no row.
  int? myStars(String userId) {
    for (final r in rows) {
      if (r.userId == userId) return r.stars;
    }
    return null;
  }

  /// Loads (or reloads) the rows for [postId], REPLACING [rows].
  ///
  /// Reconnect path: call [refresh]/[load] again — the old list is
  /// discarded, so rows are never appended twice.
  Future<void> load(String postId) async {
    this.postId = postId;
    status = RatingStatus.loading;
    errorMessage = null;
    notifyListeners();
    try {
      final fetched = await fetchRatings(postId);
      // Defensive: keep only rows for this post (account/post isolation).
      rows = List<PostRating>.unmodifiable(
        fetched.where((r) => r.postId == postId),
      );
      status = RatingStatus.loaded;
    } catch (e) {
      status = RatingStatus.error;
      errorMessage = e.toString();
    }
    notifyListeners();
  }

  /// Re-runs [load] for the current [postId]. No-op when never loaded.
  Future<void> refresh() {
    final id = postId;
    if (id == null) return Future.value();
    return load(id);
  }

  /// Sets [stars] (1..5) for [userId] on [postId], replacing any existing
  /// row. Invalid stars are rejected locally (no upsert call).
  /// Returns true on success.
  Future<bool> setStars({
    required String postId,
    required String userId,
    required int stars,
  }) async {
    final validation = PostRating.validateStars(stars);
    if (validation != null) {
      errorMessage = validation;
      notifyListeners();
      return false;
    }
    if (postId.isEmpty || userId.isEmpty) {
      errorMessage = 'Missing post or user id.';
      notifyListeners();
      return false;
    }
    if (submitting) return false;
    submitting = true;
    errorMessage = null;
    notifyListeners();
    try {
      await upsertRating(postId: postId, userId: userId, stars: stars);
      final next = <PostRating>[
        for (final r in rows)
          if (r.userId != userId) r,
        PostRating(postId: postId, userId: userId, stars: stars),
      ];
      rows = List<PostRating>.unmodifiable(next);
      if (this.postId == null) this.postId = postId;
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  /// Removes the caller's rating row. No-op returning false when they
  /// have no row. Returns true on successful delete.
  Future<bool> clear({required String postId, required String userId}) async {
    if (myStars(userId) == null) return false;
    if (submitting) return false;
    submitting = true;
    errorMessage = null;
    notifyListeners();
    try {
      await deleteRating(postId: postId, userId: userId);
      rows = List<PostRating>.unmodifiable(
        rows.where((r) => r.userId != userId),
      );
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }
}
