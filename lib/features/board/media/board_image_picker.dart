library;

/// F12 board image pick → validate (Journey Board photo attach).
///
/// Flow: [pickBoardImageBytes] (gallery/camera) feeds picked bytes into the
/// existing compose seam (`PostComposeState.attachImageBytes` via the
/// `pickImageBytes` callback on [BoardComposeScreen]); the actual Storage
/// upload + row link still runs inside `PostComposeState.submit` through the
/// injected `uploadBytes` / `updatePostImage` closures. Nothing here touches
/// Supabase directly — upload stays in the F11 seam, so a local preview can
/// never be reported as "posted".
///
/// Validation contract: images only, size cap [boardMaxImageBytes] (5 MB,
/// enforced BEFORE any upload attempt so oversize files fail fast with an
/// honest message instead of a wasted upload). Cancel (null pick) is a
/// no-op, never an error.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Size cap for one board photo pick, enforced before upload.
///
/// 5 MiB is generous for a phone photo preview while keeping Storage + row
/// churn bounded. Stated here (not buried) so the UI error can quote it.
const int boardMaxImageBytes = 5 * 1024 * 1024;

/// Thrown when the OS denied photo/camera access.
///
/// Honest terminal state for this attempt: the UI must explain the denial
/// (open app settings) rather than show a generic error or a retry loop
/// that can never succeed.
class BoardImageDeniedException implements Exception {
  final String message;

  const BoardImageDeniedException([
    this.message =
        'Photo access denied. Allow access in app settings, then try again.',
  ]);

  @override
  String toString() => 'BoardImageDeniedException($message)';
}

/// Thrown when the picked file is not an acceptable photo (wrong mime,
/// unsupported bytes, over [boardMaxImageBytes]).
///
/// Carries the human-readable [message] the UI shows; the pick is rejected
/// BEFORE any upload, so no Storage object exists for rejected picks.
class BoardImageRejectedException implements Exception {
  final String message;

  const BoardImageRejectedException(this.message);

  @override
  String toString() => 'BoardImageRejectedException($message)';
}

/// One raw platform pick: bytes plus the platform-reported mime (if any).
class RawPickedImage {
  final List<int> bytes;
  final String? mime;

  const RawPickedImage({required this.bytes, this.mime});
}

/// Injected platform pick: returns the raw pick, or null when the user
/// cancels. Production wiring passes [pickBoardRawImage]; tests inject a
/// fake (no platform channels in hermetic tests).
typedef RawImagePick = Future<RawPickedImage?> Function({
  required bool fromCamera,
});

/// Validates picked bytes WITHOUT uploading. Returns null when acceptable,
/// else the honest human-readable reason.
///
/// Checks, in order: non-empty, size cap, image mime hint (when supplied),
/// supported magic bytes (JPEG/PNG/WEBP/GIF/HEIC family). Pure Dart.
String? validateBoardImageBytes(List<int> bytes, {String? mimeHint}) {
  if (bytes.isEmpty) {
    return 'That file had no data. Pick another photo.';
  }
  if (bytes.length > boardMaxImageBytes) {
    final mb = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
    return 'Photo too large ($mb MB). Keep it under 5 MB.';
  }
  final mime = (mimeHint ?? '').trim().toLowerCase();
  if (mime.isNotEmpty && !mime.startsWith('image/')) {
    return 'That file is not an image ($mimeHint). Pick a photo.';
  }
  if (_sniffImageExt(bytes) == null) {
    return 'That file is not a supported photo '
        '(JPEG, PNG, WEBP, GIF or HEIC). Pick another photo.';
  }
  return null;
}

/// Detects the image container extension for picked bytes.
///
/// Returns `jpg`, `png`, `webp`, `gif` or `heic`. Throws
/// [BoardImageRejectedException] when the bytes are not a supported photo.
/// (Submit currently reserves `<uid>/<uuid>.jpg`; the bucket policy only
/// constrains the `<uid>/` prefix, not the extension, so the default stays
/// valid — thread this through when the coordinator wants exact extensions.)
String detectBoardImageExt(List<int> bytes, {String? mimeHint}) {
  final ext = _sniffImageExt(bytes);
  if (ext == null) {
    throw BoardImageRejectedException(
      validateBoardImageBytes(bytes, mimeHint: mimeHint) ??
          'That file is not a supported photo.',
    );
  }
  return ext;
}

/// Picks one photo's bytes for the board composer.
///
/// - [fromCamera] false = gallery, true = camera.
/// - Returns null when the user cancels (no-op for the caller, NOT an
///   error — the caller must not show any message).
/// - Throws [BoardImageDeniedException] on OS permission denial.
/// - Throws [BoardImageRejectedException] on oversize/non-image picks.
/// - Any other throw (picker crash, I/O) propagates so the caller can
///   offer retry; no local bytes are attached on any failure path.
Future<List<int>?> pickBoardImageBytes({
  required bool fromCamera,
  required RawImagePick rawPick,
}) async {
  late final RawPickedImage? raw;
  try {
    raw = await rawPick(fromCamera: fromCamera);
  } catch (e) {
    if (_looksLikePermissionDenial(e)) {
      throw const BoardImageDeniedException();
    }
    rethrow;
  }
  if (raw == null) return null;
  final error = validateBoardImageBytes(raw.bytes, mimeHint: raw.mime);
  if (error != null) throw BoardImageRejectedException(error);
  return List<int>.unmodifiable(raw.bytes);
}

