import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/board/media/board_attachment_picker.dart';
import 'package:railmate_bd/features/board/media/post_attachment.dart';
import 'package:railmate_bd/features/board/media/post_media.dart';
import 'package:railmate_bd/features/board/moderation/report_dialog.dart';
import 'package:railmate_bd/features/board/post/compose_attachment.dart';
import 'package:railmate_bd/features/board/post/post.dart';
import 'package:railmate_bd/features/board/post/post_compose_state.dart';

PickedBoardFile _pdf([String name = 'timetable.pdf']) => PickedBoardFile(
  filename: name,
  mimeType: 'application/pdf',
  bytes: List<int>.filled(2048, 7),
);

PickedBoardFile _image() => PickedBoardFile(
  filename: 'platform.jpg',
  mimeType: 'image/jpeg',
  bytes: List<int>.filled(1024, 1),
);

void main() {
  group('draft attachments', () {
    test('accepts allowlisted files and rejects bad ones with a reason', () {
      final PostComposeState state = PostComposeState();
      expect(state.addPickedAttachment(_pdf()), isNull);
      expect(state.attachments.length, 1);
      expect(state.attachments.first.kind, PostAttachmentKind.file);
      expect(state.attachments.first.statusLabel, 'Ready to upload');

      final String? tooBig = state.addPickedAttachment(
        PickedBoardFile(
          filename: 'huge.mp4',
          mimeType: 'video/mp4',
          bytes: List<int>.filled(postAttachmentMaxBytes + 1, 0),
        ),
      );
      expect(tooBig, contains('too large'));

      final String? badType = state.addPickedAttachment(
        PickedBoardFile(
          filename: 'x.exe',
          mimeType: 'application/x-msdownload',
          bytes: <int>[1, 2, 3],
        ),
      );
      expect(badType, contains('not supported'));
      expect(state.attachments.length, 1);
    });

    test('caps a post at ten attachments', () {
      final PostComposeState state = PostComposeState();
      for (int i = 0; i < postAttachmentMaxPerPost; i++) {
        expect(state.addPickedAttachment(_pdf('f$i.pdf')), isNull);
      }
      expect(
        state.addPickedAttachment(_pdf('eleventh.pdf')),
        contains('up to $postAttachmentMaxPerPost'),
      );
    });

    test('links must be https, unique and removable', () {
      final PostComposeState state = PostComposeState();
      expect(state.addLinkAttachment('http://example.com'), contains('https'));
      expect(state.addLinkAttachment('https://youtu.be/dQw4w9WgXcQ'), isNull);
      expect(
        state.addLinkAttachment('https://youtu.be/dQw4w9WgXcQ'),
        contains('already attached'),
      );
      expect(state.attachments.single.isLink, isTrue);
      state.removeAttachmentAt(0);
      expect(state.attachments, isEmpty);
    });

    test('reordering keeps the drafted order', () {
      final PostComposeState state = PostComposeState();
      state.addPickedAttachment(_pdf('a.pdf'));
      state.addPickedAttachment(_image());
      state.moveAttachment(0, 1);
      expect(state.attachments[0].filename, 'platform.jpg');
      expect(state.attachments[1].filename, 'a.pdf');
      state.reset();
      expect(state.attachments, isEmpty);
    });
  });

  group('publishing with attachments', () {
    test('uploads then inserts every attachment in order', () async {
      final PostComposeState state = PostComposeState();
      state.setBody('Platform 4 has the tea stall.');
      state.addPickedAttachment(_pdf());
      state.addLinkAttachment('https://youtu.be/dQw4w9WgXcQ');

      final List<String> uploaded = <String>[];
      final List<String> types = <String>[];
      final List<PostAttachment> inserted = <PostAttachment>[];
      int uuid = 0;

      final bool ok = await state.submitWithAttachments(
        userId: 'user-1',
        newUuid: () => 'obj${uuid++}',
        createPost: ({required String userId, required String body}) async =>
            Post(id: 'post-1', userId: userId, body: body),
        uploadAttachment:
            (String path, List<int> bytes, String contentType) async {
              uploaded.add(path);
              types.add(contentType);
            },
        insertAttachment: (PostAttachment row) async {
          inserted.add(row);
          return PostAttachment(
            id: 'att-${inserted.length}',
            postId: row.postId,
            ownerId: row.ownerId,
            kind: row.kind,
            storagePath: row.storagePath,
            externalUrl: row.externalUrl,
            mimeType: row.mimeType,
            originalFilename: row.originalFilename,
            fileSizeBytes: row.fileSizeBytes,
            displayOrder: row.displayOrder,
          );
        },
      );

      expect(ok, isTrue);
      expect(state.isDone, isTrue);
      expect(state.hasOrphan, isFalse);
      expect(uploaded.single, 'user-1/post-1/obj0.pdf');
      expect(types.single, 'application/pdf');
      expect(inserted.length, 2);
      expect(inserted.first.displayOrder, 0);
      expect(inserted.first.kind, PostAttachmentKind.file);
      expect(inserted.first.fileSizeBytes, 2048);
      expect(inserted.last.kind, PostAttachmentKind.link);
      expect(inserted.last.externalUrl, 'https://youtu.be/dQw4w9WgXcQ');
      expect(inserted.last.storagePath, isNull);
      expect(
        state.attachments.every((ComposeAttachment a) => a.isStored),
        isTrue,
      );
    });

    test('a failed upload is reported, not hidden', () async {
      final PostComposeState state = PostComposeState();
      state.setBody('Photo from the platform.');
      state.addPickedAttachment(_image());

      final bool ok = await state.submitWithAttachments(
        userId: 'user-1',
        newUuid: () => 'obj',
        createPost: ({required String userId, required String body}) async =>
            Post(id: 'post-2', userId: userId, body: body),
        uploadAttachment:
            (String path, List<int> bytes, String contentType) async {
              throw Exception('network down');
            },
        insertAttachment: (PostAttachment row) async =>
            throw StateError('must not insert after a failed upload'),
      );

      expect(ok, isFalse);
      expect(state.attachments.single.state, UploadState.failed);
      expect(state.attachments.single.errorMessage, isNotNull);
      expect(state.isDone, isFalse);
      expect(state.hasOrphan, isTrue);
      expect(state.errorMessage, contains('Some attachments failed'));
    });

    test('retry persists only what is still missing', () async {
      final PostComposeState state = PostComposeState();
      state.setBody('Retry me.');
      state.addPickedAttachment(_pdf());
      int attempts = 0;
      int inserts = 0;

      Future<bool> run() => state.submitWithAttachments(
        userId: 'user-1',
        newUuid: () => 'obj',
        createPost: ({required String userId, required String body}) async =>
            Post(id: 'post-3', userId: userId, body: body),
        uploadAttachment:
            (String path, List<int> bytes, String contentType) async {
              attempts++;
              if (attempts == 1) throw Exception('first attempt fails');
            },
        insertAttachment: (PostAttachment row) async {
          inserts++;
          return PostAttachment(
            id: 'att-1',
            postId: row.postId,
            ownerId: row.ownerId,
            kind: row.kind,
            storagePath: row.storagePath,
          );
        },
      );

      expect(await run(), isFalse);
      expect(
        await state.retryFailedAttachments(
          userId: 'user-1',
          newUuid: () => 'obj',
          uploadAttachment:
              (String path, List<int> bytes, String contentType) async {
                attempts++;
              },
          insertAttachment: (PostAttachment row) async {
            inserts++;
            return PostAttachment(
              id: 'att-1',
              postId: row.postId,
              ownerId: row.ownerId,
              kind: row.kind,
              storagePath: row.storagePath,
            );
          },
        ),
        isTrue,
      );
      expect(attempts, 2);
      expect(inserts, 1);
    });
  });

  group('reporting', () {
    test('post reasons never include impersonation', () {
      final List<ReportReason> reasons = reportReasonsFor(ReportTarget.post);
      expect(reasons, contains(ReportReason.unsafeMedia));
      expect(reasons, isNot(contains(ReportReason.impersonation)));
    });

    test('user reasons never include unsafe media', () {
      final List<ReportReason> reasons = reportReasonsFor(ReportTarget.user);
      expect(reasons, contains(ReportReason.impersonation));
      expect(reasons, isNot(contains(ReportReason.unsafeMedia)));
    });

    test('reason values match the database check constraints', () {
      expect(
        ReportReason.values.map((ReportReason r) => r.dbValue).toSet(),
        <String>{
          'spam',
          'harassment',
          'misinformation',
          'unsafe_media',
          'impersonation',
          'other',
        },
      );
    });
  });
}
