import 'package:flutter/material.dart';

/// P01 — central radius tokens (V4 `06_DESIGN_SYSTEM_SPEC.md` +
/// binding `design/UI_VISUAL_SPEC.md`).
abstract final class AppRadii {
  /// Input fields.
  static const double input = 10;

  /// Large inputs / alternate input style.
  static const double inputLarge = 12;

  /// Primary / secondary buttons.
  static const double button = 12;

  /// Cards and sheets.
  static const double card = 16;

  /// Large teal header bottom corners.
  static const double headerBottom = 24;

  /// Small chips.
  static const double chip = 10;

  /// Pill shapes (chips, status pills, large shimmer bars).
  static const double pill = 999;

  static BorderRadius get inputRadius => BorderRadius.circular(input);
  static BorderRadius get buttonRadius => BorderRadius.circular(button);
  static BorderRadius get cardRadius => BorderRadius.circular(card);
  static BorderRadius get chipRadius => BorderRadius.circular(chip);

  static BorderRadius get headerBottomRadius => const BorderRadius.only(
    bottomLeft: Radius.circular(headerBottom),
    bottomRight: Radius.circular(headerBottom),
  );
}
