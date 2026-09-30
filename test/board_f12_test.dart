import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/board/media/board_image_picker.dart';
import 'package:railmate_bd/features/board/media/post_media.dart';
import 'package:railmate_bd/features/board/post/post.dart';
import 'package:railmate_bd/features/board/post/post_compose_state.dart';

// --- Magic-byte samples (minimal valid headers) ----------------------------

List<int> _jpeg([int extra = 64]) => <int>[
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  ...List<int>.filled(extra, 7),
];

List<int> _png() => <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x01,
  0x02,
];

List<int> _gif() => <int>[0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00];

List<int> _webp() => <int>[
  0x52,
  0x49,
  0x46,
  0x46,
  0x10,
  0x00,
  0x00,
  0x00,
  0x57,
  0x45,
  0x42,
  0x50,
];

List<int> _heic() => <int>[
  0x00,
  0x00,
  0x00,
  0x20,
  0x66,
  0x74,
  0x79,
  0x70,
  0x68,
  0x65,
  0x69,
  0x63,
];

void main() {
  group('F12 validation (images only, 5 MB cap, before upload)', () {
    test('states the 5 MB cap', () {
      expect(boardMaxImageBytes, 5 * 1024 * 1024);
    });

    test('accepts supported containers', () {
      expect(validateBoardImageBytes(_jpeg()), isNull);
      expect(validateBoardImageBytes(_png()), isNull);
      expect(validateBoardImageBytes(_gif()), isNull);
      expect(validateBoardImageBytes(_webp()), isNull);
      expect(validateBoardImageBytes(_heic()), isNull);
    });

    test('detects the container extension', () {
      expect(detectBoardImageExt(_jpeg()), 'jpg');
      expect(detectBoardImageExt(_png()), 'png');
      expect(detectBoardImageExt(_webp()), 'webp');
      expect(detectBoardImageExt(_gif()), 'gif');
      expect(detectBoardImageExt(_heic()), 'heic');
    });

    test('rejects empty bytes', () {
      expect(validateBoardImageBytes(<int>[]), isNotNull);
    });

    test('rejects oversize picks before any upload', () {
      final big = <int>[
        0xFF,
        0xD8,
        0xFF,
        ...List<int>.filled(boardMaxImageBytes, 1),
      ];
      final reason = validateBoardImageBytes(big);
      expect(reason, isNotNull);
      expect(reason, contains('5 MB'));
    });

    test('accepts exactly the cap', () {
      final exact = <int>[
        0xFF,
        0xD8,
        0xFF,
        ...List<int>.filled(boardMaxImageBytes - 3, 1),
      ];
      expect(exact.length, boardMaxImageBytes);
      expect(validateBoardImageBytes(exact), isNull);
    });

    test('rejects non-photo bytes', () {
      expect(
        validateBoardImageBytes(List<int>.filled(64, 0x41)),
        contains('supported photo'),
      );
      expect(
        () => detectBoardImageExt(List<int>.filled(64, 0x41)),
        throwsA(isA<BoardImageRejectedException>()),
      );
    });

    test('rejects non-image mime hints', () {
      expect(
        validateBoardImageBytes(_jpeg(), mimeHint: 'application/pdf'),
        contains('not an image'),
      );
      expect(validateBoardImageBytes(_jpeg(), mimeHint: 'IMAGE/JPEG'), isNull);
    });
  });

  group('F12 pick (cancel no-op, denial vs retry)', () {
    test('cancel (null) is a silent no-op returning null', () async {
      final out = await pickBoardImageBytes(
        fromCamera: false,
        rawPick: ({required bool fromCamera}) async => null,
      );
      expect(out, isNull);
    });

    test('valid pick returns bytes', () async {
      final bytes = _jpeg();
      final out = await pickBoardImageBytes(
        fromCamera: false,
        rawPick: ({required bool fromCamera}) async =>
            RawPickedImage(bytes: bytes, mime: 'image/jpeg'),
      );
      expect(out, bytes);
    });

    test('oversize pick throws Rejected (never attaches)', () async {
      final big = <int>[
        0xFF,
        0xD8,
        0xFF,
        ...List<int>.filled(boardMaxImageBytes, 1),
      ];
      await expectLater(
        pickBoardImageBytes(
          fromCamera: false,
          rawPick: ({required bool fromCamera}) async =>
              RawPickedImage(bytes: big, mime: 'image/jpeg'),
        ),
        throwsA(isA<BoardImageRejectedException>()),
      );
    });

    test('empty pick throws Rejected (not a silent cancel)', () async {
      await expectLater(
        pickBoardImageBytes(
          fromCamera: false,
          rawPick: ({required bool fromCamera}) async =>
              const RawPickedImage(bytes: <int>[]),
        ),
        throwsA(isA<BoardImageRejectedException>()),
      );
    });

    test('OS permission denial maps to Denied', () async {
      await expectLater(
        pickBoardImageBytes(
          fromCamera: true,
          rawPick: ({required bool fromCamera}) async =>
              throw PlatformException(code: 'permission_denied'),
        ),
        throwsA(isA<BoardImageDeniedException>()),
      );
      await expectLater(
        pickBoardImageBytes(
          fromCamera: false,
          rawPick: ({required bool fromCamera}) async =>
              throw Exception('permission denied by user'),
        ),
        throwsA(isA<BoardImageDeniedException>()),
      );
    });

    test('unexpected picker failure propagates for retry', () async {
      await expectLater(
        pickBoardImageBytes(
          fromCamera: false,
          rawPick: ({required bool fromCamera}) async =>
              throw Exception('camera crashed'),
        ),
        throwsA(
          predicate(
            (e) =>
                e is! BoardImageDeniedException &&
                e is! BoardImageRejectedException,
          ),
        ),
      );
    });
  });

  group('F12 submit handoff (upload then link via updatePostImage)', () {
    test(
      'validated bytes upload to the owned path and link image_path',
      () async {
        final compose = PostComposeState();
        compose.setBody('Sunset at Kamalapur');
        final picked = await pickBoardImageBytes(
          fromCamera: false,
          rawPick: ({required bool fromCamera}) async =>
              RawPickedImage(bytes: _jpeg(), mime: 'image/jpeg'),
        );
        compose.attachImageBytes(picked!);

        String? uploadedPath;
        List<int>? uploadedBytes;
        String? linkedPostId;
        String? linkedPath;
        final ok = await compose.submit(
          userId: 'uid1',
          newUuid: () => 'fixed-uuid',
          createPost: ({required String userId, required String body}) async =>
              Post(id: 'p1', userId: userId, body: body),
          uploadBytes: (String path, List<int> bytes) async {
            uploadedPath = path;
            uploadedBytes = bytes;
          },
          updatePostImage:
              ({required String postId, required String imagePath}) async {
                linkedPostId = postId;
                linkedPath = imagePath;
                return Post(
                  id: postId,
                  userId: 'uid1',
                  body: 'Sunset at Kamalapur',
                  imagePath: imagePath,
                );
              },
        );

        expect(ok, isTrue);
        expect(uploadedPath, 'uid1/fixed-uuid.jpg');
        expect(uploadedBytes, isNotNull);
        expect(linkedPostId, 'p1');
        expect(linkedPath, 'uid1/fixed-uuid.jpg');
        expect(compose.createdPost?.imagePath, 'uid1/fixed-uuid.jpg');
        expect(compose.hasOrphan, isFalse);
        expect(compose.isDone, isTrue);
        compose.dispose();
      },
    );

    test(
      'upload failure keeps the row as an honest orphan with cleanup',
      () async {
        final compose = PostComposeState();
        compose.setBody('Photo post');
        compose.attachImageBytes(_jpeg());
        final ok = await compose.submit(
          userId: 'uid1',
          newUuid: () => 'fixed-uuid',
          createPost: ({required String userId, required String body}) async =>
              Post(id: 'p1', userId: userId, body: body),
          uploadBytes: (String path, List<int> bytes) async {
            throw Exception('network down');
          },
          updatePostImage: ({
            required String postId,
            required String imagePath,
          }) async => throw StateError('must not link when upload failed'),
        );
        expect(ok, isFalse);
        expect(compose.hasOrphan, isTrue);
        expect(compose.errorMessage, contains('photo failed'));
        expect(compose.media.state, UploadState.failed);
        // Never a local-only image reported as posted.
        expect(compose.media.isUploaded, isFalse);

        var rows = 0;
        var objects = 0;
        final cleaned = await compose.cleanupOrphan(
          deletePost: (String id) async {
            rows++;
            expect(id, 'p1');
          },
          deleteObject: (String path) async {
            objects++;
            expect(path, 'uid1/fixed-uuid.jpg');
          },
        );
        expect(cleaned, isTrue);
        expect(rows, 1);
        expect(objects, 1);
        expect(compose.hasOrphan, isFalse);
        compose.dispose();
      },
    );

    test('RLS upload denial surfaces honestly with retry-or-delete', () async {
      final compose = PostComposeState();
      compose.setBody('Photo post');
      compose.attachImageBytes(_jpeg());
      final ok = await compose.submit(
        userId: 'uid1',
        newUuid: () => 'fixed-uuid',
        createPost: ({required String userId, required String body}) async =>
            Post(id: 'p1', userId: userId, body: body),
        uploadBytes: (String path, List<int> bytes) async {
          throw Exception('RLS denied: new row violates post_media_upload_own');
        },
      );
      expect(ok, isFalse);
      expect(compose.hasOrphan, isTrue);
      compose.dispose();
    });
  });

  group('F12 orphan honesty', () {
    test(
      'unwired link leaves the object uploaded but unlinked (never shown)',
      () async {
        final compose = PostComposeState();
        compose.setBody('With photo');
        compose.attachImageBytes(_jpeg());
        final ok = await compose.submit(
          userId: 'uid1',
          newUuid: () => 'fixed-uuid',
          createPost: ({required String userId, required String body}) async =>
              Post(id: 'p1', userId: userId, body: body),
          uploadBytes: (String path, List<int> bytes) async {},
          // No updatePostImage: legacy behaviour — upload runs, row stays
          // image_path=null, so the feed badge/photo never appears.
        );
        expect(ok, isTrue);
        expect(compose.media.isUploaded, isTrue);
        expect(compose.reservedImagePath, 'uid1/fixed-uuid.jpg');
        expect(compose.createdPost?.imagePath, isNull);
        compose.dispose();
      },
    );

    test(
      'discard before submit uploads nothing (no orphan possible)',
      () async {
        final compose = PostComposeState();
        compose.setBody('draft');
        compose.attachImageBytes(_jpeg());
        var uploads = 0;
        compose.clearImage();
        compose.reset();
        expect(compose.media.hasBytes, isFalse);
        expect(compose.createdPost, isNull);
        expect(compose.reservedImagePath, isNull);
        expect(uploads, 0);
        compose.dispose();
      },
    );

    test('best-effort object delete never throws', () async {
      expect(await deleteBoardObjectBestEffort(null, null), isFalse);
      expect(await deleteBoardObjectBestEffort('uid1/a.jpg', null), isFalse);
      expect(
        await deleteBoardObjectBestEffort(
          'uid1/a.jpg',
          (String path) async => throw Exception('gone'),
        ),
        isFalse,
      );
      var called = 0;
      expect(
        await deleteBoardObjectBestEffort('uid1/a.jpg', (String path) async {
          called++;
        }),
        isTrue,
      );
      expect(called, 1);
    });
  });
}
