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

import 'package:flutter/material.dart';

import '../design/design.dart';
import '../features/auth/auth_state.dart';
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

  @override
  void initState() {
    super.initState();
    widget.dependencies.auth.addListener(_onAuthChanged);
    unawaited(_loadOnboarding());
  }

  @override
  void dispose() {
    widget.dependencies.auth.removeListener(_onAuthChanged);
    super.dispose();
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
