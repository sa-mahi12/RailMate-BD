/// P22 - station guide list.
///
/// Offline-first: renders the bundled [stationGuideCatalog] (twenty-four
/// demonstration entries, one per live station code) with no network call,
/// no WebView and no external URL. Tapping a card pushes
/// [GuideDetailScreen].
///
/// P22 polish:
/// * entrance stagger that plays once per entry ([StaggeredList], 40 ms
///   step, y10 rise),
/// * press feedback on every card ([PressScale] around a Material card),
/// * an honest empty state through the P26 `EmptyState` when a caller passes
///   no guides - never a bare sentence,
/// * the demonstration notice stays visible in the header.
library;

import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../../../design/state/state.dart';
import 'guide_detail_screen.dart';
import 'station_guide.dart';

const Color _primaryTeal = Color(0xFF0E5A66);
const Color _pageBackground = Color(0xFFF4F7F9);

class GuideListScreen extends StatelessWidget {
  /// Entries to render. Defaults to the full demonstration catalog.
  final List<StationGuide> guides;

  const GuideListScreen({super.key, this.guides = stationGuideCatalog});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildHeader(context),
          Expanded(
            child: guides.isEmpty
                ? const EmptyState(
                    icon: Icons.map_outlined,
                    title: 'No station guides available offline',
                    message:
                        'This build ships demonstration guides only. Reinstall '
                        'the app to restore the bundled station list.',
                  )
                : StaggeredList(
                    key: const ValueKey<String>('guide-list'),
                    padding: const EdgeInsets.all(AppSpacing.s16),
                    itemCount: guides.length,
                    itemBuilder: (context, index) {
                      final StationGuide guide = guides[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.s12),
                        child: _GuideCard(
                          key: ValueKey<String>('guide-${guide.stationCode}'),
                          guide: guide,
                        ),
                      );
                    },
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
          const SizedBox(width: AppSpacing.s12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Station Guide',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Offline demo guides — DEMONSTRATION ONLY',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  final StationGuide guide;

  const _GuideCard({super.key, required this.guide});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => GuideDetailScreen(guide: guide),
          ),
        );
      },
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: AppRadii.cardRadius),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _primaryTeal.withValues(alpha: 0.12),
                  borderRadius: AppRadii.chipRadius,
                ),
                alignment: Alignment.center,
                child: Text(
                  guide.stationCode,
                  style: const TextStyle(
                    color: _primaryTeal,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      guide.stationName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      '${guide.city} · ${guide.division} Division',
                      style: AppTypography.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      guide.facilities.join(' • '),
                      style: AppTypography.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
