import 'package:flutter/widgets.dart';

/// P01 — reduced-motion gate (V4 `16_ACCESSIBILITY_REDUCED_MOTION.md`).
///
/// [ReducedMotion] is the single inherited widget every design primitive
/// consults. [MotionGate] builds it from the system
/// `MediaQuery.disableAnimations` flag plus an optional app-level override
/// (used by profile/a11y settings in a later packet and by widget tests).
///
/// When reduced: no parallax, no big slides, no stagger, no decorative
/// loops; entrances render their final state immediately and durations
/// collapse to [Duration.zero] via the primitives' internal branches.
class ReducedMotion extends InheritedWidget {
  /// Whether motion must be reduced in this subtree.
  final bool reduced;

  const ReducedMotion({super.key, required this.reduced, required super.child});

  /// Returns the nearest [ReducedMotion.reduced], falling back to the
  /// system `MediaQuery.disableAnimations` flag when no scope is present.
  static bool isReduced(BuildContext context) {
    final ReducedMotion? scope = context
        .dependOnInheritedWidgetOfExactType<ReducedMotion>();
    if (scope != null) {
      return scope.reduced;
    }
    return MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  static ReducedMotion? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ReducedMotion>();
  }

  @override
  bool updateShouldNotify(ReducedMotion oldWidget) {
    return reduced != oldWidget.reduced;
  }
}

/// Builds a [ReducedMotion] scope.
///
/// When [overrideReduced] is null (the default for production use), the
/// system `MediaQuery.disableAnimations` value is honored. A non-null value
/// forces the branch explicitly (app accessibility setting, tests, demos).
class MotionGate extends StatelessWidget {
  final bool? overrideReduced;
  final Widget child;

  const MotionGate({super.key, this.overrideReduced, required this.child});

  @override
  Widget build(BuildContext context) {
    final bool systemReduced =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return ReducedMotion(
      reduced: overrideReduced ?? systemReduced,
      child: child,
    );
  }
}
