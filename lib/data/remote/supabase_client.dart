import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';

/// Thin wrapper around Supabase initialisation and access.
///
/// The app is offline-first (brain.md §1): initialising Supabase must never
/// block startup or throw on a missing network. `supabase_flutter` restores the
/// persisted session from local storage, so a previously logged-in user opens
/// the app authenticated with no connection.
class SupabaseService {
  const SupabaseService._();

  static bool _initialised = false;

  static Future<void> init() async {
    if (_initialised) return;
    Env.assertConfigured();

    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabasePublishableKey,
      authOptions: const FlutterAuthClientOptions(
        // Session is persisted locally so the app opens logged-in offline.
        autoRefreshToken: true,
      ),
    );

    _initialised = true;
  }

  static SupabaseClient get client => Supabase.instance.client;

  static User? get currentUser => client.auth.currentUser;

  static bool get isSignedIn => currentUser != null;
}
