import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants/app_constants.dart';
import 'core/notifications/notification_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/remote/supabase_client.dart';
import 'features/auth/providers/auth_providers.dart';
import 'features/notifications/providers/notification_providers.dart';
import 'shared/providers/sync_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Startup must not fail because the device is offline (brain.md §1). A
  // configuration error is surfaced to the user; a network error is not, since
  // the app is expected to run from the local cache.
  String? startupError;
  try {
    await SupabaseService.init();
  } on StateError catch (e) {
    startupError = e.message;
  } catch (e) {
    // Network/init failure — the app still runs against local data.
    debugPrint('Supabase init deferred: $e');
  }

  final prefs = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );

  // Local notifications back every reminder in v1 (brain.md §6.9). A refusal
  // or an unsupported platform is handled inside the service.
  //
  // Initialised after the container exists so a tap can be routed straight
  // into it.
  final notificationRouter = container.read(notificationRouterProvider);
  await Notifications.init(onTap: notificationRouter.handle);

  // A cold start never fires the tap callback: the app was launched *by* the
  // notification, so the payload has to be read back explicitly.
  final launchedBy = await Notifications.launchPayload();
  if (launchedBy != null) notificationRouter.handle(launchedBy);

  // Show the real last-sync time immediately rather than "never synced".
  // Best-effort: a failure here must not stop the app from starting.
  if (startupError == null) {
    try {
      unawaited(
        container.read(syncControllerProvider).restoreStatus().catchError((
          Object error,
        ) {
          debugPrint('Could not restore sync status: $error');
        }),
      );
    } catch (error) {
      debugPrint('Sync controller unavailable at startup: $error');
    }
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: IronYardApp(startupError: startupError),
    ),
  );
}

class IronYardApp extends ConsumerWidget {
  const IronYardApp({super.key, this.startupError});

  final String? startupError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A missing Supabase configuration is fatal: without it there is nothing to
    // authenticate against, so the router is never built.
    if (startupError != null) {
      return MaterialApp(
        title: AppConstants.appName,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        debugShowCheckedModeBanner: false,
        home: _StartupErrorScreen(message: startupError!),
      );
    }

    return MaterialApp.router(
      title: AppConstants.appName,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

/// Shown when the app was built without Supabase credentials.
class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.settings_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Configuration required',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              SelectableText(
                message,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
