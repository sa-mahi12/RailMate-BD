import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/dependencies.dart';
import 'core/supabase/supabase_client.dart';
import 'features/auth/supabase_auth_client.dart';

/// RailMate BD entry point (F02: real hosted bootstrap).
///
/// Startup order:
/// 1. `Supabase.initialize` with the publishable key from `--dart-define`
///    (`SUPABASE_URL` + `SUPABASE_ANON_KEY`, or legacy
///    `SUPABASE_PUBLISHABLE_KEY` fallback).
/// 2. Session restore (persisted login survives restarts).
/// 3. Composition ([AppDependencies]) + [RailMateApp].
///
/// When step 1 fails (missing config, no network), the app boots to a
/// genuine boot-error screen naming the problem — never to a fake backend.
/// No service-role key is ever read here.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseBootstrap.instance.initialize(connect: supabaseConnect);
  final SupabaseBootstrap boot = SupabaseBootstrap.instance;
  if (!boot.isReady) {
    runApp(BootErrorApp(message: boot.errorMessage));
    return;
  }
  final AppDependencies dependencies = AppDependencies.create();
  await dependencies.auth.restore();
  runApp(RailMateApp(dependencies: dependencies));
}
