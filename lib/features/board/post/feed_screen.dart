import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../../../design/state/state.dart';
import '../media/post_media.dart';
import '../ratings/rating_state.dart';
import '../reactions/reaction_state.dart';
import 'post.dart';
import 'post_engagement.dart';
import 'post_feed_state.dart';
import 'relative_time.dart';

/// Fixed-size shimmer cards shown while the feed loads. Static under reduced
/// motion; the layout does not jump when real cards arrive.
class _FeedLoadingSkeleton extends StatelessWidget {
  const _FeedLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        SkeletonBlock(height: 120, borderRadius: 16),
        SizedBox(height: 12),
        SkeletonBlock(height: 120, borderRadius: 16),
        SizedBox(height: 12),
        SkeletonBlock(height: 120, borderRadius: 16),
      ],
    );
  }
}

/// Journey Board feed screen (packet A07, R-13; image display in F11).
///
/// Visual tokens per `design/UI_VISUAL_SPEC.md`: page bg `#F4F7F9`, teal
/// header block (`#0E5A66`) with rounded bottom corners, white post cards
/// (radius 16, 16 padding). Covers loading/error/empty states.
///
/// Images render ONLY from a confirmed remote `imagePath` resolved through
/// [imageUrlFor] into a display URL (public `post-media` URL — the bucket
/// is world-readable per migration `20260927000004`, so no signed URL is
/// needed). Local previews are never rendered here. When [imageUrlFor] is
/// null (URL resolution not wired yet) or resolves to null, posts with an
/// `imagePath` fall back to the 'Photo attached' badge instead of a broken
/// image.
///
/// Per-post engagement (F13b): each card hosts a [PostEngagement] section
/// (own `ReactionState`/`RatingState`, authoritative aggregates, optimistic
/// toggles reconciled by refresh) when all six reaction/rating seams are
/// provided — production passes the coordinator-wired `AppDependencies`
/// closures plus [currentUserId]; null seams (default) hide the section so
/// existing callers render exactly the old card. Signed-out readers
/// ([currentUserId] null) see aggregates read-only with a sign-in hint.
///
/// Cursor pagination (F13b): a paged [PostFeedState] ([fetchPage] wired)
/// shows an honest trailer row — spinner while paging, the genuine error
/// with Retry on page failure (rows kept), else Load more. Window-mode
/// feeds show no trailer.
///
/// V4 P20 polish (behavior unchanged): header entrance with `PressScale` on
/// compose, a fixed-size skeleton while loading, the P26 ErrorState/EmptyState
/// with the same copy ('Could not load posts.' / 'No posts yet'), a
/// staggered per-card entrance, and a readable relative timestamp via
/// [formatRelativeTime] (replacing the raw `toString()` dump).
class BoardFeedScreen extends StatelessWidget {
  /// Feed state (owned by the caller; call [PostFeedState.load] first).
  final PostFeedState feed;

  /// Opens the composer. Null hides the action button.
  final VoidCallback? onCompose;

  /// Resolves a stored `posts.image_path` into a display URL.
  /// Production wiring closes over the hosted Supabase URL
  /// (`(path) => postImageUrl(supabaseUrl: url, imagePath: path)`).
  /// Null keeps the badge fallback (never a broken image).
  final ResolveBoardImageUrl? imageUrlFor;

  /// Reaction seams for the per-post engagement section. All six
  /// reaction/rating seams must be non-null for the section to render.
  final FetchReactions? fetchReactions;
  final UpsertReactionRow? upsertReaction;
  final DeleteReactionRow? deleteReaction;

  /// Rating seams for the per-post engagement section (see above).
  final FetchRatings? fetchRatings;
  final UpsertRatingRow? upsertRating;
  final DeleteRatingRow? deleteRating;

  /// Current author uid for the engagement section. Null (default) renders
  /// aggregates read-only with a sign-in hint.
  final String? currentUserId;

  const BoardFeedScreen({
    super.key,
    required this.feed,
    this.onCompose,
    this.imageUrlFor,
    this.fetchReactions,
    this.upsertReaction,
    this.deleteReaction,
    this.fetchRatings,
    this.upsertRating,
    this.deleteRating,
    this.currentUserId,
  });

  /// True when the per-post engagement section can render for [post]: all
  /// six seams wired and a concrete row id to vote on.
  bool _engagementWired(Post post) =>
      fetchReactions != null &&
      upsertReaction != null &&
      deleteReaction != null &&
      fetchRatings != null &&
      upsertRating != null &&
      deleteRating != null &&
      post.id != null &&
      post.id!.isNotEmpty;

