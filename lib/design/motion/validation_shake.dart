import 'package:flutter/widgets.dart';

import 'app_motion.dart';
import 'reduced_motion.dart';

/// P01 — validation-shake wrapper (auth errors, passenger forms, payment
/// failures — exactly one short shake per trigger).
///
/// Increment [shakeTrigger] to replay the shake, or call `shake()` through
/// a `GlobalKey<ValidationShakeState>`. Under reduced motion the shake is
/// skipped entirely (error color/text carries the meaning).
class ValidationShake extends StatefulWidget {
  final Widget child;

  /// Increment to replay the shake animation once.
  final int shakeTrigger;

  /// Total shake duration (matrix: auth error 180 ms).
  final Duration duration;

  /// Peak horizontal travel in logical pixels.
  final double distance;

  final Curve curve;

  const ValidationShake({
    super.key,
    required this.child,
    this.shakeTrigger = 0,
    this.duration = const Duration(milliseconds: 180),
    this.distance = 8,
    this.curve = AppMotion.enter,
  });

  @override
  State<ValidationShake> createState() => ValidationShakeState();
}

/// State exposed so owners can trigger [shake] imperatively via a
/// `GlobalKey<ValidationShakeState>`.
class ValidationShakeState extends State<ValidationShake>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _offset;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _rebuildOffset();
  }

  void _rebuildOffset() {
    final double d = widget.distance;
    _offset = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: 0,
          end: -d,
        ).chain(CurveTween(curve: widget.curve)),
        weight: 1,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: -d,
          end: d,
        ).chain(CurveTween(curve: widget.curve)),
        weight: 2,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: d,
          end: -d / 2,
        ).chain(CurveTween(curve: widget.curve)),
        weight: 1,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: -d / 2,
          end: 0,
        ).chain(CurveTween(curve: widget.curve)),
        weight: 1,
      ),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(ValidationShake oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.distance != oldWidget.distance ||
        widget.curve != oldWidget.curve) {
      _rebuildOffset();
    }
    if (widget.shakeTrigger != oldWidget.shakeTrigger) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          shake();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Plays one short shake; a no-op while the animation is running or when
  /// reduced motion is active.
  Future<void> shake() async {
    if (_reduced || _controller.isAnimating) {
      return;
    }
    await _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    _reduced = ReducedMotion.isReduced(context);
    return AnimatedBuilder(
      animation: _offset,
      builder: (BuildContext context, Widget? child) {
        return Transform.translate(
          offset: Offset(_offset.value, 0),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
