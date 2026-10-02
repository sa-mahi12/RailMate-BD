import 'package:flutter/widgets.dart';

import 'app_motion.dart';
import 'reduced_motion.dart';

/// P01 — press-scale button/card wrapper.
///
/// Scales to [scale] (default 0.985, 100 ms) while pressed, then springs
/// back on release. [onTap] fires immediately on tap — the animation never
/// postpones the action or navigation.
///
/// Under reduced motion there is no scale; the child stays tappable with an
/// unchanged (instant) visual.
class PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  /// Target scale while pressed.
  final double scale;

  final Duration duration;
  final Curve curve;

  /// Optional semantic label for icon-only tappables.
  final String? semanticsLabel;

  const PressScale({
    super.key,
    required this.child,
    required this.onTap,
    this.scale = AppMotion.pressScale,
    this.duration = AppMotion.press,
    this.curve = AppMotion.enter,
    this.semanticsLabel,
  });

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? label = widget.semanticsLabel;
    Widget tappable = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
      onTapUp: widget.onTap == null ? null : (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: widget.child,
    );
    if (label != null) {
      tappable = Semantics(button: true, label: label, child: tappable);
    }
    if (ReducedMotion.isReduced(context)) {
      return tappable;
    }
    return AnimatedScale(
      scale: _pressed ? widget.scale : 1.0,
      duration: widget.duration,
      curve: widget.curve,
      child: tappable,
    );
  }
}
