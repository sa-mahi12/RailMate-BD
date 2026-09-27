import 'package:flutter/material.dart';

import 'post_feed_state.dart';

/// Journey Board feed screen (packet A07, R-13).
///
/// Visual tokens per `design/UI_VISUAL_SPEC.md`: page bg `#F4F7F9`, teal
/// header block (`#0E5A66`) with rounded bottom corners, white post cards
/// (radius 16, 16 padding). Covers loading/error/empty states; images
/// render only from a confirmed remote `imagePath`, never from a local
/// preview. Comments, reactions and ratings arrive in later packets.
class BoardFeedScreen extends StatelessWidget {
  /// Feed state (owned by the caller; call [PostFeedState.load] first).
  final PostFeedState feed;

  /// Opens the composer. Null hides the action button.
  final VoidCallback? onCompose;

  const BoardFeedScreen({super.key, required this.feed, this.onCompose});

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
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (post.imagePath != null)
                      const Row(
                        children: [
                          Icon(
                            Icons.image_outlined,
                            size: 14,
                            color: Color(0xFF0E5A66),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Photo attached',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF0E5A66),
                            ),
                          ),
                        ],
                      ),
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
}
