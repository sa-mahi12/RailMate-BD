/// P42 — renders one Journey Board attachment.
///
/// Format matrix (honest per type):
/// * image → responsive network image (Storage public URL)
/// * uploaded video (MP4/WebM) → in-app `video_player` with controls
/// * allowlisted provider link (YouTube/Vimeo) → in-app WebView embed loaded
///   only on tap, plus "Open in browser"
/// * generic HTTPS link → safe host card + external open
/// * PDF → preview/open + download
/// * everything else → filename/type/size card + download
///
/// No arbitrary URL ever reaches an iframe/WebView automatically: provider
/// links are allowlisted by [externalVideoEmbedUrl], and every network failure
/// degrades to a plain, honest fallback instead of a broken player.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'post_attachment.dart';

/// Resolves a stored object path into a public display URL.
typedef ResolveAttachmentUrl = String? Function(String storagePath);

/// Opens an external HTTPS URL (url_launcher in production).
typedef OpenExternalUrl = Future<bool> Function(String url);

/// Formats one attachment; returns a compact row for unsupported types.
class BoardAttachmentView extends StatelessWidget {
  final PostAttachment attachment;

  /// Storage → public URL resolver (null hides uploaded media honestly).
  final ResolveAttachmentUrl? resolveUrl;

  /// External opener (null keeps buttons disabled).
  final OpenExternalUrl? openUrl;

  /// Test seam: when false, provider embeds never construct a WebView.
  final bool allowEmbeds;

  const BoardAttachmentView({
    super.key,
    required this.attachment,
    this.resolveUrl,
    this.openUrl,
    this.allowEmbeds = true,
  });

  String? get _storageUrl {
    final String? path = attachment.storagePath;
    if (path == null || path.isEmpty || resolveUrl == null) return null;
    try {
      return resolveUrl!(path);
    } catch (_) {
      return null;
    }
  }

  Future<void> _open(String url) async {
    final OpenExternalUrl? opener = openUrl;
    if (opener == null) return;
    try {
      await opener(url);
    } catch (_) {
      // A failed launch must not crash a feed card.
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (attachment.kind) {
      case PostAttachmentKind.image:
        return _image(context);
      case PostAttachmentKind.video:
        return _uploadedVideo(context);
      case PostAttachmentKind.link:
        return _link(context);
      case PostAttachmentKind.file:
        return _file(context);
    }
  }

  Widget _image(BuildContext context) {
    final String? url = _storageUrl;
    if (url == null) return _missing('Photo could not be loaded.');
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        width: double.infinity,
        fit: BoxFit.cover,
        semanticLabel: attachment.fileName,
        loadingBuilder:
            (BuildContext context, Widget child, ImageChunkEvent? p) {
              if (p == null) return child;
              return const SizedBox(
                height: 140,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            },
        errorBuilder: (_, _, _) => _missing('Photo could not be loaded.'),
      ),
    );
  }

  Widget _uploadedVideo(BuildContext context) {
    final String? url = _storageUrl;
    if (url == null) return _missing('Video could not be loaded.');
    return BoardNetworkVideo(
      url: url,
      label: attachment.fileName,
      onOpenExternally: () => _open(url),
    );
  }

  Widget _link(BuildContext context) {
    final String url = attachment.externalUrl ?? '';
    final String? embed = externalVideoEmbedUrl(url);
    if (embed != null && allowEmbeds) {
      return BoardProviderEmbed(
        embedUrl: embed,
        originalUrl: url,
        title: externalVideoProviderFor(url) == ExternalVideoProvider.vimeo
            ? 'Vimeo video'
            : 'YouTube video',
        onOpenExternally: () => _open(url),
      );
    }
    final Uri? uri = Uri.tryParse(url);
    final String host = (uri?.host ?? '').trim();
    return _card(
      icon: Icons.link,
      title: host.isEmpty ? 'External link' : host,
      subtitle: url,
      actionLabel: 'Open link',
      onAction: url.isEmpty ? null : () => _open(url),
    );
  }

  Widget _file(BuildContext context) {
    final String mime = (attachment.mimeType ?? '').toLowerCase();
    final bool isPdf = mime == 'application/pdf';
    final String? url = _storageUrl;
    final String size = formatAttachmentSize(attachment.fileSizeBytes);
    return _card(
      icon: isPdf
          ? Icons.picture_as_pdf_outlined
          : Icons.insert_drive_file_outlined,
      title: attachment.fileName,
      subtitle: <String>[
        if (isPdf) 'PDF document' else (mime.isEmpty ? 'File' : mime),
        if (size.isNotEmpty) size,
      ].join(' · '),
      actionLabel: url == null ? null : (isPdf ? 'Open PDF' : 'Download'),
      onAction: url == null ? null : () => _open(url),
      secondaryLabel: url == null || !isPdf ? null : 'Download',
      onSecondary: url == null || !isPdf ? null : () => _open(url),
    );
  }

