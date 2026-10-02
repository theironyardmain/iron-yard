import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/member_summary.dart';
import '../providers/member_providers.dart';
import '../widgets/member_status_chip.dart';
import 'member_detail_screen.dart';
import 'member_form_screen.dart';

/// Searchable, filterable member list (brain.md §6.3).
///
/// Reads entirely from the local cache, so it works offline.
class MemberListScreen extends ConsumerStatefulWidget {
  const MemberListScreen({super.key});

  @override
  ConsumerState<MemberListScreen> createState() => _MemberListScreenState();
}

class _MemberListScreenState extends ConsumerState<MemberListScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = ref.watch(filteredMembersProvider);
    final counts = ref.watch(memberFilterCountsProvider);
    final activeFilter = ref.watch(memberFilterProvider);

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search name, phone or email',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          ref.read(memberSearchProvider.notifier).state = '';
                        },
                      ),
                isDense: true,
              ),
              onChanged: (value) =>
                  ref.read(memberSearchProvider.notifier).state = value,
            ),
          ),

          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: MemberFilter.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final filter = MemberFilter.values[index];
                final count = counts[filter] ?? 0;

                return FilterChip(
                  label: Text('${filter.label} ($count)'),
                  selected: activeFilter == filter,
                  onSelected: (_) =>
                      ref.read(memberFilterProvider.notifier).state = filter,
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: filtered.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ErrorState(error: error),
              data: (members) => members.isEmpty
                  ? _EmptyState(
                      hasQuery: _searchController.text.isNotEmpty,
                      filter: activeFilter,
                    )
                  : ListView.builder(
                      itemCount: members.length,
                      itemBuilder: (context, index) =>
                          _MemberTile(member: members[index]),
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const MemberFormScreen(),
          ),
        ),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add member'),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member});

  final MemberSummary member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: CircleAvatar(
        child: Text(_initials(member.fullName)),
      ),
      title: Text(
        member.fullName,
        style: member.isActive
            ? null
            : TextStyle(color: theme.colorScheme.outline),
      ),
      subtitle: Text(
        member.phone?.isNotEmpty == true
            ? member.phone!
            : (member.email ?? 'No contact details'),
      ),
      trailing: MemberStatusChip(
        status: member.status,
        daysRemaining: member.daysRemaining,
        isDeactivated: !member.isActive,
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MemberDetailScreen(memberId: member.id),
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasQuery, required this.filter});

  final bool hasQuery;
  final MemberFilter filter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (icon, title, subtitle) = hasQuery
        ? (
            Icons.search_off,
            'No matches',
            'Try a different name, phone or email.',
          )
        : switch (filter) {
            MemberFilter.all => (
              Icons.people_outline,
              'No members yet',
              'Add your first member with the button below.',
            ),
            MemberFilter.inactive => (
              Icons.person_off_outlined,
              'No deactivated members',
              'Deactivated members appear here.',
            ),
            _ => (
              Icons.filter_alt_off_outlined,
              'No ${filter.label.toLowerCase()} members',
              'Try another filter.',
            ),
          };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              subtitle,
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});

  final Object error;

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
              Icons.error_outline,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text('Could not load members', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