/// Production platform pick via `image_picker` (F02 dependency).
///
/// Returns null on user cancel. Permission denial surfaces as the
/// platform's throw and is mapped to [BoardImageDeniedException] by
/// [pickBoardImageBytes]. No compression here (documented later step —
/// same note as `PostMediaAttachment`); the 5 MB cap guards uploads.
Future<RawPickedImage?> pickBoardRawImage({required bool fromCamera}) async {
  final XFile? file = await ImagePicker().pickImage(
    source: fromCamera ? ImageSource.camera : ImageSource.gallery,
  );
  if (file == null) return null;
  final Uint8List data = await file.readAsBytes();
  return RawPickedImage(bytes: data, mime: file.mimeType);
}

/// Gallery closure matching the `pickImageBytes` seam on
/// [BoardComposeScreen] (coordinator wires: `pickImageBytes:
/// boardGalleryPicker()` — or via [showBoardImageSourceAction] for a
/// gallery/camera choice sheet).
Future<List<int>?> Function() boardGalleryPicker() =>
    () => pickBoardImageBytes(
      fromCamera: false,
      rawPick: ({required bool fromCamera}) =>
          pickBoardRawImage(fromCamera: fromCamera),
    );

/// Camera closure matching the `pickImageBytes` seam on
/// [BoardComposeScreen].
Future<List<int>?> Function() boardCameraPicker() =>
    () => pickBoardImageBytes(
      fromCamera: true,
      rawPick: ({required bool fromCamera}) =>
          pickBoardRawImage(fromCamera: fromCamera),
    );

/// Gallery/camera choice sheet for the composer.
///
/// Returns the picked-bytes closure for the chosen source, or null when the
/// user dismisses the sheet (cancel = no-op). Coordinator-owned host calls
/// this and passes the result as `pickImageBytes`.
Future<Future<List<int>?> Function()?> showBoardImageSourceAction(
  BuildContext context,
) async {
  final bool? useCamera = await showModalBottomSheet<bool>(
    context: context,
    builder: (BuildContext ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.of(ctx).pop(false),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    ),
  );
  if (useCamera == null) return null;
  if (useCamera) return boardCameraPicker();
  return boardGalleryPicker();
}

/// Best-effort delete of one Storage object. Returns true when the delete
/// was attempted without throwing; false when there was nothing to do or
/// the call threw (object may not exist — e.g. the upload threw first).
/// Never throws: orphan cleanup must not fail the screen.
Future<bool> deleteBoardObjectBestEffort(
  String? path,
  Future<void> Function(String path)? deleteObject,
) async {
  if (path == null || path.isEmpty || deleteObject == null) return false;
  try {
    await deleteObject(path);
    return true;
  } catch (_) {
    return false;
  }
}

/// True when [error] looks like an OS permission denial (platform code or
/// message mentioning permission/denied). Conservative on purpose: only
/// genuine denial signals map to [BoardImageDeniedException]; everything
/// else stays retryable.
bool _looksLikePermissionDenial(Object error) {
  if (error is PlatformException) {
    final code = error.code.toLowerCase();
    if (code.contains('permission') || code.contains('denied')) return true;
  }
  final text = error.toString().toLowerCase();
  return text.contains('permission denied') ||
      text.contains('permission_denied') ||
      text.contains('photo access denied') ||
      text.contains('camera access denied');
}

/// Sniffs the image container. Returns the extension or null when the
/// bytes are not a supported photo.
String? _sniffImageExt(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'jpg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A) {
    return 'png';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 && // R
      bytes[1] == 0x49 && // I
      bytes[2] == 0x46 && // F
      bytes[3] == 0x46 && // F
      bytes[8] == 0x57 && // W
      bytes[9] == 0x45 && // E
      bytes[10] == 0x42 && // B
      bytes[11] == 0x50) {
    // P
    return 'webp';
  }
  if (bytes.length >= 6 &&
      bytes[0] == 0x47 && // G
      bytes[1] == 0x49 && // I
      bytes[2] == 0x46 && // F
      bytes[3] == 0x38 && // 8
      (bytes[4] == 0x37 || bytes[4] == 0x39) && // 7|9
      bytes[5] == 0x61) {
    // a
    return 'gif';
  }
  // HEIC/HEIF: `ftyp` box at offset 4 with a HEIC-family brand.
  if (bytes.length >= 12 &&
      bytes[4] == 0x66 && // f
      bytes[5] == 0x74 && // t
      bytes[6] == 0x79 && // y
      bytes[7] == 0x70) {
    // p
    final brand = String.fromCharCodes(bytes.sublist(8, 12)).toLowerCase();
    if (brand == 'heic' ||
        brand == 'heix' ||
        brand == 'hevc' ||
        brand == 'hevx' ||
        brand == 'heim' ||
        brand == 'heis' ||
        brand == 'mif1' ||
        brand == 'msf1') {
      return 'heic';
    }
  }
  return null;
}
