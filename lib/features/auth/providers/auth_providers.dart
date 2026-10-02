import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/local/database.dart';
import '../../../data/remote/supabase_client.dart';
import '../../../shared/providers/database_provider.dart';
import '../../notifications/data/notification_router.dart';
import '../../notifications/data/reminder_scheduler.dart';
import '../../notifications/providers/notification_providers.dart';
import '../data/auth_repository.dart';

/// Set during startup in `main()`, so the rest of the app can read prefs
/// synchronously.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main()',
  ),
);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    client: SupabaseService.client,
    profileDao: ref.watch(profileDaoProvider),
    prefs: ref.watch(sharedPreferencesProvider),
  );
});

/// Where the app is in the sign-in lifecycle.
sealed class AuthStatus {
  const AuthStatus();
}

/// Restoring a persisted session — the splash state.
class AuthLoading extends AuthStatus {
  const AuthLoading();
}

class AuthSignedOut extends AuthStatus {
  const AuthSignedOut({this.message});

  /// Shown once after an involuntary sign-out, e.g. a deactivated account.
  final String? message;
}

class AuthSignedIn extends AuthStatus {
  const AuthSignedIn(this.session);

  final AuthSession session;
}

/// Drives routing and holds the signed-in session.
class AuthController extends StateNotifier<AuthStatus> {
  AuthController(this._repository, this._database, this._notifications)
    : super(const AuthLoading()) {
    _restore();
  }

  final AuthRepository _repository;
  final AppDatabase _database;
  final NotificationRouter _notifications;

  Future<void> _restore() async {
    try {
      final session = await _repository.restoreSession();
      state = session == null
          ? const AuthSignedOut()
          : AuthSignedIn(session);
    } on SignInException catch (e) {
      // A persisted session we cannot resolve is not a usable session.
      state = AuthSignedOut(message: e.message);
    }
  }

  /// Returns null on success, or the failure to display.
  Future<AuthFailure?> signIn({
    required String email,
    required String password,
  }) async {
    state = const AuthLoading();
    try {
      final session = await _repository.signIn(
        email: email,
        password: password,
      );
      state = AuthSignedIn(session);
      return null;
    } on SignInException catch (e) {
      state = const AuthSignedOut();
      return e.failure;
    }
  }

  /// Creates an account and signs in.
  ///
  /// Returns null on success, or the failure to display. A
  /// [AuthFailure.confirmationRequired] result is not an error in the usual
  /// sense — the account was created and the user needs to confirm their
  /// email — so the caller shows it differently.
  Future<AuthFailure?> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    state = const AuthLoading();
    try {
      final session = await _repository.signUp(
        email: email,
        password: password,
        fullName: fullName,
      );
      state = AuthSignedIn(session);
      return null;
    } on SignInException catch (e) {
      state = const AuthSignedOut();
      return e.failure;
    }
  }

  /// Whether signing out now would discard local changes.
  ///
  /// Sign-out purges the local database (owner decision, tasks.md 3.7), so the
  /// UI must warn before destroying an attendance scan or payment captured
  /// offline.
  Future<bool> hasUnsyncedChanges() => _database.hasUnsyncedChanges();

  /// Signs out and wipes the local cache.
  ///
  /// The app runs on a shared front-desk tablet, so member data must not
  /// survive a sign-out. Pass [force] only after warning about unsynced work.
  Future<void> signOut({bool force = false}) async {
    if (!force && await _database.hasUnsyncedChanges()) {
      throw StateError(
        'Refusing to sign out with unsynced changes. '
        'Sync first, or call signOut(force: true).',
      );
    }
    // Reminders reference data that is about to be wiped, so they go too.
    // A notification about a membership this device no longer holds would be
    // confusing at best. Same for a payload still waiting to be routed.
    await ReminderScheduler(_database).cancelAll();
    _notifications.clear();

    await _repository.signOut();
    await _database.wipeAllData();
    state = const AuthSignedOut();
  }

  Future<AuthFailure?> sendPasswordReset(String email) async {
    try {
      await _repository.sendPasswordReset(email);
      return null;
    } on SignInException catch (e) {
      return e.failure;
    }
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthStatus>((ref) {
      return AuthController(
        ref.watch(authRepositoryProvider),
        ref.watch(databaseProvider),
        ref.watch(notificationRouterProvider),
      );
    });

/// The signed-in session, or null.
final currentSessionProvider = Provider<AuthSession?>((ref) {
  final status = ref.watch(authControllerProvider);
  return status is AuthSignedIn ? status.session : null;
});
