import 'package:flutter/foundation.dart';

import 'post.dart';

/// Lifecycle of a board feed load.
enum PostFeedStatus { idle, loading, loaded, error }

/// Injected feed fetcher: returns the newest-first [Post] rows visible to
/// the caller. Production wiring queries hosted Supabase (`public.posts`
/// ordered by `created_at` desc, paged); cursor pagination (five per page)
/// is a later packet — this slice loads one window via [limit]. Tests
/// inject a fake.
typedef FetchPosts = Future<List<Post>> Function({int limit});

/// Display list model for the Journey Board feed (packet A07, R-13).
///
/// Read-only: fetching only, no writes. Pure state + injected [FetchPosts].
class PostFeedState extends ChangeNotifier {
  /// Window size for [load]/[refresh]. Cursor paging arrives separately.
  static const int defaultLimit = 20;

  final FetchPosts fetchPosts;
  final int limit;

  PostFeedStatus status = PostFeedStatus.idle;
  String? errorMessage;
  List<Post> posts = const <Post>[];

  PostFeedState({required this.fetchPosts, this.limit = defaultLimit});

  bool get isLoading => status == PostFeedStatus.loading;

  /// True when the last load succeeded with zero rows.
  bool get isEmpty => status == PostFeedStatus.loaded && posts.isEmpty;

  /// Initial (or repeated) window load.
  Future<void> load() async {
    status = PostFeedStatus.loading;
    errorMessage = null;
    notifyListeners();
    try {
      final rows = await fetchPosts(limit: limit);
      posts = List<Post>.unmodifiable(rows);
      status = PostFeedStatus.loaded;
    } catch (e) {
      status = PostFeedStatus.error;
      errorMessage = e.toString();
    }
    notifyListeners();
  }

  /// Reloads the window (pull-to-refresh wiring). Same as [load].
  Future<void> refresh() => load();
}
