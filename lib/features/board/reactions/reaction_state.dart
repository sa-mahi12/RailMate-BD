import 'package:flutter/foundation.dart';

import 'reaction.dart';

/// Lifecycle of a reaction window load/mutation.
enum ReactionStatus { idle, loading, loaded, error }

/// Injected row fetch: returns ALL `public.post_reactions` rows for
/// [postId] visible to the caller (production: hosted Supabase select with
/// `reactions_read`; tests: fake). The returned list is the authoritative
/// source for every aggregate — counts are recomputed from it, never
/// cached-incremented.
typedef FetchReactions = Future<List<PostReaction>> Function(String postId);

/// Injected vote upsert: inserts or replaces the caller's row for
/// (`postId`, `userId`) (production: authenticated upsert under
/// `reactions_insert_own` / `reactions_update_own`; tests: fake).
typedef UpsertReactionRow = Future<void> Function({
  required String postId,
  required String userId,
  required ReactionValue reaction,
});

/// Injected vote delete: removes the row for (`postId`, `userId`)
/// (production: authenticated delete under `reactions_delete_own`).
typedef DeleteReactionRow = Future<void> Function({
  required String postId,
  required String userId,
});

/// Per-post reaction state (packet A08, R-03).
///
/// One-vote-per-user is enforced client-side: [toggle] inserts when the
/// user has no row, replaces the row when switching LIKE<->DISLIKE, and
/// removes the row when tapping the already-selected value again.
///
/// Aggregates ([likeCount]/[dislikeCount]) are always recomputed from
/// [rows]. [load]/[refresh] REPLACES [rows] (reconnect re-fetch
/// invalidates rather than appends), so a refetch can never duplicate
/// counts. Nothing here calls Supabase directly — every side effect is
/// injected.
class ReactionState extends ChangeNotifier {
  final FetchReactions fetchReactions;
  final UpsertReactionRow upsertReaction;
  final DeleteReactionRow deleteReaction;

  /// Post this state is currently showing. Null before the first [load].
  String? postId;

  ReactionStatus status = ReactionStatus.idle;
  String? errorMessage;
  bool submitting = false;

  /// Authoritative row list for [postId]. Aggregates derive from this.
  List<PostReaction> rows = const <PostReaction>[];

  ReactionState({
    required this.fetchReactions,
    required this.upsertReaction,
    required this.deleteReaction,
  });

  bool get isLoading => status == ReactionStatus.loading;

  /// Authoritative LIKE count (recomputed from [rows] on every read).
  int get likeCount =>
      rows.where((r) => r.reaction == ReactionValue.like).length;

  /// Authoritative DISLIKE count (recomputed from [rows] on every read).
  int get dislikeCount =>
      rows.where((r) => r.reaction == ReactionValue.dislike).length;

  /// The caller's current vote, or null when they have no row.
  ReactionValue? myReaction(String userId) {
    for (final r in rows) {
      if (r.userId == userId) return r.reaction;
    }
    return null;
  }

  /// Loads (or reloads) the rows for [postId], REPLACING [rows].
  ///
  /// Reconnect path: call [refresh]/[load] again — the old list is
  /// discarded, so rows are never appended twice.
  Future<void> load(String postId) async {
    this.postId = postId;
    status = ReactionStatus.loading;
    errorMessage = null;
    notifyListeners();
    try {
      final fetched = await fetchReactions(postId);
      // Defensive: keep only rows for this post (account/post isolation).
      rows = List<PostReaction>.unmodifiable(
        fetched.where((r) => r.postId == postId),
      );
      status = ReactionStatus.loaded;
    } catch (e) {
      status = ReactionStatus.error;
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

  /// Toggles [value] for [userId] on [postId]:
  /// same value again removes the vote, switching replaces it,
  /// no existing row inserts it. Returns true on success.
  Future<bool> toggle({
    required String postId,
    required String userId,
    required ReactionValue value,
  }) async {
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
      final current = myReaction(userId);
      if (current == value) {
        await deleteReaction(postId: postId, userId: userId);
        rows = List<PostReaction>.unmodifiable(
          rows.where((r) => r.userId != userId),
        );
      } else {
        await upsertReaction(postId: postId, userId: userId, reaction: value);
        final next = <PostReaction>[
          for (final r in rows)
            if (r.userId != userId) r,
          PostReaction(postId: postId, userId: userId, reaction: value),
        ];
        rows = List<PostReaction>.unmodifiable(next);
      }
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
}
