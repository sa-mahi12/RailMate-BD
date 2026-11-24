/// One attachment being composed (P42). Local bytes or an external link, plus
/// its explicit upload lifecycle. Never reports "Uploaded" until the Storage
/// upload AND the `post_attachments` row insert both succeeded.
library;

import '../media/board_attachment_picker.dart';
import '../media/post_attachment.dart';
import '../media/post_media.dart' show UploadState;

class ComposeAttachment {
  /// Local file (null for a link attachment).
  final PickedBoardFile? local;

  /// Validated external HTTPS URL (null for a file attachment).
  final String? externalUrl;

  /// Stable id for list keys / reorder animations.
  final String key;

  /// Current lifecycle state.
  UploadState state;

  /// Confirmed Storage path after a successful upload.
  String? remotePath;

  /// Persisted `post_attachments.id` after the row insert.
  String? attachmentId;

  /// Honest failure message (null unless [state] is failed).
  String? errorMessage;

  ComposeAttachment.file({
    required PickedBoardFile this.local,
    required this.key,
  }) : externalUrl = null,
       state = UploadState.local;

  ComposeAttachment.link({required String this.externalUrl, required this.key})
    : local = null,
      state = UploadState.local;

  bool get isLink => externalUrl != null;

  PostAttachmentKind get kind =>
      isLink ? PostAttachmentKind.link : attachmentKindForMime(local!.mimeType);

  String get filename => local?.filename ?? externalUrl ?? 'Link';

  String get mimeType => local?.mimeType ?? '';

  int get sizeBytes => local?.sizeBytes ?? 0;

  /// True when this attachment is fully persisted (uploaded + row inserted).
  bool get isStored =>
      state == UploadState.uploaded &&
      attachmentId != null &&
      attachmentId!.isNotEmpty;

  /// Short status line for the composer preview.
  String get statusLabel {
    if (isLink) return 'Link';
    switch (state) {
      case UploadState.local:
        return 'Ready to upload';
      case UploadState.uploading:
        return 'Uploading…';
      case UploadState.uploaded:
        return attachmentId == null ? 'Uploaded' : 'Uploaded';
      case UploadState.failed:
        return 'Upload failed';
    }
  }
}
