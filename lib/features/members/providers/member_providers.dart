import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../shared/providers/database_provider.dart';
import '../data/member_repository.dart';
import '../models/member_summary.dart';

final memberRepositoryProvider = Provider<MemberRepository>(
  (ref) => MemberRepository(ref.watch(databaseProvider)),
);

/// Every member with their current membership status, updating live.
final membersProvider = StreamProvider<List<MemberSummary>>(
  (ref) => ref.watch(memberRepositoryProvider).watchMembers(),
);

/// The member list's search term.
final memberSearchProvider = StateProvider<String>((ref) => '');

/// The member list's active filter.
final memberFilterProvider = StateProvider<MemberFilter>(
  (ref) => MemberFilter.all,
);

/// Members after search and filter — what the list renders.
final filteredMembersProvider = Provider<AsyncValue<List<MemberSummary>>>((
  ref,
) {
  final members = ref.watch(membersProvider);
  final query = ref.watch(memberSearchProvider);
  final filter = ref.watch(memberFilterProvider);

  return members.whenData(
    (list) => MemberRepository.applySearch(
      list,
      query: query,
      filter: filter,
    ),
  );
});

/// Counts per filter, for the filter chips.
final memberFilterCountsProvider = Provider<Map<MemberFilter, int>>((ref) {
  final members = ref.watch(membersProvider).valueOrNull ?? const [];
  return {
    for (final filter in MemberFilter.values)
      filter: members.where(filter.matches).length,
  };
});

/// One member, for the detail screen.
final memberSummaryProvider = FutureProvider.family<MemberSummary?, String>(
  (ref, id) {
    // Rebuild when the underlying list changes, so an edit is reflected here.
    ref.watch(membersProvider);
    return ref.watch(memberRepositoryProvider).summaryFor(id);
  },
);

/// The member's emergency contact. Device-only — never synced (brain.md §6.2).
final emergencyContactProvider =
    FutureProvider.family<EmergencyContact?, String>(
      (ref, memberId) =>
          ref.watch(memberRepositoryProvider).emergencyContactFor(memberId),
    );
