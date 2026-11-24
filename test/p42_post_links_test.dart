import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/board/share/post_links.dart';

void main() {
  group('canonical links', () {
    const String id = '3f1f8f9e-2b1a-4c3d-9e8f-0123456789ab';

    test('post permalink is the deployed Pages URL', () {
      expect(
        postPermalink(id),
        'https://sa-mahi12.github.io/RailMate-BD/post.html?id=$id',
      );
    });

    test('profile permalink encodes the id', () {
      expect(
        profilePermalink('a b'),
        'https://sa-mahi12.github.io/RailMate-BD/profile.html?id=a+b',
      );
    });

    test('in-app deep link uses the app scheme', () {
      expect(postDeepLink(id), 'railmatebd://post/$id');
    });

    test('share text carries a bounded body and always the URL', () {
      final String text = postShareText(body: 'x' * 400, postId: id);
      expect(text.endsWith(postPermalink(id)), isTrue);
      expect(text.length, lessThan(400));
      expect(postShareText(body: '   ', postId: id), postPermalink(id));
    });
  });

  group('parsePostLink', () {
    const String id = '3f1f8f9e-2b1a-4c3d-9e8f-0123456789ab';

    test('accepts both custom schemes', () {
      expect(parsePostLink(Uri.parse('railmatebd://post/$id')), id);
      expect(parsePostLink(Uri.parse('railmate://post/$id')), id);
    });

    test('accepts the public https permalink', () {
      expect(
        parsePostLink(
          Uri.parse('https://sa-mahi12.github.io/RailMate-BD/post.html?id=$id'),
        ),
        id,
      );
    });

    test('rejects wrong hosts, ids and auth links', () {
      expect(
        parsePostLink(
          Uri.parse('https://evil.test/RailMate-BD/post.html?id=$id'),
        ),
        isNull,
      );
      expect(parsePostLink(Uri.parse('railmatebd://post/not-a-uuid')), isNull);
      expect(
        parsePostLink(
          Uri.parse('railmatebd://auth/reset-password#access_token=x'),
        ),
        isNull,
      );
      expect(parsePostLink(null), isNull);
    });
  });

  test('parseProfileLink accepts app and web shapes', () {
    const String id = '3f1f8f9e-2b1a-4c3d-9e8f-0123456789ab';
    expect(parseProfileLink(Uri.parse('railmatebd://profile/$id')), id);
    expect(
      parseProfileLink(
        Uri.parse(
          'https://sa-mahi12.github.io/RailMate-BD/profile.html?id=$id',
        ),
      ),
      id,
    );
    expect(parseProfileLink(Uri.parse('railmatebd://post/$id')), isNull);
  });

  test('isUuid is strict', () {
    expect(isUuid('3f1f8f9e-2b1a-4c3d-9e8f-0123456789ab'), isTrue);
    expect(isUuid('3F1F8F9E-2B1A-4C3D-9E8F-0123456789AB'), isFalse);
    expect(isUuid(''), isFalse);
  });
}
