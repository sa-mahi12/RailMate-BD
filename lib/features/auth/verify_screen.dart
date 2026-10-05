/// A02 — Email verification screen (RailMate BD).
///
/// Ref-3 left panel: 6 OTP boxes for the email confirmation code, resend
/// timer UI and a Verify button. The Verify button submits the code through
/// [AuthState.verifyCode] (real `verifyOTP` call) and also offers
/// "I've confirmed — re-check" via [AuthState.refreshVerification] for
/// link-based confirmation flows.
///
/// Phone OTP is the A03 lane and is email-verification state only here: the
/// phone fallback button explains that and does not start any phone flow.
///
/// V4 P08 polish (behavior unchanged): one-shot [FadeSlideIn] entrances and
/// [AnimatedSwap] on the error/info messages and the Verify button's busy
/// state. The per-second resend countdown is deliberately NOT swapped — a
/// cross-fade every second is visual noise, not signal.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/design.dart';
import 'auth_state.dart';
import 'auth_theme.dart';

/// Email confirmation screen shown after registration (or on login with an
/// unconfirmed email).
class VerifyScreen extends StatefulWidget {
  /// Shared session state driving verification.
  final AuthState auth;

  /// Address the confirmation email/code was sent to.
  final String email;

  /// Route name for guard-friendly navigation.
  static const String routeName = '/verify';

  const VerifyScreen({super.key, required this.auth, required this.email});

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  static const int _codeLength = 6;
  static const int _resendSeconds = 60;

  late final List<TextEditingController> _boxes;
  late final List<FocusNode> _nodes;
  Timer? _timer;
  int _secondsLeft = _resendSeconds;
  String? _formError;
  String? _infoMessage;

  @override
  void initState() {
    super.initState();
    _boxes = List<TextEditingController>.generate(
      _codeLength,
      (_) => TextEditingController(),
    );
    _nodes = List<FocusNode>.generate(_codeLength, (_) => FocusNode());
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final TextEditingController c in _boxes) {
      c.dispose();
    }
    for (final FocusNode n in _nodes) {
      n.dispose();
    }
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

  String get _code => _boxes.map((c) => c.text).join();

  bool get _codeComplete =>
      _code.length == _codeLength && int.tryParse(_code) != null;

  String get _timerText {
    final String m = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final String s = (_secondsLeft % 60).toString().padLeft(2, '0');
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

  Future<void> _verify() async {
    setState(() {
      _formError = null;
      _infoMessage = null;
    });
    await widget.auth.verifyCode(email: widget.email, token: _code);
    if (!mounted) return;
    if (widget.auth.status == AuthStatus.authenticated) {
      setState(() => _infoMessage = 'Email verified. Welcome aboard!');
      Navigator.of(context).pop(true);
    } else {
      setState(
        () => _formError = widget.auth.errorMessage.isNotEmpty
            ? widget.auth.errorMessage
            : 'Verification did not complete. Check the code and try again.',
      );
    }
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
                    "We've sent a 6-digit code to ${widget.email}. Enter it below.",
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
                                    borderSide: const BorderSide(
                                      color: kAuthBorder,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                      color: kAuthBorder,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                      color: kAuthTeal,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 16),
                        const Text("Didn't receive the code?"),
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
                        AnimatedSwap(
                          child: AuthPrimaryButton(
                            key: ValueKey<bool>(busy),
                            label: 'Verify',
                            loading: busy,
                            onPressed: busy || !_codeComplete ? null : _verify,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: busy ? null : _recheck,
                          child: const Text(
                            "I've confirmed — re-check",
                            style: TextStyle(color: kAuthTeal),
                          ),
                        ),
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
