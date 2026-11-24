import '../media/post_attachment.dart';
import '../profile/public_profile.dart';

/// Board text post model (packet A07, requirement R-13; P42 attachments and
/// safe author identity).
///
/// Mirrors `public.posts(id, user_id, body, image_path, created_at)` plus the
/// optional P42 additions: the embedded `post_attachments` collection and the
/// safe `public.public_profile_cards` author card. Pure Dart: no Flutter, no
/// Supabase, no I/O. All server access is injected by the state layers; this
/// file only shapes data and validates the body.
class Post {
  /// Body length bounds, measured on the trimmed body.
  static const int minBodyLength = 1;

  /// Body length bounds, measured on the trimmed body.
  static const int maxBodyLength = 2000;

  /// Row id (`posts.id`). Null for a not-yet-inserted draft.
  final String? id;

  /// Author (`posts.user_id`).
  final String userId;

  /// Post text (`posts.body`, 1..2000 chars after trim).
  final String body;

  /// Storage object path (`posts.image_path`, e.g. `<uid>/<uuid>.jpg`).
  /// Null for text-only posts. Never a local preview marker.
  final String? imagePath;

  /// Row timestamp (`posts.created_at`). Null for a not-yet-inserted draft.
  final DateTime? createdAt;

  /// P42 typed attachments (0..10). Empty for legacy/text-only rows.
  final List<PostAttachment> attachments;

  /// P42 safe public author identity. Null when the reader did not load it
  /// (legacy callers/tests keep the old card without an author header).
  final PublicProfile? author;

  const Post({
    this.id,
    required this.userId,
    required this.body,
    this.imagePath,
    this.createdAt,
    this.attachments = const <PostAttachment>[],
    this.author,
  });

  /// Returns an error message when [body] is invalid, else null.
  ///
  /// Rules: trimmed length must be within 1..2000 chars.
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

  /// Builds an unpersisted post, throwing [ArgumentError] on invalid body.
  factory Post.draft({
    required String userId,
    required String body,
    String? imagePath,
  }) {
    final error = validateBody(body);
    if (error != null) throw ArgumentError(error);
    return Post(userId: userId, body: body.trim(), imagePath: imagePath);
  }

  /// A draft with an uploaded image path attached. The original is unchanged.
  Post withImage(String remotePath) => Post(
    id: id,
    userId: userId,
    body: body,
    imagePath: remotePath,
    createdAt: createdAt,
    attachments: attachments,
    author: author,
  );

  /// Same row with the safe author card attached.
  Post withAuthor(PublicProfile? profile) => Post(
    id: id,
    userId: userId,
    body: body,
    imagePath: imagePath,
    createdAt: createdAt,
    attachments: attachments,
    author: profile,
  );

  /// Parses one `public.posts` row (Supabase REST/RPC map).
  ///
  /// Accepts the PostgREST embedded shapes `post_attachments: [...]` and
  /// `author: {...}` (or `public_profile_cards: {...}`) when present. Legacy
  /// rows without them keep the pre-P42 card exactly.
  factory Post.fromMap(Map<String, dynamic> map) {
    final Object? rawAttachments =
        map['post_attachments'] ?? map['attachments'];
    final List<PostAttachment> attachments = <PostAttachment>[];
    if (rawAttachments is List) {
      for (final Object? row in rawAttachments) {
        if (row is Map) {
          attachments.add(
            PostAttachment.fromMap(Map<String, dynamic>.from(row)),
          );
        }
      }
      attachments.sort(
        (PostAttachment a, PostAttachment b) =>
            a.displayOrder.compareTo(b.displayOrder),
      );
    }
    final Object? rawAuthor = map['author'] ?? map['public_profile_cards'];
    PublicProfile? author;
    if (rawAuthor is Map) {
      final Map<String, dynamic> authorMap = Map<String, dynamic>.from(
        rawAuthor,
      );
      if ((authorMap['id'] ?? '').toString().isNotEmpty) {
        author = PublicProfile.fromMap(authorMap);
      }
    }
    return Post(
      id: map['id'] as String?,
      userId: (map['user_id'] ?? '') as String,
      body: (map['body'] ?? '') as String,
      imagePath: map['image_path'] as String?,
      createdAt: map['created_at'] == null
          ? null
          : DateTime.tryParse(map['created_at'] as String),
      attachments: attachments,
      author: author,
    );
  }

  /// Insert payload for `public.posts` (server sets id/created_at).
  Map<String, dynamic> toInsertMap() => <String, dynamic>{
    'user_id': userId,
    'body': body,
    if (imagePath != null) 'image_path': imagePath,
  };
}
