import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/board/comments/comment.dart';
import 'package:railmate_bd/features/board/comments/comment_subscription.dart';
import 'package:railmate_bd/features/board/comments/comment_thread.dart';
import 'package:railmate_bd/features/board/list/cursor_page.dart';
import 'package:railmate_bd/features/board/list/cursor_paginator.dart';

class _Item {
  final String id;
  final DateTime createdAt;
  const _Item(this.id, this.createdAt);
}

void main() {
  test('comment body rejects empty and >500 chars, accepts 1..500', () {
    expect(Comment.validateBody('   '), isNotNull);
    expect(Comment.validateBody('x' * 501), isNotNull);
    expect(Comment.validateBody('hi'), isNull);
    expect(
      () => Comment.draft(postId: 'p', userId: 'u', body: '   '),
      throwsArgumentError,
    );
    expect(
      () => Comment.draft(postId: 'p', userId: 'u', body: 'x' * 501),
      throwsArgumentError,
    );
    expect(
      () => Comment.draft(postId: '', userId: 'u', body: 'hi'),
      throwsArgumentError,
    );
  });

  test('cursor pages have no duplicate rows and stop at end', () async {
    final snapshot = List.generate(
      12,
      (i) => _Item(
        'post-${11 - i}',
        DateTime.utc(2026, 9, 27, 12, 0).add(Duration(minutes: 11 - i)),
      ),
    ).reversed.toList(); // newest first
    Future<List<_Item>> fetch({required int limit, PageCursor? before}) async {
      var start = 0;
      if (before != null) {
        final idx = snapshot.indexWhere((e) => e.id == before.id);
        start = idx < 0 ? snapshot.length : idx + 1;
      }
      return snapshot.skip(start).take(limit).toList();
    }

    final paginator = CursorPaginator<_Item>(
      fetchPage: fetch,
      idOf: (e) => e.id,
      createdAtOf: (e) => e.createdAt,
    );
    await paginator.loadFirst();
    expect(paginator.rows.length, 5);
    await paginator.loadNext();
    expect(paginator.rows.length, 10);
    await paginator.loadNext();
    expect(paginator.rows.length, 12);
    expect(paginator.hasMore, isFalse);
    final ids = paginator.rows.map((e) => e.id).toList();
    expect(ids.toSet().length, 12);
    expect(ids, snapshot.map((e) => e.id).toList());
    await paginator.loadNext(); // no-op at end
    expect(paginator.rows.length, 12);
    // realtime echo of a loaded row is dropped
    expect(paginator.insertRealtime(snapshot.first), isFalse);
    expect(paginator.rows.length, 12);
  });

  test(
    'realtime dedupe: repeat event id applied once; reconnect has no repeats',
    () async {
      final thread = CommentThread(
        postId: 'p1',
        fetchComments: ({required String postId}) async => [],
      );
      final sub = CommentRealtimeSubscription();
      final controller = StreamController<CommentRealtimeEvent>.broadcast();
      var forwarded = 0;
      await sub.subscribe(
        stream: controller.stream,
        onEvent: (e) {
          forwarded++;
          if (e.kind == CommentEventKind.insert && e.comment != null) {
            thread.applyRealtimeInsert(e.comment!);
          }
        },
      );
      Comment row(String id) =>
          Comment(id: id, postId: 'p1', userId: 'u1', body: 'hello');
      controller.add(
        CommentRealtimeEvent(
          eventId: 'e1',
          kind: CommentEventKind.insert,
          comment: row('c1'),
        ),
      );
      controller.add(
        CommentRealtimeEvent(
          eventId: 'e1',
          kind: CommentEventKind.insert,
          comment: row('c1'),
        ),
      );
      controller.add(
        CommentRealtimeEvent(
          eventId: 'e2',
          kind: CommentEventKind.insert,
          comment: row('c2'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(thread.comments.length, 2); // c1 once + c2 once
      expect(sub.seenEventCount, 2);
      expect(forwarded, 2);

      await sub.unsubscribe();
      // reconnect replays e1,e2 plus new e3 -> only e3 forwarded
      final replay = Stream<CommentRealtimeEvent>.fromIterable([
        CommentRealtimeEvent(
          eventId: 'e1',
          kind: CommentEventKind.insert,
          comment: row('c1'),
        ),
        CommentRealtimeEvent(
          eventId: 'e2',
          kind: CommentEventKind.insert,
          comment: row('c2'),
        ),
        CommentRealtimeEvent(
          eventId: 'e3',
          kind: CommentEventKind.insert,
          comment: row('c3'),
        ),
      ]);
      await sub.reconnect(
        streamFactory: (_) => replay,
        onEvent: (e) {
          forwarded++;
          if (e.kind == CommentEventKind.insert && e.comment != null) {
            thread.applyRealtimeInsert(e.comment!);
          }
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(forwarded, 3);
      expect(thread.comments.length, 3);
      await controller.close();
      await sub.dispose();
    },
  );

  test('teardown: no events after dispose', () async {
    final sub = CommentRealtimeSubscription();
    final controller = StreamController<CommentRealtimeEvent>.broadcast();
    var calls = 0;
    await sub.subscribe(stream: controller.stream, onEvent: (_) => calls++);
    await sub.dispose();
    expect(sub.isSubscribed, isFalse);
    controller.add(
      const CommentRealtimeEvent(
        eventId: 'e9',
        kind: CommentEventKind.delete,
        commentId: 'c9',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(calls, 0);
    expect(
      () => sub.subscribe(stream: controller.stream, onEvent: (_) {}),
      throwsStateError,
    );
    await controller.close();
  });
}
