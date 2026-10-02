import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/local/database.dart';
import '../../announcements/providers/announcement_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../widgets/feedback_form_sheet.dart';

/// A member's own feedback and support requests (brain.md §6.2).
///
/// Submissions are written locally and queued, so a member can raise something
/// on the gym floor with no signal.
class MyFeedbackScreen extends ConsumerWidget {
  const MyFeedbackScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberId = ref.watch(currentSessionProvider)?.userId;

    if (memberId == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final feedback = ref.watch(myFeedbackProvider(memberId));

    return Scaffold(
      appBar: AppBar(title: const Text('Feedback & support')),
      body: feedback.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load: $error')),
        data: (list) => list.isEmpty
            ? const _Empty()
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                itemCount: list.length,
                itemBuilder: (context, index) =>
                    _FeedbackCard(item: list[index]),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showFeedbackFormSheet(
          context: context,
          memberId: memberId,
        ),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('New message'),
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.item});

  final FeedbackData item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isResolved = item.status == 'resolved';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isResolved
                      ? Icons.check_circle_outline
                      : Icons.schedule_outlined,
                  size: 18,
                  color: isResolved
                      ? theme.colorScheme.primary
                      : theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.subject?.isNotEmpty == true
                        ? item.subject!
                        : 'Message',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  DateFormat.MMMd().format(item.createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(item.message, style: theme.textTheme.bodyMedium),

            if (item.adminResponse?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.reply,
                          size: 14,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          item.respondedAt == null
                              ? 'Reply from the gym'
                              : 'Reply · '
                                    '${DateFormat.MMMd().format(item.respondedAt!)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.adminResponse!,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ] else if (!isResolved) ...[
              const SizedBox(height: 8),
              Text(
                // Set the expectation: this is not a chat.
                item.isDirty
                    ? 'Will be sent when you are back online'
                    : 'Waiting for a reply',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ],
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
              Icons.forum_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('Nothing sent yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Tell the gym about equipment, classes or anything else.',
              textAlign: TextAlign.center,
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
