import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/board/media/post_attachment.dart';

void main() {
  group('PostAttachmentKind', () {
    test('parses known kinds and degrades unknown ones to file', () {
      expect(PostAttachmentKind.fromDb('image'), PostAttachmentKind.image);
      expect(PostAttachmentKind.fromDb('VIDEO'), PostAttachmentKind.video);
      expect(PostAttachmentKind.fromDb('link'), PostAttachmentKind.link);
      expect(PostAttachmentKind.fromDb('file'), PostAttachmentKind.file);
      expect(PostAttachmentKind.fromDb('audio'), PostAttachmentKind.file);
      expect(PostAttachmentKind.fromDb(null), PostAttachmentKind.file);
      expect(PostAttachmentKind.image.dbValue, 'image');
    });

    test('maps allowlisted MIME types onto the right kind', () {
      expect(attachmentKindForMime('image/png'), PostAttachmentKind.image);
      expect(attachmentKindForMime('video/mp4'), PostAttachmentKind.video);
      expect(attachmentKindForMime('application/pdf'), PostAttachmentKind.file);
      expect(attachmentKindForMime('audio/mpeg'), PostAttachmentKind.file);
      expect(attachmentKindForMime(' IMAGE/JPEG '), PostAttachmentKind.image);
    });

    test('every allowlisted MIME resolves to a usable extension', () {
      for (final String mime in postAttachmentAllowedMimes) {
        final String ext = attachmentExtensionForMime(mime);
        expect(ext, isNot('bin'), reason: 'missing extension for $mime');
        expect(ext, matches(RegExp(r'^[a-z0-9]+$')));
      }
    });
  });

  group('storage paths', () {
    test('builds uid/post/uuid.ext under the owner folder', () {
      expect(
        buildAttachmentStoragePath(
          userId: '8f9b0c1d-1111-4222-8333-444455556666',
          postId: 'aaaaaaaa-1111-4222-8333-444455556666',
          uuid: 'deadbeef',
          mimeType: 'application/pdf',
        ),
        '8f9b0c1d-1111-4222-8333-444455556666/'
        'aaaaaaaa-1111-4222-8333-444455556666/deadbeef.pdf',
      );
    });

    test('rejects empty parts and embedded slashes', () {
      expect(
        () => buildAttachmentStoragePath(
          userId: '',
          postId: 'p',
          uuid: 'u',
          mimeType: 'image/png',
        ),
        throwsArgumentError,
      );
      expect(
        () => buildAttachmentStoragePath(
          userId: 'a/b',
          postId: 'p',
          uuid: 'u',
          mimeType: 'image/png',
        ),
        throwsArgumentError,
      );
    });

    test('public URL is the world-readable Storage object path', () {
      expect(
        attachmentPublicUrl(
          supabaseUrl: 'https://example.supabase.co/',
          storagePath: '/uid/post/a.jpg',
        ),
        'https://example.supabase.co/storage/v1/object/public/'
        'post-media/uid/post/a.jpg',
      );
    });
  });

  group('external links', () {
    test('accepts https and rejects everything else', () {
      expect(validateExternalHttpsUrl('https://example.com/a?b=1'), isNull);
      expect(validateExternalHttpsUrl('http://example.com'), isNotNull);
      expect(validateExternalHttpsUrl('javascript:alert(1)'), isNotNull);
      expect(validateExternalHttpsUrl(''), isNotNull);
      expect(validateExternalHttpsUrl('https://exa mple.com'), isNotNull);
      expect(validateExternalHttpsUrl('https://u:p@example.com'), isNotNull);
      expect(
        validateExternalHttpsUrl('https://example.com/${'a' * 2100}'),
        isNotNull,
      );
    });

    test('only allowlisted providers are embeddable', () {
      expect(
        externalVideoEmbedUrl('https://youtu.be/dQw4w9WgXcQ'),
        'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?rel=0',
      );
      expect(
        externalVideoEmbedUrl('https://www.youtube.com/shorts/dQw4w9WgXcQ'),
        'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?rel=0',
      );
      expect(
        externalVideoEmbedUrl('https://vimeo.com/76979871'),
        'https://player.vimeo.com/video/76979871',
      );
      expect(
        externalVideoEmbedUrl(
          'https://youtube.com.evil.test/watch?v=dQw4w9WgXcQ',
        ),
        isNull,
      );
      expect(externalVideoEmbedUrl('https://example.com/video'), isNull);
      expect(externalVideoEmbedUrl('http://youtu.be/dQw4w9WgXcQ'), isNull);
    });
  });

  group('row parsing', () {
    test('parses a full row, including numeric-string sizes', () {
      final PostAttachment att = PostAttachment.fromMap(<String, dynamic>{
        'id': 'a1',
        'post_id': 'p1',
        'owner_id': 'u1',
        'kind': 'file',
        'storage_path': 'u1/p1/x.pdf',
        'mime_type': 'application/pdf',
        'original_filename': 'ticket.pdf',
        'file_size_bytes': '2048',
        'display_order': 2,
        'created_at': '2026-11-24T10:00:00Z',
      });
      expect(att.kind, PostAttachmentKind.file);
      expect(att.fileSizeBytes, 2048);
      expect(att.displayOrder, 2);
      expect(att.fileName, 'ticket.pdf');
      expect(att.isUploaded, isTrue);
      expect(att.isEmbeddableVideo, isFalse);
    });

    test('insert payload keeps nulls out and links separate', () {
      const PostAttachment link = PostAttachment(
        postId: 'p1',
        ownerId: 'u1',
        kind: PostAttachmentKind.link,
        externalUrl: 'https://youtu.be/dQw4w9WgXcQ',
        displayOrder: 3,
      );
      final Map<String, dynamic> payload = link.toInsertMap();
      expect(payload['kind'], 'link');
      expect(payload['external_url'], 'https://youtu.be/dQw4w9WgXcQ');
      expect(payload.containsKey('storage_path'), isFalse);
      expect(payload.containsKey('mime_type'), isFalse);
      expect(payload['display_order'], 3);
      expect(link.isEmbeddableVideo, isTrue);
    });

    test('file name falls back to the storage tail', () {
      const PostAttachment att = PostAttachment(
        postId: 'p',
        ownerId: 'u',
        kind: PostAttachmentKind.image,
        storagePath: 'u/p/abc.png',
      );
      expect(att.fileName, 'abc.png');
    });
  });

  test('formatAttachmentSize is human and empty for unknown sizes', () {
    expect(formatAttachmentSize(null), '');
    expect(formatAttachmentSize(0), '');
    expect(formatAttachmentSize(900), '900 B');
    expect(formatAttachmentSize(2048), '2 KB');
    expect(formatAttachmentSize(5 * 1024 * 1024), '5.0 MB');
  });
}
