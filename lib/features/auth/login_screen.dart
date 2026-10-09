/// A02 — Login screen (RailMate BD).
///
/// Email + password fields, a forgot-password link that opens the real reset
/// flow, a Log In button, and a signup link that navigates to
/// [RegisterScreen] for real. There is deliberately no "Remember me" (the
/// session persists on device automatically — a checkbox would lie) and no
/// social buttons (social login does not exist yet and is not advertised).
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';
import 'auth_state.dart';
import 'auth_theme.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';
import 'verify_screen.dart';

/// Email login screen.
class LoginScreen extends StatefulWidget {
  /// Shared session state driving login and post-login routing.
  final AuthState auth;

  /// Route name for guard-friendly navigation.
  static const String routeName = '/login';

  const LoginScreen({super.key, required this.auth});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _obscure = true;
  String? _formError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Supabase persists the session on device automatically; the remember-me
  /// checkbox is kept for spec parity and recorded in state only.
  Future<void> _login() async {
    setState(() => _formError = null);
    await widget.auth.signIn(email: _email.text, password: _password.text);
    if (!mounted) return;
    switch (widget.auth.status) {
      case AuthStatus.authenticated:
        Navigator.of(context).pop(true);
      case AuthStatus.needsVerification:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) =>
                VerifyScreen(auth: widget.auth, email: _email.text.trim()),
          ),
        );
      case AuthStatus.error:
        setState(() => _formError = widget.auth.errorMessage);
      case AuthStatus.unauthenticated:
      case AuthStatus.authenticating:
        break;
    }
  }

  /// Opens the real password-reset flow (P06): reset email via Supabase,
  /// then the in-app new-password form on the deep link. No credentials are
  /// collected on the reset screen itself.
  void _forgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ForgotPasswordScreen(auth: widget.auth),
      ),
    );
  }

  void _goRegister() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => RegisterScreen(auth: widget.auth),
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
            const FadeSlideIn(
              child: AuthHeader(
                title: 'Log in to RailMate BD',
                subtitle: 'Access your account to continue your journey.',
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // Email only: sign-in authenticates via Supabase email +
                        // password. Phone OTP lives in the phone/ slice (live
                        // SMS BLOCKED) and is not accepted here.
                        AuthField(
                          label: 'Email Address',
                          hint: 'Enter your email address',
                          icon: Icons.mail_outline,
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 16),
                        AuthField(
                          label: 'Password',
                          hint: 'Enter your password',
                          icon: Icons.lock_outline,
                          controller: _password,
                          obscureText: _obscure,
                          suffix: IconButton(
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Consumer gate: the old "Remember me" checkbox did
                        // nothing (Supabase persists the session on device
                        // automatically), so it was removed rather than left
                        // as a control that lies. Only the working action
                        // stays, right-aligned.
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: <Widget>[
                            TextButton(
                              onPressed: busy ? null : _forgotPassword,
                              child: const Text(
                                'Forgot password?',
                                style: TextStyle(color: kAuthTeal),
                              ),
                            ),
                          ],
                        ),
                        if (_formError != null) ...<Widget>[
                          const SizedBox(height: 4),
                          AnimatedSwap(
                            child: Text(
                              _formError!,
                              key: ValueKey<String>(_formError!),
                              style: const TextStyle(color: kAuthDanger),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        AnimatedSwap(
                          child: AuthPrimaryButton(
                            key: ValueKey<bool>(busy),
                            label: 'Log In',
                            loading: busy,
                            onPressed: busy ? null : _login,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Consumer gate: the disabled Google/Facebook buttons
                        // and their "coming soon" note advertised features
                        // that do not exist. Social login stays out of the
                        // product until it genuinely works, so all of it was
                        // removed instead of left as dead controls.
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            // P27: Flexible + wrapping, so the sign-up
                            // prompt survives large text scales.
                            Flexible(
                              child: Text(
                                "Don't have an account? ",
                                textAlign: TextAlign.end,
                              ),
                            ),
                            TextButton(
                              onPressed: busy ? null : _goRegister,
                              child: const Text(
                                'Create Account',
                                style: TextStyle(color: kAuthTeal),
                              ),
                            ),
                          ],
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
