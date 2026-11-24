/// P42 — typed Journey Board attachments (image, video, file, external link).
///
/// Mirrors `public.post_attachments`. Pure Dart: no Flutter, no Supabase, no
/// I/O. The database enforces the same rules (see migration
/// `20261124000001_p42_social_web.sql`): uploaded media must carry a Storage
/// path under the author's folder, links must be HTTPS and never fetched
/// server-side, and at most 10 attachments belong to one post.
library;

/// One attachment kind, matching the `post_attachments.kind` check.
enum PostAttachmentKind {
  image,
  video,
  file,
  link;

  /// Parses the database value; unknown values become [file] so a future
  /// server-side kind never crashes an older client (it still renders a
  /// download card).
  static PostAttachmentKind fromDb(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'image':
        return PostAttachmentKind.image;
      case 'video':
        return PostAttachmentKind.video;
      case 'link':
        return PostAttachmentKind.link;
      default:
        return PostAttachmentKind.file;
    }
  }

  String get dbValue => name;
}

/// Storage bucket holding public Journey Board media.
const String postMediaBucketName = 'post-media';

/// Per-object cap, mirrored from the bucket's `file_size_limit`.
const int postAttachmentMaxBytes = 25 * 1024 * 1024;

/// Maximum attachments on one post, mirrored from the database trigger.
const int postAttachmentMaxPerPost = 10;

/// MIME types the `post-media` bucket accepts. Anything else is rejected
/// before upload so the composer never shows a doomed "Uploading…".
const Set<String> postAttachmentAllowedMimes = <String>{
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
  'video/mp4',
  'video/webm',
  'audio/mpeg',
  'audio/mp4',
  'application/pdf',
  'text/plain',
  'text/csv',
  'application/zip',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-powerpoint',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
};

/// Extension used for a stored object, derived from an allowlisted MIME.
String attachmentExtensionForMime(String mimeType) {
  switch (mimeType.trim().toLowerCase()) {
    case 'image/jpeg':
      return 'jpg';
    case 'image/png':
      return 'png';
    case 'image/webp':
      return 'webp';
    case 'image/gif':
      return 'gif';
    case 'video/mp4':
      return 'mp4';
    case 'video/webm':
      return 'webm';
    case 'audio/mpeg':
      return 'mp3';
    case 'audio/mp4':
      return 'm4a';
    case 'application/pdf':
      return 'pdf';
    case 'text/plain':
      return 'txt';
    case 'text/csv':
      return 'csv';
    case 'application/zip':
      return 'zip';
    case 'application/msword':
      return 'doc';
    case 'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
      return 'docx';
    case 'application/vnd.ms-powerpoint':
      return 'ppt';
    case 'application/vnd.openxmlformats-officedocument.presentationml.presentation':
      return 'pptx';
    default:
      return 'bin';
  }
}

/// Kind implied by an allowlisted MIME type.
PostAttachmentKind attachmentKindForMime(String mimeType) {
  final String mime = mimeType.trim().toLowerCase();
  if (mime.startsWith('image/')) return PostAttachmentKind.image;
  if (mime.startsWith('video/')) return PostAttachmentKind.video;
  if (mime.startsWith('audio/')) return PostAttachmentKind.file;
  return PostAttachmentKind.file;
}

/// Human file size (`1.4 MB`), used by composer previews and download cards.
String formatAttachmentSize(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  final double kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
  final double mb = kb / 1024;
  return '${mb.toStringAsFixed(1)} MB';
}

/// Storage object path for one uploaded attachment.
///
/// Contract: `<auth.uid()>/<post-id>/<uuid>.<ext>` — the first path segment is
/// the owner uid, which is what the `post-media` Storage policies check. Throws
/// [ArgumentError] on empty parts or embedded slashes.
String buildAttachmentStoragePath({
  required String userId,
  required String postId,
  required String uuid,
  required String mimeType,
}) {
  final String uid = userId.trim();
  final String post = postId.trim();
  final String id = uuid.trim();
  if (uid.isEmpty || post.isEmpty || id.isEmpty) {
    throw ArgumentError('userId, postId and uuid must be non-empty.');
  }
  if (uid.contains('/') || post.contains('/') || id.contains('/')) {
    throw ArgumentError('Storage path segments must not contain "/".');
  }
  final String ext = attachmentExtensionForMime(mimeType);
  return '$uid/$post/$id.$ext';
}

/// Public display URL for one stored object (bucket is world-readable).
String attachmentPublicUrl({
  required String supabaseUrl,
  required String storagePath,
}) {
  var base = supabaseUrl.trim();
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  var path = storagePath.trim();
  while (path.startsWith('/')) {
    path = path.substring(1);
  }
  return '$base/storage/v1/object/public/$postMediaBucketName/$path';
}

/// Validates an external HTTPS link. Returns an error sentence or null.
///
/// Rules: absolute `https` URL, a host, no embedded credentials, no whitespace
/// or control characters, at most 2048 characters. `http`, `javascript:`,
/// `data:` and relative paths are rejected — the same contract the database
/// check constraint enforces.
String? validateExternalHttpsUrl(String? raw) {
  final String value = (raw ?? '').trim();
  if (value.isEmpty) return 'Paste a link first.';
  if (value.length > 2048) return 'That link is too long (max 2048).';
  if (value.contains(RegExp(r'\s'))) return 'Links cannot contain spaces.';
  final Uri? uri = Uri.tryParse(value);
  if (uri == null) return 'That does not look like a link.';
  if (uri.scheme.toLowerCase() != 'https') {
    return 'Only https:// links are allowed.';
  }
  if (uri.host.trim().isEmpty) return 'That link has no website address.';
  if (uri.userInfo.isNotEmpty) {
    return 'Links with embedded usernames or passwords are not allowed.';
  }
  return null;
}

