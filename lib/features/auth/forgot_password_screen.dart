/// P06 — forgot-password flow (RailMate BD).
///
/// Two genuine steps, both backed by real Supabase Auth calls through
/// [AuthState]:
///
/// 1. request a reset email for an address (neutral result, no enumeration);
/// 2. set the new password from the recovery credential.
///
/// Tapping the reset email opens the app itself
/// (`railmatebd://auth/reset-password`, see the Android intent filter and
/// `AppGate`'s recovery listener): the app establishes the recovery session
/// from the link tokens and opens this screen directly on step 2
/// ([ForgotPasswordScreen.startInRecovery]).
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';
import 'auth_state.dart';

/// Request-a-reset-email plus set-new-password screen.
///
/// When [startInRecovery] is true, the screen opens directly on the
/// new-password pane: the user arrived from a password-reset deep link whose
/// session the app already established (see `password_recovery.dart` and the
/// `railmatebd://auth/reset-password` intent filter). The email pane is
/// skipped because there is nothing left to send.
class ForgotPasswordScreen extends StatefulWidget {
  final AuthState auth;

  final bool startInRecovery;

  const ForgotPasswordScreen({
    super.key,
    required this.auth,
    this.startInRecovery = false,
  });

  static const String routeName = '/forgot-password';

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late bool _emailSent;
  bool _busy = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailSent = widget.startInRecovery;
    _email.text = widget.auth.user?.email ?? '';
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _sendResetEmail() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final bool ok = await widget.auth.requestPasswordReset(_email.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      // Neutral copy either way: never reveal whether the account exists.
      _emailSent = ok;
      _error = ok ? null : widget.auth.errorMessage;
    });
  }

  Future<void> _setNewPassword() async {
    final bool ok = await widget.auth.completePasswordReset(
      newPassword: _password.text,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _done = ok;
      if (!ok) _error = widget.auth.errorMessage;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset password'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: _done
            ? _SuccessPane(onDone: () => Navigator.of(context).maybePop())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.s24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      FadeSlideIn(child: _Header(emailSent: _emailSent)),
                      const SizedBox(height: AppSpacing.s24),
                      if (!_emailSent) ...<Widget>[
                        TextFormField(
                          key: const Key('forgot-email'),
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Account email',
                            prefixIcon: Icon(Icons.alternate_email),
                          ),
                          validator: (String? v) =>
                              (v == null || !v.contains('@'))
                              ? 'Enter the email you registered with.'
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.s20),
                        PressScale(
                          onTap: _busy ? null : _sendResetEmail,
                          child: AnimatedSwap(
                            child: FilledButton(
                              key: ValueKey<bool>(_busy),
                              onPressed: _busy ? null : _sendResetEmail,
                              child: _busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Send reset link'),
                            ),
                          ),
                        ),
                      ] else ...<Widget>[
                        if (widget.startInRecovery)
                          const _RecoveryNotice()
                        else
                          _EmailSentNotice(email: _email.text.trim()),
                        const SizedBox(height: AppSpacing.s20),
                        TextFormField(
                          key: const Key('forgot-new-password'),
                          controller: _password,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'New password',
                            helperText: 'At least 8 characters.',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          validator: (String? v) => (v == null || v.length < 8)
                              ? 'Password must be at least 8 characters.'
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.s20),
                        PressScale(
                          onTap: _busy ? null : _setNewPassword,
                          child: AnimatedSwap(
                            child: FilledButton(
                              key: ValueKey<bool>(_busy),
                              onPressed: _busy ? null : _setNewPassword,
                              child: _busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Set new password'),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s12),
                        TextButton(
                          onPressed: _busy ? null : _sendResetEmail,
                          child: const Text('Resend the email'),
                        ),
                      ],
                      if (_error != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.s16),
                        _ErrorNote(message: _error!),
                      ],
                      const SizedBox(height: AppSpacing.s16),
                      const _HonestyNote(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final bool emailSent;

  const _Header({required this.emailSent});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          emailSent ? 'Choose a new password' : 'Forgot your password?',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.s8),
        Text(
          emailSent
              ? 'Open the link we emailed, then set a new password here.'
              : 'We will email you a link to choose a new password.',
          style: const TextStyle(color: AppColors.secondaryText),
        ),
      ],
    );
  }
}

class _EmailSentNotice extends StatelessWidget {
  final String email;

  const _EmailSentNotice({required this.email});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.mark_email_read_outlined, color: AppColors.success),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Text(
              'If an account exists for $email, a reset link is on its way. '
              'Check spam too — the link can take a minute.',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner for deep-link arrival: the reset email already did its job, so
/// the only thing left is choosing the new password below.
class _RecoveryNotice extends StatelessWidget {
  const _RecoveryNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.link_outlined, color: AppColors.success),
          SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Text(
              'You arrived from your reset link — choose a new password '
              'below and it takes effect immediately.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  final String message;

  const _ErrorNote({required this.message});

  @override
  Widget build(BuildContext context) {
    return ValidationShake(
      key: ValueKey<String>(message),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s12),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadii.input),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HonestyNote extends StatelessWidget {
  const _HonestyNote();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Account recovery is handled by the live hosted backend. '
      'RailMate BD never stores your password.',
      textAlign: TextAlign.center,
      style: TextStyle(color: AppColors.mutedText, fontSize: 12),
    );
  }
}

class _SuccessPane extends StatelessWidget {
  final VoidCallback onDone;

  const _SuccessPane({required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FadeSlideIn(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.check_circle_outline,
                size: 56,
                color: AppColors.success,
              ),
              const SizedBox(height: AppSpacing.s16),
              const Text(
                'Password updated',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.s8),
              const Text(
                'You are signed in. Remember to use the new password next time.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.s24),
              FilledButton(onPressed: onDone, child: const Text('Continue')),
            ],
          ),
        ),
      ),
    );
  }
}