  /// True when the pagination trailer row applies: a page is loading, the
  /// last page load failed (Retry), or more pages exist (Load more).
  /// Window-mode feeds never show it ([PostFeedState.hasMore] false,
  /// [PostFeedState.pageError] null, [PostFeedState.isLoadingMore] false).
  bool get _showTrailer =>
      feed.isLoadingMore || feed.pageError != null || feed.hasMore;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: feed,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: const Color(0xFFF4F7F9),
          body: Column(
            children: [
              FadeSlideIn(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 48, 16, 20),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0E5A66),
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(24),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Journey Board',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (onCompose != null)
                        PressScale(
                          onTap: onCompose,
                          semanticsLabel: 'New post',
                          child: IconButton(
                            tooltip: 'New post',
                            onPressed: onCompose,
                            icon: const Icon(
                              Icons.add_circle_outline,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(child: _body(context)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    if (feed.isLoading && feed.posts.isEmpty) {
      return const _FeedLoadingSkeleton();
    }
    if (feed.status == PostFeedStatus.error && feed.posts.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ErrorState(
            message: 'Could not load posts.',
            retryLabel: 'Retry',
            onRetry: feed.load,
          ),
        ),
      );
    }
    if (feed.isEmpty) {
      return const Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: EmptyState(
            icon: Icons.forum_outlined,
            title: 'No posts yet',
            message: 'Be the first to share a journey tip.',
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: feed.refresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: feed.posts.length + (_showTrailer ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= feed.posts.length) return _trailer();
          final post = feed.posts[i];
          return FadeSlideIn(
            // Staggered entrance, 40 ms step, per the V4 motion matrix.
            delay: Duration(milliseconds: 40 * i.clamp(0, 6)),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(post.body, style: const TextStyle(fontSize: 14)),
                  if (post.imagePath != null) ...[
                    const SizedBox(height: 8),
                    _postImage(post.imagePath!),
                  ],
                  if (_engagementWired(post)) ...[
                    const SizedBox(height: 8),
                    PostEngagement(
                      key: ValueKey('engagement-${post.id}'),
                      post: post,
                      currentUserId: currentUserId,
                      fetchReactions: fetchReactions!,
                      upsertReaction: upsertReaction!,
                      deleteReaction: deleteReaction!,
                      fetchRatings: fetchRatings!,
                      upsertRating: upsertRating!,
                      deleteRating: deleteRating!,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Spacer(),
                      Text(
                        formatRelativeTime(post.createdAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Honest pagination trailer: a spinner while a page is in flight, the
  /// genuine page error with Retry on failure (loaded rows are kept), else
  /// the Load more action. Only built when [_showTrailer] is true.
  Widget _trailer() {
    if (feed.isLoadingMore) {
      // P32: slim skeleton bar instead of a bare spinner; matches the card
      // rhythm and does not shift the list.
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: SkeletonBlock(height: 24, borderRadius: 12),
      );
    }
    if (feed.pageError != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "Couldn't load more.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: feed.loadMore, child: const Text('Retry')),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Center(
        child: OutlinedButton(
          onPressed: feed.loadMore,
          child: const Text('Load more'),
        ),
      ),
    );
  }

  /// Resolves [imagePath] through the injected [imageUrlFor], or null when
  /// no resolver is wired. Never throws: a throwing resolver falls back to
  /// the badge (a broken resolver must not break the whole feed).
  String? _imageUrl(String? imagePath) {
    final resolve = imageUrlFor;
    if (resolve == null || imagePath == null || imagePath.isEmpty) {
      return null;
    }
    try {
      final url = resolve(imagePath);
      return (url == null || url.isEmpty) ? null : url;
    } catch (_) {
      return null;
    }
  }

  /// Display image for one post: the network photo when resolvable, else
  /// the 'Photo attached' badge. A failed download also degrades to the
  /// badge via [Image.errorBuilder] (never a red error box).
  Widget _postImage(String imagePath) {
    final url = _imageUrl(imagePath);
    if (url == null) {
      return const Row(
        children: [
          Icon(Icons.image_outlined, size: 14, color: Color(0xFF0E5A66)),
          SizedBox(width: 4),
          Text(
            'Photo attached',
            style: TextStyle(fontSize: 12, color: Color(0xFF0E5A66)),
          ),
        ],
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        width: double.infinity,
        fit: BoxFit.cover,
        semanticLabel: 'Attached photo',
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        },
        errorBuilder: (context, _, _) => const Row(
          children: [
            Icon(Icons.image_outlined, size: 14, color: Color(0xFF0E5A66)),
            SizedBox(width: 4),
            Text(
              'Photo attached',
              style: TextStyle(fontSize: 12, color: Color(0xFF0E5A66)),
            ),
          ],
        ),
      ),
    );
  }
}
