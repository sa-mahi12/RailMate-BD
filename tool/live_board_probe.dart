// ignore_for_file: avoid_print, depend_on_referenced_packages
// (supabase is a direct transitive of supabase_flutter; this CLI probe runs
// with `dart run`, so it cannot import the Flutter wrapper.)
//
// Live realtime board probe (R-02 comments, R-03 reactions, R-07 ratings).
//
// Creates two synthetic accounts, subscribes client A to Postgres Changes on
// all three board tables (the same publication the app's HomeShell uses), then
// has client B insert/update/delete rows. Every step is an actual hosted
// request; nothing is mocked.
//
// Usage (PowerShell), with the values kept out of this file:
//   $env:RM_URL=...; $env:RM_ANON=...; $env:RM_SERVICE=...
//   dart run tool/live_board_probe.dart
//
// Output never includes tokens, keys or full email addresses.
import 'dart:async';
import 'dart:io';

import 'package:supabase/supabase.dart';

Future<void> main() async {
  final String url = Platform.environment['RM_URL']!;
  final String anon = Platform.environment['RM_ANON']!;
  final String service = Platform.environment['RM_SERVICE']!;

  final admin = SupabaseClient(url, service).auth.admin;
  final String stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  // Ephemeral per-run password; nothing reusable is stored in the file.
  final String password = 'Probe#${stamp}rail';
  final List<String> created = <String>[];
  String? postId;

  try {
    // 1. Two synthetic users (trigger creates their profile + username).
    final UserResponse a = await admin.createUser(
      AdminUserAttributes(
        email: 'rt-a-$stamp@example.com',
        password: password,
        emailConfirm: true,
        userMetadata: <String, dynamic>{
          'full_name': 'Realtime Probe A',
          'username': 'rt_a_$stamp',
        },
      ),
    );
    final UserResponse b = await admin.createUser(
      AdminUserAttributes(
        email: 'rt-b-$stamp@example.com',
        password: password,
        emailConfirm: true,
        userMetadata: <String, dynamic>{
          'full_name': 'Realtime Probe B',
          'username': 'rt_b_$stamp',
        },
      ),
    );
    created.addAll(<String>[a.user!.id, b.user!.id]);
    print('accounts=2 created');

    final SupabaseClient ca = SupabaseClient(url, anon);
    final SupabaseClient cb = SupabaseClient(url, anon);
    await ca.auth.signInWithPassword(email: a.user!.email!, password: password);
    await cb.auth.signInWithPassword(email: b.user!.email!, password: password);
    print('signin=2 ok');

    final Map<String, dynamic> postRow = await ca
        .from('posts')
        .insert(<String, dynamic>{
          'user_id': a.user!.id,
          'body': 'Synthetic realtime probe post (safe to delete).',
        })
        .select()
        .single();
    final String createdPostId = postRow['id'] as String;
    postId = createdPostId;
    print('post_created=1');

    // 2. Client A listens on the three tables the shell subscribes to.
    final Map<String, List<String>> seen = <String, List<String>>{
      'post_comments': <String>[],
      'post_reactions': <String>[],
      'post_ratings': <String>[],
    };
    var expected = 0;
    final Completer<void> done = Completer<void>();
    void record(String table, PostgresChangePayload payload) {
      final Object? pid =
          payload.newRecord['post_id'] ?? payload.oldRecord['post_id'];
      if (pid != null && pid.toString() != createdPostId) return;
      seen[table]!.add(payload.eventType.name);
      if (seen.values.fold<int>(0, (int n, List<String> v) => n + v.length) >=
              expected &&
          !done.isCompleted) {
        done.complete();
      }
    }

    final RealtimeChannel channel = ca.channel('probe-board-$stamp');
    for (final String table in seen.keys) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (PostgresChangePayload payload) => record(table, payload),
      );
    }
    channel.subscribe();
    await Future<void>.delayed(const Duration(seconds: 3));
    print('subscription=requested');

    // 3. Client B writes, exactly like a second app instance would.
    expected = 2 + 3 + 3;
    await cb.from('post_comments').insert(<String, dynamic>{
      'post_id': createdPostId,
      'user_id': b.user!.id,
      'body': 'Probe comment.',
    });
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await cb
        .from('post_comments')
        .delete()
        .eq('post_id', createdPostId)
        .eq('user_id', b.user!.id);
    await Future<void>.delayed(const Duration(milliseconds: 500));

    await cb.from('post_reactions').insert(<String, dynamic>{
      'post_id': createdPostId,
      'user_id': b.user!.id,
      'reaction': 'LIKE',
    });
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await cb
        .from('post_reactions')
        .update(<String, dynamic>{'reaction': 'DISLIKE'})
        .eq('post_id', createdPostId)
        .eq('user_id', b.user!.id);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await cb
        .from('post_reactions')
        .delete()
        .eq('post_id', createdPostId)
        .eq('user_id', b.user!.id);
    await Future<void>.delayed(const Duration(milliseconds: 500));

    await cb.from('post_ratings').insert(<String, dynamic>{
      'post_id': createdPostId,
      'user_id': b.user!.id,
      'stars': 5,
    });
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await cb
        .from('post_ratings')
        .update(<String, dynamic>{'stars': 2})
        .eq('post_id', createdPostId)
        .eq('user_id', b.user!.id);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await cb
        .from('post_ratings')
        .delete()
        .eq('post_id', createdPostId)
        .eq('user_id', b.user!.id);

    try {
      await done.future.timeout(const Duration(seconds: 25));
    } on TimeoutException {
      print('timeout=1');
    }
    for (final String table in seen.keys) {
      print('$table=${seen[table]!.join(",")}');
    }

    // 4. Authoritative read-back after the deletes.
    for (final String table in seen.keys) {
      final List<Map<String, dynamic>> rows = await ca
          .from(table)
          .select('post_id')
          .eq('post_id', createdPostId);
      print('rows_$table=${rows.length}');
    }

    await ca.removeChannel(channel);
  } finally {
    // 5. Cleanup: post first (cascades), then the synthetic accounts.
    final SupabaseClient adminClient = SupabaseClient(url, service);
    if (postId != null) {
      await adminClient.from('posts').delete().eq('id', postId);
    }
    for (final String id in created) {
      await admin.deleteUser(id);
    }
    await adminClient.dispose();
    print('cleanup_done');
    // Realtime sockets can keep the isolate alive after the channel is
    // removed; the probe is done, so exit deterministically.
    exit(0);
  }
}
