/// A01 — Supabase bootstrap configuration (RailMate BD).
///
/// Loads the hosted Supabase URL and publishable (anon) key from
/// `--dart-define` values:
///
/// ```sh
/// flutter run \
///   --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=<publishable-key>
/// ```
///
/// `SUPABASE_PUBLISHABLE_KEY` is accepted as a fallback name for the same
/// key (see [kSupabasePublishableKeyDefine]).
///
/// Rules (see AGENTS.md, D-002):
/// * Never add a service-role key to this file, to any other mobile source,
///   test, log or prompt.
/// * No local business database; hosted Supabase is the single backend.
/// * No secret values are hardcoded here; missing values surface as an
///   explicit [AppConfigException], never as a silent fallback.
library;

/// Compile-time `--dart-define` name for the Supabase project URL.
const String kSupabaseUrlDefine = 'SUPABASE_URL';

/// Compile-time `--dart-define` name for the Supabase publishable (anon) key.
const String kSupabaseAnonKeyDefine = 'SUPABASE_ANON_KEY';

/// Legacy/alternate `--dart-define` name for the same publishable key.
///
/// The CI workflow historically supplied `SUPABASE_PUBLISHABLE_KEY`; the app
/// accepts it as a fallback when `SUPABASE_ANON_KEY` is empty so a naming
/// drift never silently boots the app against a missing key. Both names
/// carry the same publishable (never service-role) key.
const String kSupabasePublishableKeyDefine = 'SUPABASE_PUBLISHABLE_KEY';

/// Thrown when Supabase bootstrap configuration is missing or malformed.
class AppConfigException implements Exception {
  /// Human-readable reason, safe to display (contains no secret values).
  final String message;

  const AppConfigException(this.message);

  @override
  String toString() => 'AppConfigException: $message';
}

/// Immutable Supabase connection configuration for the mobile app.
class AppConfig {
  /// Hosted Supabase project URL, e.g. `https://<ref>.supabase.co`.
  final String supabaseUrl;

  /// Supabase publishable (anon) key. Never a service-role key.
  final String supabaseAnonKey;

  const AppConfig({required this.supabaseUrl, required this.supabaseAnonKey});

  /// Reads configuration from `--dart-define`.
  ///
  /// Pass [urlOverride]/[anonKeyOverride] only in tests; production callers
  /// use the parameterless form so values come from `String.fromEnvironment`.
  /// When [anonKeyOverride] (and the `SUPABASE_ANON_KEY` define) are empty,
  /// the `SUPABASE_PUBLISHABLE_KEY` define is used as a fallback
  /// ([publishableKeyOverride] forces that fallback path in tests).
  factory AppConfig.fromEnvironment({
    String? urlOverride,
    String? anonKeyOverride,
    String? publishableKeyOverride,
  }) {
    final String url =
        urlOverride ?? const String.fromEnvironment(kSupabaseUrlDefine);
    String anonKey =
        anonKeyOverride ?? const String.fromEnvironment(kSupabaseAnonKeyDefine);
    if (anonKey.trim().isEmpty) {
      anonKey =
          publishableKeyOverride ??
          const String.fromEnvironment(kSupabasePublishableKeyDefine);
    }
    return AppConfig(supabaseUrl: url, supabaseAnonKey: anonKey);
  }

  /// Names of required fields that are empty or whitespace-only.
  List<String> get missingFields {
    final List<String> missing = <String>[];
    if (supabaseUrl.trim().isEmpty) missing.add(kSupabaseUrlDefine);
    if (supabaseAnonKey.trim().isEmpty) missing.add(kSupabaseAnonKeyDefine);
    return missing;
  }

  /// True when both URL and publishable key are non-empty.
  bool get isConfigured => missingFields.isEmpty;

  /// Describes a malformed URL, or null when the URL shape is acceptable.
  ///
  /// Accepts absolute `http(s)` URIs so tests can use non-TLS fixtures;
  /// production must pass an `https://<ref>.supabase.co` URL.
  String? get urlError {
    final String url = supabaseUrl.trim();
    if (url.isEmpty) return 'Missing $kSupabaseUrlDefine.';
    final Uri? parsed = Uri.tryParse(url);
    if (parsed == null || !parsed.isAbsolute) {
      return 'Invalid $kSupabaseUrlDefine: not an absolute URI.';
    }
    if (parsed.scheme != 'https' && parsed.scheme != 'http') {
      return 'Invalid $kSupabaseUrlDefine: scheme must be http or https.';
    }
    if (parsed.host.isEmpty) {
      return 'Invalid $kSupabaseUrlDefine: missing host.';
    }
    return null;
  }

  /// Returns this config when usable, else throws [AppConfigException].
  ///
  /// The message names the missing `--dart-define` flags without echoing
  /// any key material. Either key name satisfies the key requirement.
  AppConfig requireValid() {
    final List<String> missing = missingFields;
    if (missing.isNotEmpty) {
      throw AppConfigException(
        'Missing Supabase configuration (${missing.join(', ')}). '
        'Rerun with --dart-define=$kSupabaseUrlDefine=<url> '
        '--dart-define=$kSupabaseAnonKeyDefine=<key> '
        '(or --dart-define=$kSupabasePublishableKeyDefine=<key>).',
      );
    }
    final String? badUrl = urlError;
    if (badUrl != null) {
      throw AppConfigException(badUrl);
    }
    return this;
  }
}
