import 'package:flutter/foundation.dart';

import 'comment.dart';

/// Injected comment fetcher: returns the newest-first [Comment] rows for one
/// post. Production wiring queries hosted Supabase (`public.post_comments`
/// where `post_id`, ordered by `created_at` desc, `id` desc); tests inject
/// a fake. Never called implicitly — only via [CommentThread.load].
typedef FetchComments = Future<List<Comment>> Function({
  required String postId,
});

/// Injected comment-row insert: creates one `public.post_comments` row and
/// returns the stored [Comment]. Production wiring calls hosted Supabase
/// (authenticated insert, own `user_id` only); tests inject a fake.
typedef AddCommentRow = Future<Comment> Function({
  required String postId,
  required String userId,
  required String body,
});

/// Injected comment-row delete: removes the `public.post_comments` row with
/// [commentId]. Production wiring calls hosted Supabase (RLS: delete own
/// only); tests inject a fake.
typedef DeleteCommentRow = Future<void> Function(String commentId);

/// Lifecycle of a comment thread load/mutation.
enum CommentThreadStatus { idle, loading, loaded, error }

/// Display + mutation state for the comments of one board post
/// (packet B08, R-02).
///
/// Ordering is newest-first (matches the `(post_id, created_at, id)` read
/// path and ref-7 "Comments(5) newest-first"). Realtime rows arrive via
/// [applyRealtimeInsert]/[applyRealtimeDelete] (wired to
/// [CommentRealtimeSubscription] by the composition root); duplicates by id
/// are ignored so a realtime echo of an optimistically added row never
/// appears twice. Nothing here calls Supabase directly — every side effect
/// is injected.
class CommentThread extends ChangeNotifier {
  /// Parent post id. All rows in [comments] belong to this post.
  final String postId;

  /// Injected reader used by [load].
  final FetchComments fetchComments;

  CommentThreadStatus status = CommentThreadStatus.idle;
  String? errorMessage;

  /// Last add/delete error (validation or injected-function throw).
  String? mutationError;

  bool adding = false;

  /// Ids with a delete currently in flight (for per-row spinners).
  final Set<String> deletingIds = <String>{};

  List<Comment> comments = const <Comment>[];

  CommentThread({required this.postId, required this.fetchComments});

  bool get isLoading => status == CommentThreadStatus.loading;

  /// True when the last load succeeded with zero rows.
  bool get isEmpty => status == CommentThreadStatus.loaded && comments.isEmpty;

  /// Loads the thread window for [postId].
  Future<void> load() async {
    status = CommentThreadStatus.loading;
    errorMessage = null;
    notifyListeners();
    try {
      final rows = await fetchComments(postId: postId);
      comments = List<Comment>.unmodifiable(
        rows.where((c) => c.postId == postId),
      );
      status = CommentThreadStatus.loaded;
    } catch (e) {
      status = CommentThreadStatus.error;
      errorMessage = e.toString();
    }
    notifyListeners();
  }

  /// Validates [body] (1..500 chars) then inserts via [addRow].
  ///
  /// On success the stored row is merged with [applyRealtimeInsert] semantics
  /// (dedupe by id, newest-first) so a later realtime echo is a no-op.
  /// Returns true on success, false on validation/injected failure with
  /// [mutationError] set.
  Future<bool> add({
    required String userId,
    required String body,
    required AddCommentRow addRow,
  }) async {
    final formError = Comment.validateBody(body);
    if (formError != null) {
      mutationError = formError;
      notifyListeners();
      return false;
    }
    if (adding) return false;
    adding = true;
    mutationError = null;
    notifyListeners();
    try {
      final row = await addRow(
        postId: postId,
        userId: userId,
        body: body.trim(),
      );
      if (row.postId != postId) {
        throw StateError('addRow returned a comment for another post.');
      }
      applyRealtimeInsert(row);
      return true;
    } catch (e) {
      mutationError = e.toString();
      return false;
    } finally {
      adding = false;
      notifyListeners();
    }
  }

  /// Deletes [commentId] via [deleteRow] and drops the local row.
  /// Returns true on success, false when the injected call throws
  /// (row is kept locally, [mutationError] set).
  Future<bool> remove(String commentId, DeleteCommentRow deleteRow) async {
    if (commentId.isEmpty || deletingIds.contains(commentId)) return false;
    deletingIds.add(commentId);
    mutationError = null;
    notifyListeners();
    try {
      await deleteRow(commentId);
      applyRealtimeDelete(commentId);
      return true;
    } catch (e) {
      mutationError = e.toString();
      return false;
    } finally {
      deletingIds.remove(commentId);
      notifyListeners();
    }
  }

  /// Merges a realtime/other-client insert. Returns true when the row was
  /// added, false when it was a duplicate id (echo) or belongs to another
  /// post. Maintains newest-first order by (`created_at`, `id`).
  bool applyRealtimeInsert(Comment row) {
    if (row.postId != postId) return false;
    final id = row.id;
    if (id != null && comments.any((c) => c.id == id)) return false;
    final next = List<Comment>.of(comments)..add(row);
    next.sort(_newestFirst);
    comments = List<Comment>.unmodifiable(next);
    notifyListeners();
    return true;
  }

  /// Drops the local row with [commentId]. Returns true when a row was
  /// removed, false when absent (stale/duplicate delete event).
  bool applyRealtimeDelete(String commentId) {
    if (commentId.isEmpty) return false;
    final before = comments.length;
    final next = comments.where((c) => c.id != commentId).toList();
    if (next.length == before) return false;
    comments = List<Comment>.unmodifiable(next);
    notifyListeners();
    return true;
  }

  /// Newest-first comparator on (`created_at`, `id`).
  /// Null timestamps sort last (drafts first only via explicit add path
  /// order — here a null sorts after any real timestamp).
  static int _newestFirst(Comment a, Comment b) {
    final ac = a.createdAt;
    final bc = b.createdAt;
    if (ac != null && bc != null) {
      final byTime = bc.compareTo(ac);
      if (byTime != 0) return byTime;
    } else if (ac != null) {
      return -1;
    } else if (bc != null) {
      return 1;
    }
    return (b.id ?? '').compareTo(a.id ?? '');
  }
}
