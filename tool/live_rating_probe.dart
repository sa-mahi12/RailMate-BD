// Live realtime probe for `public.post_ratings` (R-07).
//
// Creates two synthetic accounts, subscribes one client to Postgres Changes
// on `post_ratings`, writes a rating from the second client, then updates and
// deletes it. Every step is an actual hosted request; nothing is mocked.
//
// Usage (PowerShell), with the values kept out of this file:
//   $env:RM_URL=...; $env:RM_ANON=...; $env:RM_SERVICE=...
//   dart run tool/live_rating_probe.dart
//
// Output never includes tokens, keys or full email addresses.
// ignore_for_file: avoid_print, depend_on_referenced_packages
// (supabase is a direct transitive of supabase_flutter; this CLI probe runs
// with `dart run`, so it cannot import the Flutter wrapper.)
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

    // 2. Client A listens on the shared table/filter the shell uses.
    final List<String> seen = <String>[];
    final Completer<void> threeEvents = Completer<void>();
    final RealtimeChannel channel = ca
        .channel('probe-ratings-$stamp')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'post_ratings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'post_id',
            value: postId,
          ),
          callback: (PostgresChangePayload payload) {
            final Object? pid =
                payload.newRecord['post_id'] ?? payload.oldRecord['post_id'];
            if (pid?.toString() != postId) return;
            seen.add(payload.eventType.name);
            if (seen.length >= 3 && !threeEvents.isCompleted) {
              threeEvents.complete();
            }
          },
        )
        .subscribe();
    await Future<void>.delayed(const Duration(seconds: 3));
    print('subscription=requested');

    // 3. Client B: insert 5 -> update 2 -> delete.
    await cb.from('post_ratings').insert(<String, dynamic>{
      'post_id': postId,
      'user_id': b.user!.id,
      'stars': 5,
    });
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await cb
        .from('post_ratings')
        .update(<String, dynamic>{'stars': 2})
        .eq('post_id', postId)
        .eq('user_id', b.user!.id);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await cb
        .from('post_ratings')
        .delete()
        .eq('post_id', postId)
        .eq('user_id', b.user!.id);

    try {
      await threeEvents.future.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      print('events_received=${seen.length} (timeout)');
    }
    print('events_received=${seen.join(",")}');

    final List<Map<String, dynamic>> rows = await ca
        .from('post_ratings')
        .select('post_id, user_id, stars')
        .eq('post_id', postId);
    print('rows_after_delete=${rows.length}');

    await ca.removeChannel(channel);
    await ca.dispose();
    await cb.dispose();
  } finally {
    // 4. Cleanup: post first (cascades ratings), then the synthetic accounts.
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
