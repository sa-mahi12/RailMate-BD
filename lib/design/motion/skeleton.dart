import 'package:flutter/widgets.dart';

import '../tokens/app_colors.dart';
import 'reduced_motion.dart';

/// P01 — skeleton shimmer block (bounded pulse while content loads).
///
/// A bounded shimmer sweep: callers fix the size (width/height) so layouts
/// never jump when real content arrives. Under reduced motion this renders
/// a static block with no repeating animation ("spinner only / static" —
/// no decorative loops).
class SkeletonBlock extends StatefulWidget {
  final double? width;
  final double height;
  final double borderRadius;
  final Color baseColor;
  final Color highlightColor;

  /// One full shimmer sweep. Bounded and non-decorative.
  final Duration sweepDuration;

  const SkeletonBlock({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = 8,
    this.baseColor = AppColors.border,
    this.highlightColor = const Color(0xFFFFFFFF),
    this.sweepDuration = const Duration(milliseconds: 1200),
  });

  @override
  State<SkeletonBlock> createState() => _SkeletonBlockState();
}

class _SkeletonBlockState extends State<SkeletonBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.sweepDuration,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ReducedMotion.isReduced(context)) {
      return ExcludeSemantics(
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            color: widget.baseColor,
          ),
        ),
      );
    }
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: <Color>[
                  widget.baseColor,
                  widget.highlightColor,
                  widget.baseColor,
                ],
                stops: <double>[
                  (_controller.value - 0.35).clamp(0.0, 1.0).toDouble(),
                  _controller.value.clamp(0.0, 1.0).toDouble(),
                  (_controller.value + 0.35).clamp(0.0, 1.0).toDouble(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
