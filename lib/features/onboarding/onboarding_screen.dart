/// P04 — three-page onboarding experience (RailMate BD V4).
///
/// Implements `08_ONBOARDING_AUTH_SPEC.md` pages 1-3 with the P01 central
/// design tokens and motion primitives (`lib/design`, read-only here):
/// teal theme, staggered fade-slide copy entrances, small hero parallax that
/// follows the swipe, width/colour page-indicator tween, Skip / Next / Get
/// Started.
///
/// Honesty rules honoured: every page states DEMONSTRATION ONLY, all
/// schedules/fares are synthetic demo content and nothing claims official
/// railway data or service. The screen is intentionally free of auth, backend
/// and persistence calls — the P03 root gate owns onboarding persistence and
/// passes [onFinished] down, so this widget only reports intent.
library;

import 'dart:ui' show PathMetric, Tangent;

import 'package:flutter/material.dart';

import '../../design/design.dart';

/// Three-page onboarding shown once to a fresh, unauthenticated install.
class OnboardingScreen extends StatelessWidget {
  /// Stable route name so the P03 root gate can navigate to onboarding.
  static const String routeName = '/onboarding';

  /// Invoked by Skip and by Get Started on the final page.
  ///
  /// The gate receives this callback and performs the real persistence plus
  /// routing to Welcome; this screen never writes preferences itself.
  final VoidCallback onFinished;

  const OnboardingScreen({super.key, required this.onFinished});

  @override
  Widget build(BuildContext context) {
    return _OnboardingView(onFinished: onFinished);
  }
}

/// Immutable description of one onboarding page (copy + illustration).
class _OnboardingPage {
  final String headline;
  final String copy;
  final String semanticsLabel;
  final Widget illustration;

  const _OnboardingPage({
    required this.headline,
    required this.copy,
    required this.semanticsLabel,
    required this.illustration,
  });
}

List<_OnboardingPage> _buildPages() {
  return <_OnboardingPage>[
    _OnboardingPage(
      headline: 'Plan train journeys with less friction',
      copy:
          'Search routes, compare demo schedules and choose a journey that '
          'works for you.',
      semanticsLabel:
          'Illustration of a demo rail route with station markers and a '
          'sample train card.',
      illustration: const _RouteHero(),
    ),
    _OnboardingPage(
      headline: 'Pick seats for everyone',
      copy:
          'Select up to four seats, add passenger details and review '
          'everything before confirming.',
      semanticsLabel:
          'Illustration of a demo seat map with available, selected and '
          'booked seats.',
      illustration: const _SeatHero(),
    ),
    _OnboardingPage(
      headline: 'Tickets, bookings and travel tips',
      copy:
          'Keep demonstration tickets handy, revisit bookings and share '
          'useful station tips with the community.',
      semanticsLabel:
          'Illustration of a demonstration ticket beside a journey board '
          'post card.',
      illustration: const _TicketHero(),
    ),
  ];
}

class _OnboardingView extends StatefulWidget {
  final VoidCallback onFinished;

  const _OnboardingView({required this.onFinished});

  @override
  State<_OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<_OnboardingView> {
  final PageController _controller = PageController();
  final List<_OnboardingPage> _pages = _buildPages();

  int _index = 0;

  /// Continuous horizontal page position (fractional while swiping) that
  /// drives the hero parallax and crossfade.
  double _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isLast(int index) => index == _pages.length - 1;

  void _finish() => widget.onFinished();

  void _next() {
    if (_isLast(_index)) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: AppMotion.medium,
      curve: AppMotion.emphasized,
    );
  }

  void _goTo(int index) {
    if (index == _index) {
      return;
    }
    _controller.animateToPage(
      index,
      duration: AppMotion.medium,
      curve: AppMotion.emphasized,
    );
  }

  bool _onScroll(ScrollNotification notification) {
    final ScrollMetrics metrics = notification.metrics;
    if (notification is! ScrollUpdateNotification ||
        metrics.axis != Axis.horizontal ||
        metrics.viewportDimension <= 0) {
      return false;
    }
    final double next = (metrics.pixels / metrics.viewportDimension).clamp(
      0.0,
      (_pages.length - 1).toDouble(),
    );
    if ((next - _page).abs() < 0.001) {
      return false;
    }
    setState(() => _page = next);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final bool reduced = ReducedMotion.isReduced(context);
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _SkipBar(
              onSkip: _finish,
              showSkip: !_isLast(_index),
              reduced: reduced,
            ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (int index) => setState(() => _index = index),
                  itemBuilder: (BuildContext context, int index) =>
                      _buildPage(context, index, reduced),
                ),
              ),
            ),
            _FooterArea(
              index: _index,
              pageCount: _pages.length,
              onDotTap: _goTo,
              nextLabel: _isLast(_index) ? 'Get Started' : 'Next',
              onNext: _next,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(BuildContext context, int index, bool reduced) {
    final _OnboardingPage page = _pages[index];
    final double distance = (_page - index).abs();
    final double opacity = (1 - distance * 1.6).clamp(0.0, 1.0);

    Widget hero = Semantics(
      image: true,
      label: page.semanticsLabel,
      child: ExcludeSemantics(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(width: 300, child: page.illustration),
        ),
      ),
    );
    hero = reduced
        ? Opacity(opacity: opacity, child: hero)
        : AnimatedOpacity(
            opacity: opacity,
            duration: AppMotion.instant,
            curve: AppMotion.enter,
            child: hero,
          );
    if (!reduced) {
      hero = Transform.translate(
        offset: Offset((index - _page) * 28, 0),
        child: Transform.scale(scale: 1 - distance * 0.04, child: hero),
      );
    }

    final List<Widget> copy = <Widget>[
      Text(page.headline, style: AppTypography.onboardingDisplay),
      const SizedBox(height: AppSpacing.s12),
      Text(page.copy, style: AppTypography.body),
    ];

    Widget body = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        hero,
        const SizedBox(height: AppSpacing.s32),
        if (index == _index)
          StaggeredColumn(slide: const Offset(0, 12), children: copy)
        else
          ...copy,
      ],
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: AppSpacing.s8,
      ),
      child: body,
    );
  }
}

