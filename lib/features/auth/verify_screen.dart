/// A02 — Email verification screen (RailMate BD).
///
/// Link-first confirmation. The production signup mail (default Supabase
/// mailer, no custom SMTP) carries a confirmation *link*, not a 6-digit
/// code, so this screen offers no code entry. The primary path is tapping
/// the link in the email — it returns to the app through
/// `railmatebd://auth/verify` and signs the user in (see
/// `signup_verify.dart` + `AppGate`) — then "I've confirmed — re-check".
/// "Resend confirmation email" (60 s throttle) stays.
///
/// The typed-code seam ([AuthState.verifyCode] → real `verifyOTP`) is kept
/// dormant for future custom-SMTP/template support; no production UI calls
/// it today.
///
/// Phone OTP is the A03 lane and is email-verification state only here: the
/// phone fallback button explains that and does not start any phone flow.
///
/// V4 P08 polish (behavior unchanged): one-shot [FadeSlideIn] entrances and
/// [AnimatedSwap] on the error/info messages and the re-check button's busy
/// state. The per-second resend countdown is deliberately NOT swapped — a
/// cross-fade every second is visual noise, not signal.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/design.dart';
import 'auth_state.dart';
import 'auth_theme.dart';

/// Email confirmation screen shown after registration (or on login with an
/// unconfirmed email).
class VerifyScreen extends StatefulWidget {
  /// Shared session state driving verification.
  final AuthState auth;

  /// Address the confirmation email was sent to.
  final String email;

  /// Route name for guard-friendly navigation.
  static const String routeName = '/verify';

  const VerifyScreen({super.key, required this.auth, required this.email});

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  static const int _resendSeconds = 60;

  Timer? _timer;
  int _secondsLeft = _resendSeconds;
  String? _formError;
  String? _infoMessage;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
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

  Future<void> _recheck() async {
    setState(() {
      _formError = null;
      _infoMessage = null;
    });
    await widget.auth.refreshVerification();
    if (!mounted) return;
    if (widget.auth.status == AuthStatus.authenticated) {
      setState(() => _infoMessage = 'Email verified. Welcome aboard!');
      Navigator.of(context).pop(true);
    } else {
      setState(
        () => _infoMessage =
            'Still not confirmed. Open the confirmation link in your email, '
            'then re-check.',
      );
    }
  }

  Future<void> _resend() async {
    setState(() {
      _formError = null;
      _infoMessage = null;
    });
    await widget.auth.resendConfirmation(widget.email);
    if (!mounted) return;
    if (widget.auth.status == AuthStatus.error) {
      setState(() => _formError = widget.auth.errorMessage);
    } else {
      setState(
        () => _infoMessage = 'Confirmation email re-sent to ${widget.email}.',
      );
      _startTimer();
    }
  }

  void _phoneFallback() {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Verify with Phone Number'),
        content: const Text(
          'Phone OTP verification arrives in a later release '
          '(A03 lane). Please verify your email address for now.',
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
                    "We've sent a confirmation email to ${widget.email}. "
                    'Tap the confirmation link inside — it opens RailMate BD '
                    'and signs you in.',
              ),
            ),
            FadeSlideIn(
              delay: const Duration(milliseconds: 60),
              child: AuthSheet(
                child: ListenableBuilder(
                  listenable: widget.auth,
                  builder: (BuildContext context, _) {
                    final bool busy = widget.auth.isBusy;
                    return Column(
                      children: <Widget>[
                        const _VerifyStep(
                          icon: Icons.mark_email_read_outlined,
                          text: 'Open the confirmation email we sent you.',
                        ),
                        const SizedBox(height: 10),
                        const _VerifyStep(
                          icon: Icons.open_in_new,
                          text:
                              'Tap the confirmation link — it returns you to '
                              'the app, already signed in.',
                        ),
                        const SizedBox(height: 10),
                        const _VerifyStep(
                          icon: Icons.check_circle_outline,
                          text:
                              'If you confirmed in your browser instead, tap '
                              '"I\'ve confirmed — re-check" below.',
                        ),
                        const SizedBox(height: 20),
                        AnimatedSwap(
                          child: AuthPrimaryButton(
                            key: ValueKey<bool>(busy),
                            label: "I've confirmed — re-check",
                            loading: busy,
                            onPressed: busy ? null : _recheck,
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
                              'Resend confirmation email',
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
                          "We'll send a 6-digit code to your mobile number "
                          'in a later release.',
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

/// One numbered-style instruction row in the link-first verify flow.
class _VerifyStep extends StatelessWidget {
  final IconData icon;
  final String text;

  const _VerifyStep({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, color: kAuthTeal, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 14, height: 1.4)),
        ),
      ],
    );
  }
}
