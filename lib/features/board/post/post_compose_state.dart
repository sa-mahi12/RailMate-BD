import 'package:flutter/foundation.dart';

import '../media/board_attachment_picker.dart';
import '../media/post_attachment.dart';
import '../media/post_media.dart';
import 'compose_attachment.dart';
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

/// Injected image-link update: persists the uploaded Storage object [path]
/// onto the `public.posts` row [postId] (`image_path`) and returns the
/// stored [Post]. Production wiring calls hosted Supabase (authenticated
/// update, RLS `posts_edit_own`); tests inject a fake.
///
/// This seam exists because [CreatePostRow] inserts the text-only row first
/// and the bytes upload second — without this step the uploaded object
/// would stay orphaned (row `image_path` null) and the feed could never
/// display the photo.
typedef UpdatePostImage = Future<Post> Function({
  required String postId,
  required String imagePath,
});

/// P42 injected byte upload for one attachment, including its declared MIME
/// type (the `post-media` bucket enforces an allowlist, so a missing content
/// type would be rejected as `application/octet-stream`).
typedef UploadAttachmentBytes = Future<void> Function(
  String path,
  List<int> bytes,
  String contentType,
);

/// P42 injected attachment-row insert (`public.post_attachments`).
typedef InsertAttachmentRow = Future<PostAttachment> Function(
  PostAttachment row,
);

