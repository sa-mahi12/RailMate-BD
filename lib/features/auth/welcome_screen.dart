/// A02 — Welcome screen (RailMate BD).
///
/// Ref-2 left panel: hero title "Welcome to RailMate BD", supporting copy,
/// "Log In" + "Create Account" buttons and a dots indicator. Both buttons
/// navigate for real via [Navigator] to [LoginScreen]/[RegisterScreen].
library;

import 'package:flutter/material.dart';

import 'auth_state.dart';
import 'auth_theme.dart';
import 'login_screen.dart';
import 'register_screen.dart';

/// Entry screen of the auth slice.
class WelcomeScreen extends StatelessWidget {
  /// Shared session state passed to login/register screens.
  final AuthState auth;

  /// Route name for guard-friendly navigation.
  static const String routeName = '/welcome';

  const WelcomeScreen({super.key, required this.auth});

  void _goLogin(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => LoginScreen(auth: auth)));
  }

  void _goRegister(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => RegisterScreen(auth: auth)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kAuthTeal,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: 48),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Welcome to',
                style: TextStyle(color: Colors.white, fontSize: 26),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'RailMate BD',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Your smarter way to plan, book and explore train journeys '
                'across Bangladesh.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 15,
                ),
              ),
            ),
            const Spacer(),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: <Widget>[
                  AuthPrimaryButton(
                    label: 'Log In',
                    onPressed: () => _goLogin(context),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: OutlinedButton(
                      onPressed: () => _goRegister(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kAuthTeal,
                        side: const BorderSide(color: kAuthTeal),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Text('Create Account'),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward, size: 20),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: kAuthTeal,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
