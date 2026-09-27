/// A03 — phone number verification screen (RailMate BD).
///
/// Ref-3 Verify panel adapted to the phone lane: two states in one screen —
/// a request-code state (phone input + Send Code) and a verify state (6 OTP
/// boxes + resend timer + Verify button). Styling follows `auth_theme.dart`
/// (deep teal `#0E5A66`, white radius-16 sheet, radius-12 primary button,
/// radius-10 inputs) and mirrors `verify_screen.dart` interaction patterns
/// (paste-spread OTP boxes, digit-only input, focus traversal).
///
/// Live SMS status: BLOCKED (S04 not met — no provider/budget). The screen
/// drives only the injected [PhoneState] and shows a demo-only notice, so
/// no tap here can send or claim a live SMS. On success it pops `true` via
/// [Navigator] like the email verify screen.
///
/// Phone validation: Bangladeshi E.164 (`+880...`) enforced by
/// [PhoneAuthRepository]; server rate limits surface distinctly from wrong
/// codes via [PhoneState.rateLimited].
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth_theme.dart';
import 'phone_state.dart';

/// Phone OTP verification screen: request-code state, then verify state.
class PhoneVerifyScreen extends StatefulWidget {
  /// Shared phone-verification state (repository-injected: Supabase adapter
  /// after S04 approval, fake until then).
  final PhoneState phones;

  /// Route name for guard-friendly navigation.
  static const String routeName = '/verify-phone';

  const PhoneVerifyScreen({super.key, required this.phones});

  @override
  State<PhoneVerifyScreen> createState() => _PhoneVerifyScreenState();
}

class _PhoneVerifyScreenState extends State<PhoneVerifyScreen> {
  static const int _codeLength = 6;

