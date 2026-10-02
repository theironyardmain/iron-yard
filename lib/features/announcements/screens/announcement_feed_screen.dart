import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/local/database.dart';
import '../providers/announcement_providers.dart';

/// The member's announcement feed, cached locally (brain.md §6.9).
class AnnouncementFeedScreen extends ConsumerStatefulWidget {
  const AnnouncementFeedScreen({super.key});

  @override
  ConsumerState<AnnouncementFeedScreen> createState() =>
      _AnnouncementFeedScreenState();
}

class _AnnouncementFeedScreenState
    extends ConsumerState<AnnouncementFeedScreen> {
  @override
  void initState() {
    super.initState();
    // Subscribing here rather than at startup keeps the socket open only while
    // someone is actually looking at announcements (brain.md §4).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(announcementRealtimeProvider).subscribe();
    });
  }

  @override
  Widget build(BuildContext context) {
    final announcements = ref.watch(publishedAnnouncementsProvider);
    final unread = ref.watch(unreadAnnouncementsProvider).valueOrNull ?? 0;

    return Scaffold(
      body: announcements.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load: $error')),
        data: (list) => list.isEmpty
            ? const _Empty()
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: list.length,
                itemBuilder: (context, index) =>
                    _AnnouncementCard(announcement: list[index]),
              ),
      ),
      floatingActionButton: unread == 0
          ? null
          : FloatingActionButton.extended(
              onPressed: () =>
                  ref.read(announcementDaoProvider).markAllRead(),
              icon: const Icon(Icons.done_all),
              label: Text('Mark $unread read'),
            ),
    );
  }
}

class _AnnouncementCard extends ConsumerWidget {
  const _AnnouncementCard({required this.announcement});

  final Announcement announcement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isUnread = !announcement.isRead;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: announcement.isUrgent ? scheme.errorContainer : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isUnread
            ? () => ref
                  .read(announcementDaoProvider)
                  .markRead(announcement.id)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (announcement.isUrgent) ...[
                    Icon(
                      Icons.priority_high,
                      size: 18,
                      color: scheme.onErrorContainer,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      announcement.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: isUnread
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: announcement.isUrgent
                            ? scheme.onErrorContainer
                            : null,
                      ),
                    ),
                  ),
                  if (isUnread)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                announcement.body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: announcement.isUrgent ? scheme.onErrorContainer : null,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                announcement.publishedAt == null
                    ? 'Draft'
                    : DateFormat.yMMMd().add_jm().format(
                        announcement.publishedAt!,
                      ),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: announcement.isUrgent
                      ? scheme.onErrorContainer
                      : scheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

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
              Icons.campaign_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('No announcements', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Gym news will appear here.',
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
