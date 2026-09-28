import 'package:flutter/material.dart';

import 'dependencies.dart';
import 'home_shell.dart';
import 'routes.dart';

/// RailMate BD application root (F02: dependency-injected).
///
/// Teal `#0E5A66` theme per `design/UI_VISUAL_SPEC.md`. All navigation flows
/// through [AppRoutes.onGenerateRoute]; [HomeShell] is the initial route.
/// [dependencies] is built once in `main.dart` after real Supabase
/// initialization — screens never construct backend clients themselves.
class RailMateApp extends StatelessWidget {
  static const String appTitle = 'RailMate BD';
  static const Color primaryTeal = Color(0xFF0E5A66);

  final AppDependencies dependencies;

  const RailMateApp({super.key, required this.dependencies});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appTitle,
      theme: ThemeData(
        primaryColor: primaryTeal,
        colorScheme: ColorScheme.fromSeed(seedColor: primaryTeal),
        scaffoldBackgroundColor: const Color(0xFFF4F7F9),
        useMaterial3: true,
      ),
      onGenerateRoute: (RouteSettings settings) =>
          AppRoutes.onGenerateRoute(settings, dependencies: dependencies),
      home: HomeShell(dependencies: dependencies),
    );
  }
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
