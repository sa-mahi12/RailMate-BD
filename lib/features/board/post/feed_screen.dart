import 'package:flutter/material.dart';

import '../media/post_media.dart';
import 'post_feed_state.dart';

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
/// image. Comments, reactions and ratings arrive in later packets.
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

  const BoardFeedScreen({
    super.key,
    required this.feed,
    this.onCompose,
    this.imageUrlFor,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: feed,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: const Color(0xFFF4F7F9),
          body: Column(
            children: [
              Container(
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
                      IconButton(
                        tooltip: 'New post',
                        onPressed: onCompose,
                        icon: const Icon(
                          Icons.add_circle_outline,
                          color: Colors.white,
                        ),
                      ),
                  ],
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
      return const Center(child: CircularProgressIndicator());
    }
    if (feed.status == PostFeedStatus.error && feed.posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load posts.'),
              const SizedBox(height: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0E5A66),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: feed.load,
                child: const Text(
                  'Retry',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (feed.isEmpty) {
      return const Center(child: Text('No posts yet — be the first to share.'));
    }
    return RefreshIndicator(
      onRefresh: feed.refresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: feed.posts.length,
        itemBuilder: (context, i) {
          final post = feed.posts[i];
          return Container(
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Spacer(),
                    Text(
                      post.createdAt == null
                          ? ''
                          : post.createdAt!
                                .toLocal()
                                .toString()
                                .split('.')
                                .first,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
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
