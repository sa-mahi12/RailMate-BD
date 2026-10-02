import 'package:flutter/material.dart';

/// P01 — central elevation tokens (V4 `06_DESIGN_SYSTEM_SPEC.md`).
///
/// Low-opacity black shadows only; heavy elevations are avoided.
abstract final class AppElevation {
  /// Card shadow: y2 blur8.
  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(
      color: Color(0x14000000),
      offset: Offset(0, 2),
      blurRadius: 8,
      spreadRadius: 0,
    ),
  ];

  /// Floating / hero shadow: y4 blur16.
  static const List<BoxShadow> floating = <BoxShadow>[
    BoxShadow(
      color: Color(0x1F000000),
      offset: Offset(0, 4),
      blurRadius: 16,
      spreadRadius: 0,
    ),
  ];
}
