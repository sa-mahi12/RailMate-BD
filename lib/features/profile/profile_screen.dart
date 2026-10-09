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
import '../../design/design.dart';
import '../../design/state/state.dart';
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
              child: SingleChildScrollView(
                padding: EdgeInsets.all(24),
                child: EmptyState(
                  icon: Icons.account_circle_outlined,
                  title: 'Not signed in',
                  message: 'Sign in to see your profile.',
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
                FadeSlideIn(
                  child: AuthSheet(
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
                        // Keyed by the verification verdict so switching to
                        // "verified" cross-fades the badge.
                        AnimatedSwap(
                          child: Text(
                            user.emailConfirmed
                                ? 'Email verified'
                                : 'Email not verified yet',
                            key: ValueKey<bool>(user.emailConfirmed),
                            style: TextStyle(
                              color: user.emailConfirmed
                                  ? kAuthGreen
                                  : kAuthDanger,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 60),
                  child: AuthSheet(
                    child: Column(
                      children: <Widget>[
                        if (username != null && username.isNotEmpty)
                          _ProfileRow(label: 'Username', value: '@$username'),
                        if (user.phone != null && user.phone!.isNotEmpty)
                          _ProfileRow(label: 'Phone', value: user.phone!),
                        // Consumer gate: the raw Account ID (a database UUID) meant nothing to a
                        // passenger, so the row was removed. Support flows use
                        // the email/username above; nothing else needs the id.
                      ],
                    ),
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
                AnimatedSwap(
                  child: AuthPrimaryButton(
                    key: ValueKey<bool>(busy),
                    label: 'Sign out',
                    loading: busy,
                    onPressed: busy
                        ? null
                        : () {
                            auth.signOut();
                          },
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : () => _openKeySetup(context),
                    icon: const Icon(
                      Icons.auto_awesome_outlined,
                      color: kAuthTeal,
                    ),
                    // Consumer gate: "AI key setup" names the mechanism, not
                    // the benefit. The feature is an optional writing helper
                    // for board posts; the key mechanics live inside that
                    // screen, explained there.
                    label: const Text(
                      'AI writing help',
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
                FadeSlideIn(
                  delay: const Duration(milliseconds: 120),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: TextButton.icon(
                      onPressed: () => showAboutDialog(
                        context: context,
                        applicationName: 'RailMate BD',
                        applicationVersion: '1.0.0',
                        applicationLegalese:
                            'DEMONSTRATION ONLY. Timetables, fares and '
                            'bookings in this app are a class project '
                            'simulation: no real money moves and no ticket '
                            'shown here is valid for travel.',
                        children: const <Widget>[
                          SizedBox(height: 12),
                          Text(
                            'RailMate BD plans demo train journeys, keeps '
                            'your bookings and tickets, hosts a traveller '
                            'board, and can polish a board post draft with '
                            'an optional AI helper that only ever uses a '
                            'key you enter yourself.',
                          ),
                        ],
                      ),
                      icon: const Icon(Icons.info_outline, color: kAuthHint),
                      label: const Text(
                        'About this app',
                        style: TextStyle(color: kAuthHint),
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
