import 'package:flutter/material.dart';

import '../../../design/design.dart';
import 'reaction.dart';

/// Reaction bar for one board post (packet A08, R-03).
///
/// Visual tokens per `design/UI_VISUAL_SPEC.md`: unselected buttons are
/// white with a light border; the selected vote is deep teal `#0E5A66`
/// with white icon/text; danger is not used here (DISLIKE is a vote, not
/// a destructive action). Counts shown are the authoritative aggregates
/// passed in ([likeCount]/[dislikeCount]) — this widget never increments
/// its own counters. Loading/error/empty handling stays with the caller.
class ReactionBar extends StatelessWidget {
  /// Authoritative LIKE count (from `ReactionState.likeCount`).
  final int likeCount;

  /// Authoritative DISLIKE count (from `ReactionState.dislikeCount`).
  final int dislikeCount;

  /// Caller's current vote; null when they have no row.
  final ReactionValue? myReaction;

  /// Called on LIKE tap. Null disables the LIKE button (e.g. signed out).
  final VoidCallback? onLike;

  /// Called on DISLIKE tap. Null disables the DISLIKE button.
  final VoidCallback? onDislike;

  /// True while a toggle is in flight; disables both buttons.
  final bool isBusy;

  const ReactionBar({
    super.key,
    required this.likeCount,
    required this.dislikeCount,
    required this.myReaction,
    this.onLike,
    this.onDislike,
    this.isBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _voteButton(
          context,
          selected: myReaction == ReactionValue.like,
          icon: Icons.thumb_up_outlined,
          selectedIcon: Icons.thumb_up,
          label: '$likeCount',
          tooltip: 'Like',
          onPressed: isBusy ? null : onLike,
        ),
        const SizedBox(width: 8),
        _voteButton(
          context,
          selected: myReaction == ReactionValue.dislike,
          icon: Icons.thumb_down_outlined,
          selectedIcon: Icons.thumb_down,
          label: '$dislikeCount',
          tooltip: 'Dislike',
          onPressed: isBusy ? null : onDislike,
        ),
      ],
    );
  }

  Widget _voteButton(
    BuildContext context, {
    required bool selected,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    final reduced = ReducedMotion.isReduced(context);
    final foreground = selected ? Colors.white : const Color(0xFF0E5A66);
    final disabled = onPressed == null;
    return Tooltip(
      message: tooltip,
      child: AnimatedContainer(
        // P21: colour/scale transition on vote state (motion matrix
        // "Reaction vote"). Instant under reduced motion.
        duration: AppMotion.resolve(AppMotion.fast, reduced: reduced),
        curve: AppMotion.enter,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF0E5A66)),
          color: selected ? const Color(0xFF0E5A66) : Colors.white,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected ? selectedIcon : icon,
                    size: 16,
                    color: disabled
                        ? foreground.withValues(alpha: 0.5)
                        : foreground,
                  ),
                  const SizedBox(width: 6),
                  // Keyed by the authoritative count so an optimistic vote
                  // change cross-fades the number.
                  AnimatedSwap(
                    child: Text(
                      label,
                      key: ValueKey<String>('${tooltip}_$label'),
                      style: TextStyle(
                        color: disabled
                            ? foreground.withValues(alpha: 0.5)
                            : foreground,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
