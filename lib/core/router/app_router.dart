import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/providers/auth_providers.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/profile_screen.dart';
import '../../features/auth/screens/sign_up_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/dashboard/screens/admin_shell.dart';
import '../../features/dashboard/screens/member_shell.dart';
import '../../features/dashboard/screens/trainer_shell.dart';
import '../constants/app_constants.dart';

/// Route paths, so callers never hand-write a string.
class Routes {
  const Routes._();

  static const splash = '/';
  static const login = '/login';
  static const forgotPassword = '/forgot-password';
  static const signUp = '/sign-up';

  static const admin = '/admin';
  static const trainer = '/trainer';
  static const member = '/member';

  static const profile = '/profile';

  /// The home route for a role (brain.md §6.1).
  static String homeFor(UserRole role) => switch (role) {
    UserRole.admin => admin,
    UserRole.trainer => trainer,
    UserRole.member => member,
  };
}

/// Re-runs the router's redirect whenever auth state changes.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(this._ref) {
    _ref.listen(authControllerProvider, (_, _) => notifyListeners());
  }

  final Ref _ref;
}

final routerProvider = Provider<GoRouter>((ref) {
  final listenable = _AuthListenable(ref);
  ref.onDispose(listenable.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: listenable,
    redirect: (context, state) {
      final status = ref.read(authControllerProvider);
      final location = state.matchedLocation;

      final isAuthRoute =
          location == Routes.login ||
          location == Routes.forgotPassword ||
          location == Routes.signUp ||
          location == Routes.splash;

      switch (status) {
        case AuthLoading():
          // Hold on the splash while the persisted session is restored.
          return location == Routes.splash ? null : Routes.splash;

        case AuthSignedOut():
          return isAuthRoute && location != Routes.splash
              ? null
              : Routes.login;

        case AuthSignedIn(:final session):
          final home = Routes.homeFor(session.role);

          if (isAuthRoute) return home;

          // Role gating: the RLS policies are the real boundary, but a member
          // must not be able to reach an admin screen and see a broken page or
          // an empty list where data is silently filtered out.
          final allowedPrefix = switch (session.role) {
            UserRole.admin => Routes.admin,
            UserRole.trainer => Routes.trainer,
            UserRole.member => Routes.member,
          };

          if (location.startsWith(Routes.admin) ||
              location.startsWith(Routes.trainer) ||
              location.startsWith(Routes.member)) {
            return location.startsWith(allowedPrefix) ? null : home;
          }

          return null;
      }
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (_, _) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (_, _) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.forgotPassword,
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: Routes.signUp,
        builder: (_, _) => const SignUpScreen(),
      ),
      GoRoute(
        path: Routes.profile,
        builder: (_, _) => const ProfileScreen(),
      ),
      GoRoute(
        path: Routes.admin,
        builder: (_, _) => const AdminShell(),
      ),
      GoRoute(
        path: Routes.trainer,
        builder: (_, _) => const TrainerShell(),
      ),
      GoRoute(
        path: Routes.member,
        builder: (_, _) => const MemberShell(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              Text('Page not found: ${state.uri}'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(Routes.splash),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
});
