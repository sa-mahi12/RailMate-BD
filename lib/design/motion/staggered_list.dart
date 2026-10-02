import 'package:flutter/widgets.dart';

import 'app_motion.dart';
import 'fade_slide_in.dart';

/// P01 — staggered entrance reveals.
///
/// Each item wraps in [FadeSlideIn] with `delay = baseDelay + index *
/// stagger`. Under reduced motion the stagger collapses: every item renders
/// its final state immediately (the [FadeSlideIn] reduced branch).
class StaggeredColumn extends StatelessWidget {
  final List<Widget> children;

  /// Per-item delay step. Defaults to [AppMotion.staggerStep] (40 ms).
  final Duration stagger;

  final Duration baseDelay;
  final Duration itemDuration;
  final Offset slide;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisSize mainAxisSize;

  const StaggeredColumn({
    super.key,
    required this.children,
    this.stagger = AppMotion.staggerStep,
    this.baseDelay = Duration.zero,
    this.itemDuration = AppMotion.standard,
    this.slide = const Offset(0, 12),
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.mainAxisSize = MainAxisSize.max,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: mainAxisSize,
      children: <Widget>[
        for (int i = 0; i < children.length; i++)
          FadeSlideIn(
            delay: baseDelay + stagger * i,
            duration: itemDuration,
            slide: slide,
            child: children[i],
          ),
      ],
    );
  }
}

/// Staggered [ListView] variant for result-style lists.
///
/// New realtime rows may animate once on insert; rows must not re-animate
/// on scroll refreshes, so callers must pass stable [Key]s from
/// [itemBuilder] for identity.
class StaggeredList extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;

  /// Per-item delay step. Defaults to [AppMotion.staggerStep] (40 ms).
  final Duration stagger;

  final Duration baseDelay;
  final Duration itemDuration;
  final Offset slide;
  final Axis scrollDirection;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;
  final bool shrinkWrap;

  const StaggeredList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.stagger = AppMotion.staggerStep,
    this.baseDelay = Duration.zero,
    this.itemDuration = AppMotion.standard,
    this.slide = const Offset(0, 10),
    this.scrollDirection = Axis.vertical,
    this.padding,
    this.physics,
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      scrollDirection: scrollDirection,
      padding: padding,
      physics: physics,
      shrinkWrap: shrinkWrap,
      itemCount: itemCount,
      itemBuilder: (BuildContext context, int index) {
        return FadeSlideIn(
          delay: baseDelay + stagger * index,
          duration: itemDuration,
          slide: slide,
          child: itemBuilder(context, index),
        );
      },
    );
  }
}
