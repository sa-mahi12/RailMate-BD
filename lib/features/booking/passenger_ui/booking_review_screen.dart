import 'package:flutter/material.dart';

import 'passenger.dart';
import 'passenger_form_state.dart';

const Color _primaryTeal = Color(0xFF0E5A66);
const Color _pageBackground = Color(0xFFF4F7F9);

/// Ref-4 "Booking Review" screen (step 2 of Passengers > Review > Payment).
///
/// Read-only summary over the host-owned [formState]: journey card with
/// [onEditJourney], train details row, passenger-seat list with
/// [onEditPassengers], fare breakdown (`base + service = total`), a terms
/// checkbox and a confirm button enabled only once the terms are accepted
/// (and the form is valid). Calls [onConfirm] — the actual reservation stays
/// server-side in the later booking lane; this screen writes nothing.
///
/// Includes a one-line demonstration notice (no real money is charged).
class BookingReviewScreen extends StatefulWidget {
  final PassengerFormState formState;
  final String trainName;
  final String originCode;
  final String originName;
  final String destinationCode;
  final String destinationName;
  final String dateLabel;
  final String classLabel;
  final String departureLabel;
  final String arrivalLabel;
  final String durationLabel;
  final VoidCallback onEditJourney;
  final VoidCallback onEditPassengers;
  final VoidCallback onConfirm;

  const BookingReviewScreen({
    super.key,
    required this.formState,
    required this.onEditJourney,
    required this.onEditPassengers,
    required this.onConfirm,
    this.trainName = 'Jahanabad Express',
    this.originCode = 'DHK',
    this.originName = 'Dhaka',
    this.destinationCode = 'KHL',
    this.destinationName = 'Khulna',
    this.dateLabel = 'Thu, 11 Sep 2025',
    this.classLabel = '5 Chair (D)',
    this.departureLabel = '08:00 PM',
    this.arrivalLabel = '11:45 PM',
    this.durationLabel = '3h 45m',
  });

  @override
  State<BookingReviewScreen> createState() => _BookingReviewScreenState();
}

class _BookingReviewScreenState extends State<BookingReviewScreen> {
  bool _termsAccepted = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        backgroundColor: _primaryTeal,
        foregroundColor: Colors.white,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: const Text('Booking Review'),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: widget.formState,
        builder: (context, _) => _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final form = widget.formState;
    if (form.count == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No passengers to review. Go back and add passenger details first.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final breakdown = form.fareBreakdown;
    final confirmEnabled = _termsAccepted && form.isValid;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _Stepper(currentStep: 1),
        const SizedBox(height: 16),
        _buildJourneyCard(),
        const SizedBox(height: 12),
        _buildTrainCard(),
        const SizedBox(height: 12),
        _buildPassengersCard(),
        const SizedBox(height: 12),
        _buildFareCard(breakdown),
        const SizedBox(height: 12),
        _buildTermsRow(),
        const SizedBox(height: 12),
        const Text(
          'Demonstration booking — no real money is charged.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: confirmEnabled ? widget.onConfirm : null,
            style: FilledButton.styleFrom(
              backgroundColor: _primaryTeal,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Confirm Booking',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildJourneyCard() {
    final form = widget.formState;
    final codes = form.seatCodes.join(', ');
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Journey Summary',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              TextButton(
                onPressed: widget.onEditJourney,
                child: const Text('Edit'),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.originCode,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      widget.originName,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.train, color: _primaryTeal, size: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      widget.destinationCode,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      widget.destinationName,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: 18,
                color: _primaryTeal,
              ),
              const SizedBox(width: 6),
              Text(widget.dateLabel, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 16),
              const Icon(
                Icons.event_seat_outlined,
                size: 18,
                color: _primaryTeal,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${form.count} Seat${form.count > 1 ? 's' : ''}  $codes • ${widget.classLabel}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrainCard() {
    final form = widget.formState;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Train Details',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF0F6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.train, color: _primaryTeal),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.trainName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                'BDT ${form.fareBdt}',
                style: const TextStyle(
                  color: _primaryTeal,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _TrainFact(label: 'Departure', value: widget.departureLabel),
              _TrainFact(label: 'Arrival', value: widget.arrivalLabel),
              _TrainFact(label: 'Duration', value: widget.durationLabel),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPassengersCard() {
    final passengers = widget.formState.passengers;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Passengers (${passengers.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              TextButton(
                onPressed: widget.onEditPassengers,
                child: const Text('Edit'),
              ),
            ],
          ),
          for (var i = 0; i < passengers.length; i++) ...[
            _PassengerRow(index: i, passenger: passengers[i]),
            if (i < passengers.length - 1) const Divider(height: 20),
          ],
        ],
      ),
    );
  }

  Widget _buildFareCard(Map<String, int> breakdown) {
    final count = breakdown['passengerCount'] ?? 0;
    final perSeat = breakdown['farePerSeat'] ?? 0;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fare Breakdown',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          _FareRow(
            label: 'Base Fare ($count × BDT $perSeat)',
            value: 'BDT ${breakdown['baseFare'] ?? 0}',
          ),
          const SizedBox(height: 4),
          _FareRow(
            label: 'Service Charge',
            value: 'BDT ${breakdown['serviceCharge'] ?? 0}',
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Amount',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'BDT ${breakdown['total'] ?? 0}',
                style: const TextStyle(
                  color: _primaryTeal,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTermsRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: _termsAccepted,
          activeColor: _primaryTeal,
          onChanged: (value) => setState(() => _termsAccepted = value ?? false),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _termsAccepted = !_termsAccepted),
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text.rich(
                TextSpan(
                  text: 'I have read and agree to the ',
                  style: const TextStyle(fontSize: 13),
                  children: [
                    TextSpan(
                      text: 'Terms & Conditions',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _TrainFact extends StatelessWidget {
  final String label;
  final String value;

  const _TrainFact({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _PassengerRow extends StatelessWidget {
  final int index;
  final Passenger passenger;

  const _PassengerRow({required this.index, required this.passenger});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFFEAF0F6),
            shape: BoxShape.circle,
          ),
          child: Text(
            '${index + 1}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                passenger.name.isEmpty ? '—' : passenger.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                passenger.type == null ? 'Type not set' : passenger.type!.label,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              passenger.seatCode,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text(
              '5 Chair (D)',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

class _FareRow extends StatelessWidget {
  final String label;
  final String value;

  const _FareRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.black87)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    );
  }
}

/// Shared three-step header: step 0 Passengers, 1 Review, 2 Payment.
class _Stepper extends StatelessWidget {
  final int currentStep;

  const _Stepper({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    const labels = ['Passengers', 'Review', 'Payment'];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          Expanded(
            child: _StepDot(
              index: i,
              currentStep: currentStep,
              label: labels[i],
            ),
          ),
          if (i < labels.length - 1)
            const Expanded(
              child: Divider(color: Color(0xFFD4DDE3), thickness: 1),
            ),
        ],
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  final int index;
  final int currentStep;
  final String label;

  const _StepDot({
    required this.index,
    required this.currentStep,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final done = index < currentStep;
    final active = index == currentStep;
    final Color fill = done || active ? _primaryTeal : const Color(0xFFEAF0F6);
    final Color foreground = done || active ? Colors.white : Colors.black54;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
          child: done
              ? const Icon(Icons.check, color: Colors.white, size: 18)
              : Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: active ? Colors.black87 : Colors.grey,
          ),
        ),
      ],
    );
  }
}
