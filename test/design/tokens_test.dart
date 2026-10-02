import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/design/design.dart';

void main() {
  group('AppColors (from existing app theme + UI_VISUAL_SPEC)', () {
    test('core palette matches V3 theme values', () {
      expect(AppColors.primary, const Color(0xFF0E5A66));
      expect(AppColors.deepTeal, const Color(0xFF0A434C));
      expect(AppColors.success, const Color(0xFF1E9E6A));
      expect(AppColors.danger, const Color(0xFFE5484D));
      expect(AppColors.pageBackground, const Color(0xFFF4F7F9));
      expect(AppColors.surface, const Color(0xFFFFFFFF));
      expect(AppColors.border, const Color(0xFFE1E8EC));
      expect(AppColors.secondaryText, const Color(0xFF6F8088));
      expect(AppColors.mutedText, const Color(0xFF8A9BA3));
      expect(AppColors.bookedSeat, const Color(0xFFF2994A));
      expect(AppColors.seatAvailable, const Color(0xFFEAF0F6));
    });
  });

  group('AppSpacing', () {
    test('uses the 4-based scale from the spec', () {
      expect(AppSpacing.s4, 4);
      expect(AppSpacing.s8, 8);
      expect(AppSpacing.s12, 12);
      expect(AppSpacing.s16, 16);
      expect(AppSpacing.s20, 20);
      expect(AppSpacing.s24, 24);
      expect(AppSpacing.s32, 32);
      expect(AppSpacing.s40, 40);
      expect(AppSpacing.page, 16);
      expect(AppSpacing.card, 16);
    });
  });

  group('AppRadii', () {
    test('matches spec surface values', () {
      expect(AppRadii.input, 10);
      expect(AppRadii.button, 12);
      expect(AppRadii.card, 16);
      expect(AppRadii.headerBottom, 24);
      expect(AppRadii.chip, 10);
    });

    test('radius helpers resolve', () {
      expect(AppRadii.cardRadius, BorderRadius.circular(16));
      expect(AppRadii.buttonRadius, BorderRadius.circular(12));
      expect(
        AppRadii.headerBottomRadius,
        const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      );
    });
  });

  group('AppTypography', () {
    test('scale ordering and system font', () {
      expect(AppTypography.onboardingDisplay.fontSize, 28);
      expect(AppTypography.pageHeadline.fontSize, 24);
      expect(AppTypography.sectionTitle.fontSize, 18);
      expect(AppTypography.cardTitle.fontSize, 16);
      expect(AppTypography.body.fontSize, 14);
      expect(AppTypography.metadata.fontSize, 12);
      expect(AppTypography.button.fontSize, 16);
      expect(AppTypography.caption.fontSize, 12);
      // System font: no bundled family pinned.
      expect(AppTypography.body.fontFamily, isNull);
      expect(AppTypography.button.fontWeight, FontWeight.w700);
    });
  });

  group('AppElevation', () {
    test('card is y2/blur8, floating is y4/blur16', () {
      expect(AppElevation.card, hasLength(1));
      expect(AppElevation.card.single.offset, const Offset(0, 2));
      expect(AppElevation.card.single.blurRadius, 8);
      expect(AppElevation.floating, hasLength(1));
      expect(AppElevation.floating.single.offset, const Offset(0, 4));
      expect(AppElevation.floating.single.blurRadius, 16);
    });
  });

  group('AppMotion tokens (07 spec)', () {
    test('duration scale', () {
      expect(AppMotion.instant, const Duration(milliseconds: 80));
      expect(AppMotion.press, const Duration(milliseconds: 100));
      expect(AppMotion.fast, const Duration(milliseconds: 140));
      expect(AppMotion.standard, const Duration(milliseconds: 220));
      expect(AppMotion.medium, const Duration(milliseconds: 320));
      expect(AppMotion.slow, const Duration(milliseconds: 450));
      expect(AppMotion.hero, const Duration(milliseconds: 600));
      expect(AppMotion.staggerStep, const Duration(milliseconds: 40));
      expect(AppMotion.pressScale, 0.985);
    });

    test('curves map to spec easings', () {
      expect(AppMotion.enter, Curves.easeOutCubic);
      expect(AppMotion.exit, Curves.easeInCubic);
      expect(AppMotion.emphasized, Curves.easeInOutCubic);
      expect(AppMotion.pop, Curves.easeOutBack);
    });

    test('resolve collapses durations when reduced', () {
      const Duration d = Duration(milliseconds: 220);
      expect(AppMotion.resolve(d, reduced: true), Duration.zero);
      expect(AppMotion.resolve(d, reduced: false), d);
    });
  });
}
