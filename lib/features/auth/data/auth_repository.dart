import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthState, SupabaseClient, User, UserAttributes, AuthResponse;

import '../../../core/constants/app_constants.dart';
import '../../../data/local/daos/profile_dao.dart';

/// Why a sign-in attempt failed, in terms the UI can act on.
enum AuthFailure {
  invalidCredentials,
  network,
  emailNotConfirmed,
  noProfile,

  /// Sign-up with an email that already has an account.
  emailInUse,

  /// Sign-up with a password the server rejected as too weak.
  weakPassword,

  /// The account was created but needs email confirmation before signing in.
  confirmationRequired,

  unknown;

  String get message => switch (this) {
    AuthFailure.invalidCredentials => 'Incorrect email or password.',
    AuthFailure.network =>
      'Cannot reach the server. Check your connection and try again.',
    AuthFailure.emailNotConfirmed =>
      'This email has not been confirmed yet.',
    AuthFailure.noProfile =>
      'This account has no profile set up. Contact the gym.',
    AuthFailure.emailInUse =>
      'An account already exists for this email. Try signing in.',
    AuthFailure.weakPassword =>
      'Choose a longer password — at least 8 characters.',
    AuthFailure.confirmationRequired =>
      'Check your email to confirm your account, then sign in.',
    AuthFailure.unknown => 'Something went wrong. Please try again.',
  };
}

/// Thrown by [AuthRepository] on a failed sign-in.
///
/// Named to avoid colliding with Supabase's own `AuthException`.
class SignInException implements Exception {
  const SignInException(this.failure, [this.detail]);

  final AuthFailure failure;
  final String? detail;

  String get message => failure.message;

  @override
  String toString() => 'SignInException(${failure.name}${detail == null ? '' : ': $detail'})';
}

/// The signed-in user, as the app needs it.
class AuthSession {
  const AuthSession({
    required this.userId,
    required this.role,
    required this.fullName,
    this.email,
  });

  final String userId;
  final UserRole role;
  final String fullName;
  final String? email;
}

/// Authentication and role resolution (brain.md §6.1).
///
/// Offline-first: `supabase_flutter` persists the session to local storage, and
/// the resolved role is cached alongside it. A returning user therefore opens
/// the app signed in and correctly routed with no network — the role is only
/// re-fetched when a live call succeeds.
class AuthRepository {
  AuthRepository({
    required SupabaseClient client,
    required ProfileDao profileDao,
    required SharedPreferences prefs,
  }) : _client = client,
       _profileDao = profileDao,
       _prefs = prefs;

  final SupabaseClient _client;
  final ProfileDao _profileDao;
  final SharedPreferences _prefs;

  static const _kCachedRole = 'auth.cached_role';
  static const _kCachedUserId = 'auth.cached_user_id';
  static const _kCachedName = 'auth.cached_name';

  /// Emits on sign-in and sign-out.
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  User? get currentUser => _client.auth.currentUser;

  bool get isSignedIn => currentUser != null;

