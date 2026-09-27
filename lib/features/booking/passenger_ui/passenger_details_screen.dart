import 'package:flutter/material.dart';

import 'passenger.dart';
import 'passenger_form_state.dart';

const Color _primaryTeal = Color(0xFF0E5A66);
const Color _pageBackground = Color(0xFFF4F7F9);
const Color _inputBorder = Color(0xFFE1E8ED);
const Color _hintGrey = Color(0xFF9AA5B1);

/// Ref-4 "Passenger Details" screen (step 1 of Passengers > Review > Payment).
///
/// Renders purely from the host-owned [formState] (packet B05): the widget
/// never creates or disposes the state object, so typed names/types/contact
/// survive passenger-tab switches and back navigation. [TextEditingController]s
/// are widget-local and seeded from [formState] on first build.
///
/// Collects name + Adult/Child type per seat plus one shared contact
/// (mobile + optional email). No government ID and no payment fields are
/// collected anywhere on this screen (packet stop condition).
///
/// [onContinue] receives the validated passenger list snapshot.
class PassengerDetailsScreen extends StatefulWidget {
  final PassengerFormState formState;
  final String trainName;
  final String originCode;
  final String originName;
  final String destinationCode;
  final String destinationName;
  final String dateLabel;
  final String classLabel;
  final ValueChanged<List<Passenger>> onContinue;

  const PassengerDetailsScreen({
    super.key,
    required this.formState,
    required this.onContinue,
    this.trainName = 'Jahanabad Express',
    this.originCode = 'DHK',
    this.originName = 'Dhaka',
    this.destinationCode = 'KHL',
    this.destinationName = 'Khulna',
    this.dateLabel = 'Thu, 11 Sep 2025',
    this.classLabel = '5 Chair (D)',
  });

  @override
  State<PassengerDetailsScreen> createState() => _PassengerDetailsScreenState();
}

class _PassengerDetailsScreenState extends State<PassengerDetailsScreen> {
  int _activeTab = 0;
  final Map<String, TextEditingController> _nameControllers =
      <String, TextEditingController>{};
  late TextEditingController _mobileController;
  late TextEditingController _emailController;
  bool _mobileTouched = false;
  bool _emailTouched = false;
  final Set<String> _nameTouched = <String>{};

  @override
  void initState() {
    super.initState();
    _mobileController = TextEditingController(
      text: widget.formState.contactMobile,
    );
    _emailController = TextEditingController(
      text: widget.formState.contactEmail,
    );
    _syncNameControllers();
  }

