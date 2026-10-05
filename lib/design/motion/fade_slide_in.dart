import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app_motion.dart';
import 'reduced_motion.dart';

/// P01 — fade/slide/scale entrance wrapper.
///
/// Plays once on first insert (never replayed on rebuilds, per the V4
/// motion matrix rules): fades from 0 to 1 while translating [slide] pixels
/// to zero over [duration] with [curve]. When [beginScale] is given, the
/// child also scales from [beginScale] to 1 (splash logo, avatars).
///
/// When reduced motion is active, [child] renders in its final state
/// immediately with no delay and no offset.
class FadeSlideIn extends StatefulWidget {
  final Widget child;

  /// Start delay (used by staggered parents as `index * staggerStep`).
  final Duration delay;

  final Duration duration;

  /// Entrance offset in logical pixels (default: 12 down, per matrix).
  final Offset slide;

  /// Optional entrance start scale (e.g. 0.94 for splash logo). Null: no
  /// scale animation.
  final double? beginScale;

  final Curve curve;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = AppMotion.standard,
    this.slide = const Offset(0, 12),
    this.beginScale,
    this.curve = AppMotion.enter,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> {
  bool _scheduled = false;
  bool _visible = false;

  /// Pending start-delay timer, held so [dispose] can cancel it.
  Timer? _startDelay;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) {
      return;
    }
    _scheduled = true;
    // Reduced motion never schedules a start-delay timer: the first build
    // already renders the final state, so no pending timer may outlive the
    // widget (this also keeps widget tests hermetic).
    final bool reduced = ReducedMotion.isReduced(context);
    if (reduced || widget.delay == Duration.zero) {
      _visible = true;
    } else {
      _startDelay = Timer(widget.delay, () {
        _startDelay = null;
        if (mounted) {
          setState(() => _visible = true);
        }
      });
    }
  }

  @override
  void dispose() {
    // A staggered entrance can still be waiting when the list is torn down
    // (scroll away, route pop, test end). Cancel it so no timer outlives the
    // widget — Flutter rejects pending timers at the end of a test.
    _startDelay?.cancel();
    _startDelay = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ReducedMotion.isReduced(context)) {
      return widget.child;
    }
    final Duration duration = _visible ? widget.duration : Duration.zero;
    Widget current = AnimatedOpacity(
      opacity: _visible ? 1.0 : 0.0,
      duration: duration,
      curve: widget.curve,
      child: widget.child,
    );
    current = AnimatedContainer(
      duration: duration,
      curve: widget.curve,
      transform: Matrix4.translationValues(
        _visible ? 0.0 : widget.slide.dx,
        _visible ? 0.0 : widget.slide.dy,
        0,
      ),
      child: current,
    );
    final double? beginScale = widget.beginScale;
    if (beginScale != null) {
      current = AnimatedScale(
        scale: _visible ? 1.0 : beginScale,
        duration: duration,
        curve: widget.curve,
        child: current,
      );
    }
    return current;
  }
}
