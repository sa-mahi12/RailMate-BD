/// Stable keyset cursor pagination primitives (packet B08, R-08).
///
/// Keyset is (`created_at`, `id`) on `public.posts`, newest-first, page size
/// [CursorPaginator.pageSize] (5). Keyset (not offset) keeps pages stable
/// when other clients insert/delete concurrently: each page asks for rows
/// strictly older than [PageCursor], so a newly inserted newest row never
/// shifts already-loaded pages. Pure Dart: no Flutter, no Supabase.
library;

/// Keyset position: the last row of the previous page.
///
/// Both fields are required — rows missing either field cannot anchor a
/// page and are skipped when advancing the cursor.
class PageCursor {
  /// `created_at` of the anchor row (UTC).
  final DateTime createdAt;

  /// `id` of the anchor row (tie-breaker for equal timestamps).
  final String id;

  const PageCursor({required this.createdAt, required this.id});
}

/// One fetched window of rows plus the cursor for the next window.
class CursorPage<T> {
  /// Rows in this window, newest-first, already deduped by the paginator.
  final List<T> rows;

  /// Cursor anchoring the next page (null when there is no next page or no
  /// row in this window could anchor one).
  final PageCursor? nextCursor;

  /// False when the server reported the end of the snapshot
  /// (fewer than a full page returned).
  final bool hasMore;

  const CursorPage({
    required this.rows,
    required this.nextCursor,
    required this.hasMore,
  });

  /// True when this window carried zero new rows.
  bool get isEmpty => rows.isEmpty;
}
