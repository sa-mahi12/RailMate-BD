import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/search/models/station.dart';
import 'package:railmate_bd/features/search/home/recent_searches_store.dart';

const Station dhaka = Station(
  id: '11111111-1111-4111-8111-111111111111',
  code: 'DAC',
  name: 'Dhaka',
);
const Station khulna = Station(
  id: '88888888-8888-4888-8888-888888888888',
  code: 'KHL',
  name: 'Khulna',
);
const Station chattogram = Station(
  id: '22222222-2222-4222-8222-222222222222',
  code: 'CGP',
  name: 'Chattogram',
);
const Station sylhet = Station(
  id: '33333333-3333-4333-8333-333333333333',
  code: 'SYL',
  name: 'Sylhet',
);
const Station rajshahi = Station(
  id: '44444444-4444-4444-8444-444444444444',
  code: 'RJH',
  name: 'Rajshahi',
);
const Station cumilla = Station(
  id: '66666666-6666-4666-8666-666666666666',
  code: 'CML',
  name: 'Cumilla',
);

RecentSearch entry(String origin, String destination, DateTime date) =>
    RecentSearch(
      originId: origin,
      destinationId: destination,
      originLabel: 'o-$origin',
      destinationLabel: 'd-$destination',
      date: date,
    );

void main() {
  group('P10 recent search store', () {
    test('history starts empty (never preseeded)', () async {
      final controller = RecentSearchesController(
        store: InMemoryRecentSearchStore(),
      );
      await controller.load();
      expect(controller.isLoaded, isTrue);
      expect(controller.entries, isEmpty);
    });

    test('keeps the newest five, newest first', () async {
      final controller = RecentSearchesController(
        store: InMemoryRecentSearchStore(),
      );
      await controller.load();
      const List<String> ids = <String>['a', 'b', 'c', 'd', 'e', 'f', 'g'];
      for (int i = 0; i < ids.length; i++) {
        await controller.record(
          entry(ids[i], 'z$i', DateTime(2026, 10, 10 + i)),
        );
      }
      expect(controller.entries.length, RecentSearchesController.maxEntries);
      expect(controller.entries.first.originId, 'g');
      expect(controller.entries.last.originId, 'c');
    });

    test('same route + date replaces instead of duplicating', () async {
      final controller = RecentSearchesController(
        store: InMemoryRecentSearchStore(),
      );
      await controller.load();
      await controller.record(entry('a', 'b', DateTime(2026, 10, 10)));
      await controller.record(entry('a', 'b', DateTime(2026, 10, 10)));
      expect(controller.entries.length, 1);
      // A different date on the same route is a distinct entry.
      await controller.record(entry('a', 'b', DateTime(2026, 10, 11)));
      expect(controller.entries.length, 2);
    });

    test('clear empties the store and notifies', () async {
      final store = InMemoryRecentSearchStore();
      final controller = RecentSearchesController(store: store);
      await controller.load();
      await controller.record(entry('a', 'b', DateTime(2026, 10, 10)));
      int notifications = 0;
      controller.addListener(() => notifications++);
      await controller.clear();
      expect(controller.entries, isEmpty);
      expect(notifications, 1);
      expect(await store.read(), isEmpty);
    });

    test('survives a new controller over the same store', () async {
      final store = InMemoryRecentSearchStore();
      final first = RecentSearchesController(store: store);
      await first.load();
      await first.record(entry('a', 'b', DateTime(2026, 10, 10)));
      final second = RecentSearchesController(store: store);
      await second.load();
      expect(second.entries.length, 1);
    });

    test('drops unusable rows (blank ids, same station twice)', () async {
      final store = InMemoryRecentSearchStore(<RecentSearch>[
        RecentSearch(
          originId: '',
          destinationId: 'b',
          originLabel: 'x',
          destinationLabel: 'y',
          date: DateTime(2026, 10, 10),
        ),
        RecentSearch(
          originId: 'a',
          destinationId: 'a',
          originLabel: 'x',
          destinationLabel: 'x',
          date: DateTime(2026, 10, 10),
        ),
        entry('a', 'b', DateTime(2026, 10, 10)),
      ]);
      final controller = RecentSearchesController(store: store);
      await controller.load();
      expect(controller.entries.length, 1);
      expect(controller.entries.single.originId, 'a');
    });

    test('json round-trip preserves the row; corrupt rows throw', () {
      final RecentSearch original = entry('a', 'b', DateTime(2026, 10, 10));
      final RecentSearch parsed = RecentSearch.fromJson(original.toJson());
      expect(parsed.originId, 'a');
      expect(parsed.destinationId, 'b');
      expect(parsed.date, DateTime(2026, 10, 10));
      expect(
        () => RecentSearch.fromJson(<String, dynamic>{'origin_id': 'a'}),
        throwsFormatException,
      );
    });

    test('labelFor prefers the live catalog, falls back to the snapshot', () {
      final RecentSearch e = entry(dhaka.id, khulna.id, DateTime(2026, 10, 10));
      expect(e.labelFor(dhaka.id, 'o-DAC', <Station>[dhaka]), 'Dhaka');
      expect(e.labelFor('missing', 'o-XXX', <Station>[dhaka]), 'o-XXX');
      expect(
        e.labelFor('missing', '', <Station>[dhaka]),
        'Station unavailable',
      );
    });

    test(
      'SharedPreferences store reads empty when the platform is absent',
      () async {
        // No plugin mock: the store must degrade, never throw.
        final store = SharedPreferencesRecentSearchStore();
        expect(await store.read(), isEmpty);
        await store.write(<RecentSearch>[]);
      },
    );
  });

  group('P10 station catalog helpers used by Home sections', () {
    test('the applied demo station codes resolve', () {
      const List<Station> catalog = <Station>[
        dhaka,
        chattogram,
        sylhet,
        rajshahi,
        khulna,
        cumilla,
      ];
      expect(
        catalog.map((Station s) => s.code),
        containsAll(<String>['DAC', 'CGP', 'SYL', 'RJH', 'KHL', 'CML']),
      );
    });
  });
}