  /// Signs in and resolves the user's role.
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) async {
    final AuthResponse response;
    try {
      response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } on supabase.AuthException catch (e) {
      throw SignInException(_classify(e), e.message);
    } catch (e) {
      throw SignInException(AuthFailure.network, e.toString());
    }

    final user = response.user;
    if (user == null) {
      throw const SignInException(AuthFailure.unknown, 'No user in response');
    }

    return _resolveSession(user);
  }

  /// Creates an account and signs in (brain.md §6.1).
  ///
  /// The server's `handle_new_user` trigger creates the matching `member`
  /// profile, so a new user always lands with a usable role. Staff are
  /// promoted deliberately — sign-up never grants one.
  ///
  /// Throws [SignInException] with [AuthFailure.confirmationRequired] when the
  /// project requires email confirmation: the account exists but there is no
  /// session yet, and silently treating that as success would leave the user
  /// staring at a login screen that rejects them.
  Future<AuthSession> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final supabase.AuthResponse response;
    try {
      response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        // Read back by the trigger, so the profile carries a real name rather
        // than the email prefix.
        data: {'full_name': fullName.trim()},
      );
    } on supabase.AuthException catch (e) {
      throw SignInException(_classifySignUp(e), e.message);
    } catch (e) {
      throw SignInException(AuthFailure.network, e.toString());
    }

    final user = response.user;
    if (user == null) {
      throw const SignInException(AuthFailure.unknown, 'No user in response');
    }

    if (response.session == null) {
      throw const SignInException(AuthFailure.confirmationRequired);
    }

    return _resolveSession(user);
  }

  /// Restores a session saved on this device, without network access.
  ///
  /// Returns null when there is no persisted session. Falls back to the cached
  /// role when the profile cannot be fetched, so a returning user opens the app
  /// correctly routed while offline (brain.md §1).
  Future<AuthSession?> restoreSession() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    try {
      return await _resolveSession(user);
    } on SignInException {
      final cached = _cachedSession(user.id);
      if (cached != null) return cached;
      rethrow;
    }
  }

  /// Resolves the role from the local profile cache, falling back to the server.
  ///
  /// Local-first by design: after the first sync the profile is on-device, so
  /// this is a local read rather than a network round trip on every launch.
  Future<AuthSession> _resolveSession(User user) async {
    final local = await _profileDao.byId(user.id);
    if (local != null && !local.isDeleted) {
      final role = UserRole.fromString(local.role);
      if (role != null) {
        final session = AuthSession(
          userId: user.id,
          role: role,
          fullName: local.fullName,
          email: user.email,
        );
        await _cacheSession(session);
        return session;
      }
    }

    // Not cached yet — first sign-in on this device.
    final Map<String, dynamic>? row;
    try {
      row = await _client
          .from('profiles')
          .select('id, role, full_name')
          .eq('id', user.id)
          .maybeSingle();
    } catch (e) {
      final cached = _cachedSession(user.id);
      if (cached != null) return cached;
      throw SignInException(AuthFailure.network, e.toString());
    }

    if (row == null) {
      throw const SignInException(AuthFailure.noProfile);
    }

    final role = UserRole.fromString(row['role'] as String?);
    if (role == null) {
      throw SignInException(
        AuthFailure.noProfile,
        'Unrecognised role: ${row['role']}',
      );
    }

    final session = AuthSession(
      userId: user.id,
      role: role,
      fullName: (row['full_name'] as String?) ?? '',
      email: user.email,
    );
    await _cacheSession(session);
    return session;
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {
      // Signing out must work offline. The local session is cleared below
      // regardless; the server token expires on its own.
    }
    await _clearCache();
  }

  /// Sends a password-reset email (brain.md §6.1).
  Future<void> sendPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email.trim());
    } on supabase.AuthException catch (e) {
      throw SignInException(_classify(e), e.message);
    } catch (e) {
      throw SignInException(AuthFailure.network, e.toString());
    }
  }

  /// Updates the signed-in user's password.
  Future<void> updatePassword(String newPassword) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } on supabase.AuthException catch (e) {
      throw SignInException(_classify(e), e.message);
    } catch (e) {
      throw SignInException(AuthFailure.network, e.toString());
    }
  }

  // --- Role cache ---

  Future<void> _cacheSession(AuthSession session) async {
    await _prefs.setString(_kCachedUserId, session.userId);
    await _prefs.setString(_kCachedRole, session.role.wireValue);
    await _prefs.setString(_kCachedName, session.fullName);
  }

  AuthSession? _cachedSession(String userId) {
    // Only trust the cache for the user it was written for, so a second account
    // signing in on the same device cannot inherit the first one's role.
    if (_prefs.getString(_kCachedUserId) != userId) return null;

    final role = UserRole.fromString(_prefs.getString(_kCachedRole));
    if (role == null) return null;

    return AuthSession(
      userId: userId,
      role: role,
      fullName: _prefs.getString(_kCachedName) ?? '',
      email: _client.auth.currentUser?.email,
    );
  }

  Future<void> _clearCache() async {
    await _prefs.remove(_kCachedUserId);
    await _prefs.remove(_kCachedRole);
    await _prefs.remove(_kCachedName);
  }

  /// Sign-up failures differ from sign-in ones: "already registered" is a
  /// normal outcome here, not a credential error.
  AuthFailure _classifySignUp(supabase.AuthException e) {
    final message = e.message.toLowerCase();

    if (message.contains('already registered') ||
        message.contains('already been registered') ||
        message.contains('user already exists')) {
      return AuthFailure.emailInUse;
    }
    if (message.contains('password') &&
        (message.contains('short') || message.contains('least'))) {
      return AuthFailure.weakPassword;
    }
    if (message.contains('network') || message.contains('socket')) {
      return AuthFailure.network;
    }
    return AuthFailure.unknown;
  }

  AuthFailure _classify(supabase.AuthException e) {
    final message = e.message.toLowerCase();
    if (message.contains('invalid login') ||
        message.contains('invalid credentials')) {
      return AuthFailure.invalidCredentials;
    }
    if (message.contains('email not confirmed')) {
      return AuthFailure.emailNotConfirmed;
    }
    if (message.contains('network') || message.contains('socket')) {
      return AuthFailure.network;
    }
    return AuthFailure.unknown;
  }
}
