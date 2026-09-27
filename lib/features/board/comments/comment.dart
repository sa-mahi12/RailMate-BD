/// Board comment model (packet B08, requirement R-02).
///
/// Mirrors `public.post_comments(id, post_id, user_id, body, created_at)`
/// with `body` 1..500 chars after trim and the read index
/// `(post_id, created_at, id)`.
/// Pure Dart: no Flutter, no Supabase, no I/O. All server access is injected
/// by the state layers; this file only shapes data and validates the body.
class Comment {
  /// Body length bounds, measured on the trimmed body.
  static const int minBodyLength = 1;

  /// Body length bounds, measured on the trimmed body.
  static const int maxBodyLength = 500;

  /// Row id (`post_comments.id`). Null for a not-yet-inserted draft.
  final String? id;

  /// Parent post (`post_comments.post_id`, FK `posts` cascade).
  final String postId;

  /// Author (`post_comments.user_id`).
  final String userId;

  /// Comment text (`post_comments.body`, 1..500 chars after trim).
  final String body;

  /// Row timestamp (`post_comments.created_at`). Null for a draft.
  final DateTime? createdAt;

  const Comment({
    this.id,
    required this.postId,
    required this.userId,
    required this.body,
    this.createdAt,
  });

  /// Returns an error message when [body] is invalid, else null.
  ///
  /// Rules: trimmed length must be within 1..500 chars.
  static String? validateBody(String? body) {
    final trimmed = (body ?? '').trim();
    if (trimmed.length < minBodyLength) {
      return 'Write something first (min $minBodyLength character).';
    }
    if (trimmed.length > maxBodyLength) {
      return 'Keep it under $maxBodyLength characters '
          '(currently ${trimmed.length}).';
    }
    return null;
  }

  /// Builds an unpersisted comment, throwing [ArgumentError] on invalid body.
  factory Comment.draft({
    required String postId,
    required String userId,
    required String body,
  }) {
    if (postId.trim().isEmpty) {
      throw ArgumentError('postId must be non-empty.');
    }
    if (userId.trim().isEmpty) {
      throw ArgumentError('userId must be non-empty.');
    }
    final error = validateBody(body);
    if (error != null) throw ArgumentError(error);
    return Comment(postId: postId, userId: userId, body: body.trim());
  }

  /// Parses one `public.post_comments` row (Supabase REST/Realtime map).
  factory Comment.fromMap(Map<String, dynamic> map) => Comment(
    id: map['id'] as String?,
    postId: (map['post_id'] ?? '') as String,
    userId: (map['user_id'] ?? '') as String,
    body: (map['body'] ?? '') as String,
    createdAt: map['created_at'] == null
        ? null
        : DateTime.tryParse(map['created_at'] as String),
  );

  /// Insert payload for `public.post_comments` (server sets id/created_at).
  /// RLS: authenticated users may insert only their own rows.
  Map<String, dynamic> toInsertMap() => <String, dynamic>{
    'post_id': postId,
    'user_id': userId,
    'body': body,
  };
}
