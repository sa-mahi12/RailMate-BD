import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../ratings/rating_state.dart';
import '../ratings/star_row.dart';
import '../reactions/reaction.dart';
import '../reactions/reaction_bar.dart';
import '../reactions/reaction_state.dart';
import 'post.dart';

/// Per-post reactions + ratings section for one feed card (F13b).
///
/// Owns one [ReactionState] + one [RatingState] for [post.id] (created in
/// [initState], reloaded when the post id changes, disposed with this
/// widget), so votes on one card can never leak into another. Aggregates
/// shown are always the states' authoritative recomputed values — this
/// widget never increments its own counters.
///
/// Votes are optimistic through the states' [ReactionState.toggle] /
/// [RatingState.setStars] (same logic as the F13 state tests) and then
/// reconciled against the authoritative fetch via [refresh], so a diverged
/// server row corrects on the next frame. Nothing here calls Supabase
/// directly — every side effect arrives through the injected seams (the
/// coordinator-wired production closures in `AppDependencies`, fakes in
/// tests). The seams are fixed for the widget's lifetime.
///
/// Signed-out ([currentUserId] null/empty): aggregates still load (public
/// read) but render read-only — vote buttons disabled with the honest hint
/// "Sign in to react or rate." Posts without an id render nothing (votes
/// need a row id; a draft id never appears in the feed).
class PostEngagement extends StatefulWidget {
  /// Post this section votes on ([post.id] selects the row set).
  final Post post;

  /// Current author uid. Null/empty means signed out (read-only).
  final String? currentUserId;

  /// Injected reaction seams (production: coordinator-wired closures).
  final FetchReactions fetchReactions;
  final UpsertReactionRow upsertReaction;
  final DeleteReactionRow deleteReaction;

  /// Injected rating seams (production: coordinator-wired closures).
  final FetchRatings fetchRatings;
  final UpsertRatingRow upsertRating;
  final DeleteRatingRow deleteRating;

  const PostEngagement({
    super.key,
    required this.post,
    required this.currentUserId,
    required this.fetchReactions,
    required this.upsertReaction,
    required this.deleteReaction,
    required this.fetchRatings,
    required this.upsertRating,
    required this.deleteRating,
  });

  @override
  State<PostEngagement> createState() => _PostEngagementState();
}

class _PostEngagementState extends State<PostEngagement> {
  late final ReactionState _reactions = ReactionState(
    fetchReactions: widget.fetchReactions,
    upsertReaction: widget.upsertReaction,
    deleteReaction: widget.deleteReaction,
  );
  late final RatingState _ratings = RatingState(
    fetchRatings: widget.fetchRatings,
    upsertRating: widget.upsertRating,
    deleteRating: widget.deleteRating,
  );

  bool get _signedIn =>
      widget.currentUserId != null && widget.currentUserId!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadFor(widget.post.id);
  }

  @override
  void didUpdateWidget(PostEngagement oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id) {
      _loadFor(widget.post.id);
    }
  }

  void _loadFor(String? postId) {
    if (postId == null || postId.isEmpty) return;
    _reactions.load(postId);
    _ratings.load(postId);
  }

  @override
  void dispose() {
    _reactions.dispose();
    _ratings.dispose();
    super.dispose();
  }

  /// Optimistic toggle, then reconcile against the authoritative fetch.
  Future<void> _toggle(ReactionValue value) async {
    final uid = widget.currentUserId;
    final postId = widget.post.id;
    if (uid == null || uid.isEmpty || postId == null || postId.isEmpty) {
      return;
    }
    final ok = await _reactions.toggle(
      postId: postId,
      userId: uid,
      value: value,
    );
    if (ok) await _reactions.refresh();
  }

  /// Optimistic star set, then reconcile against the authoritative fetch.
  Future<void> _rate(int stars) async {
    final uid = widget.currentUserId;
    final postId = widget.post.id;
    if (uid == null || uid.isEmpty || postId == null || postId.isEmpty) {
      return;
    }
    final ok = await _ratings.setStars(
      postId: postId,
      userId: uid,
      stars: stars,
    );
    if (ok) await _ratings.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final postId = widget.post.id;
    if (postId == null || postId.isEmpty) {
      return const SizedBox.shrink();
    }
    final signedIn = _signedIn;
    final uid = widget.currentUserId ?? '';
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[_reactions, _ratings]),
      builder: (context, _) {
        // First load (both row sets still empty): a slim placeholder, never
        // zeroed aggregates presented as data. Later refreshes keep the old
        // bars (rows non-empty) until the new fetch lands.
        if (_reactions.rows.isEmpty &&
            _ratings.rows.isEmpty &&
            (_reactions.isLoading || _ratings.isLoading)) {
          // P21: fixed-size shimmer bars, not a bare spinner, so the card
          // height does not jump when the real bars arrive.
          return const SizedBox(
            height: 48,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SkeletonBlock(width: 140, height: 26),
                SizedBox(height: 4),
                SkeletonBlock(width: 180, height: 14),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_reactions.status == ReactionStatus.error &&
                _reactions.rows.isEmpty)
              _errorRow('Reactions unavailable.', _reactions.refresh)
            else
              ReactionBar(
                likeCount: _reactions.likeCount,
                dislikeCount: _reactions.dislikeCount,
                myReaction: signedIn ? _reactions.myReaction(uid) : null,
                onLike: signedIn ? () => _toggle(ReactionValue.like) : null,
                onDislike: signedIn
                    ? () => _toggle(ReactionValue.dislike)
                    : null,
                isBusy: _reactions.submitting,
              ),
            const SizedBox(height: 4),
            if (_ratings.status == RatingStatus.error && _ratings.rows.isEmpty)
              _errorRow('Ratings unavailable.', _ratings.refresh)
            else
              StarRow(
                averageStars: _ratings.averageStars,
                ratingCount: _ratings.ratingCount,
                myStars: signedIn ? _ratings.myStars(uid) : null,
                onRate: signedIn ? _rate : null,
                isBusy: _ratings.submitting,
              ),
            if (!signedIn)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text(
                  'Sign in to react or rate.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Honest fetch failure with a retry (re-runs the authoritative load).
  /// Shows no counts — a failed load must not present zeros as data.
  Widget _errorRow(String message, Future<void> Function() retry) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(width: 4),
        PressScale(
          onTap: () => retry(),
          semanticsLabel: 'Retry $message',
          child: const Text(
            'Retry',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF0E5A66),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
