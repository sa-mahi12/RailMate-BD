/// F03 — minimal genuine profile screen (RailMate BD).
///
/// Reads the signed-in account from the passed [AuthState] (restored once in
/// `main.dart`); no new backend client, no fake data. Shows the account
/// email, display name/username from [AuthUser], email-verification state, a
/// Sign out button (`AuthState.signOut`) and a link to the AI key setup
/// route ([AppRoutes.keySetup]).
///
/// Tab insertion is F16 (coordinator-owned `home_shell.dart`); this file only
/// exposes the constructor below so the coordinator can plug it in.
library;

import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../auth/auth_state.dart';
import '../auth/auth_theme.dart';

/// Signed-in account profile driven by the shared session state.
class ProfileScreen extends StatelessWidget {
  /// Shared session state (restored once at startup in `main.dart`).
  final AuthState auth;

  /// Route name for guard-friendly navigation (wired by F16).
  static const String routeName = '/profile';

  const ProfileScreen({super.key, required this.auth});

  void _openKeySetup(BuildContext context) {
    Navigator.of(context).pushNamed(AppRoutes.keySetup);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kAuthPageBg,
      appBar: AppBar(
        backgroundColor: kAuthTeal,
        foregroundColor: Colors.white,
        title: const Text('Profile'),
      ),
      body: ListenableBuilder(
        listenable: auth,
        builder: (BuildContext context, _) {
          final user = auth.user;
          if (user == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.account_circle_outlined,
                      size: 48,
                      color: kAuthTeal,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Not signed in',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Sign in to see your profile.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          final String? fullName = user.fullName?.trim();
          final String? username = user.username?.trim();
          final String displayName = (fullName != null && fullName.isNotEmpty)
              ? fullName
              : (username != null && username.isNotEmpty)
              ? '@$username'
              : user.email.isNotEmpty
              ? user.email
              : (user.phone ?? 'Account');
          final bool busy = auth.isBusy;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AuthSheet(
                  child: Column(
                    children: <Widget>[
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: kAuthTeal,
                        child: Text(
                          displayName.isNotEmpty
                              ? displayName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (user.email.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          user.email,
                          style: const TextStyle(color: kAuthHint),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        user.emailConfirmed
                            ? 'Email verified'
                            : 'Email not verified yet',
                        style: TextStyle(
                          color: user.emailConfirmed ? kAuthGreen : kAuthDanger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                AuthSheet(
                  child: Column(
                    children: <Widget>[
                      if (username != null && username.isNotEmpty)
                        _ProfileRow(label: 'Username', value: '@$username'),
                      if (user.phone != null && user.phone!.isNotEmpty)
                        _ProfileRow(label: 'Phone', value: user.phone!),
                      _ProfileRow(label: 'Account ID', value: user.id),
                    ],
                  ),
                ),
                if (auth.status == AuthStatus.needsVerification) ...<Widget>[
                  const Text(
                    'Check your inbox for the confirmation email to unlock '
                    'account features.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kAuthHint, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                ],
                if (auth.status == AuthStatus.error &&
                    auth.errorMessage.isNotEmpty) ...<Widget>[
                  Text(
                    auth.errorMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kAuthDanger),
                  ),
                  const SizedBox(height: 12),
                ],
                AuthPrimaryButton(
                  label: 'Sign out',
                  loading: busy,
                  onPressed: busy
                      ? null
                      : () {
                          auth.signOut();
                        },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : () => _openKeySetup(context),
                    icon: const Icon(Icons.key_outlined, color: kAuthTeal),
                    label: const Text(
                      'AI key setup',
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
            ),
          );
        },
      ),
    );
  }
}

/// Label/value row for genuine account fields (never fake data).
class _ProfileRow extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: kAuthHint, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
