/// P26 — shimmer skeletons for "structure known, data not here yet".
///
/// Wraps the P01 [SkeletonBlock] primitive, so reduced motion, bounded sizes
/// and the non-decorative single sweep behaviour are inherited unchanged
/// (under reduced motion [SkeletonBlock] renders a static block).
///
/// Every skeleton here is **shape only**: no fabricated trains, stations,
/// posts, names, fares or counts. Sizes are fixed by the caller so the layout
/// does not jump when real content replaces the skeleton.
///
/// A full-screen spinner remains correct only when no useful shell can render;
/// prefer these for Home secondary sections, results, booking cards, Board
/// posts and profile-while-resolving.
library;

import 'package:flutter/material.dart';

import '../motion/skeleton.dart';
import '../tokens/tokens.dart';

/// A stack of shimmer bars standing in for one to [lines] lines of text.
///
/// The last line is shortened so the block reads as a paragraph rather than a
/// solid rectangle. Widths are a fraction of [width] (or of the incoming
/// constraint when [width] is null).
class SkeletonTextLines extends StatelessWidget {
  final int lines;
  final double lineHeight;
  final double spacing;
  final double? width;

  /// Fraction of [width] used for lines 0..lines-2 (default 1.0).
  final double fullLineFraction;

  /// Fraction of [width] used for the final line (default 0.6).
  final double lastLineFraction;

  const SkeletonTextLines({
    super.key,
    this.lines = 2,
    this.lineHeight = 12,
    this.spacing = AppSpacing.s8,
    this.width,
    this.fullLineFraction = 1.0,
    this.lastLineFraction = 0.6,
  }) : assert(lines > 0, 'lines must be positive');

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: width ?? double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (int i = 0; i < lines; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i == lines - 1 ? 0 : spacing),
                child: FractionallySizedBox(
                  widthFactor: i == lines - 1
                      ? lastLineFraction
                      : fullLineFraction,
                  alignment: Alignment.centerLeft,
                  child: SkeletonBlock(
                    height: lineHeight,
                    borderRadius: AppRadii.chip,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shimmer circle standing in for an avatar or icon thumbnail.
class SkeletonCircle extends StatelessWidget {
  final double size;

  const SkeletonCircle({super.key, this.size = 40}) : assert(size > 0);

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SkeletonBlock(width: size, height: size, borderRadius: size / 2),
    );
  }
}

/// Shimmer block standing in for a card-shaped region (result card, booking
/// card, Board post, Home secondary section).
class SkeletonCard extends StatelessWidget {
  final double? height;
  final double? width;

  const SkeletonCard({super.key, this.height = 96, this.width})
    : assert(height == null || height > 0);

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SkeletonBlock(
        width: width,
        height: height ?? 96,
        borderRadius: AppRadii.card,
      ),
    );
  }
}

/// One list row: leading circle plus two shimmer text lines. This is the shape
/// shared by the Bookings list, the Board feed and search results.
class SkeletonRow extends StatelessWidget {
  final double leadingSize;
  final double gap;
  final double lineHeight;
  final EdgeInsetsGeometry? padding;

  /// Optional spoken label (e.g. `Loading bookings`). Null means the purely
  /// decorative skeleton is hidden from screen readers.
  final String? semanticsLabel;

  const SkeletonRow({
    super.key,
    this.leadingSize = 40,
    this.gap = AppSpacing.s12,
    this.lineHeight = 12,
    this.padding = const EdgeInsets.symmetric(vertical: AppSpacing.s12),
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final Widget row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SkeletonCircle(size: leadingSize),
        SizedBox(width: gap),
        Expanded(child: SkeletonTextLines(lines: 2, lineHeight: lineHeight)),
      ],
    );
    final Widget content = padding == null
        ? row
        : Padding(padding: padding!, child: row);
    final String? label = semanticsLabel;
    if (label == null) {
      return ExcludeSemantics(child: content);
    }
    return Semantics(label: label, container: true, child: content);
  }
}

/// Vertical stack of [itemCount] shimmer [itemBuilder] rows.
///
/// Intentionally a plain `Column`, not a `ListView`: the caller decides
/// whether this sits inside its own scroll view (results/feed) or inside a
/// padded body (Home section). Pagination placeholders (Board page 2) use the
/// same widget with a smaller count.
class SkeletonList extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final double spacing;
  final EdgeInsetsGeometry? padding;
  final String? semanticsLabel;

  const SkeletonList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.spacing = AppSpacing.s12,
    this.padding,
    this.semanticsLabel,
  }) : assert(itemCount >= 0, 'itemCount must not be negative');

  @override
  Widget build(BuildContext context) {
    final Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < itemCount; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == itemCount - 1 ? 0 : spacing),
            child: itemBuilder(context, i),
          ),
      ],
    );
    final Widget body = padding == null
        ? content
        : Padding(padding: padding!, child: content);
    final String? label = semanticsLabel;
    if (label == null) {
      return ExcludeSemantics(child: body);
    }
    return Semantics(label: label, container: true, child: body);
  }
}
