import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'station_guide.dart';

/// F15: interactive station guide rendered through a Flutter WebView.
///
/// Loads the bundled parameterized page at [guideAssetPath] (requires the
/// coordinator-owned `flutter/assets` pubspec entry for `web-guide/`).
/// After load, the initial station is selected via the page's
/// `window.RailMateGuide.showStation(code)` hook so one asset file serves
/// all demo stations.
///
/// Offline/no-network behavior is genuine degradation, never faked content:
/// - If the bundled asset itself cannot load (e.g. assets not wired yet),
///   a real offline message with a retry button is shown.
/// - If the asset loads but CDN libraries (Leaflet/GSAP/YouTube) are
///   unreachable, the page renders its own static fallback content and
///   offline notes (see `web-guide/guide.js`).
class GuideWebViewScreen extends StatefulWidget {
  final StationGuide guide;

  const GuideWebViewScreen({super.key, required this.guide});

  @override
  State<GuideWebViewScreen> createState() => _GuideWebViewScreenState();
}

class _GuideWebViewScreenState extends State<GuideWebViewScreen> {
  late final WebViewController _controller;
  bool _loadFailed = false;
  String _failureDetail = '';

  @override
  void initState() {
    super.initState();
    final String code = normalizeGuideStationCode(widget.guide.stationCode);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF4F7F9))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            // Select the requested station on the parameterized page.
            // Guarded in-page; a no-op if the hook is missing.
            _controller.runJavaScript(
              "if (window.RailMateGuide) { window.RailMateGuide.showStation('$code'); }",
            );
          },
          onWebResourceError: (WebResourceError error) {
            // Main-frame failures (e.g. asset missing) degrade to the
            // offline message. Sub-resource CDN failures are handled by
            // the page itself; only surface main-frame errors here.
            if (error.isForMainFrame ?? false) {
              setState(() {
                _loadFailed = true;
                _failureDetail = error.description;
              });
            }
          },
        ),
      );
    _loadGuide();
  }

  Future<void> _loadGuide() async {
    try {
      await _controller.loadFlutterAsset(guideAssetPath);
    } catch (e) {
      // e.g. web-guide/ assets not yet registered in pubspec.yaml.
      if (mounted) {
        setState(() {
          _loadFailed = true;
          _failureDetail = e.toString();
        });
      }
    }
  }

  void _retry() {
    setState(() {
      _loadFailed = false;
      _failureDetail = '';
    });
    _loadGuide();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E5A66),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text('${widget.guide.stationName} guide'),
      ),
      body: _loadFailed
          ? _buildOffline(context)
          : WebViewWidget(controller: _controller),
    );
  }

  Widget _buildOffline(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 48, color: Color(0xFF0E5A66)),
            const SizedBox(height: 12),
            const Text(
              'Guide unavailable offline',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'The interactive guide page could not be loaded. '
              'Your saved offline guide details are still available on the '
              'previous screen. DEMONSTRATION ONLY.',
              textAlign: TextAlign.center,
            ),
            if (_failureDetail.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _failureDetail,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: _retry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
