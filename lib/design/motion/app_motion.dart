import 'package:flutter/animation.dart';

/// P01 — central motion tokens (V4 `07_GLOBAL_MOTION_SYSTEM.md`).
///
/// Single source of truth for durations and curves. Most transitions finish
/// in 140-350 ms; large onboarding hero transitions may use 450-650 ms.
/// This file also owns the raw duration scale referenced by the design-token
/// layer, so durations are defined exactly once.
abstract final class AppMotion {
  /// Instant state crossfade (reduced-motion adjacent, tab switches).
  static const Duration instant = Duration(milliseconds: 80);

  /// Press feedback window.
  static const Duration press = Duration(milliseconds: 100);

  /// Fast micro-transitions (chips, icon pops, button morphs).
  static const Duration fast = Duration(milliseconds: 140);

  /// Default transition length for entrances and reveals.
  static const Duration standard = Duration(milliseconds: 220);

  /// Medium transitions (success checks, larger reveals).
  static const Duration medium = Duration(milliseconds: 320);

  /// Slow transitions (splash logo, large hero motion).
  static const Duration slow = Duration(milliseconds: 450);

  /// Hero transitions (onboarding hero, ticket reveal).
  static const Duration hero = Duration(milliseconds: 600);

  /// Per-item stagger step for sequential reveals.
  static const Duration staggerStep = Duration(milliseconds: 40);

  /// Enter curve: easeOutCubic.
  static const Curve enter = Cubic(0.215, 0.61, 0.355, 1.0);

  /// Exit curve: easeInCubic.
  static const Curve exit = Cubic(0.55, 0.055, 0.675, 0.19);

  /// Emphasized curve: easeInOutCubic.
  static const Curve emphasized = Cubic(0.645, 0.045, 0.355, 1.0);

  /// Tiny selection pop curve: easeOutBack. Never used for full-page motion.
  static final Curve pop = Curves.easeOutBack;

  /// Press-down target scale (e.g. result cards, primary buttons).
  static const double pressScale = 0.985;

  /// Collapses [duration] to [Duration.zero] when [reduced] is true.
  static Duration resolve(Duration duration, {required bool reduced}) {
    return reduced ? Duration.zero : duration;
  }
}