/// Allowlisted embeddable video providers. Anything else stays a plain link.
enum ExternalVideoProvider { youtube, vimeo }

/// Recognised provider for a URL, or null for a generic link.
ExternalVideoProvider? externalVideoProviderFor(String? raw) {
  if (validateExternalHttpsUrl(raw) != null) return null;
  final Uri uri = Uri.parse(raw!.trim());
  final String host = uri.host.toLowerCase();
  if (host == 'youtu.be' ||
      host == 'youtube.com' ||
      host == 'www.youtube.com' ||
      host == 'm.youtube.com' ||
      host == 'music.youtube.com') {
    return ExternalVideoProvider.youtube;
  }
  if (host == 'vimeo.com' ||
      host == 'www.vimeo.com' ||
      host == 'player.vimeo.com') {
    return ExternalVideoProvider.vimeo;
  }
  return null;
}

/// Extracts the provider video id (YouTube 11 chars, Vimeo digits), or null.
String? externalVideoIdFor(String? raw) {
  final ExternalVideoProvider? provider = externalVideoProviderFor(raw);
  if (provider == null) return null;
  final Uri uri = Uri.parse(raw!.trim());
  switch (provider) {
    case ExternalVideoProvider.youtube:
      if (uri.host.toLowerCase() == 'youtu.be') {
        final String id = uri.pathSegments.isEmpty
            ? ''
            : uri.pathSegments.first;
        return RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id) ? id : null;
      }
      final String v = uri.queryParameters['v'] ?? '';
      if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(v)) return v;
      // /shorts/<id>, /embed/<id>, /live/<id>
      for (final String segment in uri.pathSegments) {
        if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(segment)) return segment;
      }
      return null;
    case ExternalVideoProvider.vimeo:
      for (final String segment in uri.pathSegments.reversed) {
        if (RegExp(r'^\d{5,12}$').hasMatch(segment)) return segment;
      }
      return null;
  }
}

/// Privacy-friendly embed URL for a recognised provider, else null.
String? externalVideoEmbedUrl(String? raw) {
  final String? id = externalVideoIdFor(raw);
  if (id == null) return null;
  switch (externalVideoProviderFor(raw)) {
    case ExternalVideoProvider.youtube:
      return 'https://www.youtube-nocookie.com/embed/$id?rel=0';
    case ExternalVideoProvider.vimeo:
      return 'https://player.vimeo.com/video/$id';
    case null:
      return null;
  }
}

/// One row of `public.post_attachments`.
class PostAttachment {
  final String? id;
  final String postId;
  final String ownerId;
  final PostAttachmentKind kind;
  final String? storagePath;
  final String? externalUrl;
  final String? mimeType;
  final String? originalFilename;
  final int? fileSizeBytes;
  final int displayOrder;
  final DateTime? createdAt;

  const PostAttachment({
    this.id,
    required this.postId,
    required this.ownerId,
    required this.kind,
    this.storagePath,
    this.externalUrl,
    this.mimeType,
    this.originalFilename,
    this.fileSizeBytes,
    this.displayOrder = 0,
    this.createdAt,
  });

  /// Parses one `post_attachments` row. Missing optional columns become null;
  /// a malformed `kind` degrades to a file card rather than throwing.
  factory PostAttachment.fromMap(Map<String, dynamic> map) {
    final Object? size = map['file_size_bytes'];
    return PostAttachment(
      id: map['id'] as String?,
      postId: (map['post_id'] ?? '') as String,
      ownerId: (map['owner_id'] ?? '') as String,
      kind: PostAttachmentKind.fromDb(map['kind'] as String?),
      storagePath: map['storage_path'] as String?,
      externalUrl: map['external_url'] as String?,
      mimeType: map['mime_type'] as String?,
      originalFilename: map['original_filename'] as String?,
      fileSizeBytes: size is int
          ? size
          : (size is num ? size.toInt() : int.tryParse('$size')),
      displayOrder: (map['display_order'] as num?)?.toInt() ?? 0,
      createdAt: map['created_at'] == null
          ? null
          : DateTime.tryParse(map['created_at'] as String),
    );
  }

  /// Insert payload (server sets `id`/`created_at`).
  Map<String, dynamic> toInsertMap() => <String, dynamic>{
    'post_id': postId,
    'owner_id': ownerId,
    'kind': kind.dbValue,
    if (storagePath != null) 'storage_path': storagePath,
    if (externalUrl != null) 'external_url': externalUrl,
    if (mimeType != null) 'mime_type': mimeType,
    if (originalFilename != null) 'original_filename': originalFilename,
    if (fileSizeBytes != null) 'file_size_bytes': fileSizeBytes,
    'display_order': displayOrder,
  };

  /// True when this row points at a Storage object.
  bool get isUploaded => (storagePath ?? '').isNotEmpty;

  /// True when this row is an allowlisted video provider embed.
  bool get isEmbeddableVideo =>
      kind == PostAttachmentKind.link &&
      externalVideoProviderFor(externalUrl) != null;

  /// Best label for a file card: original name, else the path tail.
  String get fileName {
    final String name = (originalFilename ?? '').trim();
    if (name.isNotEmpty) return name;
    final String path = (storagePath ?? '').trim();
    if (path.isEmpty) return 'Attachment';
    final int slash = path.lastIndexOf('/');
    return slash >= 0 ? path.substring(slash + 1) : path;
  }
}
