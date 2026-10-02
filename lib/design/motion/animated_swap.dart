import 'package:flutter/widgets.dart';

import 'app_motion.dart';
import 'reduced_motion.dart';

/// P01 — animated swap wrapper (tab content, passenger forms, seat counts,
/// date chips, swap-route icon).
///
/// Crossfades between keyed children with a small [slide] (default 8 px
/// horizontal, per the passenger-page matrix row). Swaps must use distinct
/// [Key]s (typically `ValueKey`) or [AnimatedSwitcher] cannot distinguish
/// old from new. Under reduced motion the swap is instant.
class AnimatedSwap extends StatelessWidget {
  /// Current child; must carry a distinguishing [Key] to animate swaps.
  final Widget child;

  final Duration duration;

  /// Small entrance travel in logical pixels (fades only when zero).
  final Offset slide;

  final Curve curve;

  const AnimatedSwap({
    super.key,
    required this.child,
    this.duration = AppMotion.standard,
    this.slide = const Offset(8, 0),
    this.curve = AppMotion.enter,
  });

  @override
  Widget build(BuildContext context) {
    final bool reduced = ReducedMotion.isReduced(context);
    final Duration effective = reduced ? Duration.zero : duration;
    return AnimatedSwitcher(
      duration: effective,
      reverseDuration: effective,
      switchInCurve: curve,
      switchOutCurve: AppMotion.exit,
      transitionBuilder: (Widget c, Animation<double> animation) {
        if (reduced) {
          return c;
        }
        return FadeTransition(
          opacity: animation,
          child: AnimatedBuilder(
            animation: animation,
            builder: (BuildContext context, Widget? inner) {
              final double t = 1.0 - animation.value;
              return Transform.translate(
                offset: Offset(slide.dx * t, slide.dy * t),
                child: inner,
              );
            },
            child: c,
          ),
        );
      },
      child: child,
    );
  }
}