  Widget _card({
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
    String? secondaryLabel,
    VoidCallback? onSecondary,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1E8ED)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: const Color(0xFF0E5A66)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF5B6B73),
                    ),
                  ),
              ],
            ),
          ),
          if (secondaryLabel != null && onSecondary != null)
            TextButton(
              onPressed: onSecondary,
              child: Text(secondaryLabel, style: const TextStyle(fontSize: 12)),
            ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel, style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _missing(String message) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF4F7F9),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: <Widget>[
        const Icon(Icons.broken_image_outlined, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );
}

/// In-app player for an uploaded MP4/WebM. A failed initialise shows the
/// reason and an "Open externally" escape hatch — never a frozen black box.
class BoardNetworkVideo extends StatefulWidget {
  final String url;
  final String label;
  final VoidCallback? onOpenExternally;

  const BoardNetworkVideo({
    super.key,
    required this.url,
    required this.label,
    this.onOpenExternally,
  });

  @override
  State<BoardNetworkVideo> createState() => _BoardNetworkVideoState();
}

class _BoardNetworkVideoState extends State<BoardNetworkVideo> {
  VideoPlayerController? _controller;
  String? _error;
  bool _initialising = false;

  Future<void> _init() async {
    if (_initialising || _controller != null) return;
    setState(() {
      _initialising = true;
      _error = null;
    });
    final VideoPlayerController controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
    );
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(false);
      setState(() {
        _controller = controller;
        _initialising = false;
      });
    } catch (_) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _error = "This video couldn't play in the app.";
        _initialising = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? controller = _controller;
    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F7F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.videocam_off_outlined, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${widget.label} — $_error',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            if (widget.onOpenExternally != null)
              TextButton(
                onPressed: widget.onOpenExternally,
                child: const Text('Open', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
      );
    }
    if (controller == null) {
      return InkWell(
        onTap: _init,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 140,
          decoration: BoxDecoration(
            color: const Color(0xFF0E5A66),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: _initialising
                ? const CircularProgressIndicator(color: Colors.white)
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.play_circle_outline, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Play video', style: TextStyle(color: Colors.white)),
                    ],
                  ),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: <Widget>[
          AspectRatio(
            aspectRatio: controller.value.aspectRatio == 0
                ? 16 / 9
                : controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
          VideoProgressIndicator(controller, allowScrubbing: true),
          Row(
            children: <Widget>[
              IconButton(
                tooltip: controller.value.isPlaying ? 'Pause' : 'Play',
                onPressed: () {
                  setState(() {
                    controller.value.isPlaying
                        ? controller.pause()
                        : controller.play();
                  });
                },
                icon: Icon(
                  controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                ),
              ),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// In-app provider embed (YouTube/Vimeo) loaded only after an explicit tap.
///
/// The embed URL is built by [externalVideoEmbedUrl] from an allowlisted
/// provider + validated id; the raw user URL is never passed to the WebView.
class BoardProviderEmbed extends StatefulWidget {
  final String embedUrl;
  final String originalUrl;
  final String title;
  final VoidCallback? onOpenExternally;

  const BoardProviderEmbed({
    super.key,
    required this.embedUrl,
    required this.originalUrl,
    required this.title,
    this.onOpenExternally,
  });

  @override
  State<BoardProviderEmbed> createState() => _BoardProviderEmbedState();
}

class _BoardProviderEmbedState extends State<BoardProviderEmbed> {
  WebViewController? _controller;
  bool _failed = false;

  void _load() {
    try {
      final WebViewController controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF000000))
        ..loadRequest(Uri.parse(widget.embedUrl));
      setState(() => _controller = controller);
    } catch (_) {
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Container(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            const Icon(Icons.videocam_off_outlined, size: 16),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                "This video can't be embedded here.",
                style: TextStyle(fontSize: 12),
              ),
            ),
            if (widget.onOpenExternally != null)
              TextButton(
                onPressed: widget.onOpenExternally,
                child: const Text('Open', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
      );
    }
    final WebViewController? controller = _controller;
    if (controller == null) {
      return InkWell(
        onTap: _load,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 140,
          decoration: BoxDecoration(
            color: const Color(0xFF0E5A66),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.play_circle_outline, color: Colors.white),
                const SizedBox(height: 6),
                Text(
                  'Play ${widget.title}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Loads the provider player on tap',
                  style: TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: WebViewWidget(controller: controller),
      ),
    );
  }
}

/// Default external opener (url_launcher, external application).
Future<bool> openExternalHttps(String url) async {
  final Uri uri = Uri.parse(url);
  if (uri.scheme.toLowerCase() != 'https') return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
