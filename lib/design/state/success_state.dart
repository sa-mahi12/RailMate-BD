import 'package:flutter/material.dart';

import '../tokens/tokens.dart';
import 'state_layout.dart';

/// P26 — short positive confirmation state (booking confirmed, email verified,
/// cancellation complete, post published, key saved...).
///
/// Deliberately **short**: the entrance is one 220 ms fade + 12 px rise and
/// nothing loops, so a success state never delays navigation longer than the
/// motion matrix allows (matrix: payment success check 320 ms, reduced motion
/// fade only). Callers navigate once the real operation has completed; this
/// widget only presents the confirmation.
class SuccessState extends StatelessWidget {
  /// Short confirmation headline, e.g. `Booking confirmed`.
  final String title;

  /// One-line explanation of what actually happened.
  final String message;

  /// Optional follow-up action (e.g. `View ticket`, `Done`).
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Icon; defaults to a check, the shared success mark.
  final IconData icon;

  /// Caller-owned extra content (booking reference, next steps).
  final Widget? detail;

  /// Inline (false) or centred full-screen (true) presentation.
  final bool centered;

  const SuccessState({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.icon = Icons.check_circle_outline,
    this.detail,
    this.centered = true,
  });

  @override
  Widget build(BuildContext context) {
    final Widget layout = StateLayout(
      icon: icon,
      title: title,
      message: message,
      accent: AppColors.success,
      actionLabel: actionLabel,
      onAction: onAction,
      detail: detail,
      centered: centered,
    );
    return centered ? layout : StateCard(child: layout);
  }
}
