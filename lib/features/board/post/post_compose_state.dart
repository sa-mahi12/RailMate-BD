import 'package:flutter/foundation.dart';

import '../media/post_media.dart';
import 'post.dart';

/// Injected post-row insert: creates a text-only `public.posts` row and
/// returns the stored [Post]. Production wiring calls hosted Supabase
/// (authenticated insert); tests inject a fake.
typedef CreatePostRow = Future<Post> Function({
  required String userId,
  required String body,
});

/// Injected post-row delete: removes the `public.posts` row with [postId].
/// Used for partial-failure (orphan) cleanup.
typedef DeletePostRow = Future<void> Function(String postId);

/// Compose state for one board post (packet A07, R-13).
///
/// Flow in [submit]:
/// 1. validate body via [Post.validateBody] (1..2000 chars);
/// 2. insert the text-only post row via [CreatePostRow];
/// 3. when image bytes are attached, upload them to the owned path
///    [buildOwnedImagePath] via the injected [UploadBytes].
///
/// Partial failure: the post row may exist while the image upload failed
/// ([hasOrphan] true). The row is left in place and [cleanupOrphan] is
/// exposed so the UI offers an explicit retry-or-delete choice; cleanup
/// deletes the row via [DeletePostRow] and best-effort deletes the reserved
/// object path via [DeleteObject] when provided. Nothing here calls
/// Supabase directly — every side effect is injected.
class PostComposeState extends ChangeNotifier {
  /// Local media attachment (preview bytes + explicit [UploadState]).
  final PostMediaAttachment media = PostMediaAttachment();

  String _body = '';
  String? bodyError;
  bool submitting = false;
  String? errorMessage;

  /// The inserted post row, or null before a successful insert.
  Post? createdPost;

  /// The owned object path reserved for this submit attempt. Set even when
  /// the upload failed, so cleanup can best-effort remove a half-written
  /// object. Null for text-only submits.
  String? reservedImagePath;

  PostComposeState() {
    media.addListener(notifyListeners);
  }

  @override
  void dispose() {
    media.removeListener(notifyListeners);
    media.dispose();
    super.dispose();
  }

  /// Current body text.
  String get body => _body;

  /// Trimmed body length (for the counter UI).
  int get bodyLength => _body.trim().length;

  /// True when the post row exists but its image upload failed — the UI
  /// must surface the [cleanupOrphan] action in this case.
  bool get hasOrphan =>
      createdPost != null && media.state == UploadState.failed;

  /// True when a full post (row, plus image if attached) is done.
  bool get isDone =>
      createdPost != null &&
      (!media.hasBytes || media.state == UploadState.uploaded);

  /// Updates the body and revalidates (clears [bodyError] when valid).
  void setBody(String value) {
    _body = value;
    bodyError = Post.validateBody(_body);
    notifyListeners();
  }

  /// Forwards picked bytes to [media] as a local preview.
  void attachImageBytes(List<int> data) => media.attach(data);

  /// Discards the attached image (also clears a failed upload state).
  void clearImage() {
    media.clear();
    reservedImagePath = null;
    notifyListeners();
  }

  /// Runs the create-then-upload flow described above.
  ///
  /// [newUuid] supplies the random object name segment (uuid without
  /// slashes); kept as a parameter so tests inject a fixed value and the
  /// slice stays free of uuid packages. Returns true when the whole submit
  /// (row, plus image if attached) succeeded.
  Future<bool> submit({
    required String userId,
    required String Function() newUuid,
    required CreatePostRow createPost,
    required UploadBytes uploadBytes,
  }) async {
    bodyError = Post.validateBody(_body);
    if (bodyError != null) {
      notifyListeners();
      return false;
    }
    if (submitting) return false;
    submitting = true;
    errorMessage = null;
    notifyListeners();
    try {
      final row = await createPost(userId: userId, body: _body.trim());
      createdPost = row;
      if (!media.hasBytes) {
        return true;
      }
      reservedImagePath = buildOwnedImagePath(userId, newUuid());
      final ok = await media.upload(
        path: reservedImagePath!,
        uploadBytes: uploadBytes,
      );
      if (!ok) {
        errorMessage =
            'Post saved, but the photo failed to upload. '
            'Retry the photo or delete the post.';
      }
      return ok;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  /// Removes the orphan post row (and best-effort the reserved object)
  /// after a partial failure. Returns true when the row was deleted.
  /// No-op returning false when there is nothing to clean up.
  Future<bool> cleanupOrphan({
    required DeletePostRow deletePost,
    DeleteObject? deleteObject,
  }) async {
    final row = createdPost;
    if (row == null || row.id == null) return false;
    try {
      await deletePost(row.id!);
      final path = reservedImagePath;
      if (path != null && deleteObject != null) {
        try {
          await deleteObject(path);
        } catch (_) {
          // Best-effort: the object may not exist (upload threw first).
        }
      }
      createdPost = null;
      reservedImagePath = null;
      media.clear();
      errorMessage = null;
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Resets to a pristine composer (e.g. after leaving the screen).
  void reset() {
    _body = '';
    bodyError = null;
    errorMessage = null;
    createdPost = null;
    reservedImagePath = null;
    submitting = false;
    media.clear();
    notifyListeners();
  }
}
