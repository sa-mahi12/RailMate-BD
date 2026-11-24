/// One Journey Board post card (P42): safe author identity, body, typed
/// attachments, engagement, comments, share/copy/report actions and time.
///
/// Shared by the feed and the single-post permalink screen so a post looks the
/// same in both places. Every backend effect arrives through injected seams;
/// the card itself performs no I/O beyond rendering the resolved media URLs.
library;

import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../comments/comment_section.dart';
import '../comments/comment_subscription.dart';
import '../comments/comment_thread.dart';
import '../media/attachment_view.dart';
import '../media/post_attachment.dart';
import '../media/post_media.dart';
import '../ratings/rating_realtime.dart';
import '../ratings/rating_state.dart';
import '../reactions/reaction_realtime.dart';
import '../reactions/reaction_state.dart';
import 'post.dart';
import 'post_engagement.dart';
import 'relative_time.dart';

class BoardPostCard extends StatelessWidget {
  final Post post;

  /// Legacy single-image resolver (`posts.image_path`).
  final ResolveBoardImageUrl? imageUrlFor;

  /// P42 attachment Storage resolver.
  final ResolveAttachmentUrl? resolveAttachmentUrl;

  /// External link opener.
  final OpenExternalUrl? openExternal;

  final String? currentUserId;
  final FetchReactions? fetchReactions;
  final UpsertReactionRow? upsertReaction;
  final DeleteReactionRow? deleteReaction;
  final FetchRatings? fetchRatings;
  final UpsertRatingRow? upsertRating;
  final DeleteRatingRow? deleteRating;
  final FetchComments? fetchComments;
  final AddCommentRow? addComment;
  final DeleteCommentRow? deleteComment;
  final Stream<CommentRealtimeEvent>? commentEvents;
  final Stream<ReactionRealtimeEvent>? reactionEvents;
  final Stream<RatingRealtimeEvent>? ratingEvents;

  /// Native share sheet for this post (canonical URL included).
  final VoidCallback? onShare;

  /// Copy the canonical URL to the clipboard.
  final VoidCallback? onCopyLink;

  /// Report this post (opens the report dialog).
  final VoidCallback? onReportPost;

  /// Open the author's public profile page.
  final VoidCallback? onOpenProfile;

  /// Test seam: provider embeds are skipped when false.
  final bool allowEmbeds;

  const BoardPostCard({
    super.key,
    required this.post,
    this.imageUrlFor,
    this.resolveAttachmentUrl,
    this.openExternal,
    this.currentUserId,
    this.fetchReactions,
    this.upsertReaction,
    this.deleteReaction,
    this.fetchRatings,
    this.upsertRating,
    this.deleteRating,
    this.fetchComments,
    this.addComment,
    this.deleteComment,
    this.commentEvents,
    this.reactionEvents,
    this.ratingEvents,
    this.onShare,
    this.onCopyLink,
    this.onReportPost,
    this.onOpenProfile,
    this.allowEmbeds = true,
  });

  bool get _engagementWired =>
      fetchReactions != null &&
      upsertReaction != null &&
      deleteReaction != null &&
      fetchRatings != null &&
      upsertRating != null &&
      deleteRating != null &&
      post.id != null &&
      post.id!.isNotEmpty;

  bool get _commentsWired =>
      fetchComments != null &&
      addComment != null &&
      deleteComment != null &&
      post.id != null &&
      post.id!.isNotEmpty;

