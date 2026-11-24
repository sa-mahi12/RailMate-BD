import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/board/post/post.dart';
import 'package:railmate_bd/features/board/profile/public_profile.dart';

void main() {
  group('Post parsing', () {
    test('reads embedded attachments in display order', () {
      final Post post = Post.fromMap(<String, dynamic>{
        'id': 'post-1',
        'user_id': 'user-1',
        'body': 'Two photos and a link',
        'image_path': null,
        'created_at': '2026-11-24T09:00:00Z',
        'post_attachments': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'b',
            'post_id': 'post-1',
            'owner_id': 'user-1',
            'kind': 'link',
            'external_url': 'https://vimeo.com/76979871',
            'display_order': 2,
          },
          <String, dynamic>{
            'id': 'a',
            'post_id': 'post-1',
            'owner_id': 'user-1',
            'kind': 'image',
            'storage_path': 'user-1/post-1/a.jpg',
            'mime_type': 'image/jpeg',
            'display_order': 0,
          },
        ],
      });
      expect(post.attachments.length, 2);
      expect(post.attachments.first.id, 'a');
      expect(post.attachments.last.isEmbeddableVideo, isTrue);
      expect(post.author, isNull);
    });

    test('legacy rows keep working with no attachments', () {
      final Post post = Post.fromMap(<String, dynamic>{
        'id': 'post-2',
        'user_id': 'user-2',
        'body': 'Old photo post',
        'image_path': 'user-2/post-2/old.jpg',
        'created_at': '2026-10-01T09:00:00Z',
      });
      expect(post.attachments, isEmpty);
      expect(post.imagePath, 'user-2/post-2/old.jpg');
      expect(post.author, isNull);
    });

    test('withAuthor/withImage preserve attachments', () {
      final Post post = Post.draft(
        userId: 'u',
        body: 'hi',
      ).withImage('u/p/x.jpg');
      expect(post.imagePath, 'u/p/x.jpg');
      expect(post.attachments, isEmpty);
      final Post withAuthor = post.withAuthor(
        const PublicProfile(id: 'u', username: 'sam', displayName: 'Sam'),
      );
      expect(withAuthor.author?.username, 'sam');
      expect(withAuthor.imagePath, 'u/p/x.jpg');
    });
  });

  group('PublicProfile', () {
    test('parses only the public card fields', () {
      final PublicProfile card = PublicProfile.fromMap(<String, dynamic>{
        'id': 'user-1',
        'username': 'sam',
        'display_name': 'Sam Mahi',
        'joined_at': '2026-09-01T00:00:00Z',
        'post_count': 4,
        // Fields that must never be read even if a payload carries them.
        'email': 'leak@example.com',
        'phone': '+880000000000',
        'telegram_user_id': 42,
      });
      expect(card.id, 'user-1');
      expect(card.username, 'sam');
      expect(card.postCount, 4);
      expect(card.label, 'Sam Mahi');
      expect(card.identityLine, 'Sam Mahi · @sam');
      expect(card.initials, 'SM');
    });

    test('degrades honestly without a display name', () {
      const PublicProfile card = PublicProfile(id: 'u', username: 'sam');
      expect(card.label, '@sam');
      expect(card.identityLine, '@sam');
      const PublicProfile empty = PublicProfile(id: 'u');
      expect(empty.label, 'Traveller');
      expect(empty.handle, isNull);
      expect(empty.initials, '?');
    });
  });
}