  final TextEditingController _phoneController = TextEditingController();
  late final List<TextEditingController> _boxes;
  late final List<FocusNode> _nodes;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _boxes = List<TextEditingController>.generate(
      _codeLength,
      (_) => TextEditingController(),
    );
    _nodes = List<FocusNode>.generate(_codeLength, (_) => FocusNode());
    // Re-renders the resend countdown each second while a code is pending.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.phones.hasPendingCode) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _phoneController.dispose();
    for (final TextEditingController c in _boxes) {
      c.dispose();
    }
    for (final FocusNode n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  String get _code => _boxes.map((TextEditingController c) => c.text).join();

  bool get _codeComplete =>
      _code.length == _codeLength && int.tryParse(_code) != null;

  String _timerText(Duration left) {
    final String m = (left.inSeconds ~/ 60).toString().padLeft(2, '0');
    final String s = (left.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _onBoxChanged(int index, String value) {
    if (value.length > 1) {
      // Pasted content: spread digits across remaining boxes.
      final String digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      for (int i = 0; i < digits.length && index + i < _codeLength; i++) {
        _boxes[index + i].text = digits[i];
      }
      if (index + digits.length < _codeLength) {
        _nodes[index + digits.length].requestFocus();
      } else {
        _nodes[_codeLength - 1].unfocus();
      }
    } else if (value.isNotEmpty && index + 1 < _codeLength) {
      _nodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _nodes[index - 1].requestFocus();
    }
    setState(() {});
  }

  Future<void> _sendCode() async {
    widget.phones.clearError();
    await widget.phones.requestCode(_phoneController.text);
  }

  Future<void> _verify() async {
    await widget.phones.verifyCode(_code);
    if (!mounted) return;
    if (widget.phones.isPhoneVerified) {
      Navigator.of(context).pop(true);
    }
  }

  void _useDifferentNumber() {
    for (final TextEditingController c in _boxes) {
      c.clear();
    }
    widget.phones.reset();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kAuthPageBg,
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            AuthHeader(
              title: 'Verify with Phone Number',
              subtitle:
                  "We'll send a 6-digit code to your mobile number. "
                  'Enter it below.',
            ),
            AuthSheet(
              child: ListenableBuilder(
                listenable: widget.phones,
                builder: (BuildContext context, _) {
                  final PhoneState phones = widget.phones;
                  final bool busy = phones.isBusy;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const _DemoSmsNotice(),
                      const SizedBox(height: 16),
                      if (!phones.hasPendingCode) ...<Widget>[
                        _requestState(phones, busy),
                      ] else ...<Widget>[_verifyState(phones, busy)],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _requestState(PhoneState phones, bool busy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AuthField(
          label: 'Phone Number',
          hint: '+880 1712 345678',
          icon: Icons.phone_outlined,
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          onChanged: (_) {
            if (phones.errorMessage.isNotEmpty) phones.clearError();
          },
        ),
        if (phones.errorMessage.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            phones.errorMessage,
            style: const TextStyle(color: kAuthDanger),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 16),
        AuthPrimaryButton(
          label: 'Send Code',
          loading: busy,
          onPressed: busy || _phoneController.text.trim().isEmpty
              ? null
              : _sendCode,
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('Or', style: TextStyle(color: Colors.grey.shade600)),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: busy ? null : () => Navigator.of(context).pop(false),
            icon: const Icon(Icons.email_outlined, color: kAuthTeal),
            label: const Text(
              'Verify with Email Instead',
              style: TextStyle(color: kAuthTeal),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kAuthTeal),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Bangladeshi numbers only (+880). Standard SMS rates would '
          'apply once a provider is approved.',
          style: TextStyle(color: kAuthHint, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _verifyState(PhoneState phones, bool busy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          "We've sent a 6-digit code to ${phones.phone}. Enter it below.",
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List<Widget>.generate(_codeLength, (int i) {
            return SizedBox(
              width: 44,
              height: 52,
              child: TextField(
                controller: _boxes[i],
                focusNode: _nodes[i],
                enabled: !busy,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 2,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                onChanged: (String v) => _onBoxChanged(i, v),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: EdgeInsets.zero,
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
            );
          }),
        ),
        const SizedBox(height: 16),
        const Text("Didn't receive the code?", textAlign: TextAlign.center),
        const SizedBox(height: 4),
        if (!phones.canResend)
          Text(
            'Resend in ${_timerText(phones.resendRemaining)}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: kAuthTeal,
              fontWeight: FontWeight.w600,
            ),
          )
        else
          TextButton(
            onPressed: busy ? null : phones.resend,
            child: const Text(
              'Resend code',
              style: TextStyle(color: kAuthTeal),
            ),
          ),
        if (phones.errorMessage.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (phones.rateLimited)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(
                    Icons.timer_outlined,
                    color: kAuthDanger,
                    size: 18,
                  ),
                ),
              Flexible(
                child: Text(
                  phones.rateLimited
                      ? 'Too many attempts — ${phones.errorMessage}'
                      : phones.errorMessage,
                  style: const TextStyle(color: kAuthDanger),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        AuthPrimaryButton(
          label: 'Verify',
          loading: busy,
          onPressed: busy || !_codeComplete ? null : _verify,
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('Or', style: TextStyle(color: Colors.grey.shade600)),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: busy ? null : _useDifferentNumber,
            icon: const Icon(Icons.phone_outlined, color: kAuthTeal),
            label: const Text(
              'Use a Different Number',
              style: TextStyle(color: kAuthTeal),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kAuthTeal),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Honest capability banner: live SMS is not configured, so this build only
/// demonstrates the flow and never sends (or claims) a real code.
class _DemoSmsNotice extends StatelessWidget {
  const _DemoSmsNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF0C36D)),
      ),
      child: const Row(
        children: <Widget>[
          Icon(Icons.info_outline, color: Color(0xFF8A6D1B), size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'DEMO ONLY — live SMS is not set up yet, so no real code '
              'is sent in this build.',
              style: TextStyle(color: Color(0xFF8A6D1B), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
