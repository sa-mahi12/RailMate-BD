import 'package:flutter/material.dart';

import '../../design/design.dart';
import '../../design/state/state.dart';
import 'booking_history.dart';

const Color _primaryTeal = Color(0xFF0E5A66);
const Color _dangerRed = Color(0xFFE5484D);
const Color _pageBackground = Color(0xFFF4F7F9);

/// B07 "My bookings" history list screen (APP-BOOK, lane B).
///
/// Renders [BookingSummary] rows supplied by [repository] for [ownerId];
/// this screen performs no Supabase calls itself — all I/O flows through
/// the repository's injected functions. Cancellation is whole-booking only
/// via `cancel_booking_service` (see [BookingHistoryRepository.cancelOwned]
/// stop-condition comment) behind a confirm dialog, and a repeat cancel is
/// a no-op success. Every state carries a DEMONSTRATION ONLY banner; demo
/// bookings grant no travel entitlement and no real money moves.
///
/// V4 P18 polish (behavior unchanged): a fixed-size skeleton while loading,
/// the P26 [ErrorState]/[EmptyState] for error/empty (same copy), a
/// [StaggeredColumn] entrance over the booking cards, an [AnimatedSwap] on
/// the status chip (so the cancelled state visibly transitions) and on the
/// cancel button's busy state.
class BookingHistoryScreen extends StatefulWidget {
  /// History + cancel repository with injected fetch/rpc functions.
  final BookingHistoryRepository repository;

  /// Owning user id whose bookings are listed/cancelled.
  final String ownerId;

  const BookingHistoryScreen({
    super.key,
    required this.repository,
    required this.ownerId,
  });

  @override
  State<BookingHistoryScreen> createState() => _BookingHistoryScreenState();
}

class _BookingHistoryScreenState extends State<BookingHistoryScreen> {
  late Future<List<BookingSummary>> _future;
  final Set<String> _cancelling = <String>{};

  @override
  void initState() {
    super.initState();
    _future = widget.repository.listOwned(widget.ownerId);
  }

  void _reload() {
    setState(() {
      _future = widget.repository.listOwned(widget.ownerId);
    });
  }

  Future<void> _confirmAndCancel(BookingSummary booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel booking?'),
        content: Text(
          'This cancels the whole booking ${booking.id} and releases its '
          'seats. This cannot be undone. DEMONSTRATION ONLY.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep booking'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _dangerRed),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel booking'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _cancelNow(booking);
  }

  /// Executes the whole-booking cancel WITHOUT re-asking for confirmation.
  ///
  /// [_confirmAndCancel] shows the confirm dialog once, then delegates here;
  /// the failure SnackBar's Retry action also calls here directly so an
  /// already-confirmed cancel retries without a second dialog. The ONLY
  /// write path is [BookingHistoryRepository.cancelOwned] (injected
  /// `cancelRpc` -> deployed `cancel-booking` Edge); a `false` return (Edge
  /// status was not CANCELLED) is treated as failure, never fake success.
  Future<void> _cancelNow(BookingSummary booking) async {
    setState(() => _cancelling.add(booking.id));
    try {
      final ok = await widget.repository.cancelOwned(
        ownerId: widget.ownerId,
        bookingId: booking.id,
      );
      if (!ok) throw Exception('BOOKING_CANCEL_FAILED');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking cancelled (demo).')),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cancel failed: ${_publicMessage(e)}'),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => _cancelNow(booking),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _cancelling.remove(booking.id));
    }
  }

  /// Maps internal errors to public UI codes without leaking internals.
  ///
  /// Covers the genuine Edge failure shapes: NOT_FOUND (unknown id or
  /// non-owner), UNAUTHORIZED (missing/expired JWT), and transport failures
  /// (network/timeout) — each with an honest message plus the SnackBar
  /// Retry above. Anything else maps to BOOKING_CANCEL_FAILED.
  String _publicMessage(Object e) {
    final text = e.toString();
    if (text.contains('NOT_FOUND')) {
      return 'NOT_FOUND — booking does not exist or is not yours.';
    }
    if (text.contains('UNAUTHORIZED')) {
      return 'UNAUTHORIZED — please sign in again.';
    }
    if (text.contains('SocketException') ||
        text.contains('ClientException') ||
        text.contains('TimeoutException') ||
        text.contains('Network is unreachable') ||
        text.contains('Failed host lookup')) {
      return 'Network error — check connection and retry.';
    }
    return 'BOOKING_CANCEL_FAILED';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        backgroundColor: _primaryTeal,
        foregroundColor: Colors.white,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: const Text('My bookings'),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _DemoNote(),
          const SizedBox(height: 12),
          FutureBuilder<List<BookingSummary>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const _HistoryLoadingSkeleton();
              }
              if (snapshot.hasError) {
                return ErrorState(
                  message: 'Could not load bookings.',
                  retryLabel: 'Retry',
                  onRetry: _reload,
                );
              }
              final items = snapshot.data ?? const <BookingSummary>[];
              if (items.isEmpty) {
                return const EmptyState(
                  icon: Icons.confirmation_number_outlined,
                  title: 'No bookings yet',
                  message:
                      'Demo bookings appear here after a booking. '
                      'DEMONSTRATION ONLY.',
                );
              }
              return StaggeredColumn(
                children: [
                  for (final booking in items) ...[
                    _BookingCard(
                      booking: booking,
                      busy: _cancelling.contains(booking.id),
                      onCancel: () => _confirmAndCancel(booking),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DemoNote extends StatelessWidget {
  const _DemoNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _dangerRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _dangerRed.withValues(alpha: 0.4)),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: _dangerRed, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'DEMONSTRATION ONLY — demo bookings grant no travel '
              'entitlement. No real money moves.',
              style: TextStyle(
                color: _dangerRed,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fixed-size shimmer shown while the history loads. Static under reduced
/// motion; the layout does not jump when the real cards arrive.
class _HistoryLoadingSkeleton extends StatelessWidget {
  const _HistoryLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SkeletonBlock(height: 120, borderRadius: 16),
        SizedBox(height: 12),
        SkeletonBlock(height: 120, borderRadius: 16),
        SizedBox(height: 12),
        SkeletonBlock(height: 120, borderRadius: 16),
      ],
    );
  }
}

class _BookingCard extends StatelessWidget {
  final BookingSummary booking;
  final bool busy;
  final VoidCallback onCancel;

  const _BookingCard({
    required this.booking,
    required this.busy,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final statusLabel = switch (booking.status) {
      BookingStatus.confirmed => 'CONFIRMED',
      BookingStatus.cancelled => 'CANCELLED',
      BookingStatus.unknown => 'UNAVAILABLE',
    };
    final statusColor = switch (booking.status) {
      BookingStatus.confirmed => _primaryTeal,
      BookingStatus.cancelled => Colors.black54,
      BookingStatus.unknown => _dangerRed,
    };
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Ref: ${booking.id}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  // Keyed by status so CONFIRMED → CANCELLED visibly
                  // transitions after a cancel + reload.
                  child: AnimatedSwap(
                    child: Text(
                      statusLabel,
                      key: ValueKey<String>(statusLabel),
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Total: BDT ${booking.totalFareBdt}',
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
            if (booking.isActive) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: AnimatedSwap(
                  child: OutlinedButton(
                    key: ValueKey<bool>(busy),
                    onPressed: busy ? null : onCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _dangerRed,
                      side: const BorderSide(color: _dangerRed),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: _dangerRed,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text('Cancel whole booking'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