/// Compose state for one board post (packet A07, R-13).
///
/// Flow in [submit]:
/// 1. validate body via [Post.validateBody] (1..2000 chars);
/// 2. insert the text-only post row via [CreatePostRow];
/// 3. when image bytes are attached, upload them to the owned path
///    [buildOwnedImagePath] via the injected [UploadBytes];
/// 4. when [UpdatePostImage] is provided, persist the uploaded object path
///    onto the row via [linkUploadedImage] so the feed can display it.
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

  /// Last image-link error (persisting `image_path` after a successful
  /// upload threw). Null unless a link attempt failed; the post row AND the
  /// uploaded object both exist in that case, so the UI should offer cleanup
  /// via [cleanupOrphan] just like the upload-failure orphan path.
  String? imageLinkError;

  /// P42 multi-attachment draft (0..[postAttachmentMaxPerPost]).
  final List<ComposeAttachment> attachments = <ComposeAttachment>[];

  int _attachmentSeq = 0;

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
  /// must surface the [cleanupOrphan] action in this case. Also true when
  /// the upload succeeded but linking `image_path` failed ([imageLinkError]
  /// set): row and object both exist, so the same delete action applies.
  /// P42: a failed multi-attachment upload is the same kind of partial
  /// failure, so it also marks the draft as an orphan.
  bool get hasOrphan =>
      createdPost != null &&
      (media.state == UploadState.failed ||
          imageLinkError != null ||
          attachments.any(
            (ComposeAttachment a) => a.state == UploadState.failed,
          ));

  /// True when a full post (row, plus image if attached) is done.
  bool get isDone =>
      createdPost != null &&
      (!media.hasBytes || media.state == UploadState.uploaded) &&
      attachments.every((ComposeAttachment a) => a.isStored);

  /// Updates the body and revalidates (clears [bodyError] when valid).
  void setBody(String value) {
    _body = value;
    bodyError = Post.validateBody(_body);
    notifyListeners();
  }

  /// Forwards picked bytes to [media] as a local preview.
  void attachImageBytes(List<int> data) => media.attach(data);

  /// Discards the attached image (also clears failed upload/link state).
  void clearImage() {
    media.clear();
    reservedImagePath = null;
    imageLinkError = null;
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // P42 multi-attachment draft
  // ------------------------------------------------------------------

  /// Adds one picked file. Returns an honest error message, or null on
  /// success. Rejects empty/oversize/non-allowlisted files and the 10-item cap
  /// BEFORE anything is uploaded.
  String? addPickedAttachment(PickedBoardFile file) {
    if (attachments.length >= postAttachmentMaxPerPost) {
      return 'You can attach up to $postAttachmentMaxPerPost items per post.';
    }
    final String? invalid = validatePickedAttachment(file);
    if (invalid != null) return invalid;
    attachments.add(
      ComposeAttachment.file(local: file, key: 'att-${_attachmentSeq++}'),
    );
    notifyListeners();
    return null;
  }

  /// Adds one external HTTPS link. Returns an honest error message, or null.
  /// Duplicate URLs on the same draft are rejected (they would render twice).
  String? addLinkAttachment(String rawUrl) {
    if (attachments.length >= postAttachmentMaxPerPost) {
      return 'You can attach up to $postAttachmentMaxPerPost items per post.';
    }
    final String? invalid = validateExternalHttpsUrl(rawUrl);
    if (invalid != null) return invalid;
    final String url = rawUrl.trim();
    if (attachments.any((ComposeAttachment a) => a.externalUrl == url)) {
      return 'That link is already attached.';
    }
    attachments.add(
      ComposeAttachment.link(externalUrl: url, key: 'att-${_attachmentSeq++}'),
    );
    notifyListeners();
    return null;
  }

  /// Removes one draft attachment (also clears its failure state).
  void removeAttachmentAt(int index) {
    if (index < 0 || index >= attachments.length) return;
    attachments.removeAt(index);
    notifyListeners();
  }

  /// Reorders one attachment (drag/reorder controls in the composer).
  void moveAttachment(int from, int to) {
    if (from < 0 || from >= attachments.length) return;
    if (to < 0 || to >= attachments.length) return;
    if (from == to) return;
    final ComposeAttachment item = attachments.removeAt(from);
    attachments.insert(to, item);
    notifyListeners();
  }

  /// Publishes a text post plus every draft attachment.
  ///
  /// Order matters: the post row is inserted first (attachments need its id),
  /// then each file is uploaded to `<uid>/<postId>/<uuid>.<ext>` and its row is
  /// inserted, then each link row is inserted. A failure marks that attachment
  /// [UploadState.failed] and stops the submit — the UI must not claim success
  /// and offers Retry or Delete. Text-only posts keep working with no
  /// attachments at all.
  Future<bool> submitWithAttachments({
    required String userId,
    required String Function() newUuid,
    required CreatePostRow createPost,
    required UploadAttachmentBytes uploadAttachment,
    required InsertAttachmentRow insertAttachment,
    UpdatePostImage? updatePostImage,
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
      final Post row = await createPost(userId: userId, body: _body.trim());
      createdPost = row;
      if (attachments.isEmpty) return true;
      final String postId = row.id ?? '';
      if (postId.isEmpty) {
        errorMessage = "The post was saved, but its id came back empty.";
        return false;
      }
      return await _persistAttachments(
        userId: userId,
        postId: postId,
        newUuid: newUuid,
        uploadAttachment: uploadAttachment,
        insertAttachment: insertAttachment,
      );
    } catch (_) {
      errorMessage = "Couldn't publish. Check your connection and retry.";
      return false;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  /// Retries every attachment that is not yet stored, for an already-created
  /// post row. Returns true when all of them are now persisted.
  Future<bool> retryFailedAttachments({
    required String userId,
    required String Function() newUuid,
    required UploadAttachmentBytes uploadAttachment,
    required InsertAttachmentRow insertAttachment,
  }) async {
    final Post? row = createdPost;
    if (row == null || row.id == null || row.id!.isEmpty) return false;
    if (submitting) return false;
    submitting = true;
    errorMessage = null;
    notifyListeners();
    try {
      return await _persistAttachments(
        userId: userId,
        postId: row.id!,
        newUuid: newUuid,
        uploadAttachment: uploadAttachment,
        insertAttachment: insertAttachment,
      );
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  Future<bool> _persistAttachments({
    required String userId,
    required String postId,
    required String Function() newUuid,
    required UploadAttachmentBytes uploadAttachment,
    required InsertAttachmentRow insertAttachment,
  }) async {
    for (int i = 0; i < attachments.length; i++) {
      final ComposeAttachment item = attachments[i];
      if (item.isStored) continue;
      try {
        if (!item.isLink && item.state != UploadState.uploaded) {
          item.state = UploadState.uploading;
          notifyListeners();
          final String path = buildAttachmentStoragePath(
            userId: userId,
            postId: postId,
            uuid: newUuid(),
            mimeType: item.mimeType,
          );
          await uploadAttachment(path, item.local!.bytes, item.mimeType);
          item.remotePath = path;
          item.state = UploadState.uploaded;
          notifyListeners();
        }
        final PostAttachment stored = await insertAttachment(
          PostAttachment(
            postId: postId,
            ownerId: userId,
            kind: item.kind,
            storagePath: item.remotePath,
            externalUrl: item.externalUrl,
            mimeType: item.isLink ? null : item.mimeType,
            originalFilename: item.isLink ? null : item.filename,
            fileSizeBytes: item.isLink ? null : item.sizeBytes,
            displayOrder: i,
          ),
        );
        item.attachmentId = stored.id;
        item.state = UploadState.uploaded;
        item.errorMessage = null;
        notifyListeners();
      } catch (_) {
        item.state = UploadState.failed;
        item.errorMessage = item.isLink
            ? "Couldn't save that link. Remove it or retry."
            : "Couldn't upload that file. Retry or remove it.";
        errorMessage =
            'Some attachments failed. Retry them or remove them before '
            'leaving — the post is already visible with the items that '
            'succeeded.';
        notifyListeners();
        return false;
      }
    }
    return true;
  }

  /// Runs the create-then-upload-then-link flow described above.
  ///
  /// [newUuid] supplies the random object name segment (uuid without
  /// slashes); kept as a parameter so tests inject a fixed value and the
  /// slice stays free of uuid packages. Returns true when the whole submit
  /// (row, plus image if attached) succeeded.
  ///
  /// [updatePostImage] persists the uploaded object path onto the post row.
  /// Null (current production wiring) keeps the old create-then-upload
  /// behaviour: the upload still runs and [reservedImagePath]/[media] still
  /// report it, but the row's `image_path` is linked only when this is
  /// provided. Pass it as soon as the coordinator wires the closure —
  /// otherwise attached photos upload yet never display in the feed.
  Future<bool> submit({
    required String userId,
    required String Function() newUuid,
    required CreatePostRow createPost,
    required UploadBytes uploadBytes,
    UpdatePostImage? updatePostImage,
  }) async {
    bodyError = Post.validateBody(_body);
    if (bodyError != null) {
      notifyListeners();
      return false;
    }
    if (submitting) return false;
    submitting = true;
    errorMessage = null;
    imageLinkError = null;
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
        return false;
      }
      final link = updatePostImage;
      if (link == null) {
        return true;
      }
      return await linkUploadedImage(updateRow: link);
    } catch (_) {
      // Consumer gate: the raw backend error never reaches the UI.
      errorMessage = "Couldn't publish. Check your connection and retry.";
      return false;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  /// Persists the already-uploaded object ([media.remotePath]) onto the
  /// created post row via [updateRow] and replaces [createdPost] with the
  /// stored row (so `image_path` is visible to the feed immediately).
  ///
  /// No-op returning false when there is no created row id or no uploaded
  /// object. On link failure sets [imageLinkError]/[errorMessage] and
  /// returns false — row and object both exist, so the caller should offer
  /// [cleanupOrphan]. Returns true on success.
  Future<bool> linkUploadedImage({required UpdatePostImage updateRow}) async {
    final row = createdPost;
    final path = media.remotePath;
    if (row == null || row.id == null || path == null) return false;
    if (media.state != UploadState.uploaded) return false;
    try {
      final linked = await updateRow(postId: row.id!, imagePath: path);
      createdPost = linked;
      imageLinkError = null;
      notifyListeners();
      return true;
    } catch (e) {
      imageLinkError = e.toString();
      errorMessage =
          'Post and photo uploaded, but the photo could not be linked. '
          'Delete the post and retry.';
      notifyListeners();
      return false;
    }
  }

  /// Removes the orphan post row (and best-effort every known object: the
  /// reserved upload path plus the row's linked `image_path`) after a
  /// partial failure. Returns true when the row was deleted.
  /// No-op returning false when there is nothing to clean up.
  Future<bool> cleanupOrphan({
    required DeletePostRow deletePost,
    DeleteObject? deleteObject,
  }) async {
    final row = createdPost;
    if (row == null || row.id == null) return false;
    try {
      await deletePost(row.id!);
      // F13b orphan follow-up: remove every known object for this post —
      // the reserved upload path AND the row's linked `image_path` (they
      // match in the normal flow, but the link step may have persisted a
      // path while `reservedImagePath` was cleared or vice versa).
      // Best-effort per path: objects may not exist; failures are swallowed
      // silently (repo convention — no user-facing error, no log output).
      final paths = <String>{};
      final reserved = reservedImagePath;
      if (reserved != null && reserved.isNotEmpty) paths.add(reserved);
      final linked = row.imagePath;
      if (linked != null && linked.isNotEmpty) paths.add(linked);
      for (final ComposeAttachment item in attachments) {
        final String? remote = item.remotePath;
        if (remote != null && remote.isNotEmpty) paths.add(remote);
      }
      if (deleteObject != null) {
        for (final path in paths) {
          try {
            await deleteObject(path);
          } catch (_) {
            // Best-effort: the object may not exist (upload threw first).
          }
        }
      }
      createdPost = null;
      reservedImagePath = null;
      media.clear();
      attachments.clear();
      errorMessage = null;
      notifyListeners();
      return true;
    } catch (_) {
      // Consumer gate: the raw backend error never reaches the UI.
      errorMessage = "Couldn't delete the post. Please try again.";
      notifyListeners();
      return false;
    }
  }

  /// Resets to a pristine composer (e.g. after leaving the screen).
  void reset() {
    _body = '';
    bodyError = null;
    errorMessage = null;
    imageLinkError = null;
    createdPost = null;
    reservedImagePath = null;
    submitting = false;
    media.clear();
    attachments.clear();
    notifyListeners();
  }
}
