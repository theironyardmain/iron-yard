import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/widgets/sign_out_action.dart';
import '../../checkin/providers/checkin_providers.dart';
import '../../notifications/data/notification_router.dart';
import '../../notifications/providers/notification_providers.dart';
import '../../../shared/providers/sync_providers.dart';
import '../../../shared/widgets/sync_indicator.dart';
import '../../../data/sync/sync_controller.dart';

/// A destination in a role's bottom navigation.
class ShellDestination {
  const ShellDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.body,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Widget body;
}

/// Shared scaffold for the three role shells (brain.md §6.1).
///
/// Holds the navigation structure; each destination's content is filled in by
/// its own phase.
class RoleShell extends ConsumerStatefulWidget {
  const RoleShell({
    required this.title,
    required this.destinations,
    super.key,
  });

  final String title;
  final List<ShellDestination> destinations;

  @override
  ConsumerState<RoleShell> createState() => _RoleShellState();
}

class _RoleShellState extends ConsumerState<RoleShell> {
  int _index = 0;

  /// Opens the tab a tapped notification points at (tasks.md 13.5).
  ///
  /// Called once the shell exists. A payload recorded during a cold start, or
  /// while the session was still restoring, has been waiting in the router
  /// until now.
  void _consumePendingNotification() {
    final NotificationRouter router;
    try {
      router = ref.read(notificationRouterProvider);
    } catch (error) {
      debugPrint('Notification router unavailable: $error');
      return;
    }

    final payload = router.consume();
    if (payload == null) return;

    final tab = tabFor(payload).index;

    // Only the member shell has these tabs. A staff device with a stray
    // payload simply stays where it is rather than jumping somewhere odd.
    if (tab >= widget.destinations.length) return;
    if (!mounted) return;

    setState(() => _index = tab);
  }

  @override
  void initState() {
    super.initState();
    // After login (brain.md §4). Deferred so the first frame is not blocked.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sync(SyncTrigger.login);

      // Re-arm the daily check-in reminder: scheduled notifications do not
      // survive a reinstall or an OS clear, so the saved preference is
      // reapplied on each sign-in (brain.md §6.7).
      //
      // Best-effort, like the sync trigger above: reading the settings store
      // can fail outside a fully configured app, and a missing reminder must
      // never take the screen down with it.
      try {
        unawaited(
          ref.read(checkInRepositoryProvider).applyReminder().catchError((
            Object error,
          ) {
            debugPrint('Could not re-arm check-in reminder: $error');
          }),
        );
      } catch (error) {
        debugPrint('Check-in reminder unavailable: $error');
      }

      // Independent of the reminder above: a failure there must not stop a
      // tapped notification from reaching its screen.
      _consumePendingNotification();
    });
  }

  /// Syncs on a trigger. The controller throttles section triggers, so
  /// switching tabs repeatedly does not hammer the server.
  ///
  /// Sync is best-effort: the app is offline-first (brain.md §1), so a sync
  /// that cannot even start — no Supabase, no network — must never break the
  /// screen the user is looking at.
  void _sync(SyncTrigger trigger) {
    try {
      unawaited(
        runSyncThenReceipts(
          controller: ref.read(syncControllerProvider),
          uploader: ref.read(receiptUploaderProvider),
          trigger: trigger,
        ).then((report) async {
          // Reminders depend on data the sync may have just changed — a
          // renewal elsewhere, a cancelled class — so rebuild them after.
          final memberId = ref.read(currentSessionProvider)?.userId;
          if (memberId != null) {
            await ref
                .read(reminderSchedulerProvider)
                .rescheduleFor(memberId);
          }
          return report;
        }).catchError((Object error) {
          debugPrint('Sync ($trigger) failed: $error');
          return null;
        }),
      );
    } catch (error) {
      debugPrint('Sync ($trigger) could not start: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentSessionProvider);
    final destination = widget.destinations[_index];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          const SyncIndicator(),
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: session?.fullName ?? 'Profile',
            onPressed: () => context.push(Routes.profile),
          ),
          const SignOutAction(),
        ],
      ),
      body: destination.body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          // Opening a major section (brain.md §4) — throttled, never on every
          // navigation.
          _sync(SyncTrigger.section);
        },
        destinations: [
          for (final d in widget.destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

/// Placeholder for a destination whose feature phase has not landed yet.
///
/// Deliberately explicit rather than a fake empty state, so it is never
/// mistaken for a working screen with no data.
class ComingSoon extends StatelessWidget {
  const ComingSoon({required this.feature, required this.phase, super.key});

  final String feature;
  final String phase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.construction_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(feature, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Built in $phase',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
