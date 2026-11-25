import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

import {
  coverageLine,
  durationLabel,
  filterTrains,
  formatDate,
  isOvernight,
  minutesOfDay,
  stationName,
  stationOptions,
  trainsAtStation,
} from './timetable_logic.mjs';

const dataset = JSON.parse(
  readFileSync(new URL('../data/official-timetable.json', import.meta.url), 'utf8'),
);

test('the published dataset has the expected shape', () => {
  assert.equal(dataset.dataset_id, 'bd-railway-timetable-54-intercity-2025-03-10');
  assert.equal(dataset.trains.length, 130);
  assert.equal(dataset.stations.length, 29);
  assert.equal(dataset.coverage.intermediate_stops_published, false);
  assert.equal(dataset.timetable_number, '54');
  assert.equal(dataset.effective_from, '2025-03-10');
});

test('a known row is exactly what the PDF prints', () => {
  const train = dataset.trains.find((entry) => entry.train_number === '701');
  assert.equal(train.name_en, 'Suborno Express');
  assert.equal(train.origin.station, 'CTG');
  assert.equal(train.origin.departure, '07:00');
  assert.equal(train.destination.station, 'DAC');
  assert.equal(train.destination.arrival, '11:55');
  assert.deepEqual(train.off_days, ['monday']);
  assert.equal(train.source.page, 1);
  assert.equal(train.source.serial, 1);
});

test('weekday filtering removes the published off day only', () => {
  const monday = filterTrains(dataset, { weekday: 'monday' });
  const tuesday = filterTrains(dataset, { weekday: 'tuesday' });
  assert.equal(monday.some((t) => t.train_number === '701'), false);
  assert.equal(tuesday.some((t) => t.train_number === '701'), true);
});

test('route filtering matches the published endpoints only', () => {
  const results = filterTrains(dataset, { from: 'CTG', to: 'DAC' });
  assert.ok(results.length > 0);
  for (const train of results) {
    assert.equal(train.origin.station, 'CTG');
    assert.equal(train.destination.station, 'DAC');
  }
  assert.deepEqual(filterTrains(dataset, { from: 'SYL', to: 'CXB' }), []);
});

test('free text searches number, names and stations', () => {
  assert.deepEqual(
    filterTrains(dataset, { text: 'suborno' }).map((t) => t.train_number),
    ['701', '702'],
  );
  assert.equal(filterTrains(dataset, { text: '3131' })[0].name_en, 'Mitali Express');
  assert.ok(filterTrains(dataset, { text: 'কক্সবাজার' }).length > 0);
});

test('phased services are hidden unless requested', () => {
  assert.deepEqual(filterTrains(dataset, { text: 'tangua' }), []);
  assert.equal(
    filterTrains(dataset, { text: 'tangua', includePhased: true }).length,
    2,
  );
});

test('results are sorted by departure time', () => {
  const results = filterTrains(dataset, {});
  for (let i = 1; i < results.length; i += 1) {
    const previous = minutesOfDay(results[i - 1].origin.departure);
    const current = minutesOfDay(results[i].origin.departure);
    assert.ok(previous <= current);
  }
});

test('overnight inference is arithmetic on the two published times', () => {
  for (const train of dataset.trains) {
    const departure = minutesOfDay(train.origin.departure);
    const arrival = minutesOfDay(train.destination.arrival);
    assert.equal(isOvernight(train), arrival <= departure);
  }
  const sundarban = dataset.trains.find((t) => t.train_number === '725');
  assert.equal(isOvernight(sundarban), true);
  assert.equal(durationLabel(sundarban), '7h 25m');
});

test('formatting helpers never invent data', () => {
  assert.equal(formatDate('2025-03-10'), '10 Mar 2025');
  assert.equal(formatDate('not-a-date'), 'not-a-date');
  assert.equal(minutesOfDay('24:00'), null);
  assert.equal(minutesOfDay('7:00'), null);
  assert.equal(stationName(dataset, 'DAC'), 'Dhaka');
  assert.equal(stationName(dataset, 'ZZZ'), 'ZZZ');
  const options = stationOptions(dataset);
  assert.equal(options[0].name_en <= options.at(-1).name_en, true);
  assert.ok(trainsAtStation(dataset, 'DAC').length > 0);
  assert.match(coverageLine(dataset), /130 published intercity services/);
});

test('no live-status field is published', () => {
  const encoded = JSON.stringify(dataset.trains).toLowerCase();
  for (const forbidden of ['delay', 'eta', 'platform', 'seat_available', 'occupancy']) {
    assert.equal(encoded.includes(`"${forbidden}"`), false, forbidden);
  }
});
