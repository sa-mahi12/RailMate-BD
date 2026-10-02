import 'package:flutter/material.dart';

import '../tokens/tokens.dart';
import 'state_layout.dart';

/// P26 — honest empty state (`15_LOADING_EMPTY_ERROR_SUCCESS_SPEC.md`).
///
/// Shape: relevant icon + clear title + short explanation + next action.
/// Every string is supplied by the caller because the honest copy is
/// screen-specific: Bookings is `No bookings yet` / "Search for a journey
/// and confirmed demo tickets will appear here." / `Find a train`, while the
/// Board is `No posts yet` / "Share a station or travel tip..." / `Create
/// post`. This widget ships **no** default copy so an adopting screen can
/// never silently render a generic placeholder.
///
/// Use [centered: false] inside [StateCard] for an inline (non full-screen)
/// empty block, e.g. the Board feed with zero posts.
class EmptyState extends StatelessWidget {
  /// Short honest headline, e.g. `No bookings yet`.
  final String title;

  /// Short explanation of what would fill this space and how.
  final String message;

  /// Icon that matches the surface, e.g. `Icons.inbox_outlined`.
  final IconData icon;

  /// Optional next-action label, e.g. `Find a train`.
  final String? actionLabel;

  /// Fires immediately on tap; null hides the action entirely.
  final VoidCallback? onAction;

  /// Overrides the default filled primary action (e.g. an outlined CTA).
  final Widget Function(BuildContext context, String label, VoidCallback onTap)?
  actionBuilder;

  /// Caller-owned extra content (filters, tips, secondary links).
  final Widget? detail;

  /// Inline (false) or centred full-screen (true) presentation.
  final bool centered;

  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
    this.actionBuilder,
    this.detail,
    this.centered = true,
  });

  @override
  Widget build(BuildContext context) {
    final Widget layout = StateLayout(
      icon: icon,
      title: title,
      message: message,
      accent: AppColors.secondaryText,
      actionLabel: actionLabel,
      onAction: onAction,
      actionBuilder: actionBuilder,
      detail: detail,
      centered: centered,
    );
    return centered ? layout : StateCard(child: layout);
  }
}
