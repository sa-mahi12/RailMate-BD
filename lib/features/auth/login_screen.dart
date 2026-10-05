/// A02 — Login screen (RailMate BD).
///
/// Ref-2 middle panel: email/phone + password fields, remember-me checkbox,
/// forgot-password note, Log In button, Google/Facebook buttons rendered
/// disabled with a 'coming soon' note (no fake auth), and a signup link that
/// navigates to [RegisterScreen] for real.
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
  bool _rememberMe = true;
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
                        Row(
                          children: <Widget>[
                            Checkbox(
                              value: _rememberMe,
                              activeColor: kAuthTeal,
                              onChanged: busy
                                  ? null
                                  : (bool? value) => setState(
                                      () => _rememberMe = value ?? false,
                                    ),
                            ),
                            const Text('Remember me'),
                            const Spacer(),
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
                        Row(
                          children: <Widget>[
                            const Expanded(child: Divider()),
                            // P27: Flexible + wrapping label, so this row
                            // survives large accessibility text scales
                            // instead of overflowing horizontally.
                            Flexible(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Text(
                                  'or continue with',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: null,
                                icon: const Text(
                                  'G',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                label: const Text('Google'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: null,
                                icon: const Text(
                                  'f',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                label: const Text('Facebook'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Center(
                          child: Text(
                            'Social login coming soon — email login only.',
                            style: TextStyle(color: kAuthHint, fontSize: 12),
                          ),
                        ),
                        const SizedBox(height: 12),
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
