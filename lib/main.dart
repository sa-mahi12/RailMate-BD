import 'package:flutter/material.dart';

import 'app/app.dart';

/// RailMate BD entry point (I01).
///
/// Note: hosted Supabase initialization (`Supabase.initialize` + auth/session
/// restore) is a coordinator/startup wiring step that needs the project URL
/// and anon key outside source. Until then the shell runs with explicitly
/// unconfigured backends that report "setup required" through each screen's
/// normal error/placeholder path — no fake data anywhere.
void main() {
  runApp(const RailMateApp());
}
