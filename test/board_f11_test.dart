import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/board/media/post_media.dart';
import 'package:railmate_bd/features/board/post/feed_screen.dart';
import 'package:railmate_bd/features/board/post/post.dart';
import 'package:railmate_bd/features/board/post/post_compose_state.dart';
import 'package:railmate_bd/features/board/post/post_feed_state.dart';

const String _supabaseUrl = 'https://example.supabase.co';

Post _row(String id, String body, {String? imagePath}) => Post(
  id: id,
  userId: 'uid1',
  body: body,
  imagePath: imagePath,
  createdAt: DateTime.utc(2026, 9, 27, 12, 0),
);

void main() {
  group('F11 image URL helper (public bucket, no signed URLs)', () {
    test('shapes the public storage URL', () {
      expect(
        postImageUrl(supabaseUrl: _supabaseUrl, imagePath: 'uid1/abc.jpg'),
        '$_supabaseUrl/storage/v1/object/public/post-media/uid1/abc.jpg',
      );
    });

    test('trims duplicate slashes', () {
      expect(
        postImageUrl(supabaseUrl: '$_supabaseUrl/', imagePath: '/uid1/abc.jpg'),
        '$_supabaseUrl/storage/v1/object/public/post-media/uid1/abc.jpg',
      );
    });

    test('null/empty/blank inputs resolve to null (no image widget)', () {
      expect(postImageUrl(supabaseUrl: _supabaseUrl, imagePath: null), isNull);
      expect(postImageUrl(supabaseUrl: _supabaseUrl, imagePath: ''), isNull);
      expect(postImageUrl(supabaseUrl: _supabaseUrl, imagePath: '  '), isNull);
      expect(postImageUrl(supabaseUrl: _supabaseUrl, imagePath: '///'), isNull);
      expect(postImageUrl(supabaseUrl: '  ', imagePath: 'uid1/a.jpg'), isNull);
    });
  });

  group('F11 feed rows render', () {
    testWidgets('text rows render bodies; empty shows genuine empty state', (
      tester,
    ) async {
      final feed = PostFeedState(
        fetchPosts: ({int limit = 20}) async => <Post>[
          _row('p1', 'Platform 2 tea stall is great'),
          _row('p2', 'Boat to Barisal delayed'),
        ],
      );
      await feed.load();
      await tester.pumpWidget(MaterialApp(home: BoardFeedScreen(feed: feed)));
      await tester.pumpAndSettle();
      expect(find.text('Platform 2 tea stall is great'), findsOneWidget);
      expect(find.text('Boat to Barisal delayed'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      feed.dispose();
    });

    testWidgets('image post renders Image when resolver wired', (tester) async {
      final feed = PostFeedState(
        fetchPosts: ({int limit = 20}) async => <Post>[
          _row('p1', 'Sunset at Kamalapur', imagePath: 'uid1/sunset.jpg'),
        ],
      );
      await feed.load();
      await tester.pumpWidget(
        MaterialApp(
          home: BoardFeedScreen(
            feed: feed,
            imageUrlFor: (path) =>
                postImageUrl(supabaseUrl: _supabaseUrl, imagePath: path),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      // Hermetic env: the fake URL cannot load, so Image.errorBuilder
      // degrades to the badge (production shows the photo). This proves the
      // resolver path was chosen AND the failure degradation works.
      await tester.pumpAndSettle();
      expect(find.text('Photo attached'), findsOneWidget);
      feed.dispose();
    });

    testWidgets('image post falls back to badge when resolver missing', (
      tester,
    ) async {
      final feed = PostFeedState(
        fetchPosts: ({int limit = 20}) async => <Post>[
          _row('p1', 'Sunset at Kamalapur', imagePath: 'uid1/sunset.jpg'),
        ],
      );
      await feed.load();
      await tester.pumpWidget(MaterialApp(home: BoardFeedScreen(feed: feed)));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.text('Photo attached'), findsOneWidget);
      feed.dispose();
    });

    testWidgets('error state shows Retry; empty shows empty text', (
      tester,
    ) async {
      final failing = PostFeedState(
        fetchPosts: ({int limit = 20}) async => throw Exception('network down'),
      );
      await failing.load();
      await tester.pumpWidget(
        MaterialApp(home: BoardFeedScreen(feed: failing)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Could not load posts.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      failing.dispose();

      final empty = PostFeedState(
        fetchPosts: ({int limit = 20}) async => <Post>[],
      );
      await empty.load();
      await tester.pumpWidget(MaterialApp(home: BoardFeedScreen(feed: empty)));
      await tester.pumpAndSettle();
      expect(find.textContaining('No posts yet'), findsOneWidget);
      empty.dispose();
    });
  });

  group('F11 create flow', () {
    test('submit calls createPost with (userId, body)', () async {
      final compose = PostComposeState();
      compose.setBody('  Morning train tip  ');
      String? seenUser;
      String? seenBody;
      final ok = await compose.submit(
        userId: 'uid1',
        newUuid: () => 'uuid-x',
        createPost: ({required String userId, required String body}) async {
          seenUser = userId;
          seenBody = body;
          return Post(id: 'p9', userId: userId, body: body);
        },
        uploadBytes: (path, bytes) async {},
      );
      expect(ok, isTrue);
      expect(seenUser, 'uid1');
      expect(seenBody, 'Morning train tip');
      expect(compose.createdPost?.id, 'p9');
      compose.dispose();
    });

    test('image submit links image_path onto the row', () async {
      final compose = PostComposeState();
      compose.setBody('With photo');
      compose.attachImageBytes([1, 2, 3]);
      String? linkedPostId;
      String? linkedPath;
      final ok = await compose.submit(
        userId: 'uid1',
        newUuid: () => 'fixed-uuid',
        createPost: ({required String userId, required String body}) async =>
            Post(id: 'p1', userId: userId, body: body),
        uploadBytes: (path, bytes) async {},
        updatePostImage:
            ({required String postId, required String imagePath}) async {
              linkedPostId = postId;
              linkedPath = imagePath;
              return Post(
                id: postId,
                userId: 'uid1',
                body: 'With photo',
                imagePath: imagePath,
              );
            },
      );
      expect(ok, isTrue);
      expect(linkedPostId, 'p1');
      expect(linkedPath, 'uid1/fixed-uuid.jpg');
      expect(compose.createdPost?.imagePath, 'uid1/fixed-uuid.jpg');
      expect(compose.imageLinkError, isNull);
      expect(compose.hasOrphan, isFalse);
      compose.dispose();
    });

    test(
      'link failure exposes orphan cleanup (row + object both exist)',
      () async {
        final compose = PostComposeState();
        compose.setBody('With photo');
        compose.attachImageBytes([1, 2, 3]);
        final ok = await compose.submit(
          userId: 'uid1',
          newUuid: () => 'fixed-uuid',
          createPost: ({required String userId, required String body}) async =>
              Post(id: 'p1', userId: userId, body: body),
          uploadBytes: (path, bytes) async {},
          updatePostImage:
              ({required String postId, required String imagePath}) async {
                throw Exception('RLS denied');
              },
        );
        expect(ok, isFalse);
        expect(compose.imageLinkError, isNotNull);
        expect(compose.hasOrphan, isTrue);

        var rowDeletes = 0;
        var objectDeletes = 0;
        final cleaned = await compose.cleanupOrphan(
          deletePost: (id) async {
            rowDeletes++;
            expect(id, 'p1');
          },
          deleteObject: (path) async {
            objectDeletes++;
            expect(path, 'uid1/fixed-uuid.jpg');
          },
        );
        expect(cleaned, isTrue);
        expect(rowDeletes, 1);
        // Best-effort object delete runs against the uploaded remote path.
        expect(objectDeletes, 1);
        compose.dispose();
      },
    );

    test('upload failure keeps orphan path with cleanup', () async {
      final compose = PostComposeState();
      compose.setBody('Photo post');
      compose.attachImageBytes([4, 5, 6]);
      final ok = await compose.submit(
        userId: 'uid1',
        newUuid: () => 'fixed-uuid',
        createPost: ({required String userId, required String body}) async =>
            Post(id: 'p1', userId: userId, body: body),
        uploadBytes: (path, bytes) async {
          throw Exception('network down');
        },
      );
      expect(ok, isFalse);
      expect(compose.hasOrphan, isTrue);
      expect(compose.createdPost?.id, 'p1');
      expect(compose.reservedImagePath, 'uid1/fixed-uuid.jpg');
      expect(compose.media.state, UploadState.failed);

      var rowDeletes = 0;
      final cleaned = await compose.cleanupOrphan(
        deletePost: (id) async => rowDeletes++,
      );
      expect(cleaned, isTrue);
      expect(rowDeletes, 1);
      expect(compose.hasOrphan, isFalse);
      compose.dispose();
    });
  });
}
