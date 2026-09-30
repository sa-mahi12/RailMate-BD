import 'package:flutter/foundation.dart';

import '../../search/models/trip_seat.dart';

/// Lifecycle of a seat-inventory load for one trip.
enum SeatSelectionStatus { idle, loading, loaded, error }

/// Injectable seat fetcher: given a trip id, return the latest server
/// [TripSeat] rows. Production wiring queries hosted Supabase
/// (`public.trip_seats` filtered by `trip_id`); tests inject a fake.
///
/// Read-only: this layer never writes `booking_id` (booking is the A05 lane).
typedef SeatFetcher = Future<List<TripSeat>> Function(String tripId);

/// ChangeNotifier holding seat inventory + selection for one trip.
///
/// Rules (packet A04 / R-06, F06 demo_reserved):
/// - at most [maxSelection] distinct seats may be selected;
/// - only seats with `isAvailable` (`bookingId == null && !demoReserved`)
///   are selectable;
/// - unavailable seats (really booked OR demo-held) are disabled in the UI;
/// - [toggle] adds/removes available seats, ignoring unavailable codes and
///   ignoring additions beyond the max;
/// - [revalidate] refetches and drops selected codes that became booked or
///   demo-held (stale detection); [refresh] is the same refetch keeping
///   still-valid selections and updating [loadedAt].
class SeatSelectionState extends ChangeNotifier {
  /// Maximum distinct seats per booking (product contract: 1-4).
  static const int maxSelection = 4;

  /// After this age, [isStale] reports true so the UI can prompt refresh.
  static const Duration staleAfterDefault = Duration(seconds: 30);

  final String tripId;
  final SeatFetcher fetchSeats;
  final Duration staleAfter;

  SeatSelectionStatus status = SeatSelectionStatus.idle;
  String? errorMessage;
  List<TripSeat> seats = <TripSeat>[];
  DateTime? loadedAt;

  final Set<String> _selected = <String>{};

  SeatSelectionState({
    required this.tripId,
    required this.fetchSeats,
    this.staleAfter = staleAfterDefault,
  });

  /// Sorted selected seat codes (e.g. `['C1', 'C2']`).
  List<String> get selectedSeatCodes {
    final codes = _selected.toList()..sort();
    return codes;
  }

  /// Number of currently selected seats.
  int get selectedCount => _selected.length;

  bool get isLoading => status == SeatSelectionStatus.loading;

  /// True when the last load succeeded with zero rows.
  bool get isEmpty => status == SeatSelectionStatus.loaded && seats.isEmpty;

  /// True when loaded data is older than [staleAfter].
  bool get isStale {
    final loaded = loadedAt;
    if (status != SeatSelectionStatus.loaded || loaded == null) return false;
    return DateTime.now().difference(loaded) > staleAfter;
  }

  /// Lookup helper for UI cells.
  TripSeat? seatByCode(String seatCode) {
    for (final seat in seats) {
      if (seat.seatCode == seatCode) return seat;
    }
    return null;
  }

  bool isSelected(String seatCode) => _selected.contains(seatCode);

  /// True when the known row for [seatCode] is unavailable (really booked
  /// or demo-held: `!isAvailable`). Unknown codes are treated as not
  /// selectable (safe default).
  bool isBooked(String seatCode) {
    final seat = seatByCode(seatCode);
    if (seat == null) return true;
    return !seat.isAvailable;
  }

  /// True when [seatCode] may be added to the selection right now.
  bool canSelect(String seatCode) {
    final seat = seatByCode(seatCode);
    if (seat == null || !seat.isAvailable) return false;
    if (_selected.contains(seatCode)) return true;
    return _selected.length < maxSelection;
  }

  /// Toggle selection for [seatCode].
  ///
  /// Returns true when the selection changed. Ignored (returns false) when
  /// the seat is unknown/booked, or when adding beyond [maxSelection].
  /// Never writes booked state — pure local selection.
  bool toggle(String seatCode) {
    final seat = seatByCode(seatCode);
    if (seat == null || !seat.isAvailable) return false;
    if (_selected.contains(seatCode)) {
      _selected.remove(seatCode);
      notifyListeners();
      return true;
    }
    if (_selected.length >= maxSelection) return false;
    _selected.add(seatCode);
    notifyListeners();
    return true;
  }

  /// Clears the local selection (e.g. when leaving the screen).
  void clearSelection() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }

  /// Initial load of seat inventory for [tripId].
  Future<void> load() async {
    status = SeatSelectionStatus.loading;
    errorMessage = null;
    notifyListeners();
    try {
      final rows = await fetchSeats(tripId);
      seats = List<TripSeat>.unmodifiable(rows);
      _selected.removeWhere((code) {
        final seat = seatByCode(code);
        return seat == null || !seat.isAvailable;
      });
      loadedAt = DateTime.now();
      status = SeatSelectionStatus.loaded;
    } catch (e) {
      status = SeatSelectionStatus.error;
      errorMessage = e.toString();
    }
    notifyListeners();
  }

  /// Refetch latest inventory, keeping selections that are still available.
  /// Updates [loadedAt] on success so [isStale] resets.
  Future<void> refresh() async => revalidate();

  /// Refetch latest inventory and drop selected seats that are newly
  /// unavailable — booked OR demo-held — (or vanished). Returns the dropped
  /// codes so the UI can surface a "stale result detected" notice.
  Future<List<String>> revalidate() async {
    status = SeatSelectionStatus.loading;
    errorMessage = null;
    notifyListeners();
    try {
      final rows = await fetchSeats(tripId);
      seats = List<TripSeat>.unmodifiable(rows);
      final dropped = <String>[];
      _selected.removeWhere((code) {
        final seat = seatByCode(code);
        final stale = seat == null || !seat.isAvailable;
        if (stale) dropped.add(code);
        return stale;
      });
      dropped.sort();
      loadedAt = DateTime.now();
      status = SeatSelectionStatus.loaded;
      notifyListeners();
      return dropped;
    } catch (e) {
      status = SeatSelectionStatus.error;
      errorMessage = e.toString();
      notifyListeners();
      return <String>[];
    }
  }
}
