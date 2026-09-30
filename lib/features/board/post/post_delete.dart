import '../media/post_media.dart';
import 'post.dart';
import 'post_compose_state.dart';

/// Deletes one published board post row plus its image object (F13b orphan
/// follow-up).
///
/// Flow: delete the `public.posts` row via [deletePost], then best-effort
/// delete the Storage object at [post.imagePath] via [deleteObject] when
/// both are provided. Object failures are swallowed silently (the object
/// may not exist; the row delete already succeeded) — same convention as
/// [PostComposeState.cleanupOrphan] and `deleteBoardObjectBestEffort`: no
/// throw, no user-facing error, no log output. Nothing here calls Supabase
/// directly — every side effect is injected.
///
/// Returns true when the row was deleted, false when [post.id] is null
/// (nothing to delete — no injected call runs). Throws when [deletePost]
/// itself throws (row delete is NOT best-effort: the caller must surface
/// that failure honestly).
Future<bool> deletePostAndImage({
  required Post post,
  required DeletePostRow deletePost,
  DeleteObject? deleteObject,
}) async {
  final id = post.id;
  if (id == null || id.isEmpty) return false;
  await deletePost(id);
  final path = post.imagePath;
  final remove = deleteObject;
  if (path != null && path.isNotEmpty && remove != null) {
    try {
      await remove(path);
    } catch (_) {
      // Best-effort: the object may not exist. Row is already gone.
    }
  }
  return true;
}
