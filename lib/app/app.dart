import 'package:flutter/material.dart';

import 'home_shell.dart';
import 'routes.dart';

/// RailMate BD application root (I01, R-21).
///
/// Teal `#0E5A66` theme per `design/UI_VISUAL_SPEC.md`. All navigation flows
/// through [AppRoutes.onGenerateRoute]; [HomeShell] is the initial route.
class RailMateApp extends StatelessWidget {
  static const String appTitle = 'RailMate BD';
  static const Color primaryTeal = Color(0xFF0E5A66);

  const RailMateApp({super.key});

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
      onGenerateRoute: AppRoutes.onGenerateRoute,
      home: const HomeShell(),
    );
  }
}
