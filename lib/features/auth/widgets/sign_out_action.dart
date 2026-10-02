import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_providers.dart';

/// Sign-out button with the confirmation the purge-on-logout policy requires.
///
/// Signing out wipes the local database (owner decision, tasks.md 3.7) because
/// the app runs on a shared front-desk tablet. That makes sign-out destructive
/// when offline work is still queued, so this always confirms, and warns
/// explicitly when unsynced changes would be lost.
class SignOutAction extends ConsumerWidget {
  const SignOutAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.logout),
      tooltip: 'Sign out',
      onPressed: () => confirmAndSignOut(context, ref),
    );
  }

  /// Confirms, then signs out. Returns true when the user signed out.
  static Future<bool> confirmAndSignOut(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final controller = ref.read(authControllerProvider.notifier);
    final hasUnsynced = await controller.hasUnsyncedChanges();

    if (!context.mounted) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Signing out removes all gym data from this device. '
              'You will need an internet connection to sign in again.',
            ),
            if (hasUnsynced) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_outlined,
                      size: 20,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Some changes have not been synced yet and will be '
                        'lost. Connect to the internet and sync first.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: hasUnsynced
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  )
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(hasUnsynced ? 'Sign out anyway' : 'Sign out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    // force: the user was shown the warning and chose to proceed.
    await controller.signOut(force: true);
    return true;
  }
}
