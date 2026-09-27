/// A02 — Register screen (RailMate BD).
///
/// Ref-2 right panel: full name, email, phone, username and password fields
/// plus a Create Account button. The username field is a plain text field:
/// availability checking belongs to the B02 lane (Worker B owns
/// `lib/features/auth/username/**`) and is intentionally absent here.
/// On success the screen routes to [VerifyScreen] (unconfirmed email) or
/// pops (already-confirmed session).
library;

import 'package:flutter/material.dart';

import 'auth_state.dart';
import 'auth_theme.dart';
import 'login_screen.dart';
import 'verify_screen.dart';

/// Email registration screen.
class RegisterScreen extends StatefulWidget {
  /// Shared session state driving registration and post-signup routing.
  final AuthState auth;

  /// Route name for guard-friendly navigation.
  static const String routeName = '/register';

  const RegisterScreen({super.key, required this.auth});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _fullName = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _obscure = true;
  String? _formError;

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _phone.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    setState(() => _formError = null);
    await widget.auth.signUp(
      email: _email.text,
      password: _password.text,
      fullName: _fullName.text,
      phone: _phone.text,
      username: _username.text,
    );
    if (!mounted) return;
    switch (widget.auth.status) {
      case AuthStatus.needsVerification:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) =>
                VerifyScreen(auth: widget.auth, email: _email.text.trim()),
          ),
        );
      case AuthStatus.authenticated:
        Navigator.of(context).pop(true);
      case AuthStatus.error:
        setState(() => _formError = widget.auth.errorMessage);
      case AuthStatus.unauthenticated:
      case AuthStatus.authenticating:
        break;
    }
  }

  void _goLogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => LoginScreen(auth: widget.auth)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kAuthPageBg,
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            const AuthHeader(
              title: 'Create Account',
              subtitle: 'Join RailMate BD and start your journey today.',
            ),
            AuthSheet(
              child: ListenableBuilder(
                listenable: widget.auth,
                builder: (BuildContext context, _) {
                  final bool busy = widget.auth.isBusy;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      AuthField(
                        label: 'Full Name',
                        hint: 'Enter your full name',
                        icon: Icons.person_outline,
                        controller: _fullName,
                        keyboardType: TextInputType.name,
                      ),
                      const SizedBox(height: 16),
                      AuthField(
                        label: 'Email Address',
                        hint: 'Enter your email address',
                        icon: Icons.mail_outline,
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 16),
                      AuthField(
                        label: 'Phone Number',
                        hint: 'Enter your phone number',
                        icon: Icons.phone_outlined,
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 16),
                      AuthField(
                        label: 'Username',
                        hint: 'Choose a username',
                        icon: Icons.alternate_email,
                        controller: _username,
                      ),
                      const SizedBox(height: 16),
                      AuthField(
                        label: 'Password',
                        hint: 'Create a password',
                        icon: Icons.lock_outline,
                        controller: _password,
                        obscureText: _obscure,
                        suffix: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Use at least 8 characters with a mix of letters, '
                        'numbers and symbols.',
                        style: TextStyle(color: kAuthHint, fontSize: 12),
                      ),
                      if (_formError != null) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          _formError!,
                          style: const TextStyle(color: kAuthDanger),
                        ),
                      ],
                      const SizedBox(height: 16),
                      AuthPrimaryButton(
                        label: 'Create Account',
                        loading: busy,
                        onPressed: busy ? null : _register,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const Text('Already have an account? '),
                          TextButton(
                            onPressed: busy ? null : _goLogin,
                            child: const Text(
                              'Log In',
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
          ],
        ),
      ),
    );
  }
}
