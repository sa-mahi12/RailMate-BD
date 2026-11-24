/// Single-post screen for a permanent link / app deep link (P42).
///
/// Loads exactly one post by id (`fetchPost`), then renders the same
/// [BoardPostCard] used by the feed, so comments, reactions, ratings,
/// attachments and author identity behave identically. Honest states:
/// loading, not-found (deleted post or bad id), and load-error with Retry.
library;

import 'package:flutter/material.dart';

import '../comments/comment_subscription.dart';
import '../comments/comment_thread.dart';
import '../media/attachment_view.dart';
import '../media/post_media.dart';
import '../ratings/rating_realtime.dart';
import '../ratings/rating_state.dart';
import '../reactions/reaction_realtime.dart';
import '../reactions/reaction_state.dart';
import 'post.dart';
import 'post_card.dart';

class BoardPostScreen extends StatefulWidget {
  /// Post id from the link.
  final String postId;

  /// One-row fetch (hosted Supabase in production).
  final Future<Post?> Function(String postId) fetchPost;

  final ResolveBoardImageUrl? imageUrlFor;
  final ResolveAttachmentUrl? resolveAttachmentUrl;
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
  final void Function(Post post)? onShare;
  final void Function(Post post)? onCopyLink;
  final void Function(Post post)? onReportPost;
  final void Function(Post post)? onOpenProfile;

  const BoardPostScreen({
    super.key,
    required this.postId,
    required this.fetchPost,
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
  });

  @override
  State<BoardPostScreen> createState() => _BoardPostScreenState();
}

class _BoardPostScreenState extends State<BoardPostScreen> {
  Post? _post;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Post? post = await widget.fetchPost(widget.postId);
      if (!mounted) return;
      setState(() {
        _post = post;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't load this post. Check your connection and retry.";
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E5A66),
        foregroundColor: Colors.white,
        title: const Text('Post'),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final String? error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(error, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final Post? post = _post;
    if (post == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'This post is not available. It may have been deleted.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        BoardPostCard(
          post: post,
          imageUrlFor: widget.imageUrlFor,
          resolveAttachmentUrl: widget.resolveAttachmentUrl,
          openExternal: widget.openExternal,
          currentUserId: widget.currentUserId,
          fetchReactions: widget.fetchReactions,
          upsertReaction: widget.upsertReaction,
          deleteReaction: widget.deleteReaction,
          fetchRatings: widget.fetchRatings,
          upsertRating: widget.upsertRating,
          deleteRating: widget.deleteRating,
          fetchComments: widget.fetchComments,
          addComment: widget.addComment,
          deleteComment: widget.deleteComment,
          commentEvents: widget.commentEvents,
          reactionEvents: widget.reactionEvents,
          ratingEvents: widget.ratingEvents,
          onShare: widget.onShare == null ? null : () => widget.onShare!(post),
          onCopyLink: widget.onCopyLink == null
              ? null
              : () => widget.onCopyLink!(post),
          onReportPost: widget.onReportPost == null
              ? null
              : () => widget.onReportPost!(post),
          onOpenProfile: widget.onOpenProfile == null
              ? null
              : () => widget.onOpenProfile!(post),
        ),
      ],
    );
  }
}
