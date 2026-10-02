import 'package:flutter/material.dart';

/// P01 — central color tokens for RailMate BD (V4 design system).
///
/// Values are taken from the existing app theme (`lib/app/app.dart`,
/// `lib/features/auth/auth_theme.dart`) and the binding visual authority
/// (`design/UI_VISUAL_SPEC.md` + `design/reference/`):
/// deep teal headers/primary buttons, page background `#F4F7F9`, white
/// cards, light borders. No new visual identity is introduced here.
abstract final class AppColors {
  /// Primary deep teal: headers, primary buttons, selected states.
  static const Color primary = Color(0xFF0E5A66);

  /// Darker teal for pressed states and header gradients.
  static const Color deepTeal = Color(0xFF0A434C);

  /// Success / verified green.
  static const Color success = Color(0xFF1E9E6A);

  /// Danger red for errors and destructive actions.
  static const Color danger = Color(0xFFE5484D);

  /// Page scaffold background.
  static const Color pageBackground = Color(0xFFF4F7F9);

  /// Card / sheet / input-fill surface.
  static const Color surface = Color(0xFFFFFFFF);

  /// Light border for inputs and dividers.
  static const Color border = Color(0xFFE1E8EC);

  /// Secondary text (labels, chips).
  static const Color secondaryText = Color(0xFF6F8088);

  /// Muted hint text.
  static const Color mutedText = Color(0xFF8A9BA3);

  /// Near-black dark blue-gray primary body text used across V3 screens.
  static const Color primaryText = Color(0xFF1B2A32);

  /// Text / icons drawn on top of [primary].
  static const Color onPrimary = Color(0xFFFFFFFF);

  /// Booked-seat fill (never animated as tappable).
  static const Color bookedSeat = Color(0xFFF2994A);

  /// Available-seat background (paired with dark text, never color-only).
  static const Color seatAvailable = Color(0xFFEAF0F6);
}
