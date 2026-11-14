/// Realtime seam for per-post star ratings (R-07, 2026-11-14).
///
/// Mirrors `ReactionRealtimeEvent`: transport-free, so the widget layer never
/// imports Supabase. The composition root ({@code HomeShell}) maps ONE
/// Supabase Realtime channel on `public.post_ratings`
/// (postgres_changes INSERT/UPDATE/DELETE) into [RatingRealtimeEvent]s and
/// injects the resulting broadcast `Stream` into every visible
/// `PostEngagement`, which filters by its own post id and then asks
/// [RatingState.refresh] for the authoritative rows.
///
/// Why refresh instead of hand-maintained deltas: the average and count are
/// always recomputed from rows, so an echoed/duplicate event can at worst cost
/// one extra fetch — it can never double-count. No aggregate is ever mutated
/// directly from an event here.
library;

/// Kind of a realtime rating event on `public.post_ratings`.
enum RatingRealtimeKind {
  /// A traveller rated a post for the first time.
  insert,

  /// A traveller changed their stars.
  update,

  /// A traveller removed their rating.
  delete,
}

/// One realtime rating change for a single post.
class RatingRealtimeEvent {
  /// Transport dedupe/diagnostic token (commit timestamp + post + user).
  final String eventId;

  /// What changed.
  final RatingRealtimeKind kind;

  /// Affected `post_ratings.post_id`. Never empty (the composition root drops
  /// payloads without a post id).
  final String postId;

  const RatingRealtimeEvent({
    required this.eventId,
    required this.kind,
    required this.postId,
  });

  /// True when this event belongs to [otherPostId] (the card's own id).
  bool appliesTo(String otherPostId) =>
      postId.isNotEmpty && postId == otherPostId;

  @override
  String toString() => 'RatingRealtimeEvent($kind, post: $postId)';
}
