// Public official-timetable page.
//
// Reads the read-only dataset published next to this file, renders it with
// plain DOM (textContent only - the data is text, never HTML), and keeps every
// rule in `timetable_logic.mjs` so the Flutter app and this page cannot drift.
// No Supabase, no service key, no writes.

import {
  WEEKDAYS,
  coverageLine,
  durationLabel,
  filterTrains,
  formatDate,
  isOvernight,
  stationName,
  stationOptions,
} from './timetable_logic.mjs';

const status = document.getElementById('status');
const provenance = document.getElementById('provenance');
const trainsRoot = document.getElementById('trains');
const countLine = document.getElementById('count');
const fromSelect = document.getElementById('from');
const toSelect = document.getElementById('to');
const weekdaySelect = document.getElementById('weekday');
const textInput = document.getElementById('text');
const phasedInput = document.getElementById('phased');

let dataset = null;

function showStatus(message) {
  status.textContent = message;
  status.hidden = !message;
}

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function fillSelect(select, entries, placeholder) {
  const first = el('option', null, placeholder);
  first.value = '';
  select.append(first);
  for (const entry of entries) {
    const option = el('option', null, entry.label);
    option.value = entry.value;
    select.append(option);
  }
}

function renderBanner(data) {
  provenance.textContent = '';
  const title = el(
    'h2',
    null,
    `Timetable No. ${data.timetable_number} · effective ${formatDate(data.effective_from)}`,
  );
  const notice = el('p', null, data.notice);
  const coverage = el('p', 'timetable-meta', coverageLine(data));
  const checked = el(
    'p',
    'timetable-meta',
    `Last checked ${formatDate(data.last_verified)} · rows transcribed from the published PDFs`,
  );
  provenance.append(title, notice, coverage, checked);
  if (Array.isArray(data.coverage?.not_imported) && data.coverage.not_imported.length) {
    const gapText = data.coverage.not_imported
      .map((gap) => `${gap.section} (pages ${gap.pages})`)
      .join('; ');
    provenance.append(
      el('p', 'timetable-meta', `Not imported yet, and not guessed: ${gapText}.`),
    );
  }
}

function renderTrain(data, train) {
  const card = el('article', 'timetable-card');
  const head = el('div', 'timetable-card-head');
  head.append(
    el('span', 'timetable-number', train.train_number),
    el('span', 'timetable-name', train.name_en || train.name_bn || train.train_number),
  );
  if (train.operational_status !== 'published') {
    head.append(el('span', 'timetable-chip', 'Phased'));
  }
  card.append(head);

  if (train.name_bn && train.name_en) {
    card.append(el('p', 'timetable-meta', train.name_bn));
  }

  const times = el('div', 'timetable-times');
  const origin = el('div');
  origin.append(
    el('strong', null, train.origin.departure),
    el('span', 'timetable-meta', stationName(data, train.origin.station)),
  );
  const destination = el('div', 'timetable-arrival');
  destination.append(
    el('strong', null, train.destination.arrival),
    el('span', 'timetable-meta', stationName(data, train.destination.station)),
  );
  if (isOvernight(train)) {
    destination.append(el('span', 'timetable-chip', 'next day (inferred)'));
  }
  times.append(origin, el('span', 'timetable-arrow', '→'), destination);
  card.append(times);

  const facts = el('div', 'timetable-facts');
  const offDays = train.off_days ?? [];
  facts.append(
    el(
      'span',
      'timetable-chip',
      offDays.length
        ? `Weekly off: ${offDays.join(', ')}`
        : 'No weekly off day published',
    ),
    el('span', 'timetable-chip', train.zone === 'eastern' ? 'Eastern Zone' : 'Western Zone'),
    el('span', 'timetable-chip', durationLabel(train)),
  );
  if (train.service_class === 'international') {
    facts.append(el('span', 'timetable-chip', 'International'));
  }
  if (train.stops && train.stops.length > 0) {
    facts.append(el('span', 'timetable-chip', `${train.stops.length} stops`));
  } else {
    facts.append(el('span', 'timetable-chip', 'Intermediate stops not published'));
  }
  card.append(facts);

  card.append(
    el(
      'p',
      'timetable-source',
      `Source: ${train.source.document === 'eastern' ? 'Eastern' : 'Western'} Zone PDF, page ${train.source.page}, row ${train.source.serial}.`,
    ),
  );
  return card;
}

function render() {
  if (!dataset) return;
  const results = filterTrains(dataset, {
    from: fromSelect.value,
    to: toSelect.value,
    weekday: weekdaySelect.value,
    text: textInput.value,
    includePhased: phasedInput.checked,
  });
  trainsRoot.textContent = '';
  countLine.textContent =
    results.length === 1 ? '1 service' : `${results.length} services`;

  if (results.length === 0) {
    const empty = el('div', 'status');
    empty.append(
      el('strong', null, 'No published service matches'),
      el(
        'span',
        null,
        'The published summary lists each service by its origin and destination only. Try the exact endpoints or clear the filters.',
      ),
    );
    trainsRoot.append(empty);
    return;
  }

  const fragment = document.createDocumentFragment();
  for (const train of results) {
    fragment.append(renderTrain(dataset, train));
  }
  trainsRoot.append(fragment);
}

async function boot() {
  try {
    const response = await fetch('data/official-timetable.json', { cache: 'no-cache' });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    dataset = await response.json();
  } catch (error) {
    showStatus(
      `The published dataset could not be loaded (${error.message}). This page never falls back to invented rows.`,
    );
    return;
  }

  renderBanner(dataset);
  const stations = stationOptions(dataset).map((station) => ({
    value: station.id,
    label: `${station.name_en} (${station.id})`,
  }));
  fillSelect(fromSelect, stations, 'Any');
  fillSelect(toSelect, stations, 'Any');
  fillSelect(
    weekdaySelect,
    WEEKDAYS.map((day) => ({
      value: day,
      label: day[0].toUpperCase() + day.slice(1),
    })),
    'Any day',
  );
  render();
}

for (const control of [fromSelect, toSelect, weekdaySelect, phasedInput]) {
  control.addEventListener('change', render);
}
textInput.addEventListener('input', render);

boot();