class _SkipBar extends StatelessWidget {
  final VoidCallback onSkip;
  final bool showSkip;
  final bool reduced;

  const _SkipBar({
    required this.onSkip,
    required this.showSkip,
    required this.reduced,
  });

  @override
  Widget build(BuildContext context) {
    final Widget button = IgnorePointer(
      ignoring: !showSkip,
      child: TextButton(
        onPressed: onSkip,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(88, 48),
          textStyle: AppTypography.button.copyWith(color: AppColors.primary),
        ),
        child: const Text('Skip'),
      ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
          child: reduced
              ? Offstage(offstage: !showSkip, child: button)
              : AnimatedOpacity(
                  opacity: showSkip ? 1.0 : 0.0,
                  duration: AppMotion.fast,
                  curve: AppMotion.enter,
                  child: button,
                ),
        ),
      ),
    );
  }
}

class _FooterArea extends StatelessWidget {
  final int index;
  final int pageCount;
  final ValueChanged<int> onDotTap;
  final String nextLabel;
  final VoidCallback onNext;

  const _FooterArea({
    required this.index,
    required this.pageCount,
    required this.onDotTap,
    required this.nextLabel,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final bool reduced = ReducedMotion.isReduced(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.s16,
        AppSpacing.page,
        AppSpacing.s16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _PageDots(
            count: pageCount,
            index: index,
            reduced: reduced,
            onDotTap: onDotTap,
          ),
          const SizedBox(height: AppSpacing.s20),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadii.buttonRadius,
                ),
                textStyle: AppTypography.button,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(nextLabel),
                  const SizedBox(width: AppSpacing.s8),
                  const Icon(Icons.arrow_forward, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          const Text(
            'DEMONSTRATION ONLY — synthetic demo schedules and fares. '
            'Not an official rail service.',
            textAlign: TextAlign.center,
            style: AppTypography.caption,
          ),
        ],
      ),
    );
  }
}

/// Page indicator: width + colour tween (220 ms), colour only when reduced.
class _PageDots extends StatelessWidget {
  final int count;
  final int index;
  final bool reduced;
  final ValueChanged<int> onDotTap;

  const _PageDots({
    required this.count,
    required this.index,
    required this.reduced,
    required this.onDotTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Page ${index + 1} of $count',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          for (int i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Semantics(
                button: true,
                selected: i == index,
                label: 'Go to page ${i + 1}',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onDotTap(i),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.s12),
                    child: AnimatedContainer(
                      duration: reduced ? Duration.zero : AppMotion.standard,
                      curve: AppMotion.emphasized,
                      width: !reduced && i == index ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == index
                            ? AppColors.primary
                            : AppColors.border,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(AppRadii.pill),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Page 1 illustration: rail line with station markers plus a demo train card.
class _RouteHero extends StatelessWidget {
  const _RouteHero();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          height: 132,
          width: double.infinity,
          child: CustomPaint(painter: _RouteRailPainter(progress: 0.62)),
        ),
        const SizedBox(height: AppSpacing.s12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.s12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.cardRadius,
            border: Border.all(color: AppColors.border),
            boxShadow: AppElevation.card,
          ),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.train_outlined,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.s8),
              const Expanded(
                child: Text(
                  'Dhaka → Khulna',
                  style: AppTypography.cardTitle,
                  maxLines: 1,
                ),
              ),
              Text('DEMO BDT 720', style: AppTypography.caption, maxLines: 1),
            ],
          ),
        ),
      ],
    );
  }
}

class _RouteRailPainter extends CustomPainter {
  final double progress;

  _RouteRailPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    const double inset = 10;
    final double h = size.height;
    final double w = size.width;
    final double yLow = h * 0.72;
    final double yHigh = h * 0.28;

    final Path path = Path()
      ..moveTo(inset, yLow)
      ..cubicTo(w * 0.28, yLow, w * 0.28, yHigh, w * 0.5, yHigh)
      ..cubicTo(w * 0.72, yHigh, w * 0.72, yLow, w - inset, yLow);

