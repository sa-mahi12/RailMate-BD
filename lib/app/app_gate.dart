/// P03 — root application gate (RailMate BD).
///
/// Replaces V3's unconditional `HomeShell` root with a real startup state
/// machine so a first-time user is never dropped straight into the app:
///
/// ```text
/// BOOT/SPLASH
///   ├─ authenticated                      -> HOME SHELL
///   ├─ session present but unconfirmed    -> VERIFY
///   ├─ unauthenticated + onboarding done  -> WELCOME (login/register)
///   └─ unauthenticated + first run        -> ONBOARDING -> WELCOME
/// ```
///
/// Logout returns to WELCOME and deliberately does **not** replay onboarding:
/// completion lives in [OnboardingStore], independent of the auth session.
library;

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../design/design.dart';
import '../features/auth/auth_state.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/password_recovery.dart';
import '../features/auth/verify_screen.dart';
import '../features/auth/welcome_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import 'boot_splash.dart';
import 'dependencies.dart';
import 'home_shell.dart';
import 'onboarding_store.dart';

/// Coarse startup phase, useful for tests and for the QA walkthrough.
enum AppGatePhase {
  /// Dependencies/session still resolving; splash is on screen.
  splash,

  /// Fresh install, onboarding not completed yet.
  onboarding,

  /// Onboarding done, signed out — offer login/register.
  welcome,

  /// Signed in but the email is not confirmed yet.
  needsVerification,

  /// Authenticated; the tabbed shell owns navigation.
  home,
}

/// Chooses the startup screen from onboarding + session state.
///
/// [store] is only read once per mount; [AuthState] is observed live so
/// sign-in, sign-out and verification all re-evaluate the gate without a
/// restart.
class AppGate extends StatefulWidget {
  final AppDependencies dependencies;
  final OnboardingStore store;

  const AppGate({super.key, required this.dependencies, required this.store});

  @override
  State<AppGate> createState() => AppGateState();
}

/// Public state so integration tests and QA can assert the current phase
/// without reaching into private fields.
class AppGateState extends State<AppGate> {
  bool _onboardingComplete = false;
  bool _resolved = false;

  /// Password-recovery deep-link subscription. Started only when a real
  /// backend client exists (production); test compositions have a null
  /// client and never listen.
  StreamSubscription<Uri>? _linkSub;
  bool _handlingLink = false;

  @override
  void initState() {
    super.initState();
    widget.dependencies.auth.addListener(_onAuthChanged);
    unawaited(_loadOnboarding());
    _listenForRecoveryLinks();
  }

  @override
  void dispose() {
    widget.dependencies.auth.removeListener(_onAuthChanged);
    unawaited(_linkSub?.cancel());
    super.dispose();
  }

  /// Listens for `railmatebd://auth/reset-password` links — cold start
  /// (the link that launched the app) and warm (a tap while running).
  void _listenForRecoveryLinks() {
    if (widget.dependencies.client == null) return;
    final AppLinks links = AppLinks();
    unawaited(links.getInitialLink().then((Uri? uri) => _handleLink(uri)));
    _linkSub = links.uriLinkStream.listen(_handleLink, onError: (_) {});
  }

  /// Establishes the recovery session from the link and opens the
  /// new-password pane. An invalid/expired link falls back to the manual
  /// reset screen with a plain-language notice — never a dead end, never a
  /// code.
  Future<void> _handleLink(Uri? uri) async {
    if (uri == null || _handlingLink) return;
    final RecoveryCredentials? creds = parseRecoveryLink(uri);
    if (creds == null) return;
    final client = widget.dependencies.client;
    if (client == null || !mounted) return;
    _handlingLink = true;
    try {
      await client.auth.setSession(
        creds.refreshToken,
        accessToken: creds.accessToken,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ForgotPasswordScreen(
            auth: widget.dependencies.auth,
            startInRecovery: true,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This reset link is invalid or expired. '
            'Request a new one below.',
          ),
        ),
      );
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ForgotPasswordScreen(auth: widget.dependencies.auth),
        ),
      );
    } finally {
      _handlingLink = false;
    }
  }

  Future<void> _loadOnboarding() async {
    final bool completed = await widget.store.isCompleted();
    if (!mounted) return;
    setState(() {
      _onboardingComplete = completed;
      _resolved = true;
    });
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  /// Current startup phase, recomputed from live state.
  AppGatePhase get phase {
    if (!_resolved) return AppGatePhase.splash;
    final AuthState auth = widget.dependencies.auth;
    if (auth.isAuthenticated) return AppGatePhase.home;
    if (auth.status == AuthStatus.needsVerification) {
      return AppGatePhase.needsVerification;
    }
    return _onboardingComplete ? AppGatePhase.welcome : AppGatePhase.onboarding;
  }

  Future<void> _completeOnboarding() async {
    await widget.store.markCompleted();
    if (!mounted) return;
    setState(() => _onboardingComplete = true);
  }

  @override
  Widget build(BuildContext context) {
    final Widget screen = switch (phase) {
      AppGatePhase.splash => const BootSplashScreen(
        status: 'Restoring your session',
      ),
      AppGatePhase.onboarding => OnboardingScreen(
        onFinished: _completeOnboarding,
      ),
      AppGatePhase.welcome => WelcomeScreen(
        key: const ValueKey<String>('gate-welcome'),
        auth: widget.dependencies.auth,
      ),
      AppGatePhase.needsVerification => VerifyScreen(
        auth: widget.dependencies.auth,
        email: widget.dependencies.auth.user?.email ?? '',
      ),
      AppGatePhase.home => HomeShell(dependencies: widget.dependencies),
    };

    return FadeSlideIn(
      // Re-keyed on phase so a genuine screen change animates; the value is
      // the phase name, not a per-frame identity.
      key: ValueKey<AppGatePhase>(phase),
      child: screen,
    );
  }
}
