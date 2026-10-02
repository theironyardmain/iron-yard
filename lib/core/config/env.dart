/// Environment configuration.
///
/// Values are injected at build time via `--dart-define` so that keys are never
/// committed to the repository. See `README.md` for the run/build commands.
///
/// The Supabase anon key is safe to ship in a client binary — it is public by
/// design and every table is protected by Row Level Security (see brain.md §2).
/// It is kept out of source control anyway so that rotating a key, or pointing a
/// build at a different project, does not require a code change.
class Env {
  const Env._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Supabase publishable key (formerly "anon key").
  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  /// Whether both required values were supplied at build time.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  /// Throws if the app was built without Supabase credentials.
  ///
  /// Called during startup so a misconfigured build fails immediately with a
  /// clear message, rather than surfacing as an opaque network error later.
  static void assertConfigured() {
    if (!isConfigured) {
      throw StateError(
        'Missing Supabase configuration. Run with:\n'
        '  flutter run --dart-define=SUPABASE_URL=... '
        '--dart-define=SUPABASE_ANON_KEY=...\n'
        'Or use: flutter run --dart-define-from-file=env.json',
      );
    }
  }
}
