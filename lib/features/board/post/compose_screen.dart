import 'package:flutter/material.dart';

import '../media/board_image_picker.dart';
import '../media/post_media.dart';
import 'post.dart';
import 'post_compose_state.dart';

/// Compose screen for one Journey Board post (packet A07, R-13).
///
/// Visual tokens per `design/UI_VISUAL_SPEC.md`: page bg `#F4F7F9`, teal
/// header block (`#0E5A66`) with rounded bottom corners, white cards
/// (radius 16), teal primary button (radius 12), danger red `#E5484D`
/// for the orphan-delete action.
///
/// Image bytes arrive through [pickImageBytes] (method channel-agnostic
/// picker callback owned by the caller); this screen never touches
/// platform channels or picker packages directly. All server effects come
/// from the injected [createPost]/[uploadBytes]/[deletePost] functions via
/// [compose]; there are no Supabase calls in this slice.
class BoardComposeScreen extends StatefulWidget {
  /// Compose state (owned by the caller).
  final PostComposeState compose;

  /// Current author uid (first segment of the owned storage path).
  final String userId;

  /// Supplies the random object-name segment for the image path.
  final String Function() newUuid;

  /// Injected row insert (hosted Supabase in production, fake in tests).
  final CreatePostRow createPost;

  /// Injected byte upload (hosted Storage in production, fake in tests).
  final UploadBytes uploadBytes;

  /// Injected row delete for orphan cleanup.
  final DeletePostRow deletePost;

  /// Injected object delete for best-effort orphan cleanup (optional).
  final DeleteObject? deleteObject;

  /// Injected image-link update: persists the uploaded object path onto the
  /// post row (`image_path`) after a successful upload (optional until the
  /// coordinator wires it — without it photos upload but never display).
  final UpdatePostImage? updatePostImage;

  /// Method channel-agnostic image picker: returns picked bytes or null
  /// when the user cancels. Null hides the attach button.
  final Future<List<int>?> Function()? pickImageBytes;

  /// Called once a full submit (row, plus image if attached) succeeds.
  final VoidCallback? onDone;

  const BoardComposeScreen({
    super.key,
    required this.compose,
    required this.userId,
    required this.newUuid,
    required this.createPost,
    required this.uploadBytes,
    required this.deletePost,
    this.deleteObject,
    this.updatePostImage,
    this.pickImageBytes,
    this.onDone,
  });

  @override
  State<BoardComposeScreen> createState() => _BoardComposeScreenState();
}

class _BoardComposeScreenState extends State<BoardComposeScreen> {
  late final TextEditingController _body;

  @override
  void initState() {
    super.initState();
    _body = TextEditingController(text: widget.compose.body);
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  /// Runs the injected picker and attaches validated bytes.
  ///
  /// Cancel (null/empty pick) is a silent no-op. Permission denial shows an
  /// honest settings message; rejected files show the validation reason;
  /// unexpected picker failures show a retry SnackBar. Bytes are attached
  /// only after [validateBoardImageBytes] passes, so oversize/non-image
  /// picks never reach the F11 upload seam.
  Future<void> _pick() async {
    final pick = widget.pickImageBytes;
    if (pick == null) return;
    late final List<int>? bytes;
    try {
      bytes = await pick();
    } on BoardImageDeniedException catch (e) {
      if (mounted) _showPickError(e.message, retry: false);
      return;
    } on BoardImageRejectedException catch (e) {
      if (mounted) _showPickError(e.message, retry: true);
      return;
    } catch (e) {
      if (mounted) {
        _showPickError(
          'Could not pick the photo ($e). Retry or continue without a photo.',
          retry: true,
        );
      }
      return;
    }
    if (bytes == null || bytes.isEmpty) return;
    final validation = validateBoardImageBytes(bytes);
    if (validation != null) {
      if (mounted) _showPickError(validation, retry: true);
      return;
    }
    widget.compose.attachImageBytes(bytes);
  }

  /// Honest picker-failure notice. Denials point at app settings (retry
  /// cannot help); other failures offer a Retry action re-running [_pick].
  void _showPickError(String message, {required bool retry}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: retry ? SnackBarAction(label: 'Retry', onPressed: _pick) : null,
      ),
    );
  }

  Future<void> _submit() async {
    final ok = await widget.compose.submit(
      userId: widget.userId,
      newUuid: widget.newUuid,
      createPost: widget.createPost,
      uploadBytes: widget.uploadBytes,
      updatePostImage: widget.updatePostImage,
    );
    if (ok && mounted) widget.onDone?.call();
  }

  String _uploadLabel(UploadState state) {
    switch (state) {
      case UploadState.local:
        return 'Preview only — not uploaded';
      case UploadState.uploading:
        return 'Uploading…';
      case UploadState.uploaded:
        return 'Uploaded';
      case UploadState.failed:
        return 'Upload failed';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.compose,
      builder: (context, _) {
        final compose = widget.compose;
        return Scaffold(
          backgroundColor: const Color(0xFFF4F7F9),
          body: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 48, 16, 20),
                decoration: const BoxDecoration(
                  color: Color(0xFF0E5A66),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.chevron_left, color: Colors.white),
                    ),
                    const Text(
                      'New post',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _body,
                            maxLines: 6,
                            maxLength: Post.maxBodyLength,
                            onChanged: compose.setBody,
                            decoration: InputDecoration(
                              hintText: 'Share a station tip…',
                              errorText: compose.bodyError,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (widget.pickImageBytes != null)
                            OutlinedButton.icon(
                              onPressed: compose.submitting ? null : _pick,
                              icon: const Icon(Icons.photo_outlined),
                              label: const Text('Attach photo'),
                            ),
                          if (compose.media.hasBytes) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(
                                  Icons.image_outlined,
                                  color: Color(0xFF0E5A66),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${compose.media.bytes!.length} bytes · '
                                    '${_uploadLabel(compose.media.state)}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Remove photo',
                                  onPressed: compose.submitting
                                      ? null
                                      : compose.clearImage,
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ],
                          if (compose.errorMessage != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              compose.errorMessage!,
                              style: const TextStyle(
                                color: Color(0xFFE5484D),
                                fontSize: 13,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0E5A66),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: compose.submitting ? null : _submit,
                            child: compose.submitting
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'Post',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                          if (compose.hasOrphan) ...[
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFE5484D),
                              ),
                              onPressed: () => compose.cleanupOrphan(
                                deletePost: widget.deletePost,
                                deleteObject: widget.deleteObject,
                              ),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Delete post (photo failed)'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
