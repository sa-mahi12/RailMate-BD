import 'dart:async';

import 'comment.dart';

/// Kind of a realtime comment event on one post's channel.
enum CommentEventKind {
  /// A row was inserted (or updated and re-broadcast as insert).
  insert,

  /// A row was deleted.
  delete,
}

/// One realtime event for a post's comment channel (packet B08, R-02).
///
/// [eventId] is the dedupe/reconnect token (the transport's event id; the
/// composition root maps Supabase Realtime commit timestamps / WAL ids into
/// this field). It must be non-empty — empty ids are dropped without
/// invoking the sink. For [CommentEventKind.insert], [comment] carries the
/// row; for delete, [commentId] carries the removed row id.
class CommentRealtimeEvent {
  final String eventId;
  final CommentEventKind kind;
  final Comment? comment;
  final String? commentId;

  const CommentRealtimeEvent({
    required this.eventId,
    required this.kind,
    this.comment,
    this.commentId,
  });

  /// Affected row id: `comment.id` for inserts, [commentId] for deletes.
  String? get rowId =>
      kind == CommentEventKind.insert ? comment?.id : commentId;
}

/// Realtime subscription abstraction for one post's comments.
///
/// No Supabase import here: the composition root injects an already-filtered
/// `Stream<CommentRealtimeEvent>` (e.g. mapped from a Supabase Realtime
/// channel on `public.post_comments:post_id=eq.<id>`), plus the sink that
/// applies events (usually [CommentThread.applyRealtimeInsert] /
/// [applyRealtimeDelete]). This class owns lifecycle only:
///
/// - [subscribe] attaches to [stream] and forwards each event once to
///   [onEvent]; repeat deliveries with an already-seen [eventId] are dropped.
/// - [reconnect] re-attaches via [streamFactory] (which receives the current
///   [lastEventId] so the transport can replay from that point); events
///   already seen are still dropped, so reconnects never double-apply.
/// - [unsubscribe]/[dispose] detach; after [dispose] no further events are
///   forwarded and any later [subscribe] throws. Teardown is therefore
///   verifiable: "no events after dispose".
class CommentRealtimeSubscription {
  final Set<String> _seenEventIds = <String>{};
  StreamSubscription<CommentRealtimeEvent>? _sub;
  bool _disposed = false;

  /// Last accepted (non-duplicate, non-empty-id) event id, or null before
  /// the first event. Passed back to [streamFactory] on [reconnect].
  String? lastEventId;

  /// True while attached to a stream.
  bool get isSubscribed => _sub != null;

  /// True after [dispose] was called.
  bool get isDisposed => _disposed;

  /// Count of distinct accepted event ids (for tests/diagnostics).
  int get seenEventCount => _seenEventIds.length;

  /// Attaches to [stream], replacing any existing attachment.
  /// Throws [StateError] after [dispose].
  Future<void> subscribe({
    required Stream<CommentRealtimeEvent> stream,
    required void Function(CommentRealtimeEvent event) onEvent,
  }) async {
    if (_disposed) throw StateError('CommentRealtimeSubscription disposed.');
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
  Future<void> unsubscribe() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// Re-attaches via [streamFactory], handing it the current [lastEventId].
  ///
  /// The factory may replay events from that point; already-seen ids are
  /// dropped, so reconnects never double-apply. Throws [StateError] after
  /// [dispose].
  Future<void> reconnect({
    required Stream<CommentRealtimeEvent> Function(String? lastEventId)
    streamFactory,
    required void Function(CommentRealtimeEvent event) onEvent,
  }) => subscribe(stream: streamFactory(lastEventId), onEvent: onEvent);

  /// Permanently detaches. After this, no events are forwarded and
  /// [subscribe]/[reconnect] throw.
  Future<void> dispose() async {
    _disposed = true;
    await unsubscribe();
  }
}
