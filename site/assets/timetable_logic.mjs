// Pure helpers for the public official-timetable page.
//
// No DOM and no network: the page loads `data/official-timetable.json` and hands
// it to these functions, which are unit-tested in `timetable_logic.test.mjs`.
// The rules match the Flutter feature exactly:
//   * published rows only, unless the caller opts into phased rows;
//   * route filtering matches the published origin/destination only;
//   * a weekday filter removes services whose published off day is that weekday;
//   * nothing is inferred, so an impossible pair simply returns an empty list.

export const WEEKDAYS = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

/** Minutes since midnight for an `HH:MM` string, or null when malformed. */
export function minutesOfDay(value) {
  const match = /^(\d{2}):(\d{2})$/.exec(String(value ?? ''));
  if (!match) return null;
  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  if (hours > 23 || minutes > 59) return null;
  return hours * 60 + minutes;
}

/** `2025-03-10` -> `10 Mar 2025`; returns the input when it is not ISO. */
export function formatDate(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(value ?? ''));
  if (!match) return String(value ?? '');
  const months = [
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
  const month = Number(match[2]);
  if (month < 1 || month > 12) return String(value);
  return `${Number(match[3])} ${months[month - 1]} ${match[1]}`;
}

/** English station name for an id, falling back to the id itself. */
export function stationName(dataset, id) {
  const station = (dataset?.stations ?? []).find((entry) => entry.id === id);
  return station?.name_en ?? String(id ?? '');
}

/** Station choices sorted by English name. */
export function stationOptions(dataset) {
  return [...(dataset?.stations ?? [])].sort((a, b) =>
    String(a.name_en).localeCompare(String(b.name_en)),
  );
}

/** Published services touching a station, earliest departure first. */
export function trainsAtStation(dataset, stationId) {
  return filterTrains(dataset, {}).filter(
    (train) =>
      train.origin?.station === stationId ||
      train.destination?.station === stationId,
  );
}

/**
 * Filters the dataset.
 * @param {object} dataset parsed official-timetable.json
 * @param {{from?: string, to?: string, weekday?: string, text?: string,
 *          includePhased?: boolean}} options
 */
export function filterTrains(dataset, options = {}) {
  const {
    from = '',
    to = '',
    weekday = '',
    text = '',
    includePhased = false,
  } = options;
  const needle = String(text).trim().toLowerCase();

  return (dataset?.trains ?? [])
    .filter((train) => {
      if (!includePhased && train.operational_status !== 'published') {
        return false;
      }
      if (from && train.origin?.station !== from) return false;
      if (to && train.destination?.station !== to) return false;
      if (weekday && (train.off_days ?? []).includes(weekday)) return false;
      if (!needle) return true;
      const haystack = [
        train.train_number,
        train.name_en,
        train.name_bn,
        stationName(dataset, train.origin?.station),
        stationName(dataset, train.destination?.station),
      ]
        .filter(Boolean)
        .join(' ')
        .toLowerCase();
      return haystack.includes(needle);
    })
    .sort((a, b) => {
      const left = minutesOfDay(a.origin?.departure) ?? 0;
      const right = minutesOfDay(b.origin?.departure) ?? 0;
      if (left !== right) return left - right;
      return String(a.train_number).localeCompare(String(b.train_number));
    });
}

/** True when the published arrival time is at or before the departure time. */
export function isOvernight(train) {
  const departure = minutesOfDay(train?.origin?.departure);
  const arrival = minutesOfDay(train?.destination?.arrival);
  if (departure === null || arrival === null) return false;
  return arrival <= departure;
}

/** Human duration for two published times, using the inferred day rollover. */
export function durationLabel(train) {
  const departure = minutesOfDay(train?.origin?.departure);
  const arrival = minutesOfDay(train?.destination?.arrival);
  if (departure === null || arrival === null) return '';
  const total = isOvernight(train) ? arrival - departure + 24 * 60 : arrival - departure;
  const hours = Math.floor(total / 60);
  const minutes = total % 60;
  if (hours === 0) return `${minutes} min`;
  if (minutes === 0) return `${hours}h`;
  return `${hours}h ${minutes}m`;
}

/** Provenance line for the page banner. */
export function coverageLine(dataset) {
  if (!dataset) return '';
  const imported = dataset.coverage?.rows_transcribed ?? 0;
  const excluded = dataset.coverage?.rows_excluded ?? 0;
  return `${imported} published intercity services · ${excluded} printed rows excluded as ambiguous`;
}
