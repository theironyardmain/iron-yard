import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iron_yard/core/constants/app_constants.dart';
import 'package:iron_yard/core/router/app_router.dart';
import 'package:iron_yard/features/auth/data/auth_repository.dart';
import 'package:iron_yard/features/auth/providers/auth_providers.dart';
import 'package:iron_yard/features/dashboard/screens/admin_shell.dart';
import 'package:iron_yard/features/dashboard/screens/member_shell.dart';
import 'package:iron_yard/features/dashboard/screens/trainer_shell.dart';

/// Drives [AuthStatus] directly, so routing can be tested without Supabase.
class _FakeAuthController extends StateNotifier<AuthStatus>
    implements AuthController {
  _FakeAuthController(super.state);

  @override
  Future<bool> hasUnsyncedChanges() async => false;

  @override
  Future<AuthFailure?> signIn({
    required String email,
    required String password,
  }) async => null;

  @override
  Future<void> signOut({bool force = false}) async {
    state = const AuthSignedOut();
  }

  @override
  Future<AuthFailure?> sendPasswordReset(String email) async => null;

  @override
  Future<AuthFailure?> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

AuthSession _session(UserRole role) => AuthSession(
  userId: 'user-${role.name}',
  role: role,
  fullName: '${role.name} user',
  email: '${role.name}@example.com',
);

Future<GoRouter> _pumpWith(
  WidgetTester tester,
  AuthStatus status, {
  String? startAt,
}) async {
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((ref) => _FakeAuthController(status)),
    ],
  );
  addTearDown(container.dispose);

  final router = container.read(routerProvider);
  if (startAt != null) router.go(startAt);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );

  // Bounded pumps rather than pumpAndSettle: the splash and the profile screen
  // both show an indefinite CircularProgressIndicator, which never settles.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }

  return router;
}

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

void main() {
  group('role-based landing (brain.md §6.1)', () {
    testWidgets('an admin lands on the admin shell', (tester) async {
      final router = await _pumpWith(
        tester,
        AuthSignedIn(_session(UserRole.admin)),
      );

      expect(_location(router), Routes.admin);
      expect(find.byType(AdminShell), findsOneWidget);
    });

    testWidgets('a trainer lands on the trainer shell', (tester) async {
      final router = await _pumpWith(
        tester,
        AuthSignedIn(_session(UserRole.trainer)),
      );

      expect(_location(router), Routes.trainer);
      expect(find.byType(TrainerShell), findsOneWidget);
    });

    testWidgets('a member lands on the member shell', (tester) async {
      final router = await _pumpWith(
        tester,
        AuthSignedIn(_session(UserRole.member)),
      );

      expect(_location(router), Routes.member);
      expect(find.byType(MemberShell), findsOneWidget);
    });
  });

  group('role gating', () {
    testWidgets('a member navigating to /admin is sent home', (tester) async {
      final router = await _pumpWith(
        tester,
        AuthSignedIn(_session(UserRole.member)),
        startAt: Routes.admin,
      );

      expect(_location(router), Routes.member);
      expect(find.byType(AdminShell), findsNothing);
    });

    testWidgets('a trainer navigating to /admin is sent home', (tester) async {
      final router = await _pumpWith(
        tester,
        AuthSignedIn(_session(UserRole.trainer)),
        startAt: Routes.admin,
      );

      expect(_location(router), Routes.trainer);
      expect(find.byType(AdminShell), findsNothing);
    });

    testWidgets('an admin navigating to /member is sent home', (tester) async {
      // Gating runs in both directions: an admin should not land inside the
      // member shell either.
      final router = await _pumpWith(
        tester,
        AuthSignedIn(_session(UserRole.admin)),
        startAt: Routes.member,
      );

      expect(_location(router), Routes.admin);
    });

    testWidgets('a shared route stays reachable for every role', (
      tester,
    ) async {
      for (final role in UserRole.values) {
        final router = await _pumpWith(
          tester,
          AuthSignedIn(_session(role)),
          startAt: Routes.profile,
        );
        expect(
          _location(router),
          Routes.profile,
          reason: '${role.name} should reach the shared profile route',
        );
      }
    });
  });

  group('signed-out routing', () {
    testWidgets('a signed-out user gets the login screen', (tester) async {
      final router = await _pumpWith(tester, const AuthSignedOut());
      expect(_location(router), Routes.login);
    });

    testWidgets('a signed-out user cannot reach a role shell', (tester) async {
      final router = await _pumpWith(
        tester,
        const AuthSignedOut(),
        startAt: Routes.admin,
      );

      expect(_location(router), Routes.login);
      expect(find.byType(AdminShell), findsNothing);
    });

    testWidgets('sign-up is reachable while signed out', (tester) async {
      // Without this a new member has no way into the app at all.
      final router = await _pumpWith(
        tester,
        const AuthSignedOut(),
        startAt: Routes.signUp,
      );

      expect(_location(router), Routes.signUp);
    });

    testWidgets('a signed-in user is redirected away from sign-up', (
      tester,
    ) async {
      final router = await _pumpWith(
        tester,
        AuthSignedIn(_session(UserRole.member)),
        startAt: Routes.signUp,
      );

      expect(_location(router), Routes.member);
    });

    testWidgets('forgot-password is reachable while signed out', (
      tester,
    ) async {
      final router = await _pumpWith(
        tester,
        const AuthSignedOut(),
        startAt: Routes.forgotPassword,
      );

      expect(_location(router), Routes.forgotPassword);
    });
  });

  group('loading', () {
    testWidgets('holds on the splash while restoring a session', (
      tester,
    ) async {
      final router = await _pumpWith(
        tester,
        const AuthLoading(),
        startAt: Routes.admin,
      );

      // Routing before the role is known would flash the wrong shell.
      expect(_location(router), Routes.splash);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
