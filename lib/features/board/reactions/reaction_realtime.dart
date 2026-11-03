/// Realtime seam for per-post reactions (teacher final gate, 2026-11-03).
///
/// Transport-free, like `CommentRealtimeSubscription`: the composition root
/// ({@code HomeShell}) maps ONE Supabase Realtime channel on
/// `public.post_reactions` (postgres_changes INSERT/UPDATE/DELETE) into
/// [ReactionRealtimeEvent]s and injects the resulting broadcast `Stream` into
/// every visible `PostEngagement`, which filters by its own post id and then
/// asks [ReactionState.refresh] for the authoritative rows.
///
/// Why refresh instead of hand-maintained deltas: counts are always
/// recomputed from rows, so a duplicate/echoed event can at worst cause one
/// extra fetch — it can never double-increment a count. No optimistic local
/// aggregate is ever updated from an event here.
library;

/// Kind of a realtime reaction event on `public.post_reactions`.
enum ReactionRealtimeKind {
  /// A row was inserted (a traveller cast a vote).
  insert,

  /// A row was updated (LIKE <-> DISLIKE).
  update,

  /// A row was deleted (vote removed).
  delete,
}

/// One realtime reaction change for a single post.
///
/// [eventId] is the transport's dedupe/diagnostic token (commit timestamp +
/// post + user). Consumers do not need it for correctness: [postId] selects
/// the affected card and the reconcile step is an authoritative refetch.
class ReactionRealtimeEvent {
  /// Commit-scoped id, e.g. `2026-11-03T10:00:00.000Z:<post>:<user>`.
  final String eventId;

  /// What changed.
  final ReactionRealtimeKind kind;

  /// Affected `post_reactions.post_id`. Never empty (mapped payloads with no
  /// post id are dropped by the composition root).
  final String postId;

  const ReactionRealtimeEvent({
    required this.eventId,
    required this.kind,
    required this.postId,
  });

  /// True when this event belongs to [otherPostId] (the card's own id).
  bool appliesTo(String otherPostId) =>
      postId.isNotEmpty && postId == otherPostId;

  @override
  String toString() => 'ReactionRealtimeEvent($kind, post: $postId)';
}
