import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/booking/passenger_ui/passenger.dart';
import 'package:railmate_bd/features/booking/passenger_ui/passenger_form_state.dart';

void main() {
  group('Passenger.validateName negatives', () {
    test('empty name is invalid', () {
      expect(Passenger.validateName(''), isNotNull);
    });
    test('whitespace-only name is invalid', () {
      expect(Passenger.validateName('   '), isNotNull);
    });
    test('1-char name is invalid (min 2)', () {
      expect(Passenger.validateName('A'), isNotNull);
    });
    test('51-char name is invalid (max 50)', () {
      expect(Passenger.validateName('A' * 51), isNotNull);
    });
    test('2-char and 50-char names are valid', () {
      expect(Passenger.validateName('Ab'), isNull);
      expect(Passenger.validateName('A' * 50), isNull);
    });
  });

  group('Passenger.validate', () {
    test('missing type is invalid', () {
      const p = Passenger(name: 'Tanvir Ahmed', type: null, seatCode: 'C1');
      expect(p.isValid, isFalse);
      expect(p.validate(), contains('type'));
    });
    test('missing seat is invalid', () {
      const p = Passenger(
        name: 'Tanvir Ahmed',
        type: PassengerType.adult,
        seatCode: ' ',
      );
      expect(p.isValid, isFalse);
    });
    test('complete row is valid', () {
      const p = Passenger(
        name: 'Tanvir Ahmed',
        type: PassengerType.adult,
        seatCode: 'C1',
      );
      expect(p.isValid, isTrue);
      expect(p.validate(), isNull);
    });
  });

  group('PassengerFormState sizing negatives + 4-passenger max', () {
    test('rejects zero seats', () {
      expect(
        () => PassengerFormState(seatCodes: [], fareBdt: 700),
        throwsArgumentError,
      );
    });
    test('rejects five seats (over 4-passenger max)', () {
      expect(
        () => PassengerFormState(
          seatCodes: ['C1', 'C2', 'C3', 'C4', 'C5'],
          fareBdt: 700,
        ),
        throwsArgumentError,
      );
    });
    test('rejects duplicate seat codes', () {
      expect(
        () => PassengerFormState(seatCodes: ['C1', 'C1'], fareBdt: 700),
        throwsArgumentError,
      );
    });
    test('accepts four passengers (max legal booking)', () {
      final form = PassengerFormState(
        seatCodes: ['C1', 'C2', 'C3', 'C4'],
        fareBdt: 700,
      );
      expect(form.count, 4);
      expect(form.seatCodes, ['C1', 'C2', 'C3', 'C4']);
    });
  });

  group('fare breakdown (ref-4: 2 x 700 + 40 = 1440)', () {
    test('two passengers at BDT 700', () {
      final form = PassengerFormState(seatCodes: ['C1', 'C2'], fareBdt: 700);
      expect(form.fareBreakdown, {
        'passengerCount': 2,
        'farePerSeat': 700,
        'baseFare': 1400,
        'serviceCharge': 40,
        'total': 1440,
      });
    });
    test('four passengers at BDT 700', () {
      final form = PassengerFormState(
        seatCodes: ['C1', 'C2', 'C3', 'C4'],
        fareBdt: 700,
      );
      expect(form.totalBdt, 2840);
    });
  });

  group('validity gating + contact negatives', () {
    PassengerFormState validTwo() {
      final form = PassengerFormState(seatCodes: ['C1', 'C2'], fareBdt: 700);
      form.updateName(0, 'Tanvir Ahmed');
      form.updateType(0, PassengerType.adult);
      form.updateName(1, 'Nusrat Jahan');
      form.updateType(1, PassengerType.adult);
      form.setContactMobile('01712 345678');
      return form;
    }

    test('blank form is invalid (Continue stays disabled)', () {
      final form = PassengerFormState(seatCodes: ['C1', 'C2'], fareBdt: 700);
      expect(form.isValid, isFalse);
    });
    test('fully typed form with contact is valid', () {
      expect(validTwo().isValid, isTrue);
    });
    test('bad mobile keeps form invalid', () {
      final form = validTwo();
      form.setContactMobile('abc');
      expect(form.isValid, isFalse);
    });
    test('bad optional email keeps form invalid; empty email is fine', () {
      final form = validTwo();
      form.setContactEmail('not-an-email');
      expect(form.isValid, isFalse);
      form.setContactEmail('');
      expect(form.isValid, isTrue);
    });
  });

  group('retargetSeats preserves typed rows', () {
    test('keeps C1 data when selection changes C1,C2 -> C1,C3', () {
      final form = PassengerFormState(seatCodes: ['C1', 'C2'], fareBdt: 700);
      form.updateName(0, 'Tanvir Ahmed');
      form.updateType(0, PassengerType.adult);
      form.retargetSeats(['C1', 'C3']);
      expect(form.seatCodes, ['C1', 'C3']);
      expect(form.passengers[0].name, 'Tanvir Ahmed');
      expect(form.passengers[0].type, PassengerType.adult);
      expect(form.passengers[1].name, isEmpty);
    });
  });
}
