import 'package:flutter/material.dart';

import '../../../design/design.dart';

/// Star rating row for one board post (packet A08, R-07).
///
/// Visual tokens per `design/UI_VISUAL_SPEC.md`: filled stars use deep
/// teal `#0E5A66`, empty stars use light grey; the average label is small
/// grey text. The row shows the authoritative [averageStars]/[ratingCount]
/// passed in and highlights the caller's [myStars]; it never computes or
/// caches its own aggregate. Loading/error/empty handling stays with the
/// caller.
class StarRow extends StatelessWidget {
  /// Authoritative mean (from `RatingState.averageStars`).
  final double averageStars;

  /// Authoritative rater count (from `RatingState.ratingCount`).
  final int ratingCount;

  /// Caller's current stars (1..5), null when they have no row.
  final int? myStars;

  /// Called with 1..5 on star tap. Null renders read-only stars.
  final ValueChanged<int>? onRate;

  /// True while a rating write is in flight; disables taps.
  final bool isBusy;

  const StarRow({
    super.key,
    required this.averageStars,
    required this.ratingCount,
    required this.myStars,
    this.onRate,
    this.isBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    // Highlight uses the caller's own stars when set, else the rounded
    // average (display-only; the authoritative mean stays in the state).
    final highlight = myStars ?? averageStars.round().clamp(0, 5);
    final reduced = ReducedMotion.isReduced(context);
    final duration = AppMotion.resolve(AppMotion.fast, reduced: reduced);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          // P21: each star scales up briefly on hover/press and eases when
          // the highlight passes it (motion matrix "Star rating").
          AnimatedScale(
            key: ValueKey<String>('star-$i-${i <= highlight}'),
            scale: i <= highlight ? 1.08 : 1.0,
            duration: duration,
            curve: AppMotion.enter,
            child: IconButton(
              tooltip: 'Rate $i star${i == 1 ? '' : 's'}',
              onPressed: onRate == null || isBusy ? null : () => onRate!(i),
              icon: Icon(
                i <= highlight ? Icons.star : Icons.star_border,
                size: 22,
                color: i <= highlight
                    ? const Color(0xFF0E5A66)
                    : Colors.grey.shade400,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ),
        const SizedBox(width: 4),
        // Keyed by the authoritative aggregate so an optimistic rating
        // cross-fades the label instead of popping it.
        AnimatedSwap(
          child: Text(
            ratingCount == 0
                ? 'No ratings yet'
                : '${averageStars.toStringAsFixed(1)} ($ratingCount)',
            key: ValueKey<String>('avg_${averageStars}_$ratingCount'),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      ],
    );
  }
}
