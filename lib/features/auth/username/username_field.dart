/// B02 — username input with live availability feedback (RailMate BD).
///
/// Register-screen field per UI_VISUAL_SPEC ref-2: teal-styled text input,
/// green `Available` pill, red taken message, spinner while checking.
///
/// Styling reuses the shared auth tokens (`auth_theme.dart`) so this field
/// matches `AuthField` exactly — same label, hint, border radius, fill and
/// focus colour - instead of carrying a private copy of the palette.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../auth_theme.dart';
import 'username.dart';
import 'username_availability.dart';

/// Debounced username input wired to a [UsernameAvailabilityChecker].
///
/// Invalid format short-circuits locally (no query); valid input waits for
/// [debounce] of idle time, then shows a spinner while the checker runs.
/// Stale responses are discarded so fast typing cannot show a wrong state.
class UsernameField extends StatefulWidget {
  /// Checker with injectable query (fake in tests, Supabase query in prod).
  final UsernameAvailabilityChecker checker;

  /// Optional external controller; an internal one is used when null.
  final TextEditingController? controller;

  /// Emitted whenever the availability status settles or changes.
  final ValueChanged<UsernameAvailability>? onStatusChanged;

  /// Idle delay before a keystroke triggers a server check.
  final Duration debounce;

  const UsernameField({
    super.key,
    required this.checker,
    this.controller,
    this.onStatusChanged,
    this.debounce = const Duration(milliseconds: 400),
  });

  @override
  State<UsernameField> createState() => _UsernameFieldState();
}

class _UsernameFieldState extends State<UsernameField> {
  late final TextEditingController _controller;
  bool _ownsController = false;
  Timer? _debounce;
  int _request = 0;
  UsernameAvailability _status = UsernameAvailability.initial;

  /// Current availability status (for form gating by the parent screen).
  UsernameAvailability get status => _status;

  /// Normalized value of the current input.
  String get normalizedUsername => normalizeUsername(_controller.text);

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _controller = TextEditingController();
      _ownsController = true;
    } else {
      _controller = widget.controller!;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _setStatus(UsernameAvailability status) {
    if (_status == status) return;
    setState(() => _status = status);
    widget.onStatusChanged?.call(status);
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final String normalized = normalizeUsername(value);
    if (normalized.isEmpty) {
      _setStatus(UsernameAvailability.initial);
      return;
    }
    if (!isValidUsername(normalized)) {
      _setStatus(UsernameAvailability.invalid);
      return;
    }
    _debounce = Timer(widget.debounce, () => _query(normalized));
  }

  Future<void> _query(String normalized) async {
    final int token = ++_request;
    _setStatus(UsernameAvailability.checking);
    final UsernameAvailability result = await widget.checker.check(normalized);
    if (!mounted || token != _request) return;
    _setStatus(result);
  }

  Widget _availablePill() {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      // `widthFactor`/`heightFactor` keep the pill shrink-wrapped. A plain
      // `Center` expands to the field's full width, which squeezed the text
      // area to zero and hid what the user typed.
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: kAuthGreen,
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text(
            'Available',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool checking = _status == UsernameAvailability.checking;
    final bool available = _status == UsernameAvailability.available;

    String? errorText;
    if (_status == UsernameAvailability.taken) {
      errorText = 'That username is taken — try another.';
    } else if (_status == UsernameAvailability.invalid) {
      errorText = validateUsername(_controller.text);
    } else if (_status == UsernameAvailability.error) {
      errorText = 'Could not check availability — retry.';
    }

    Widget? suffix;
    if (checking) {
      suffix = const Padding(
        padding: EdgeInsets.only(right: 12),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(color: kAuthTeal, strokeWidth: 2),
          ),
        ),
      );
    } else if (available) {
      suffix = _availablePill();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Username',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          onChanged: _onChanged,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.none,
          keyboardType: TextInputType.text,
          decoration: InputDecoration(
            hintText: 'Choose a username',
            hintStyle: const TextStyle(color: kAuthHint, fontSize: 14),
            prefixIcon: const Icon(
              Icons.alternate_email,
              color: Colors.black54,
            ),
            suffixIcon: suffix,
            errorText: errorText,
            errorStyle: const TextStyle(color: kAuthDanger),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: kAuthBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: kAuthBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: kAuthTeal, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
