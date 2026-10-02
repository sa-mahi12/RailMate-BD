import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../tokens/tokens.dart';

/// P26 — shared presentation shell for the empty / error / success states.
///
/// One layout, one entrance. [StateLayout] renders the four-part state shape
/// required by `15_LOADING_EMPTY_ERROR_SUCCESS_SPEC.md`:
///
/// 1. a relevant [icon],
/// 2. a clear [title],
/// 3. a short explanatory [message],
/// 4. an optional [actionLabel] + [onAction] next step.
///
/// It contains **no data logic**: callers pass the real strings they already
/// hold (a real message from the real failure, the real empty copy for that
/// screen). Nothing here fetches, retries, or fabricates content.
///
/// Motion: a single [StateEntrance] fade + 12 px rise (220 ms) so a state
/// appearing never looks like a spinner replacing a spinner. Under reduced
/// motion the state renders in its final state immediately.
class StateLayout extends StatelessWidget {
  /// Relevant icon for the state (e.g. `Icons.inbox_outlined`).
  final IconData icon;

  /// Short, honest headline (e.g. `No bookings yet`).
  final String title;

  /// Short explanation of *why* the state happened and what to do next.
  ///
  /// Must be caller supplied — never a hardcoded generic string, and never a
  /// raw exception body.
  final String message;

  /// Accent colour for the icon badge (danger / success / neutral).
  final Color accent;

  /// Optional next-action label. When null, no button is rendered.
  final String? actionLabel;

  /// Invoked immediately on tap — the entrance animation never postpones the
  /// action (motion rules: no delayed taps).
  final VoidCallback? onAction;

  /// Builds the next-action button. Defaults to a token-styled
  /// [FilledButton]; supply a custom builder for a secondary (outlined) look.
  final Widget Function(BuildContext context, String label, VoidCallback onTap)?
  actionBuilder;

  /// Extra content rendered between the message and the action (e.g. a
  /// secondary text button, or a technical detail the caller wants to own).
  final Widget? detail;

  /// Icon size. 48 px default per the existing `SignInRequiredScreen` shape.
  final double iconSize;

  /// When true the block is centred and vertically centred in the available
  /// space (full-screen states); when false it is left-aligned and top-aligned
  /// (inline card states).
  final bool centered;

  const StateLayout({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.accent,
    this.actionLabel,
    this.onAction,
    this.actionBuilder,
    this.detail,
    this.iconSize = 48,
    this.centered = true,
  });

  @override
  Widget build(BuildContext context) {
    final String? action = actionLabel;
    final VoidCallback? onAction = this.onAction;
    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: <Widget>[
        _StateIconBadge(icon: icon, accent: accent, size: iconSize),
        const SizedBox(height: AppSpacing.s12),
        Text(
          title,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: AppTypography.sectionTitle,
        ),
        const SizedBox(height: AppSpacing.s8),
        Text(
          message,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: AppTypography.body,
        ),
        if (detail != null) ...<Widget>[
          const SizedBox(height: AppSpacing.s12),
          detail!,
        ],
        if (action != null && onAction != null) ...<Widget>[
          const SizedBox(height: AppSpacing.s16),
          actionBuilder?.call(context, action, onAction) ??
              _PrimaryStateAction(label: action, onTap: onAction),
        ],
      ],
    );

    if (centered) {
      content = Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s24,
            vertical: AppSpacing.s24,
          ),
          child: content,
        ),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: content,
      );
    }

    // Semantics: the icon badge is decorative and excluded; the real title,
    // message and action button keep their own semantics. The block is a live
    // region so a state change (for example a failed booking) is announced.
    return Semantics(
      container: true,
      liveRegion: true,
      child: StateEntrance(child: content),
    );
  }
}

/// P26 — the one entrance every state shares: fade 0 -> 1 plus a 12 px rise
/// over [AppMotion.standard] (220 ms, easeOutCubic), played once when the
/// state is inserted.
///
/// Public so adopting screens can wrap their own heading/refresh affordances
/// in the same language. Under reduced motion the child renders in its final
/// state immediately and no controller is ever started, so a reduced-motion
/// user sees the state with no flash and no pending frame callback.
class StateEntrance extends StatefulWidget {
  final Widget child;

  /// Entrance travel in logical pixels (vertical by default).
  final Offset slide;

  const StateEntrance({
    super.key,
    required this.child,
    this.slide = const Offset(0, 12),
  });

  @override
  State<StateEntrance> createState() => _StateEntranceState();
}

class _StateEntranceState extends State<StateEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.standard,
  );

  bool _reduced = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reduced = ReducedMotion.isReduced(context);
    if (reduced) {
      _started = true;
      return;
    }
    if (_started) {
      return;
    }
    _started = true;
    // Start after the first frame so the state is built hidden and then
    // revealed, rather than flashing its final position for one frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _reduced = ReducedMotion.isReduced(context);
    if (_reduced) {
      return widget.child;
    }
    final Offset slide = widget.slide;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        final double t = AppMotion.enter.transform(_controller.value);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(slide.dx * (1 - t), slide.dy * (1 - t)),
            child: child,
          ),
        );
      },
    );
  }
}

/// Circular tinted badge behind the state icon.
class _StateIconBadge extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final double size;

  const _StateIconBadge({
    required this.icon,
    required this.accent,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size + AppSpacing.s24,
        height: size + AppSpacing.s24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: size, color: accent),
      ),
    );
  }
}

/// Token-styled filled next-action button (48 px minimum touch target).
class _PrimaryStateAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PrimaryStateAction({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: AppRadii.buttonRadius),
          textStyle: AppTypography.button,
        ),
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}

/// Convenience container: a card surface for an inline (non full-screen) state
/// using the token border radius, border and shadow.
class StateCard extends StatelessWidget {
  final Widget child;

  const StateCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: AppColors.border),
        boxShadow: AppElevation.card,
      ),
      child: child,
    );
  }
}
