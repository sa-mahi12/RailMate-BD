/// P02/P03 — animated Flutter boot splash (RailMate BD).
///
/// The native launch window (deep teal + brand mark) covers process start;
/// this screen takes over the moment Flutter's first frame is ready and stays
/// until the session state resolves. It animates a rail line with a travelling
/// train cue and respects the P01 reduced-motion preference (final state
/// immediately, no timers).
library;

import 'package:flutter/material.dart';

import '../design/design.dart';

/// Branded boot splash shown while the session/onboarding state resolves.
///
/// Intentionally short-lived: the gate swaps it out as soon as
/// [AppGateState] is known. It never imposes an artificial delay beyond one
/// paint so a fast boot does not feel stalled.
class BootSplashScreen extends StatefulWidget {
  /// Optional status line under the wordmark (e.g. "Restoring your session").
  final String? status;

  const BootSplashScreen({super.key, this.status});

  @override
  State<BootSplashScreen> createState() => _BootSplashScreenState();
}

class _BootSplashScreenState extends State<BootSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Inherited widgets (MediaQuery / ReducedMotion) are only safe to read
    // here, not in initState.
    if (_started) return;
    _started = true;
    _controller = AnimationController(vsync: this, duration: AppMotion.slow);
    if (ReducedMotion.isReduced(context)) {
      // Hold the final frame; no animation loop, no timers.
      _controller.value = 1.0;
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool reduced = ReducedMotion.isReduced(context);
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _BrandMark(reduced: reduced, controller: _controller),
            const SizedBox(height: AppSpacing.s24),
            const Text(
              'RailMate BD',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              widget.status ?? 'Starting up',
              style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// Centred brand mark with a travelling rail-line cue.
class _BrandMark extends StatelessWidget {
  final bool reduced;
  final AnimationController controller;

  const _BrandMark({required this.reduced, required this.controller});

  @override
  Widget build(BuildContext context) {
    Widget train = Container(
      width: 56,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.input),
      ),
      child: const Icon(
        Icons.train_rounded,
        color: AppColors.primary,
        size: 30,
      ),
    );

    if (!reduced) {
      train = AnimatedBuilder(
        animation: controller,
        builder: (BuildContext context, Widget? child) {
          // -1..1 sweep across the rail, then a gentle opacity pulse.
          final double t = controller.value * 2 - 1;
          final double opacity = 0.55 + 0.45 * (1 - controller.value);
          return Transform.translate(
            offset: Offset(t * 26, 0),
            child: Opacity(opacity: opacity, child: child),
          );
        },
        child: train,
      );
    }

    return SizedBox(
      width: 140,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          train,
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: AppColors.success,
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: const Color(0x59FFFFFF),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
