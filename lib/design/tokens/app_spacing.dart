/// P01 — central spacing tokens (V4 `06_DESIGN_SYSTEM_SPEC.md`).
///
/// Predictable 4-based scale shared by all V4 slices.
abstract final class AppSpacing {
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;

  /// Default page gutter.
  static const double page = s16;

  /// Default card inner padding.
  static const double card = s16;
}
