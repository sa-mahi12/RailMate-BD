import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/core/config/app_config.dart';
import 'package:railmate_bd/core/supabase/supabase_client.dart';

void main() {
  test(
    'missing config reports fields and throws with --dart-define guidance',
    () {
      const config = AppConfig(supabaseUrl: '', supabaseAnonKey: '');
      expect(config.isConfigured, isFalse);
      expect(
        config.missingFields,
        containsAll(<String>[kSupabaseUrlDefine, kSupabaseAnonKeyDefine]),
      );
      expect(() => config.requireValid(), throwsA(isA<AppConfigException>()));
    },
  );

  test('missing config maps to missingConfig state, no network', () async {
    final bootstrap = SupabaseBootstrap.instance..resetForTests();
    var attempted = false;
    await bootstrap.initialize(
      config: const AppConfig(supabaseUrl: '', supabaseAnonKey: ''),
      connect: (_) async {
        attempted = true;
      },
    );
    expect(bootstrap.state, SupabaseConnectionState.missingConfig);
    expect(bootstrap.errorMessage, contains(kSupabaseUrlDefine));
    expect(attempted, isFalse);
    bootstrap.resetForTests();
  });

  test('malformed URL maps to error state, connect hook never runs', () async {
    final bootstrap = SupabaseBootstrap.instance..resetForTests();
    var attempted = false;
    await bootstrap.initialize(
      config: const AppConfig(
        supabaseUrl: 'not-a-url',
        supabaseAnonKey: 'dummy-key',
      ),
      connect: (_) async {
        attempted = true;
      },
    );
    expect(bootstrap.state, SupabaseConnectionState.error);
    expect(attempted, isFalse);
    bootstrap.resetForTests();
  });

  test(
    'valid config without SDK hook maps to error with wiring guidance',
    () async {
      final bootstrap = SupabaseBootstrap.instance..resetForTests();
      await bootstrap.initialize(
        config: const AppConfig(
          supabaseUrl: 'https://example.supabase.co',
          supabaseAnonKey: 'dummy-key',
        ),
      );
      expect(bootstrap.state, SupabaseConnectionState.error);
      expect(bootstrap.errorMessage, contains('supabase_flutter'));
      bootstrap.resetForTests();
    },
  );

  test('failing connect hook maps to error state', () async {
    final bootstrap = SupabaseBootstrap.instance..resetForTests();
    await bootstrap.initialize(
      config: const AppConfig(
        supabaseUrl: 'https://example.supabase.co',
        supabaseAnonKey: 'dummy-key',
      ),
      connect: (_) async {
        throw Exception('offline');
      },
    );
    expect(bootstrap.state, SupabaseConnectionState.error);
    expect(bootstrap.errorMessage, contains('offline'));
    bootstrap.resetForTests();
  });

  test('successful connect hook maps to ready state', () async {
    final bootstrap = SupabaseBootstrap.instance..resetForTests();
    var attempted = false;
    await bootstrap.initialize(
      config: const AppConfig(
        supabaseUrl: 'https://example.supabase.co',
        supabaseAnonKey: 'dummy-key',
      ),
      connect: (_) async {
        attempted = true;
      },
    );
    expect(bootstrap.state, SupabaseConnectionState.ready);
    expect(attempted, isTrue);
    expect(bootstrap.config, isNotNull);
    bootstrap.resetForTests();
  });
}
