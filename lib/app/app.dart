import 'package:flutter/material.dart';

import '../design/design.dart';
import 'app_gate.dart';
import 'dependencies.dart';
import 'onboarding_store.dart';
import 'routes.dart';

/// RailMate BD application root (F02: dependency-injected).
///
/// Teal `#0E5A66` theme per `design/UI_VISUAL_SPEC.md`. All navigation flows
/// through [AppRoutes.onGenerateRoute].
///
/// P03: the root no longer hardcodes [HomeShell] as `home`. [AppGate] owns
/// the startup state machine (splash -> onboarding -> welcome -> verify ->
/// home) and renders the tabbed shell only for an authenticated session.
/// [dependencies] is built once in `main.dart` after real Supabase
/// initialization — screens never construct backend clients themselves.
class RailMateApp extends StatelessWidget {
  static const String appTitle = 'RailMate BD';
  static const Color primaryTeal = Color(0xFF0E5A66);

  final AppDependencies dependencies;

  /// First-run onboarding flag store (P03). Injected so tests can supply an
  /// in-memory store instead of touching device storage.
  final OnboardingStore onboardingStore;

  const RailMateApp({
    super.key,
    required this.dependencies,
    this.onboardingStore = const _EphemeralOnboardingStore(),
  });

  @override
  Widget build(BuildContext context) {
    return MotionGate(
      child: MaterialApp(
        title: appTitle,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primaryColor: primaryTeal,
          colorScheme: ColorScheme.fromSeed(seedColor: primaryTeal),
          scaffoldBackgroundColor: AppColors.pageBackground,
          useMaterial3: true,
        ),
        onGenerateRoute: (RouteSettings settings) =>
            AppRoutes.onGenerateRoute(settings, dependencies: dependencies),
        home: AppGate(dependencies: dependencies, store: onboardingStore),
      ),
    );
  }
}

/// Fallback store used when no store is injected (e.g. an isolated widget
/// test). It starts as *completed* so a bare harness reaches Welcome instead
/// of silently replaying onboarding; production always injects a real
/// persistent store from `main.dart`.
class _EphemeralOnboardingStore implements OnboardingStore {
  const _EphemeralOnboardingStore();

  @override
  Future<bool> isCompleted() async => true;

  @override
  Future<void> markCompleted() async {}
}

/// Genuine boot-failure screen: shown ONLY when Supabase initialization
/// fails (missing `--dart-define` values, malformed URL, no network).
/// This is an error path, not a placeholder — the message names the cause.
class BootErrorApp extends StatelessWidget {
  final String message;

  const BootErrorApp({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: RailMateApp.appTitle,
      home: Scaffold(
        backgroundColor: const Color(0xFFF4F7F9),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_off_outlined,
                  size: 48,
                  color: Color(0xFF0E5A66),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Could not connect',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
