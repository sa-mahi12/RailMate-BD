/// Defensive auth-callback screen (RailMate BD).
///
/// Belt-and-braces for `railmatebd://auth/verify` and
/// `railmatebd://auth/reset-password`: with `flutter_deeplinking_enabled`
/// off, Flutter never turns these links into Navigator routes — `AppGate`
/// consumes them via `app_links`. If one ever DOES reach [AppRoutes] (e.g.
/// a build missing the manifest flag), this screen is shown INSTEAD of the
/// generic [RouteErrorScreen], so an auth tap never looks like app failure.
///
/// Behavior: shows a "completing" state and pops itself as soon as the
/// session authenticates (the gate underneath then routes home). A
/// "Continue" control always offers a manual way back.
library;

import 'package:flutter/material.dart';

import 'auth_state.dart';
import 'auth_theme.dart';

/// Which auth callback landed on the route table.
enum AuthCallbackKind {
  /// `railmatebd://auth/verify` — signup confirmation link.
  signupVerify,

  /// `railmatebd://auth/reset-password` — password recovery link.
  passwordReset,
}

class AuthCallbackScreen extends StatefulWidget {
  /// Shared session state observed for completion.
  final AuthState auth;

  /// Which callback arrived, for honest copy.
  final AuthCallbackKind kind;

  const AuthCallbackScreen({super.key, required this.auth, required this.kind});

  @override
  State<AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends State<AuthCallbackScreen> {
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  @override
  void dispose() {
    widget.auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (_popped || !widget.auth.isAuthenticated) return;
    _popped = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isReset = widget.kind == AuthCallbackKind.passwordReset;
    return Scaffold(
      backgroundColor: kAuthPageBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const CircularProgressIndicator(color: kAuthTeal),
              const SizedBox(height: 20),
              Text(
                isReset ? 'Preparing password reset…' : 'Completing sign-in…',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Your email link was received and is being processed. '
                'If nothing happens, go back — you can resend it from '
                'the previous screen.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              AuthPrimaryButton(
                label: 'Continue',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
