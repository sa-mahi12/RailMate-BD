/// A02 — Email verification screen (RailMate BD).
///
/// Supabase signup emails carry a real six-digit token through Mailjet.
/// Code verification uses the existing [AuthState.verifyCode] path; the
/// root gate advances on a confirmed session. Old auth callbacks remain
/// supported separately, and password recovery stays link-based.
///
/// Phone OTP is the A03 lane. Production passes a real [PhoneState] (backed by
/// the Supabase adapter), so the fallback button opens the actual
/// [PhoneVerifyScreen]: a real code request, a real 6-digit verify and honest
/// provider errors. When no state is injected (hermetic widget tests) the
/// button explains that the phone lane is unavailable in that build.
///
/// V4 P08 polish (behavior unchanged): one-shot [FadeSlideIn] entrances and
/// [AnimatedSwap] on the error/info messages and the verify button's busy
/// state. The per-second resend countdown is deliberately NOT swapped — a
/// cross-fade every second is visual noise, not signal.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/design.dart';
import 'auth_state.dart';
import 'auth_theme.dart';
import 'phone/phone_state.dart';
import 'phone/phone_verify_screen.dart';

/// Email confirmation screen shown after registration (or on login with an
/// unconfirmed email).
class VerifyScreen extends StatefulWidget {
  /// Shared session state driving verification.
  final AuthState auth;

  /// Address the confirmation email was sent to.
  final String email;

  /// Optional phone lane state. Production injects the composed real state;
  /// null (tests only) keeps the button honest about the lane being absent.
  final PhoneState? phoneState;

  /// Route name for guard-friendly navigation.
  static const String routeName = '/verify';

  const VerifyScreen({
    super.key,
    required this.auth,
    required this.email,
    this.phoneState,
  });

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  static const int _resendSeconds = 60;

  Timer? _timer;
  int _secondsLeft = _resendSeconds;
  String? _formError;
  String? _infoMessage;
  final TextEditingController _code = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft -= 1);
      }
    });
  }

  String get _timerText {
    final String m = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final String s = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _verify() async {
    if (_submitting || widget.auth.isBusy) return;
    if (!RegExp(r'^[0-9]{6}$').hasMatch(_code.text)) {
      setState(() => _formError = 'Enter the 6-digit code from your email.');
      return;
    }
    setState(() {
      _submitting = true;
      _formError = null;
      _infoMessage = null;
    });
    await widget.auth.verifyCode(email: widget.email, token: _code.text);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (widget.auth.status == AuthStatus.authenticated) {
      setState(() => _infoMessage = 'Email verified. Welcome aboard!');
      // Root verification belongs to AppGate; only close a pushed auth pane.
      final route = ModalRoute.of(context);
      if (route != null && !route.isFirst && route.isCurrent) {
        Navigator.of(context).pop(true);
      }
    } else {
      setState(() => _formError = widget.auth.errorMessage);
    }
  }

  Future<void> _resend() async {
    if (_secondsLeft > 0 || _submitting || widget.auth.isBusy) return;
    setState(() {
      _submitting = true;
      _formError = null;
      _infoMessage = null;
    });
    await widget.auth.resendConfirmation(widget.email);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (widget.auth.errorMessage.isNotEmpty) {
      setState(() => _formError = widget.auth.errorMessage);
    } else {
      setState(
        () => _infoMessage =
            'A new code was requested. Check your Inbox or Spam.',
      );
      _startTimer();
    }
  }

  Future<void> _phoneFallback() async {
    final PhoneState? phones = widget.phoneState;
    if (phones != null) {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (BuildContext context) => PhoneVerifyScreen(phones: phones),
        ),
      );
      if (!mounted) return;
      if (phones.isPhoneVerified) {
        setState(
          () => _infoMessage =
              'Phone number verified. You can keep using this account.',
        );
      }
      return;
    }
    // No phone lane in this composition (hermetic tests / unwired host).
    // Never pretend a code was sent.
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Verify with Phone Number'),
        content: const Text(
          'Phone verification is not available in this build. '
          'Please verify your email address.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kAuthPageBg,
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            FadeSlideIn(
              child: AuthHeader(
                title: 'Verify your account',
                subtitle:
                    'Enter the 6-digit code sent to ${widget.email}. '
                    'Check your Inbox or Spam folder.',
              ),
            ),
            FadeSlideIn(
              delay: const Duration(milliseconds: 60),
              child: AuthSheet(
                child: ListenableBuilder(
                  listenable: widget.auth,
                  builder: (BuildContext context, _) {
                    final bool busy = _submitting || widget.auth.isBusy;
                    return Column(
                      children: <Widget>[
                        TextField(
                          controller: _code,
                          enabled: !busy,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          autofillHints: const <String>[
                            AutofillHints.oneTimeCode,
                          ],
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Email verification code',
                            hintText: '6 digits',
                          ),
                          onSubmitted: (_) => _verify(),
                        ),
                        const SizedBox(height: 20),
                        AnimatedSwap(
                          child: AuthPrimaryButton(
                            key: ValueKey<bool>(busy),
                            label: 'Verify code',
                            loading: busy,
                            onPressed: busy ? null : _verify,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text("Didn't receive the email?"),
                        const SizedBox(height: 4),
                        if (_secondsLeft > 0)
                          Text(
                            'Resend in $_timerText',
                            style: const TextStyle(
                              color: kAuthTeal,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        else
                          TextButton(
                            onPressed: busy ? null : _resend,
                            child: const Text(
                              'Resend code',
                              style: TextStyle(color: kAuthTeal),
                            ),
                          ),
                        if (_formError != null) ...<Widget>[
                          const SizedBox(height: 8),
                          AnimatedSwap(
                            child: Text(
                              _formError!,
                              key: ValueKey<String>('err_${_formError!}'),
                              style: const TextStyle(color: kAuthDanger),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                        if (_infoMessage != null) ...<Widget>[
                          const SizedBox(height: 8),
                          AnimatedSwap(
                            child: Text(
                              _infoMessage!,
                              key: ValueKey<String>('info_$_infoMessage'),
                              style: const TextStyle(color: kAuthGreen),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: <Widget>[
                            const Expanded(child: Divider()),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                'Or',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton.icon(
                            onPressed: busy ? null : _phoneFallback,
                            icon: const Icon(
                              Icons.phone_outlined,
                              color: kAuthTeal,
                            ),
                            label: const Text(
                              'Verify with Phone Number',
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
                          "We'll send a 6-digit code to your mobile number.",
                          style: TextStyle(color: kAuthHint, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
