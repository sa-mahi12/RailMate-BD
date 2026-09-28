import 'package:flutter/foundation.dart';

/// Explicit lifecycle of one board image.
///
/// `local` means "bytes held on this device only" (picker preview).
/// A local preview must NEVER be rendered or reported as a cloud upload —
/// only [uploaded] means bytes reached the `post-media` bucket.
enum UploadState {
  /// Bytes selected locally; nothing sent to Storage.
  local,

  /// An upload call is in flight.
  uploading,

  /// Bytes confirmed stored at [PostMediaAttachment.remotePath].
  uploaded,

  /// The last upload attempt threw; see [PostMediaAttachment.errorMessage].
  failed,
}

/// Builds the owned Storage object path for a board image.
///
/// Contract (see `supabase/migrations/20260927000004_storage_policy.sql`):
/// RLS only allows upload/delete under the folder `<auth.uid()>/`, so the
/// first path segment MUST be the author's uid:
/// `<userId>/<uuid>.jpg`. Throws [ArgumentError] on empty parts, slashes
/// inside either part, or an unusable extension.
String buildOwnedImagePath(String userId, String uuid, {String ext = 'jpg'}) {
  final uid = userId.trim();
  final id = uuid.trim();
  if (uid.isEmpty || id.isEmpty) {
    throw ArgumentError('userId and uuid must both be non-empty.');
  }
  if (uid.contains('/') || id.contains('/')) {
    throw ArgumentError('userId and uuid must not contain "/".');
  }
  final cleanExt = ext.trim().toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9]'),
    '',
  );
  if (cleanExt.isEmpty) {
    throw ArgumentError('ext must contain at least one alphanumeric char.');
  }
  return '$uid/$id.$cleanExt';
}

/// Storage bucket holding board images.
const String postMediaBucket = 'post-media';

/// Builds the PUBLIC display URL for a board image object.
///
/// Contract (see `supabase/migrations/20260927000004_storage_policy.sql`):
/// `post_media_read` grants SELECT on `post-media` to `anon,authenticated`,
/// so the bucket is publicly readable and NO signed URL is needed — the
/// standard Supabase Storage public-object URL is sufficient:
/// `<supabaseUrl>/storage/v1/object/public/post-media/<imagePath>`.
///
/// Returns null when [imagePath] is null/empty (text-only post) so callers
/// render no image widget at all. Trims a trailing `/` from [supabaseUrl]
/// and leading `/`s from [imagePath] so composition never doubles slashes.
/// Pure Dart: no Flutter, no Supabase, no I/O.
String? postImageUrl({
  required String supabaseUrl,
  required String? imagePath,
}) {
  final path = (imagePath ?? '').trim();
  if (path.isEmpty) return null;
  var base = supabaseUrl.trim();
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  if (base.isEmpty) return null;
  var clean = path;
  while (clean.startsWith('/')) {
    clean = clean.substring(1);
  }
  if (clean.isEmpty) return null;
  return '$base/storage/v1/object/public/$postMediaBucket/$clean';
}

/// Injected public-URL resolver for one stored object path.
///
/// Production wiring closes over the hosted Supabase URL
/// (`(path) => postImageUrl(supabaseUrl: url, imagePath: path)`);
/// tests inject a fake. Null (the default on screens) means "no URL
/// resolution wired" — the feed falls back to the 'Photo attached' badge
/// instead of rendering a broken image.
typedef ResolveBoardImageUrl = String? Function(String? imagePath);

/// Injected byte upload: store [bytes] at Storage object [path].
/// Production wiring calls hosted Supabase Storage
/// (`post-media` bucket); tests inject a fake. Never called implicitly by
/// the attachment — only via [PostMediaAttachment.upload].
typedef UploadBytes = Future<void> Function(String path, List<int> bytes);

/// Injected object delete: remove the Storage object at [path].
/// Used for best-effort partial-failure cleanup.
typedef DeleteObject = Future<void> Function(String path);

/// One locally-picked board image plus its explicit upload lifecycle.
///
/// Bytes arrive via [attach] from a method channel-agnostic picker callback
/// (no image_picker/compression packages in this slice; compression is a
/// documented later step — see handoff). Uploads only happen through
/// [upload] with an explicitly injected [UploadBytes] function.
class PostMediaAttachment extends ChangeNotifier {
  /// Locally held bytes (preview). Null when no image is attached.
  List<int>? bytes;

  /// Confirmed remote object path. Set only on [UploadState.uploaded].
  String? remotePath;

  /// Current lifecycle state. Starts at [UploadState.local].
  UploadState state = UploadState.local;

  /// Last upload error, human-readable. Null unless [state] is failed.
  String? errorMessage;

  /// True when local bytes are attached (regardless of upload state).
  bool get hasBytes => bytes != null && bytes!.isNotEmpty;

  /// True only after bytes were confirmed stored remotely.
  bool get isUploaded => state == UploadState.uploaded && remotePath != null;

  /// Attaches picked bytes as a LOCAL preview. Explicitly resets the state
  /// to [UploadState.local] — attaching never implies an upload.
  void attach(List<int> data) {
    if (data.isEmpty) throw ArgumentError('Cannot attach empty bytes.');
    bytes = List<int>.unmodifiable(data);
    remotePath = null;
    errorMessage = null;
    state = UploadState.local;
    notifyListeners();
  }

  /// Discards the local bytes and resets to pristine local state.
  void clear() {
    bytes = null;
    remotePath = null;
    errorMessage = null;
    state = UploadState.local;
    notifyListeners();
  }

  /// Uploads the attached bytes to [path] via [uploadBytes].
  ///
  /// Returns true on success ([state] becomes uploaded with [remotePath]
  /// set). Returns false on failure ([state] becomes failed with
  /// [errorMessage] set). No-op returning false when no bytes are attached.
  Future<bool> upload({
    required String path,
    required UploadBytes uploadBytes,
  }) async {
    final data = bytes;
    if (data == null || data.isEmpty) return false;
    state = UploadState.uploading;
    errorMessage = null;
    notifyListeners();
    try {
      await uploadBytes(path, data);
      remotePath = path;
      state = UploadState.uploaded;
      notifyListeners();
      return true;
    } catch (e) {
      // Bytes may or may not exist remotely; the caller decides cleanup.
      remotePath = null;
      errorMessage = e.toString();
      state = UploadState.failed;
      notifyListeners();
      return false;
    }
  }
}
