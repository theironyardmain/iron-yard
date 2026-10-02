import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/local/database.dart';
import '../../../shared/providers/database_provider.dart';
import '../../announcements/providers/announcement_providers.dart';

/// Admin inbox for member feedback (brain.md §6.2).
class FeedbackInboxScreen extends ConsumerStatefulWidget {
  const FeedbackInboxScreen({super.key});

  @override
  ConsumerState<FeedbackInboxScreen> createState() =>
      _FeedbackInboxScreenState();
}

class _FeedbackInboxScreenState extends ConsumerState<FeedbackInboxScreen> {
  bool _openOnly = true;

  @override
  Widget build(BuildContext context) {
    final feedback = ref.watch(allFeedbackProvider(_openOnly));

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Open'),
                  selected: _openOnly,
                  onSelected: (_) => setState(() => _openOnly = true),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('All'),
                  selected: !_openOnly,
                  onSelected: (_) => setState(() => _openOnly = false),
                ),
              ],
            ),
          ),
          Expanded(
            child: feedback.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Could not load: $error')),
              data: (list) => list.isEmpty
                  ? _Empty(openOnly: _openOnly)
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: list.length,
                      itemBuilder: (context, index) =>
                          _InboxCard(item: list[index]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxCard extends ConsumerWidget {
  const _InboxCard({required this.item});

  final FeedbackData item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isResolved = item.status == 'resolved';
    final member = ref.watch(_memberNameProvider(item.memberId));

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: isResolved
                      ? theme.colorScheme.surfaceContainerHighest
                      : theme.colorScheme.tertiaryContainer,
                  child: Icon(
                    isResolved ? Icons.check : Icons.mark_email_unread_outlined,
                    size: 16,
                    color: isResolved
                        ? theme.colorScheme.outline
                        : theme.colorScheme.onTertiaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.valueOrNull ?? '…',
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        item.subject?.isNotEmpty == true
                            ? item.subject!
                            : 'No subject',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
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
            const SizedBox(height: 12),
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
                    Text(
                      'Your reply',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(item.adminResponse!),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: () => _showReplySheet(context, ref),
                  child: const Text('Reply'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showReplySheet(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();

    final reply = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Reply',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Your reply',
                  alignLabelWithHint: true,
                ),
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
                autofocus: true,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  final text = controller.text.trim();
                  if (text.isEmpty) return;
                  Navigator.of(context).pop(text);
                },
                child: const Text('Send reply'),
              ),
            ],
          ),
        ),
      ),
    );

    controller.dispose();

    if (reply == null || reply.isEmpty) return;

    // Replying resolves the item: an answered question is handled, and the
    // member can raise a new message if they need more.
    await ref.read(announcementDaoProvider).respondToFeedback(
      id: item.id,
      response: reply,
    );
  }
}

final _memberNameProvider = FutureProvider.family<String?, String>((
  ref,
  memberId,
) async {
  final profile = await ref.watch(profileDaoProvider).byId(memberId);
  return profile?.fullName;
});

class _Empty extends StatelessWidget {
  const _Empty({required this.openOnly});

  final bool openOnly;

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
              openOnly ? Icons.done_all : Icons.forum_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              openOnly ? 'Nothing to answer' : 'No messages yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              openOnly
                  ? 'Member messages needing a reply appear here.'
                  : 'Members can message you from their app.',
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