  bool get _hasActions =>
      onShare != null || onCopyLink != null || onReportPost != null;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (post.author != null) ...<Widget>[
            _authorHeader(context),
            const SizedBox(height: 10),
          ],
          Text(post.body, style: const TextStyle(fontSize: 14)),
          if (post.attachments.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            _attachments(context),
          ],
          // Legacy single-image rows stay visible even before the backfill
          // runs (and for any row inserted by an older client).
          if (post.imagePath != null && post.attachments.isEmpty) ...<Widget>[
            const SizedBox(height: 8),
            _legacyImage(),
          ],
          if (_engagementWired) ...<Widget>[
            const SizedBox(height: 8),
            PostEngagement(
              key: ValueKey<String>('engagement-${post.id}'),
              post: post,
              currentUserId: currentUserId,
              fetchReactions: fetchReactions!,
              upsertReaction: upsertReaction!,
              deleteReaction: deleteReaction!,
              fetchRatings: fetchRatings!,
              upsertRating: upsertRating!,
              deleteRating: deleteRating!,
              realtime: reactionEvents,
              ratingRealtime: ratingEvents,
            ),
          ],
          if (_commentsWired) ...<Widget>[
            const SizedBox(height: 8),
            CommentSection(
              key: ValueKey<String>('comments-${post.id}'),
              postId: post.id!,
              currentUserId: currentUserId,
              fetchComments: fetchComments!,
              addComment: addComment!,
              deleteComment: deleteComment!,
              realtime: commentEvents,
            ),
          ],
          if (_hasActions) ...<Widget>[
            const SizedBox(height: 4),
            _actionRow(context),
          ],
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              const Spacer(),
              Text(
                formatRelativeTime(post.createdAt),
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _authorHeader(BuildContext context) {
    final profile = post.author;
    final String label = profile?.identityLine ?? 'Traveller';
    final String initials = profile?.initials ?? '?';
    final Widget avatar = CircleAvatar(
      radius: 16,
      backgroundColor: const Color(0xFF0E5A66),
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    final Widget text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        if (profile?.username != null && profile!.displayName.isNotEmpty)
          Text(
            profile.handle!,
            style: const TextStyle(fontSize: 11, color: Color(0xFF5B6B73)),
          ),
      ],
    );
    final Widget row = Row(
      children: <Widget>[
        avatar,
        const SizedBox(width: 8),
        Expanded(child: text),
      ],
    );
    if (profile == null || onOpenProfile == null) return row;
    return InkWell(
      onTap: onOpenProfile,
      borderRadius: BorderRadius.circular(8),
      child: row,
    );
  }

  Widget _attachments(BuildContext context) {
    final List<PostAttachment> items = post.attachments;
    final List<PostAttachment> images = items
        .where((PostAttachment a) => a.kind == PostAttachmentKind.image)
        .toList();
    final List<PostAttachment> others = items
        .where((PostAttachment a) => a.kind != PostAttachmentKind.image)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (images.isNotEmpty)
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              if (images.length == 1) {
                return BoardAttachmentView(
                  attachment: images.first,
                  resolveUrl: resolveAttachmentUrl,
                  openUrl: openExternal,
                  allowEmbeds: allowEmbeds,
                );
              }
              final bool two = images.length == 2;
              final double tileWidth = two
                  ? (constraints.maxWidth - 8) / 2
                  : (constraints.maxWidth - 16) / 3;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final PostAttachment image in images)
                    SizedBox(
                      width: tileWidth,
                      child: BoardAttachmentView(
                        attachment: image,
                        resolveUrl: resolveAttachmentUrl,
                        openUrl: openExternal,
                        allowEmbeds: allowEmbeds,
                      ),
                    ),
                ],
              );
            },
          ),
        for (final PostAttachment other in others) ...<Widget>[
          const SizedBox(height: 8),
          BoardAttachmentView(
            attachment: other,
            resolveUrl: resolveAttachmentUrl,
            openUrl: openExternal,
            allowEmbeds: allowEmbeds,
          ),
        ],
      ],
    );
  }

  Widget _legacyImage() {
    final String? url = _resolveLegacy();
    if (url == null) {
      return const Row(
        children: <Widget>[
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
        errorBuilder: (_, _, _) => const Row(
          children: <Widget>[
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

  String? _resolveLegacy() {
    final resolve = imageUrlFor;
    final String? path = post.imagePath;
    if (resolve == null || path == null || path.isEmpty) return null;
    try {
      final String? url = resolve(path);
      return (url == null || url.isEmpty) ? null : url;
    } catch (_) {
      return null;
    }
  }

  Widget _actionRow(BuildContext context) {
    return Row(
      children: <Widget>[
        if (onShare != null)
          PressScale(
            onTap: onShare,
            semanticsLabel: 'Share post',
            child: TextButton.icon(
              onPressed: onShare,
              icon: const Icon(Icons.ios_share, size: 16),
              label: const Text('Share', style: TextStyle(fontSize: 12)),
            ),
          ),
        if (onCopyLink != null)
          TextButton.icon(
            onPressed: onCopyLink,
            icon: const Icon(Icons.link, size: 16),
            label: const Text('Copy link', style: TextStyle(fontSize: 12)),
          ),
        const Spacer(),
        if (onReportPost != null)
          IconButton(
            tooltip: 'Report post',
            visualDensity: VisualDensity.compact,
            onPressed: onReportPost,
            icon: const Icon(Icons.flag_outlined, size: 16),
          ),
      ],
    );
  }
}
