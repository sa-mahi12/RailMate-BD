import 'package:flutter/material.dart';

import 'guide_webview_screen.dart';
import 'station_guide.dart';

const Color _primaryTeal = Color(0xFF0E5A66);
const Color _pageBackground = Color(0xFFF4F7F9);

/// Offline station guide detail (B09 slice, ref-9 Overview) + F15 entry point.
///
/// Shows hero placeholder, name, facility fact chips, description
/// (how-to-reach), and Quick Information rows (helpline) — all offline.
/// The "Interactive guide" card opens [GuideWebViewScreen], which loads the
/// bundled `web-guide/index.html` page (Leaflet map, YouTube embed, GSAP).
/// The legacy Map/Video placeholder cards below it remain as explicit
/// local-only placeholders.
class GuideDetailScreen extends StatelessWidget {
  final StationGuide guide;

  const GuideDetailScreen({super.key, required this.guide});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOverviewCard(),
                  const SizedBox(height: 12),
                  _buildQuickInfoCard(),
                  const SizedBox(height: 12),
                  _buildInteractiveGuideCard(context),
                  const SizedBox(height: 12),
                  _buildPendingEmbedCard(
                    title: 'Map',
                    body: 'Map embed placeholder. Google Maps iframe loads here only after teacher approval (R-10 BLOCKED).',
                  ),
                  const SizedBox(height: 12),
                  _buildPendingEmbedCard(
                    title: 'Video',
                    body: 'Video embed placeholder. YouTube player loads here only after teacher approval (R-09 BLOCKED).',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 20),
      decoration: const BoxDecoration(
        color: _primaryTeal,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.chevron_left, color: Colors.white),
              onPressed: () => Navigator.maybePop(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${guide.stationName} (${guide.stationCode})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'DEMONSTRATION ONLY — offline demo data',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: _primaryTeal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const Text(
                'Hero photo placeholder (local only)',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Facilities',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final String facility in guide.facilities)
                  Chip(
                    label: Text(facility),
                    backgroundColor: _primaryTeal.withValues(alpha: 0.1),
                    labelStyle: const TextStyle(
                      color: _primaryTeal,
                      fontSize: 12,
                    ),
                    side: BorderSide.none,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'How to reach',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              guide.howToReach,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickInfoCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Quick Information',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _infoRow(Icons.confirmation_number, 'Code', guide.stationCode),
            const Divider(height: 20),
            _infoRow(Icons.support_agent, 'Helpline', guide.helpline),
            const Divider(height: 20),
            const _InfoRowStatic(
              icon: Icons.wifi_off,
              label: 'Mode',
              value: 'Offline demo — no network required',
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: _primaryTeal),
        const SizedBox(width: 10),
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ],
    );
  }

  /// F15 entry point: opens the bundled interactive guide page
  /// (Leaflet map + video + GSAP) in a WebView. The offline list and detail
  /// above stay intact; without network or unwired assets the WebView screen
  /// degrades to a genuine offline message.
  Widget _buildInteractiveGuideCard(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Interactive guide',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Map, video and animation in one page. DEMONSTRATION ONLY — needs network for map/video.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => GuideWebViewScreen(guide: guide),
                  ),
                );
              },
              icon: const Icon(Icons.map_outlined),
              label: const Text('Open interactive guide'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingEmbedCard({required String title, required String body}) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRowStatic extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRowStatic({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: _primaryTeal),
        const SizedBox(width: 10),
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ],
    );
  }
}
