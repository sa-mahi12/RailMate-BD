import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/search/models/station.dart';
import 'package:railmate_bd/features/search/home/popular_routes_catalog.dart';
import 'package:railmate_bd/features/search/home/upcoming_booking.dart';

const Station dhaka = Station(
  id: '11111111-1111-4111-8111-111111111111',
  code: 'DAC',
  name: 'Dhaka',
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
const Station khulna = Station(
  id: '88888888-8888-4888-8888-888888888888',
  code: 'KHL',
  name: 'Khulna',
);

void main() {
  group('P10 popular routes catalog', () {
    test('offers 5-8 shortcuts (pack 09)', () {
      expect(kDemoPopularRoutes.length, inInclusiveRange(5, 8));
    });

    test('every shortcut code exists in the applied demo catalog', () {
      const Set<String> appliedCodes = <String>{
        'DAC',
        'AIR',
        'CML',
        'FEN',
        'CGP',
        'SYL',
        'RJH',
        'KHL',
      };
      for (final DemoPopularRoute route in kDemoPopularRoutes) {
        expect(
          appliedCodes,
          contains(route.originCode),
          reason: 'invented origin code ${route.originCode}',
        );
        expect(
          appliedCodes,
          contains(route.destinationCode),
          reason: 'invented destination code ${route.destinationCode}',
        );
        expect(route.originCode, isNot(route.destinationCode));
        expect(route.serviceLabel, contains('(Demo)'));
      }
    });

    test('resolves against the live station list', () {
      final List<ResolvedPopularRoute> resolved = resolvePopularRoutes(
        const <Station>[dhaka, chattogram, sylhet, rajshahi, khulna],
      );
      expect(resolved.length, kDemoPopularRoutes.length);
      expect(resolved.first.origin.name, 'Dhaka');
      expect(resolved.first.destination.name, 'Chattogram');
      expect(resolved.first.label, contains('DAC'));
      expect(resolved.first.label, contains('CGP'));
    });

    test('unresolvable codes are dropped, never rendered', () {
      final List<ResolvedPopularRoute> resolved = resolvePopularRoutes(
        const <Station>[dhaka],
      );
      expect(resolved, isEmpty);
      // Case/whitespace tolerant.
      expect(
        resolvePopularRoutes(const <Station>[
          Station(id: 'x', code: ' dac ', name: 'Dhaka'),
          Station(id: 'y', code: 'CGP', name: 'Chattogram'),
        ]).length,
        greaterThan(0),
      );
    });

    test('honours an injected catalog', () {
      final List<ResolvedPopularRoute> resolved = resolvePopularRoutes(
        const <Station>[dhaka, khulna],
        catalog: const <DemoPopularRoute>[
          DemoPopularRoute(
            originCode: 'DAC',
            destinationCode: 'KHL',
            serviceLabel: 'Sundarban Express (Demo)',
          ),
        ],
      );
      expect(resolved.single.label, contains('KHL'));
    });
  });

  group('P10 upcoming booking model', () {
    test('route/seat labels are derived, never invented', () {
      final UpcomingBooking booking = UpcomingBooking(
        reference: 'A1B2C3D4',
        originLabel: 'DAC',
        destinationLabel: 'KHL',
        serviceLabel: 'Sundarban Express (Demo)',
        departureAt: DateTime(2026, 10, 15, 8, 15),
        seatCodes: <String>['A1', 'A2'],
      );
      expect(booking.routeLabel, 'DAC \u2192 KHL');
      expect(booking.seatsLabel, 'A1, A2');
    });

    test('missing seat rows render an honest placeholder', () {
      final UpcomingBooking booking = UpcomingBooking(
        reference: 'A1B2C3D4',
        originLabel: 'DAC',
        destinationLabel: 'CGP',
        serviceLabel: 'Subarna Express (Demo)',
        departureAt: DateTime(2026, 10, 15, 7),
        seatCodes: <String>[],
      );
      expect(booking.seatsLabel, 'Seats not listed');
    });
  });
}
