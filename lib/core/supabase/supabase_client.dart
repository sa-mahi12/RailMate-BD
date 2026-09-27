/// A01 — Supabase bootstrap singleton (RailMate BD).
///
/// Startup connection/error states: [SupabaseConnectionState.notInitialized]
/// (before first [SupabaseBootstrap.initialize] call),
/// [SupabaseConnectionState.missingConfig] (URL or publishable key absent),
/// [SupabaseConnectionState.ready] (connect hook succeeded), and
/// [SupabaseConnectionState.error] (malformed URL, missing SDK wiring, or a
/// failed connect attempt).
///
/// This slice performs no network I/O itself: the real SDK call is injected
/// via the [SupabaseConnect] hook so unit tests never touch the network.
/// `supabase_flutter` is not yet a project dependency, so calling
/// [SupabaseBootstrap.initialize] without a [SupabaseConnect] hook reports
/// [SupabaseConnectionState.error] with wiring guidance instead of
/// attempting a connection.
///
/// Rules: no service-role key, no local DB, no hardcoded URL or key material.
library;

import '../config/app_config.dart';

/// Lifecycle state of the Supabase app bootstrap.
enum SupabaseConnectionState {
  /// [SupabaseBootstrap.initialize] has not run yet.
  notInitialized,

  /// Supabase URL and/or publishable key are missing.
  missingConfig,

  /// The injected connect hook completed successfully.
  ready,

  /// Malformed URL, missing SDK wiring, or failed connect attempt.
  error,
}

/// Injectable SDK connect step. Receives a validated [AppConfig] and performs
/// the real `Supabase.initialize` call once `supabase_flutter` is added.
typedef SupabaseConnect = Future<void> Function(AppConfig config);

/// Singleton owning Supabase startup state. Safe for tests via [resetForTests].
class SupabaseBootstrap {
  /// Shared instance.
  static final SupabaseBootstrap instance = SupabaseBootstrap._internal();

  SupabaseBootstrap._internal();

  SupabaseConnectionState _state = SupabaseConnectionState.notInitialized;
  AppConfig? _config;
  String _errorMessage = '';

  /// Current lifecycle state.
  SupabaseConnectionState get state => _state;

  /// Last validated config that reached [SupabaseConnectionState.ready].
  AppConfig? get config => _config;

  /// Human-readable failure reason, or empty when there is none.
  /// Never contains key material.
  String get errorMessage => _errorMessage;

  /// True only after a successful [initialize].
  bool get isReady => _state == SupabaseConnectionState.ready;

  /// Runs startup validation and, when valid, the injected [connect] hook.
  ///
  /// Pass [config] in tests to avoid `String.fromEnvironment`; production
  /// callers omit it so values come from `--dart-define`.
  Future<void> initialize({AppConfig? config, SupabaseConnect? connect}) async {
    final AppConfig resolved = config ?? AppConfig.fromEnvironment();

    if (!resolved.isConfigured) {
      _config = null;
      _errorMessage =
          'Missing Supabase configuration (${resolved.missingFields.join(', ')}). '
          'Rerun with --dart-define=$kSupabaseUrlDefine=<url> '
          '--dart-define=$kSupabaseAnonKeyDefine=<key>.';
      _state = SupabaseConnectionState.missingConfig;
      return;
    }

    final String? badUrl = resolved.urlError;
    if (badUrl != null) {
      _config = null;
      _errorMessage = badUrl;
      _state = SupabaseConnectionState.error;
      return;
    }

    if (connect == null) {
      _config = null;
      _errorMessage =
          'supabase_flutter is not wired yet: ask the coordinator to add '
          'supabase_flutter to pubspec.yaml and pass a connect hook that '
          'calls Supabase.initialize. No network was attempted.';
      _state = SupabaseConnectionState.error;
      return;
    }

    try {
      await connect(resolved);
      _config = resolved;
      _errorMessage = '';
      _state = SupabaseConnectionState.ready;
    } catch (e) {
      _config = null;
      _errorMessage = 'Supabase initialization failed: $e';
      _state = SupabaseConnectionState.error;
    }
  }

  /// Test-only reset to [SupabaseConnectionState.notInitialized].
  /// Never call from production code.
  void resetForTests() {
    _config = null;
    _errorMessage = '';
    _state = SupabaseConnectionState.notInitialized;
  }
}
