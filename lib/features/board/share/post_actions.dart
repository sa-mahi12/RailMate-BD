/// Share/copy actions for Journey Board posts (P42).
///
/// One place builds the shared payload so the native sheet, the clipboard and
/// the public website always advertise the same canonical URL. Nothing here
/// writes to the backend: sharing is a local, user-initiated action.
library;

import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'post_links.dart';

/// Opens the native share sheet with the post body and its permanent link.
Future<void> shareBoardPost({
  required String body,
  required String postId,
}) async {
  await SharePlus.instance.share(
    ShareParams(
      text: postShareText(body: body, postId: postId),
    ),
  );
}

/// Copies the canonical post URL and reports success to the caller.
Future<bool> copyBoardPostLink(String postId) async {
  try {
    await Clipboard.setData(ClipboardData(text: postPermalink(postId)));
    return true;
  } catch (_) {
    return false;
  }
}
