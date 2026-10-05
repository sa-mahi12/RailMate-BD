/// P20 — relative timestamp formatting for Journey Board posts.
///
/// Pure Dart: no Flutter, no network. The feed previously rendered
/// `DateTime.toLocal().toString().split('.').first`, which prints raw
/// database-style text ("2026-10-04 10:00:00") instead of something a
/// reader can scan. This formats an honest relative label and falls back to
/// an absolute date beyond a week (so old posts never claim "1m ago").
library;

/// Formats [createdAt] as an age relative to [now].
///
/// Buckets (earliest label wins):
/// * under 1 minute -> `just now`
/// * under 60 minutes -> `Nm ago`
/// * under 24 hours -> `Nh ago`
/// * under 7 days -> `Nd ago`
/// * otherwise -> absolute `D MMM yyyy` (e.g. `4 Oct 2026`)
///
/// A future timestamp (clock skew between device and server) is clamped to
/// `just now` rather than printing a negative age. Returns `''` for a null
/// input so the caller can render nothing at all.
String formatRelativeTime(DateTime? createdAt, {DateTime? now}) {
  if (createdAt == null) return '';
  final DateTime reference = now ?? DateTime.now();
  final Duration age = reference.difference(createdAt);
  if (age.isNegative || age.inSeconds < 60) return 'just now';
  if (age.inMinutes < 60) return '${age.inMinutes}m ago';
  if (age.inHours < 24) return '${age.inHours}h ago';
  if (age.inDays < 7) return '${age.inDays}d ago';
  return formatAbsoluteDate(createdAt);
}

/// Absolute fallback label: `D MMM yyyy` (day, short month, year).
String formatAbsoluteDate(DateTime date) {
  const List<String> months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final int monthIndex = date.month - 1;
  final String month = (monthIndex >= 0 && monthIndex < months.length)
      ? months[monthIndex]
      : '${date.month}';
  return '${date.day} $month ${date.year}';
}
