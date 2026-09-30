import 'package:flutter/foundation.dart';

import '../list/cursor_paginator.dart';
import 'post.dart';

/// Lifecycle of a board feed load.
enum PostFeedStatus { idle, loading, loaded, error }

/// Injected feed fetcher: returns the newest-first [Post] rows visible to
/// the caller. Production wiring queries hosted Supabase (`public.posts`
/// ordered by `created_at` desc, paged); cursor pagination (five per page)
/// runs through [PostFeedState.fetchPage] in paged mode — window mode loads
/// one window via [limit]. Tests inject a fake.
typedef FetchPosts = Future<List<Post>> Function({int limit});

/// Display list model for the Journey Board feed (packet A07, R-13; cursor
/// paging in F13b).
///
/// Two modes (fixed at construction):
/// - window mode (default, [fetchPage] null): [load]/[refresh] fetch one
///   [limit]-sized window via [fetchPosts]. There are no further pages:
///   [hasMore] is always false and [loadMore] is a no-op.
/// - paged mode ([fetchPage] set): [load]/[refresh] run the 5-per-page
///   keyset paginator ([CursorPaginator.pageSize]) via [fetchPage];
///   [loadMore] appends the next deduped window and [hasMore] reports the
///   paginator. Rows never duplicate across pages (dedupe by id).
///
/// Read-only: fetching only, no post writes. Pure state + injected readers.
class PostFeedState extends ChangeNotifier {
  /// Window size for [load]/[refresh] in window mode.
  static const int defaultLimit = 20;

  final FetchPosts fetchPosts;
  final int limit;

  /// Keyset page reader for paged mode (F13b). Null keeps window mode.
  /// Production wiring queries hosted Supabase (`public.posts` newest-first
  /// keyset on `(created_at, id)`); tests inject a fake.
  final FetchCursorPage<Post>? fetchPage;

  /// Paging engine for paged mode (null in window mode). The F13 realtime
  /// bridge merges events through this (seen-id dedupe); UI reads [posts].
  final CursorPaginator<Post>? paginator;

  PostFeedStatus status = PostFeedStatus.idle;
  String? errorMessage;

  /// Last [loadMore] failure, human-readable. Rows are kept on page errors;
  /// the feed shows an honest Retry tile. Null when the last page load
  /// succeeded (or none was attempted yet).
  String? pageError;

  List<Post> _window = const <Post>[];

  PostFeedState({
    required this.fetchPosts,
    this.limit = defaultLimit,
    FetchCursorPage<Post>? fetchPage,
  }) : fetchPage = fetchPage,
       paginator = fetchPage == null
           ? null
           : CursorPaginator<Post>(
               fetchPage: fetchPage,
               idOf: (Post row) => row.id,
               createdAtOf: (Post row) => row.createdAt,
             );

  /// True when cursor paging is wired (5/page via [fetchPage]).
  bool get isPaged => paginator != null;

  bool get isLoading => status == PostFeedStatus.loading;

  /// True while a [loadMore] page is in flight (paged mode only).
  bool get isLoadingMore => paginator?.isLoading ?? false;

  /// True when another page may exist: paged mode only, after a successful
  /// load, while the paginator has not reported the end.
  bool get hasMore {
    final engine = paginator;
    return engine != null && status == PostFeedStatus.loaded && engine.hasMore;
  }

  /// Visible rows, newest-first: the window in window mode, the accumulated
  /// deduped pages in paged mode.
  List<Post> get posts => paginator?.rows ?? _window;

  /// True when the last load succeeded with zero rows.
  bool get isEmpty => status == PostFeedStatus.loaded && posts.isEmpty;

  /// Initial (or repeated) load: the window in window mode, the first
  /// cursor page (resetting accumulated pages) in paged mode.
  Future<void> load() async {
    final engine = paginator;
    if (engine == null) {
      status = PostFeedStatus.loading;
      errorMessage = null;
      notifyListeners();
      try {
        final rows = await fetchPosts(limit: limit);
        _window = List<Post>.unmodifiable(rows);
        status = PostFeedStatus.loaded;
      } catch (e) {
        status = PostFeedStatus.error;
        errorMessage = e.toString();
      }
      notifyListeners();
      return;
    }
    status = PostFeedStatus.loading;
    errorMessage = null;
    pageError = null;
    notifyListeners();
    try {
      await engine.loadFirst();
      if (engine.status == CursorPaginatorStatus.error) {
        status = PostFeedStatus.error;
        errorMessage = engine.errorMessage;
      } else {
        status = PostFeedStatus.loaded;
      }
    } catch (e) {
      status = PostFeedStatus.error;
      errorMessage = e.toString();
    }
    notifyListeners();
  }

  /// Reloads from the start (pull-to-refresh wiring). Same as [load].
  Future<void> refresh() => load();

  /// Loads the next cursor page (paged mode only). No-op in window mode,
  /// while a page is in flight, or when [hasMore] is false. Failures keep
  /// existing rows and set [pageError] (never a fake page, never lost rows).
  Future<void> loadMore() async {
    final engine = paginator;
    if (engine == null || !hasMore || engine.isLoading) return;
    pageError = null;
    notifyListeners();
    await engine.loadNext();
    if (engine.status == CursorPaginatorStatus.error) {
      pageError = engine.errorMessage;
    }
    notifyListeners();
  }

  /// Replaces the loaded window after an externally-mapped mutation (F13
  /// realtime bridge, window mode) and notifies listeners. The bridge
  /// computes the new list; this method is the only non-[load] writer of
  /// the window so listener notification stays inside the [ChangeNotifier].
  ///
  /// Window mode only: paged feeds merge through [paginator] via
  /// `applyPostEventToFeed` (a wholesale replace would lose the seen-id
  /// set), so calling this on a paged feed throws [StateError].
  void replaceWindow(List<Post> rows) {
    if (paginator != null) {
      throw StateError(
        'replaceWindow is window-only; '
        'paged feeds merge via applyPostEventToFeed.',
      );
    }
    _window = List<Post>.unmodifiable(rows);
    notifyListeners();
  }

  /// Notifies listeners after the realtime bridge mutated [paginator] rows
  /// in place (the paginator itself is not a [ChangeNotifier]).
  /// Bridge-only; UI never calls this.
  void notifyFeedChanged() => notifyListeners();
}
