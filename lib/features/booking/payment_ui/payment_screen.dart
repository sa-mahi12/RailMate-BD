import 'package:flutter/material.dart';

import '../passenger_ui/passenger_form_state.dart';
import 'payment_state.dart';

const Color _primaryTeal = Color(0xFF0E5A66);
const Color _successGreen = Color(0xFF1E9E6A);
const Color _dangerRed = Color(0xFFE5484D);
const Color _pageBackground = Color(0xFFF4F7F9);

/// Ref-4 "Payment" screen (step 3 of Passengers > Review > Payment).
///
/// Simulated payment only: two buttons drive [paymentState]
/// (`Simulate success` / `Simulate failure`). No real financial integration
/// and no credential input exists on this screen — no card, bKash, Nagad or
/// bank fields are collected, per the packet stop condition.
///
/// Fare numbers are read live from the host-owned [formState]
/// (`fareBreakdown`/`totalBdt`, packet B05 API). The host also owns
/// [paymentState]; this screen never creates, replaces or disposes either
/// object. [onSucceeded] fires once when the state reaches
/// [PaymentStatus.succeeded] so the host can enter the booking lane; a
/// failure creates no booking intent and stays on this screen.
///
/// Includes a one-line demonstration notice (no real money is charged).
class PaymentScreen extends StatelessWidget {
  final PassengerFormState formState;
  final PaymentState paymentState;
  final VoidCallback onSucceeded;

  const PaymentScreen({
    super.key,
    required this.formState,
    required this.paymentState,
    required this.onSucceeded,
  });

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
        title: const Text('Payment'),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([formState, paymentState]),
        builder: (context, _) => _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final breakdown = formState.fareBreakdown;
    final status = paymentState.status;
    final busy = status == PaymentStatus.processing;
    final done = status == PaymentStatus.succeeded;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _Stepper(currentStep: 2),
        const SizedBox(height: 16),
        _FareCard(breakdown: breakdown),
        const SizedBox(height: 12),
        _StatusCard(status: status),
        const SizedBox(height: 12),
        const Text(
          'DEMONSTRATION ONLY — no real money is charged and no payment credentials are collected.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: busy || done
                ? null
                : () {
                    if (paymentState.simulateSuccess()) onSucceeded();
                  },
            style: FilledButton.styleFrom(
              backgroundColor: _successGreen,
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
                  'Simulate success',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(width: 8),
                Icon(Icons.check_circle_outline),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: busy || done
                ? null
                : () => paymentState.simulateFailure(),
            style: FilledButton.styleFrom(
              backgroundColor: _dangerRed,
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
                  'Simulate failure',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(width: 8),
                Icon(Icons.cancel_outlined),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FareCard extends StatelessWidget {
  final Map<String, int> breakdown;

  const _FareCard({required this.breakdown});

  @override
  Widget build(BuildContext context) {
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
}

class _StatusCard extends StatelessWidget {
  final PaymentStatus status;

  const _StatusCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      PaymentStatus.idle => (
        'No payment simulated yet.',
        Colors.black54,
        Icons.info_outline,
      ),
      PaymentStatus.processing => (
        'Processing…',
        _primaryTeal,
        Icons.hourglass_empty,
      ),
      PaymentStatus.succeeded => (
        'Payment simulated: SUCCESS. Booking intent created.',
        _successGreen,
        Icons.check_circle,
      ),
      PaymentStatus.failed => (
        'Payment simulated: FAILED. No booking was created.',
        _dangerRed,
        Icons.error_outline,
      ),
      PaymentStatus.unknown => (
        'Unrecognized response. Reconcile by request ID before retrying.',
        Colors.black54,
        Icons.help_outline,
      ),
    };
    return _Card(
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
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
