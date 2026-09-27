/// Explicit-date helpers for trip search.
///
/// The repository layer never assumes "today": every function here takes an
/// explicit [DateTime]. UI screens may default the visible picker to the
/// current date, but they must display that date (see [SearchState]).
library;

const List<String> _weekdays = <String>[
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

const List<String> _months = <String>[
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

/// Calendar-day start of [date] in local time.
DateTime dayStartOf(DateTime date) => DateTime(date.year, date.month, date.day);

/// True when [date] is before today's calendar date in local time.
bool isPastCalendarDate(DateTime date) {
  final now = DateTime.now();
  return dayStartOf(date).isBefore(DateTime(now.year, now.month, now.day));
}

/// Five-day strip centred on [selected]: selected − 2 … selected + 2,
/// matching the ref-1 date chips (e.g. 09–13 with 11 selected).
List<DateTime> dateStrip(DateTime selected) {
  final center = dayStartOf(selected);
  return List<DateTime>.generate(5, (i) => center.add(Duration(days: i - 2)));
}

/// `Thu, 11 Sep 2025` — journey-date label used on both search screens.
String formatJourneyDate(DateTime date) =>
    '${_weekdays[date.weekday - 1]}, ${date.day} ${_months[date.month - 1]} ${date.year}';

/// `11 Sep, 2025` — compact per-card date line under train times.
String formatShortDate(DateTime date) =>
    '${date.day} ${_months[date.month - 1]}, ${date.year}';

/// `08:00 AM` — 12-hour train time.
String formatTime12(DateTime time) {
  final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  final period = time.hour < 12 ? 'AM' : 'PM';
  return '${hour12.toString().padLeft(2, '0')}:$minute $period';
}

/// `Duration 7h 45m` — ref-1 duration line between departure and arrival.
String formatDuration(DateTime departure, DateTime arrival) {
  final totalMinutes = arrival.difference(departure).inMinutes;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  return 'Duration ${hours}h ${minutes}m';
}
