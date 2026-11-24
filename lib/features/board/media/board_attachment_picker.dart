/// P42 — pick + validate one board attachment before upload.
///
/// One seam for every supported source:
/// * [BoardPickSource.gallery] / [BoardPickSource.camera] → `image_picker`
/// * [BoardPickSource.video] / [BoardPickSource.document] → `file_picker`
///
/// Nothing here uploads: validation runs first, so an oversize or
/// non-allowlisted pick never creates a Storage object or an attachment row.
/// Tests inject their own [PickBoardAttachment] and never touch a platform
/// channel.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'post_attachment.dart';

/// Where a pick comes from (drives the picker + accepted types).
enum BoardPickSource { gallery, camera, video, document }

/// One picked file held in memory until the post row exists.
class PickedBoardFile {
  final String filename;
  final String mimeType;
  final List<int> bytes;

  const PickedBoardFile({
    required this.filename,
    required this.mimeType,
    required this.bytes,
  });

  int get sizeBytes => bytes.length;

  PostAttachmentKind get kind => attachmentKindForMime(mimeType);
}

/// Thrown when the picked file cannot be published (size/MIME/empty).
class BoardAttachmentRejectedException implements Exception {
  final String message;

  const BoardAttachmentRejectedException(this.message);

  @override
  String toString() => 'BoardAttachmentRejectedException($message)';
}

/// Injected picker. Returns null on user cancel (a no-op, never an error).
typedef PickBoardAttachment = Future<PickedBoardFile?> Function(
  BoardPickSource source,
);

/// Maps a filename extension onto the allowlisted MIME type it implies.
///
/// Android pickers frequently report `application/octet-stream`; the extension
/// is a better signal and the bucket checks the declared type, so we resolve a
/// real MIME before upload. Unknown extensions stay octet-stream and are
/// rejected by [validatePickedAttachment].
String mimeTypeForFilename(String filename) {
  final String name = filename.trim().toLowerCase();
  final int dot = name.lastIndexOf('.');
  final String ext = dot < 0 ? '' : name.substring(dot + 1);
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'gif':
      return 'image/gif';
    case 'mp4':
    case 'm4v':
      return 'video/mp4';
    case 'webm':
      return 'video/webm';
    case 'mp3':
      return 'audio/mpeg';
    case 'm4a':
      return 'audio/mp4';
    case 'pdf':
      return 'application/pdf';
    case 'txt':
      return 'text/plain';
    case 'csv':
      return 'text/csv';
    case 'zip':
      return 'application/zip';
    case 'doc':
      return 'application/msword';
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'ppt':
      return 'application/vnd.ms-powerpoint';
    case 'pptx':
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    default:
      return 'application/octet-stream';
  }
}

/// Validates one pick without uploading. Returns null when acceptable, else
/// the honest reason shown to the author.
String? validatePickedAttachment(PickedBoardFile file) {
  if (file.bytes.isEmpty) return 'That file had no data. Pick another file.';
  if (file.bytes.length > postAttachmentMaxBytes) {
    final String mb = (file.bytes.length / (1024 * 1024)).toStringAsFixed(1);
    return 'File too large ($mb MB). Keep each file under 25 MB.';
  }
  final String mime = file.mimeType.trim().toLowerCase();
  if (!postAttachmentAllowedMimes.contains(mime)) {
    return 'That file type ($mime) is not supported. '
        'Use an image, MP4/WebM video, audio, PDF, text, ZIP or Office file.';
  }
  return null;
}

/// Safe display filename (path stripped, control characters removed, bounded).
String sanitizeAttachmentFilename(String raw) {
  final String base = raw.split(RegExp(r'[/\\]')).last.trim();
  final String cleaned = base.replaceAll(RegExp(r'[\x00-\x1F]'), '');
  if (cleaned.isEmpty) return 'attachment';
  return cleaned.length <= 200 ? cleaned : cleaned.substring(0, 200);
}

/// Production picker used by the composer.
///
/// Images go through `image_picker` (camera or gallery); video and documents go
/// through `file_picker` with `withData: true` so the upload seam receives
/// bytes. Cancel returns null; permission failures surface as the platform
/// exception and are mapped by the composer into a plain-language notice.
Future<PickedBoardFile?> pickBoardAttachment(BoardPickSource source) async {
  switch (source) {
    case BoardPickSource.gallery:
    case BoardPickSource.camera:
      final XFile? file = await ImagePicker().pickImage(
        source: source == BoardPickSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 2400,
      );
      if (file == null) return null;
      final Uint8List data = await file.readAsBytes();
      final String name = sanitizeAttachmentFilename(file.name);
      final String mime = (file.mimeType ?? '').trim().isNotEmpty
          ? file.mimeType!.trim().toLowerCase()
          : mimeTypeForFilename(name);
      return PickedBoardFile(filename: name, mimeType: mime, bytes: data);

    case BoardPickSource.video:
      final PlatformFile? file = await FilePicker.pickFile(
        type: FileType.video,
      );
      return _fromPickedFile(file);

    case BoardPickSource.document:
      final List<PlatformFile> files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>[
          'pdf',
          'txt',
          'csv',
          'zip',
          'doc',
          'docx',
          'ppt',
          'pptx',
        ],
      );
      return _fromPickedFile(files.isEmpty ? null : files.first);
  }
}

/// Reads one picked file after a size pre-check, so an oversize file is
/// rejected WITHOUT loading 25+ MB into memory (low-RAM devices included).
Future<PickedBoardFile?> _fromPickedFile(PlatformFile? file) async {
  if (file == null) return null;
  final String name = sanitizeAttachmentFilename(file.name);
  final String mime = mimeTypeForFilename(name);
  final int? declared = file.lengthSync();
  if (declared != null && declared > postAttachmentMaxBytes) {
    throw BoardAttachmentRejectedException(
      'File too large (${(declared / (1024 * 1024)).toStringAsFixed(1)} MB). '
      'Keep each file under 25 MB.',
    );
  }
  final Uint8List data;
  try {
    data = await file.readAsBytes();
  } catch (_) {
    throw const BoardAttachmentRejectedException(
      "Couldn't read that file. Pick it again.",
    );
  }
  return PickedBoardFile(filename: name, mimeType: mime, bytes: data);
}
