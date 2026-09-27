import 'cursor_page.dart';

/// Injected keyset fetch: returns up to [limit] rows strictly older than
/// [before] (newest-first), or the newest window when [before] is null.
/// Production wiring queries hosted Supabase (`public.posts` ordered by
/// `created_at` desc, `id` desc with a `(created_at, id) < (...)` filter);
/// tests inject a fake over a fixed snapshot.
typedef FetchCursorPage<T> = Future<List<T>> Function({
  required int limit,
  PageCursor? before,
});

/// Extracts the row id for dedupe. Null/empty ids cannot dedupe and are
/// treated as distinct rows.
typedef IdOf<T> = String? Function(T row);

/// Extracts the row timestamp for cursor anchoring. Null timestamps cannot
/// anchor a page.
typedef CreatedAtOf<T> = DateTime? Function(T row);

/// Lifecycle of a cursor pagination load.
enum CursorPaginatorStatus { idle, loading, loaded, error }

/// Stable 5-post cursor paginator (packet B08, R-08).
///
/// Guarantees:
/// - page size is [pageSize] (5);
/// - no duplicate rows across pages (seen ids are filtered on every window,
///   so concurrent inserts/deletes cannot repeat or skip anchored rows);
/// - [insertRealtime] dedupes by id: a realtime echo of an already-loaded
///   row is a no-op returning false.
///
/// Pure Dart: no Flutter, no Supabase. For UI wiring, wrap in a
/// `ChangeNotifier`/`ValueNotifier` at the composition root or call
/// [loadFirst]/[loadNext] from an existing state object.
class CursorPaginator<T> {
  /// Fixed window size (Journey Board contract: five per page).
  static const int pageSize = 5;

  /// Injected keyset reader.
  final FetchCursorPage<T> fetchPage;

  /// Row field extractors (keep this file dependency-free of Post/Comment).
  final IdOf<T> idOf;
  final CreatedAtOf<T> createdAtOf;

  CursorPaginatorStatus status = CursorPaginatorStatus.idle;
  String? errorMessage;

  /// All loaded rows, newest-first, deduped by id.
  List<T> rows = List<T>.empty(growable: false);

  /// Cursor for the next [loadNext] (null before the first load or when the
  /// end was reached / no row could anchor).
  PageCursor? cursor;

  /// False once the server reported the end of the snapshot.
  bool hasMore = true;

  final Set<String> _seenIds = <String>{};

  CursorPaginator({
    required this.fetchPage,
    required this.idOf,
    required this.createdAtOf,
  });

  bool get isLoading => status == CursorPaginatorStatus.loading;
  bool get isEmpty => status == CursorPaginatorStatus.loaded && rows.isEmpty;

  /// Number of distinct ids loaded (for tests/diagnostics).
  int get seenCount => _seenIds.length;

  /// Loads the first window, resetting all accumulated state.
  Future<void> loadFirst() async {
    cursor = null;
    hasMore = true;
    _seenIds.clear();
    rows = List<T>.empty(growable: false);
    await _load(before: null, replace: true);
  }

  /// Loads the next window after [cursor]. No-op while loading, after an
  /// in-progress error recovery, or when [hasMore] is false.
  Future<void> loadNext() async {
    if (isLoading || !hasMore) return;
    await _load(before: cursor, replace: false);
  }

  /// Merges a realtime/other-client newest row (e.g. a fresh post echoed
  /// over Realtime). Returns true when inserted at the front, false when
  /// its non-empty id was already loaded (echo dedupe).
  ///
  /// Rows with a null/empty id cannot dedupe and are always inserted.
  bool insertRealtime(T row) {
    final id = idOf(row);
    if (id != null && id.isNotEmpty) {
      if (_seenIds.contains(id)) return false;
      _seenIds.add(id);
    }
    rows = List<T>.unmodifiable(<T>[row, ...rows]);
    return true;
  }

  /// Drops all loaded state back to pristine idle.
  void reset() {
    status = CursorPaginatorStatus.idle;
    errorMessage = null;
    rows = List<T>.empty(growable: false);
    cursor = null;
    hasMore = true;
    _seenIds.clear();
  }

  Future<void> _load({
    required PageCursor? before,
    required bool replace,
  }) async {
    status = CursorPaginatorStatus.loading;
    errorMessage = null;
    try {
      final raw = await fetchPage(limit: pageSize, before: before);
      final fresh = <T>[];
      for (final row in raw) {
        final id = idOf(row);
        if (id != null && id.isNotEmpty) {
          if (_seenIds.contains(id)) continue;
          _seenIds.add(id);
        }
        fresh.add(row);
      }
      rows = List<T>.unmodifiable(<T>[if (!replace) ...rows, ...fresh]);
      cursor = _anchorFrom(raw) ?? (replace ? null : before);
      // A short window proves the end; a full window may still be the end
      // (verified on the next loadNext returning short/empty).
      if (raw.length < pageSize) {
        hasMore = false;
        // Keep the anchor when rows exist so a later realtime insert does
        // not lose position; cursor stays for a potential refresh-continue.
      }
      status = CursorPaginatorStatus.loaded;
    } catch (e) {
      status = CursorPaginatorStatus.error;
      errorMessage = e.toString();
    }
  }

  /// Anchors the next page on the last anchorable row of the raw window.
  /// Returns null when no row has both timestamp and id.
  PageCursor? _anchorFrom(List<T> raw) {
    for (var i = raw.length - 1; i >= 0; i--) {
      final createdAt = createdAtOf(raw[i]);
      final id = idOf(raw[i]);
      if (createdAt != null && id != null && id.isNotEmpty) {
        return PageCursor(createdAt: createdAt, id: id);
      }
    }
    return null;
  }
}
