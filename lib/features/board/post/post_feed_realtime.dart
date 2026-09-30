library;

import 'dart:async';

import '../list/cursor_paginator.dart';
import 'post.dart';
import 'post_feed_state.dart';

/// F13 realtime feed updates + cursor pagination adapter (Journey Board).
///
/// Transport-free, like `CommentRealtimeSubscription`: the composition root
/// maps a Supabase Realtime channel on `public.posts` (`postgres_changes`
/// INSERT/UPDATE/DELETE) into [BoardPostEvent]s and injects the resulting
/// `Stream` here. Realtime-off/degraded means the caller keeps the last
/// loaded window and says so in the UI (non-live list) — rows are never
/// synthesised locally.
///
/// Reactions/ratings need NO new table: `public.post_reactions` and
/// `public.post_ratings` (+ RLS) already exist per migration
/// `20260927000001_initial_schema.sql` / `20260927000002_rls.sql`, and the
/// UI (`ReactionBar`, `StarRow`) already renders authoritative aggregates
/// from the injectable `ReactionState` / `RatingState` seams. Only the
/// production fetch/upsert/delete closures are pending coordinator wiring
/// (exact code in the handoff).

/// Kind of a realtime post event on the board feed channel.
enum BoardPostEventKind {
  /// A row was inserted (new post from another client).
  insert,

  /// A row was updated (body/image_path edited).
  update,

  /// A row was deleted.
  delete,
}

/// One realtime event for the board feed channel.
///
/// [eventId] is the dedupe/reconnect token (the transport's commit
/// timestamp / WAL id mapped by the composition root). Empty ids are
/// dropped without invoking the sink. For [BoardPostEventKind.delete],
/// [postId] carries the removed row id; otherwise [post] carries the row.
class BoardPostEvent {
  final String eventId;
  final BoardPostEventKind kind;
  final Post? post;
  final String? postId;

  const BoardPostEvent({
    required this.eventId,
    required this.kind,
    this.post,
    this.postId,
  });

  /// Affected row id: `post.id` for insert/update, [postId] for deletes.
  String? get rowId => kind == BoardPostEventKind.delete ? postId : post?.id;
}

/// Realtime subscription lifecycle for the board feed.
///
/// No Supabase import here: the composition root injects an already-mapped
/// `Stream<BoardPostEvent>` plus the sink that applies events (usually
/// [applyPostEventToPaginator] / [applyPostEventToFeed]).
///
/// - [subscribe] attaches to [stream] and forwards each event once to
///   [onEvent]; repeat deliveries with an already-seen [eventId] are
///   dropped, so at-least-once transports never double-apply.
/// - [reconnect] re-attaches via [streamFactory] (receives [lastEventId]
///   so the transport can replay/resubscribe from that point); seen ids
///   are still dropped.
/// - [unsubscribe]/[dispose] detach; after [dispose] no further events are
///   forwarded and any later [subscribe] throws. Dispose is verifiable:
///   "no events after dispose" (the composition root also closes the
///   Supabase channel there).
class BoardPostFeedRealtime {
  final Set<String> _seenEventIds = <String>{};
  StreamSubscription<BoardPostEvent>? _sub;
  bool _disposed = false;

  /// Last accepted (non-duplicate, non-empty-id) event id, or null before
  /// the first event. Passed back to [streamFactory] on [reconnect].
  String? lastEventId;

  /// True while attached to a stream (nominally "live").
  bool get isSubscribed => _sub != null;

  /// True after [dispose] was called.
  bool get isDisposed => _disposed;

  /// Count of distinct accepted event ids (for tests/diagnostics).
  int get seenEventCount => _seenEventIds.length;

  /// Attaches to [stream], replacing any existing attachment.
  /// Throws [StateError] after [dispose].
  Future<void> subscribe({
    required Stream<BoardPostEvent> stream,
    required void Function(BoardPostEvent event) onEvent,
  }) async {
    if (_disposed) throw StateError('BoardPostFeedRealtime disposed.');
    await unsubscribe();
    _sub = stream.listen((event) {
      if (_disposed) return;
      if (event.eventId.isEmpty) return;
      if (_seenEventIds.contains(event.eventId)) return;
      _seenEventIds.add(event.eventId);
      lastEventId = event.eventId;
      onEvent(event);
    });
  }

  /// Detaches from the current stream, if any. Safe to call repeatedly.
  /// Realtime-off lands here: the loaded list stays as-is (honest
  /// non-live list), nothing is fabricated.
  Future<void> unsubscribe() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// Re-attaches via [streamFactory], handing it the current [lastEventId].
  /// Throws [StateError] after [dispose].
  Future<void> reconnect({
    required Stream<BoardPostEvent> Function(String? lastEventId) streamFactory,
    required void Function(BoardPostEvent event) onEvent,
  }) => subscribe(stream: streamFactory(lastEventId), onEvent: onEvent);