    final Paint base = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, base);

    final PathMetric metric = path.computeMetrics().first;
    final double travelled =
        metric.length * progress.clamp(0.0, 1.0).toDouble();
    final Paint travelledPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(metric.extractPath(0.0, travelled), travelledPaint);

    final Paint dotFill = Paint()..color = AppColors.surface;
    final Paint dotStroke = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    for (final Offset center in <Offset>[
      Offset(inset, yLow),
      Offset(w * 0.5, yHigh),
      Offset(w - inset, yLow),
    ]) {
      canvas.drawCircle(center, 7, dotFill);
      canvas.drawCircle(center, 7, dotStroke);
    }

    final Tangent? tangent = metric.getTangentForOffset(travelled);
    if (tangent != null) {
      canvas.drawCircle(
        tangent.position,
        8,
        Paint()..color = AppColors.primary,
      );
      canvas.drawCircle(
        tangent.position,
        3,
        Paint()..color = AppColors.onPrimary,
      );
    }
  }

  @override
  bool shouldRepaint(_RouteRailPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Page 2 illustration: seat map with a legend. Seat state uses shape/icon in
/// addition to colour (never colour only).
class _SeatHero extends StatelessWidget {
  const _SeatHero();

  static const List<bool> _selected = <bool>[false, true, true, false, false];
  static const List<bool> _booked = <bool>[false, false, false, false, true];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(
              Icons.event_seat_outlined,
              size: 18,
              color: AppColors.primary,
            ),
            const SizedBox(width: AppSpacing.s8),
            Flexible(
              child: Text(
                'Coach A · DEMO',
                style: AppTypography.metadata,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Text('2 of 4 seats', style: AppTypography.metadata),
          ],
        ),
        const SizedBox(height: AppSpacing.s12),
        for (int row = 0; row < 3; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (int column = 0; column < 5; column++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _SeatTile(
                      label: '${String.fromCharCode(65 + row)}${column + 1}',
                      selected: _selected[column],
                      booked: _booked[column] && row == 1,
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.s8),
        const FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _LegendSwatch(color: AppColors.seatAvailable, icon: null),
              SizedBox(width: AppSpacing.s8),
              Text('Available', style: AppTypography.caption),
              SizedBox(width: AppSpacing.s16),
              _LegendSwatch(color: AppColors.primary, icon: Icons.check),
              SizedBox(width: AppSpacing.s8),
              Text('Selected', style: AppTypography.caption),
              SizedBox(width: AppSpacing.s16),
              _LegendSwatch(color: AppColors.bookedSeat, icon: Icons.block),
              SizedBox(width: AppSpacing.s8),
              Text('Booked', style: AppTypography.caption),
            ],
          ),
        ),
      ],
    );
  }
}

class _SeatTile extends StatelessWidget {
  final String label;
  final bool selected;
  final bool booked;

  const _SeatTile({
    required this.label,
    required this.selected,
    required this.booked,
  });

  @override
  Widget build(BuildContext context) {
    final Color background = booked
        ? AppColors.bookedSeat
        : selected
        ? AppColors.primary
        : AppColors.seatAvailable;
    final Color foreground = booked || selected
        ? AppColors.onPrimary
        : AppColors.primaryText;
    return Container(
      width: 40,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadii.input),
        border: Border.all(color: AppColors.border),
      ),
      child: Icon(
        booked
            ? Icons.block
            : selected
            ? Icons.check
            : Icons.event_seat_outlined,
        size: 15,
        color: foreground,
      ),
    );
  }
}

class _LegendSwatch extends StatelessWidget {
  final Color color;
  final IconData? icon;

  const _LegendSwatch({required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: icon == null
          ? null
          : Icon(icon, size: 11, color: AppColors.onPrimary),
    );
  }
}

/// Page 3 illustration: a demonstration ticket beside a journey board card.
class _TicketHero extends StatelessWidget {
  const _TicketHero();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.cardRadius,
            boxShadow: AppElevation.floating,
          ),
          child: Column(
            children: <Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s12,
                  vertical: AppSpacing.s8,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(AppRadii.card),
                    topRight: Radius.circular(AppRadii.card),
                  ),
                ),
                child: const Text(
                  'DEMONSTRATION ONLY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onPrimary,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.s12),
                child: Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'Dhaka → Khulna',
                        style: AppTypography.cardTitle,
                        maxLines: 1,
                      ),
                    ),
                    Text(
                      'Coach A · 5A/5B',
                      style: AppTypography.caption,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.s12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.cardRadius,
            border: Border.all(color: AppColors.border),
            boxShadow: AppElevation.card,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.deepTeal,
                child: Icon(
                  Icons.person_outline,
                  size: 16,
                  color: AppColors.onPrimary,
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Kamal H. · Station tip',
                      style: AppTypography.cardTitle,
                      maxLines: 1,
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      'Platform side changes at Khulna — sample post.',
                      style: AppTypography.caption,
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
