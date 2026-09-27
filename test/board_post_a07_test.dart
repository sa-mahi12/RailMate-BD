import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/board/media/post_media.dart';
import 'package:railmate_bd/features/board/post/post.dart';
import 'package:railmate_bd/features/board/post/post_compose_state.dart';

void main() {
  group('body-length negatives', () {
    test('blank too short, 2001 too long, 2000 ok, draft empty throws', () {
      expect(Post.validateBody('   '), isNotNull);
      expect(Post.validateBody('x' * 2001), isNotNull);
      expect(Post.validateBody('x' * 2000), isNull);
      expect(() => Post.draft(userId: 'u1', body: ''), throwsArgumentError);
    });
  });

  group('owned-path builder', () {
    test(
      'builds owned path; rejects traversal/empty/bad ext; lowercases ext',
      () {
        expect(buildOwnedImagePath('uid1', 'abc-123'), 'uid1/abc-123.jpg');
        expect(
          buildOwnedImagePath('uid1', 'abc-123', ext: 'PNG'),
          'uid1/abc-123.png',
        );
        expect(
          () => buildOwnedImagePath('../x', 'abc-123'),
          throwsArgumentError,
        );
        expect(() => buildOwnedImagePath('uid1', ''), throwsArgumentError);
        expect(
          () => buildOwnedImagePath('uid1', 'abc-123', ext: '!!!'),
          throwsArgumentError,
        );
      },
    );
  });

  group('partial-failure cleanup', () {
    test(
      'upload throw leaves orphan; cleanup deletes row + reserved object once',
      () async {
        final compose = PostComposeState();
        compose.setBody('Hello from the train');
        compose.attachImageBytes([1, 2, 3]);
        var rowDeletes = 0;
        var objectDeletes = 0;
        final ok = await compose.submit(
          userId: 'uid1',
          newUuid: () => 'fixed-uuid',
          createPost: ({required String userId, required String body}) async =>
              Post(id: 'p1', userId: userId, body: body),
          uploadBytes: (String path, List<int> bytes) async {
            throw Exception('network down');
          },
        );
        expect(ok, isFalse);
        expect(compose.hasOrphan, isTrue);
        expect(compose.createdPost?.id, 'p1');
        expect(compose.media.state, UploadState.failed);

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
        expect(objectDeletes, 1);
        expect(await compose.cleanupOrphan(deletePost: (_) async {}), isFalse);
      },
    );
  });

  group('preview never reported as uploaded', () {
    test(
      'attach stays local; failed upload never uploaded; success uploads',
      () async {
        final media = PostMediaAttachment();
        media.attach([9, 9]);
        expect(media.state, UploadState.local);
        expect(media.remotePath, isNull);
        expect(media.isUploaded, isFalse);

        final failed = await media.upload(
          path: 'uid1/x.jpg',
          uploadBytes: (String path, List<int> bytes) async {
            throw Exception('down');
          },
        );
        expect(failed, isFalse);
        expect(media.state, UploadState.failed);
        expect(media.isUploaded, isFalse);

        final done = await media.upload(
          path: 'uid1/x.jpg',
          uploadBytes: (String path, List<int> bytes) async {},
        );
        expect(done, isTrue);
        expect(media.isUploaded, isTrue);
        expect(media.remotePath, 'uid1/x.jpg');
      },
    );
  });
}
