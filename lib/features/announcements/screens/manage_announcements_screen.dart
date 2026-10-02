import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/local/database.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/announcement_providers.dart';

/// Admin view: compose, publish and manage announcements (brain.md §6.3).
class ManageAnnouncementsScreen extends ConsumerWidget {
  const ManageAnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final announcements = ref.watch(allAnnouncementsProvider);

    return Scaffold(
      body: announcements.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load: $error')),
        data: (list) => list.isEmpty
            ? const _Empty()
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                itemCount: list.length,
                itemBuilder: (context, index) =>
                    _ManageTile(announcement: list[index]),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ComposeScreen()),
        ),
        icon: const Icon(Icons.campaign),
        label: const Text('New announcement'),
      ),
    );
  }
}

class _ManageTile extends ConsumerWidget {
  const _ManageTile({required this.announcement});

  final Announcement announcement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDraft = announcement.publishedAt == null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: announcement.isUrgent
              ? theme.colorScheme.errorContainer
              : theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            announcement.isUrgent ? Icons.priority_high : Icons.campaign,
            size: 20,
            color: announcement.isUrgent
                ? theme.colorScheme.onErrorContainer
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        title: Text(announcement.title),
        subtitle: Text(
          isDraft
              ? 'Draft — not visible to members'
              : DateFormat.yMMMd().add_jm().format(announcement.publishedAt!),
          style: isDraft
              ? TextStyle(color: theme.colorScheme.tertiary)
              : null,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            final dao = ref.read(announcementDaoProvider);
            switch (value) {
              case 'edit':
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ComposeScreen(announcement: announcement),
                  ),
                );
              case 'publish':
                await dao.publish(announcement.id);
              case 'delete':
                await _confirmDelete(context, ref);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            if (isDraft)
              const PopupMenuItem(value: 'publish', child: Text('Publish')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete announcement?'),
        content: Text(
          announcement.publishedAt == null
              ? 'This draft will be removed.'
              // Members who already saw it keep it until their next sync, so
              // say so rather than implying an instant recall.
              : 'It will disappear from members\' feeds on their next sync.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(announcementDaoProvider).remove(announcement.id);
  }
}

/// Composes a new announcement or edits an existing one.
class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({this.announcement, super.key});

  final Announcement? announcement;

  bool get isEditing => announcement != null;

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;

  late bool _isUrgent;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.announcement?.title ?? '',
    );
    _bodyController = TextEditingController(
      text: widget.announcement?.body ?? '',
    );
    _isUrgent = widget.announcement?.isUrgent ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _save({required bool publish}) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final dao = ref.read(announcementDaoProvider);
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    if (widget.isEditing) {
      await dao.edit(
        id: widget.announcement!.id,
        title: title,
        body: body,
        isUrgent: _isUrgent,
      );
      if (publish) await dao.publish(widget.announcement!.id);
    } else {
      final session = ref.read(currentSessionProvider);
      await dao.create(
        title: title,
        body: body,
        authorId: session?.userId,
        isUrgent: _isUrgent,
        publish: publish,
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(publish ? 'Announcement published' : 'Draft saved'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alreadyPublished = widget.announcement?.publishedAt != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit announcement' : 'New announcement'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title *',
                      prefixIcon: Icon(Icons.title),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    autofocus: !widget.isEditing,
                    enabled: !_saving,
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? 'Enter a title'
                        : null,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _bodyController,
                    decoration: const InputDecoration(
                      labelText: 'Message *',
                      alignLabelWithHint: true,
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 8,
                    enabled: !_saving,
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? 'Enter a message'
                        : null,
                  ),
                  const SizedBox(height: 8),

                  SwitchListTile(
                    value: _isUrgent,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _isUrgent = value),
                    title: const Text('Mark urgent'),
                    subtitle: const Text(
                      'Highlighted, and notified with high priority',
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),

                  const SizedBox(height: 16),
                  Card(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 20,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              // Set the expectation honestly: members offline
                              // right now receive it when they reconnect.
                              'Members online receive this immediately. '
                              'Everyone else sees it on their next sync.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : () => _save(publish: true),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            alreadyPublished ? 'Save changes' : 'Publish now',
                          ),
                  ),
                  if (!alreadyPublished) ...[
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _saving ? null : () => _save(publish: false),
                      child: const Text('Save as draft'),
                    ),
                  ],
                ],
              ),
            ),
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
            Text('No announcements yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Post gym news, closures or schedule changes.',
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