  /// Permanently detaches. After this, no events are forwarded and
  /// [subscribe]/[reconnect] throw.
  Future<void> dispose() async {
    _disposed = true;
    await unsubscribe();
  }
}

/// Builds the Journey Board cursor paginator over [fetchPage].
///
/// Page size is the contract [CursorPaginator.pageSize] (5); keyset is
/// (`created_at`, `id`) newest-first; rows dedupe by id across pages, so
/// concurrent inserts/deletes cannot repeat or skip anchored rows.
CursorPaginator<Post> newPostPaginator(FetchCursorPage<Post> fetchPage) =>
    CursorPaginator<Post>(
      fetchPage: fetchPage,
      idOf: (Post row) => row.id,
      createdAtOf: (Post row) => row.createdAt,
    );

/// Merges one realtime event into a cursor-paged window.
///
/// - insert: front-inserts via [CursorPaginator.insertRealtime] (echo
///   dedupe by id: already-loaded ids return false, no duplicate row).
/// - update: replaces the loaded row in place (order preserved); an
///   update for an unknown id front-inserts (it is genuinely new here).
/// - delete: drops the visible row; the id stays in the seen-set so a
///   stale echo-insert of the deleted row is still dropped (documented:
///   a deleted row never resurrects from a late duplicate event).
/// Returns true when visible [rows] changed.
bool applyPostEventToPaginator(
  CursorPaginator<Post> paginator,
  BoardPostEvent event,
) {
  switch (event.kind) {
    case BoardPostEventKind.insert:
      final row = event.post;
      if (row == null) return false;
      return paginator.insertRealtime(row);
    case BoardPostEventKind.update:
      final row = event.post;
      if (row == null) return false;
      final id = row.id;
      if (id == null || id.isEmpty) return paginator.insertRealtime(row);
      final rows = paginator.rows;
      final index = rows.indexWhere((p) => p.id == id);
      if (index < 0) return paginator.insertRealtime(row);
      final next = List<Post>.of(rows)..[index] = row;
      paginator.rows = List<Post>.unmodifiable(next);
      return true;
    case BoardPostEventKind.delete:
      final id = event.postId;
      if (id == null || id.isEmpty) return false;
      final before = paginator.rows.length;
      final next = paginator.rows.where((p) => p.id != id).toList();
      if (next.length == before) return false;
      paginator.rows = List<Post>.unmodifiable(next);
      return true;
  }
}

/// Merges one realtime event into a windowed [PostFeedState].
///
/// Same insert/update/delete semantics as [applyPostEventToPaginator],
/// keeping newest-first order by (`created_at`, `id`). Notifies listeners
/// when the visible list changed. Realtime-off callers simply stop calling
/// this (list stays, UI says non-live).
void applyPostEventToFeed(PostFeedState feed, BoardPostEvent event) {
  switch (event.kind) {
    case BoardPostEventKind.insert:
      final row = event.post;
      if (row == null) return;
      if (row.id != null && feed.posts.any((p) => p.id == row.id)) return;
      feed.replaceWindow(<Post>[...feed.posts, row]..sort(_newestFirst));
    case BoardPostEventKind.update:
      final row = event.post;
      if (row == null) return;
      final id = row.id;
      if (id == null || id.isEmpty) {
        feed.replaceWindow(<Post>[...feed.posts, row]..sort(_newestFirst));
        return;
      }
      final rows = feed.posts;
      final index = rows.indexWhere((p) => p.id == id);
      if (index < 0) {
        feed.replaceWindow(<Post>[...rows, row]..sort(_newestFirst));
      } else {
        feed.replaceWindow(List<Post>.of(rows)..[index] = row);
      }
    case BoardPostEventKind.delete:
      final id = event.postId;
      if (id == null || id.isEmpty) return;
      final before = feed.posts.length;
      final next = feed.posts.where((p) => p.id != id).toList();
      if (next.length == before) return;
      feed.replaceWindow(next);
  }
}

/// Newest-first comparator on (`created_at`, `id`). Null timestamps sort
/// last; null/empty ids compare as empty strings.
int _newestFirst(Post a, Post b) {
  final ac = a.createdAt;
  final bc = b.createdAt;
  if (ac != null && bc != null) {
    final byTime = bc.compareTo(ac);
    if (byTime != 0) return byTime;
  } else if (ac != null) {
    return -1;
  } else if (bc != null) {
    return 1;
  }
  return (b.id ?? '').compareTo(a.id ?? '');
}