  @override
  void didUpdateWidget(PassengerDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.formState, widget.formState)) {
      _disposeNameControllers();
      _mobileController.dispose();
      _emailController.dispose();
      _mobileController = TextEditingController(
        text: widget.formState.contactMobile,
      );
      _emailController = TextEditingController(
        text: widget.formState.contactEmail,
      );
      _activeTab = 0;
      _nameTouched.clear();
      _syncNameControllers();
    } else {
      _syncNameControllers();
    }
  }

  @override
  void dispose() {
    _disposeNameControllers();
    _mobileController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _disposeNameControllers() {
    for (final controller in _nameControllers.values) {
      controller.dispose();
    }
    _nameControllers.clear();
  }

  /// Ensures one controller per current seat code, seeded from the
  /// host-owned state (new codes get the preserved/blank name).
  void _syncNameControllers() {
    final seats = widget.formState.seatCodes;
    for (final key in List<String>.of(_nameControllers.keys)) {
      if (!seats.contains(key)) {
        _nameControllers.remove(key)?.dispose();
        _nameTouched.remove(key);
      }
    }
    for (final passenger in widget.formState.passengers) {
      final existing = _nameControllers[passenger.seatCode];
      if (existing == null) {
        _nameControllers[passenger.seatCode] = TextEditingController(
          text: passenger.name,
        );
      } else if (existing.text != passenger.name &&
          !_nameTouched.contains(passenger.seatCode)) {
        existing.text = passenger.name;
      }
    }
    if (_activeTab >= seats.length) _activeTab = 0;
  }

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
        title: const Text('Passenger Details'),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: widget.formState,
        builder: (context, _) {
          _syncNameControllers();
          return _buildBody(context);
        },
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
            'No seats selected. Go back and choose 1–4 seats first.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final index = _activeTab.clamp(0, form.count - 1);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _Stepper(currentStep: 0),
        const SizedBox(height: 16),
        _buildJourneyCard(),
        const SizedBox(height: 16),
        _buildPassengerTabs(),
        const SizedBox(height: 12),
        _buildNameField(index),
        const SizedBox(height: 12),
        _buildTypeField(index),
        const SizedBox(height: 16),
        _buildContactCard(),
        const SizedBox(height: 16),
        _buildContinueButton(),
      ],
    );
  }

  Widget _buildJourneyCard() {
    final form = widget.formState;
    final codes = form.seatCodes.join(', ');
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
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

  Widget _buildPassengerTabs() {
    final form = widget.formState;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF0F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (var i = 0; i < form.count; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _activeTab = i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: i == _activeTab ? _primaryTeal : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Passenger ${i + 1}',
                    style: TextStyle(
                      color: i == _activeTab ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNameField(int index) {
    final passenger = widget.formState.passengers[index];
    final controller = _nameControllers[passenger.seatCode]!;
    final touched = _nameTouched.contains(passenger.seatCode);
    final error = touched ? Passenger.validateName(controller.text) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: 'Full Name ',
            style: const TextStyle(fontSize: 13),
            children: [
              TextSpan(
                text: '• Seat ${passenger.seatCode}',
                style: const TextStyle(
                  color: _primaryTeal,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.person_outline),
            hintText: 'Tanvir Ahmed',
            hintStyle: const TextStyle(color: _hintGrey),
            errorText: error,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _inputBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _inputBorder),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
          onChanged: (value) {
            _nameTouched.add(passenger.seatCode);
            widget.formState.updateName(index, value);
          },
        ),
      ],
    );
  }

  Widget _buildTypeField(int index) {
    final passenger = widget.formState.passengers[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Passenger Type', style: TextStyle(fontSize: 13)),
        const SizedBox(height: 6),
        DropdownButtonFormField<PassengerType>(
          initialValue: passenger.type,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.badge_outlined),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _inputBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _inputBorder),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
          hint: const Text('Select type', style: TextStyle(color: _hintGrey)),
          items: const [
            DropdownMenuItem(
              value: PassengerType.adult,
              child: Text('Adult (A)'),
            ),
            DropdownMenuItem(
              value: PassengerType.child,
              child: Text('Child (C)'),
            ),
          ],
          onChanged: (value) => widget.formState.updateType(index, value),
        ),
      ],
    );
  }

  Widget _buildContactCard() {
    final form = widget.formState;
    final mobileError = _mobileTouched
        ? PassengerFormState.validateContactMobile(_mobileController.text)
        : null;
    final emailError = _emailTouched
        ? PassengerFormState.validateContactEmail(_emailController.text)
        : null;
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Contact Information',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 4),
          const Text(
            'We will send booking confirmation to this contact.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 12),
          const Text('Mobile Number', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _mobileController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.phone_outlined),
              hintText: '01712 345678',
              hintStyle: const TextStyle(color: _hintGrey),
              errorText: mobileError,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _inputBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _inputBorder),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: (value) {
              _mobileTouched = true;
              form.setContactMobile(value);
            },
          ),
          const SizedBox(height: 12),
          const Text(
            'Email Address (optional)',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.mail_outline),
              hintText: 'tanvir.ahmed@example.com',
              hintStyle: const TextStyle(color: _hintGrey),
              errorText: emailError,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _inputBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _inputBorder),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: (value) {
              _emailTouched = true;
              form.setContactEmail(value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildContinueButton() {
    final enabled = widget.formState.isValid;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: enabled
            ? () => widget.onContinue(
                List<Passenger>.of(widget.formState.passengers),
              )
            : null,
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
            Text('Continue', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward),
          ],
        ),
      ),
    );
  }
}

/// Three-step header shared with the review screen: 1 Passengers,
/// 2 Review, 3 Payment. [currentStep] is 0-indexed.
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
