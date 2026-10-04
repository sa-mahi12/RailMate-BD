/// P22 - station guide detail (B09 slice + F15 entry point).
///
/// Shows the station identity block (name, code, city/division/district),
/// facility chips, the demonstration description, the arrival/access tip, the
/// "how to reach" directions and Quick Information - all offline, all marked
/// DEMONSTRATION ONLY.
///
/// P22 honesty rules on this screen:
/// * the helpline row is **omitted** when the entry has none, with one short
///   line explaining why (no official helpline could be verified);
/// * the "Interactive guide" card is only offered for stations the bundled
///   page really has a pin for ([hasGuideMapPage]); for the others it says so
///   instead of silently showing another station's marker;
/// * the hero block is an explicit local placeholder, never a stock photo of
///   a real station.
///
/// Motion: one [StateEntrance] (fade + 12 px rise, 220 ms, reduced-motion
/// aware) as the page settles, and the WebView screen fades in once its page
/// has loaded (F15).
library;

import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../../../design/state/state.dart';
import 'guide_webview_screen.dart';
import 'station_guide.dart';

const Color _primaryTeal = Color(0xFF0E5A66);
const Color _pageBackground = Color(0xFFF4F7F9);

class GuideDetailScreen extends StatelessWidget {
  final StationGuide guide;

  const GuideDetailScreen({super.key, required this.guide});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildHeader(context),
          Expanded(
            child: StateEntrance(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.s16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _buildOverviewCard(),
                      const SizedBox(height: AppSpacing.s12),
                      _buildArrivalTipCard(),
                      const SizedBox(height: AppSpacing.s12),
                      _buildQuickInfoCard(),
                      const SizedBox(height: AppSpacing.s12),
                      _buildInteractiveGuideCard(context),
                      const SizedBox(height: AppSpacing.s12),
                      _buildPendingEmbedCard(
                        title: 'About this guide',
                        body:
                            'Every value on this screen is demonstration '
                            'content written for this academic project. It is '
                            'not official railway information and must not be '
                            'used for real travel.',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s40 + AppSpacing.s8,
        AppSpacing.s16,
        AppSpacing.s20,
      ),
      decoration: const BoxDecoration(
        color: _primaryTeal,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: <Widget>[
          _BackButton(onPressed: () => Navigator.maybePop(context)),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${guide.stationName} (${guide.stationCode})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${guide.city} · ${guide.division} Division · '
                  '${guide.district} District',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
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
      shape: RoundedRectangleBorder(borderRadius: AppRadii.cardRadius),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: _primaryTeal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppSpacing.s12),
              ),
              alignment: Alignment.center,
              child: const Text(
                'Hero photo placeholder (local only)',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(guide.description, style: AppTypography.body),
            const SizedBox(height: AppSpacing.s12),
            const Text('Facilities', style: AppTypography.cardTitle),
            const SizedBox(height: AppSpacing.s8),
            Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: <Widget>[
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
            const SizedBox(height: AppSpacing.s12),
            const Text('How to reach', style: AppTypography.cardTitle),
            const SizedBox(height: AppSpacing.s4),
            Text(guide.howToReach, style: AppTypography.body),
          ],
        ),
      ),
    );
  }

  /// Generic arrival/access tip (guide field "arrival tip"). Never a promise
  /// about a specific train, platform or service.
  Widget _buildArrivalTipCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: AppRadii.cardRadius),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.directions_walk_outlined,
                  size: 18,
                  color: _primaryTeal,
                ),
                const SizedBox(width: AppSpacing.s8),
                Text('Arrival tip', style: AppTypography.cardTitle),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(guide.arrivalTip, style: AppTypography.body),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickInfoCard() {
    final String? helpline = guide.helpline;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: AppRadii.cardRadius),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Quick Information', style: AppTypography.cardTitle),
            const SizedBox(height: AppSpacing.s8),
            _infoRow(Icons.confirmation_number, 'Code', guide.stationCode),
            const Divider(height: 20),
            _infoRow(Icons.location_city, 'Division', guide.division),
            const Divider(height: 20),
            _infoRow(Icons.map_outlined, 'District', guide.district),
            const Divider(height: 20),
            _infoRow(
              Icons.my_location,
              'Coordinates',
              guide.hasMapPage
                  ? '${guide.latitude}, ${guide.longitude} (demo values)'
                  : 'Not in the bundled demo map',
            ),
            const Divider(height: 20),
            // Helpline row is omitted when the entry has none: printing an
            // unverified number would be a fabricated official claim.
            if (helpline != null && helpline.isNotEmpty) ...<Widget>[
              _infoRow(Icons.support_agent, 'Helpline', helpline),
              const Divider(height: 20),
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
                child: Text(
                  'Helpline: not shown. No official station helpline could be '
                  'verified for this demo, so none is printed here.',
                  style: AppTypography.caption,
                ),
              ),
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
      children: <Widget>[
        Icon(icon, size: 18, color: _primaryTeal),
        const SizedBox(width: AppSpacing.s8),
        SizedBox(width: 88, child: Text(label, style: AppTypography.caption)),
        Expanded(child: Text(value, style: AppTypography.body)),
      ],
    );
  }

  /// F15 entry point: opens the bundled interactive guide page
  /// (Leaflet map + video + GSAP) in a WebView. The offline list and detail
  /// above stay intact; without network or unwired assets the WebView screen
  /// degrades to a genuine offline message.
  ///
  /// Only offered when the bundled page really has a pin for this station, so
  /// the reader is never shown another station's marker.
  Widget _buildInteractiveGuideCard(BuildContext context) {
    final bool mapped = hasGuideMapPage(guide.stationCode);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: AppRadii.cardRadius),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Interactive guide', style: AppTypography.cardTitle),
            const SizedBox(height: AppSpacing.s4),
            Text(
              mapped
                  ? 'Map, video and animation in one page. DEMONSTRATION '
                        'ONLY — needs network for map/video.'
                  : 'The bundled interactive page covers the eight demo map '
                        'stations only, so it is not offered for '
                        '${guide.stationName}. The offline guide above is '
                        'complete.',
              style: AppTypography.caption,
            ),
            const SizedBox(height: AppSpacing.s12),
            FilledButton.icon(
              onPressed: mapped
                  ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => GuideWebViewScreen(guide: guide),
                        ),
                      );
                    }
                  : null,
              icon: const Icon(Icons.map_outlined),
              label: Text(
                mapped ? 'Open interactive guide' : 'Map not bundled',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingEmbedCard({required String title, required String body}) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: AppRadii.cardRadius),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: AppTypography.cardTitle),
            const SizedBox(height: AppSpacing.s4),
            Text(body, style: AppTypography.caption),
          ],
        ),
      ),
    );
  }
}

/// Circular translucent back control used by the guide screens.
class _BackButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _BackButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: const Icon(Icons.chevron_left, color: Colors.white),
        onPressed: onPressed,
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
      children: <Widget>[
        Icon(icon, size: 18, color: _primaryTeal),
        const SizedBox(width: AppSpacing.s8),
        SizedBox(width: 88, child: Text(label, style: AppTypography.caption)),
        Expanded(child: Text(value, style: AppTypography.body)),
      ],
    );
  }
}
