/// Board reaction model (packet A08, requirement R-03).
///
/// Mirrors `public.post_reactions(post_id, user_id, reaction, created_at)`
/// with `PK(post_id, user_id)` = one vote per user/post and
/// `CHECK (reaction IN ('LIKE','DISLIKE'))`.
/// Pure Dart: no Flutter, no Supabase, no I/O. Server access is injected
/// by [ReactionState]; this file only shapes data and validates values.
///
/// RLS (see `supabase/migrations/20260927000002_rls.sql`, read-only here):
/// `reactions_read` (public select), `reactions_insert_own`,
/// `reactions_update_own`, `reactions_delete_own` (owner writes only).
enum ReactionValue {
  /// Server value `'LIKE'`.
  like,

  /// Server value `'DISLIKE'`.
  dislike,
}

/// Server string for [value] (`'LIKE'` / `'DISLIKE'`).
String reactionToServer(ReactionValue value) =>
    value == ReactionValue.like ? 'LIKE' : 'DISLIKE';

/// Parses a server reaction string. Returns null for anything else.
ReactionValue? reactionFromServer(String? raw) {
  switch ((raw ?? '').trim().toUpperCase()) {
    case 'LIKE':
      return ReactionValue.like;
    case 'DISLIKE':
      return ReactionValue.dislike;
    default:
      return null;
  }
}

/// One `public.post_reactions` row.
class PostReaction {
  /// Row post (`post_reactions.post_id`).
  final String postId;

  /// Row author (`post_reactions.user_id`).
  final String userId;

  /// Row vote (`post_reactions.reaction`).
  final ReactionValue reaction;

  const PostReaction({
    required this.postId,
    required this.userId,
    required this.reaction,
  });

  /// Parses one `public.post_reactions` row map. Throws [ArgumentError]
  /// on missing ids or an unknown reaction string.
  factory PostReaction.fromMap(Map<String, dynamic> map) {
    final postId = (map['post_id'] ?? '').toString();
    final userId = (map['user_id'] ?? '').toString();
    final reaction = reactionFromServer(map['reaction'] as String?);
    if (postId.isEmpty || userId.isEmpty || reaction == null) {
      throw ArgumentError('Invalid post_reactions row: $map');
    }
    return PostReaction(postId: postId, userId: userId, reaction: reaction);
  }

  /// Upsert payload for `public.post_reactions` (PK covers post+user).
  Map<String, dynamic> toUpsertMap() => <String, dynamic>{
    'post_id': postId,
    'user_id': userId,
    'reaction': reactionToServer(reaction),
  };
}
