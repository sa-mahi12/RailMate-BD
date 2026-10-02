import 'package:flutter/material.dart';

import '../tokens/tokens.dart';
import 'state_layout.dart';

/// P26 — human-mapped error state.
///
/// Honesty rules from `15_LOADING_EMPTY_ERROR_SUCCESS_SPEC.md`:
/// the caller maps a technical failure to a **human** [message]; this widget
/// never prints a raw exception, stack trace, SQL text or status code. It
/// renders exactly the string it is given.
///
/// The [onRetry] action is optional so read-only failures (for example a
/// permission denial) can render without a misleading Retry button.
class ErrorState extends StatelessWidget {
  /// Human-readable, already-mapped failure description.
  final String message;

  /// Short headline, e.g. `Could not load bookings`.
  final String title;

  /// Optional retry label. Default `Retry` when [onRetry] is supplied.
  final String? retryLabel;

  /// Invoked immediately on tap. Null removes the action entirely.
  final VoidCallback? onRetry;

  /// Icon that matches the failure class (offline, auth, seat conflict...).
  final IconData icon;

  /// Caller-owned extra content, e.g. a "sign in again" text button or a
  /// support hint rendered below the message.
  final Widget? detail;

  /// Inline (false) or centred full-screen (true) presentation.
  final bool centered;

  const ErrorState({
    super.key,
    required this.message,
    this.title = 'Something went wrong',
    this.retryLabel = 'Retry',
    this.onRetry,
    this.icon = Icons.error_outline,
    this.detail,
    this.centered = true,
  });

  @override
  Widget build(BuildContext context) {
    final Widget layout = StateLayout(
      icon: icon,
      title: title,
      message: message,
      accent: AppColors.danger,
      actionLabel: onRetry == null ? null : (retryLabel ?? 'Retry'),
      onAction: onRetry,
      detail: detail,
      centered: centered,
    );
    return centered ? layout : StateCard(child: layout);
  }
}
