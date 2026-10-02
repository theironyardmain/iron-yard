import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../shared/providers/database_provider.dart';
import '../data/membership_repository.dart';

final membershipRepositoryProvider = Provider<MembershipRepository>(
  (ref) => MembershipRepository(ref.watch(databaseProvider)),
);

/// All active plans, updating live — what the assign picker offers.
final activePlansProvider = StreamProvider<List<MembershipPlan>>(
  (ref) => ref.watch(membershipDaoProvider).watchPlans(),
);

/// Every plan including retired ones, for the management screen.
final allPlansProvider = FutureProvider<List<MembershipPlan>>(
  (ref) => ref.watch(membershipDaoProvider).plans(activeOnly: false),
);

/// A member's membership history, newest first.
final membershipHistoryProvider =
    StreamProvider.family<List<Membership>, String>(
      (ref, memberId) =>
          ref.watch(membershipDaoProvider).watchHistoryFor(memberId),
    );

/// Memberships expiring inside the warning window (brain.md §6.3).
final expiringMembershipsProvider = FutureProvider<List<Membership>>(
  (ref) => ref.watch(membershipDaoProvider).expiringWithin(),
);

/// How many memberships reference a plan — shown before retiring it.
final planUsageProvider = FutureProvider.family<int, String>(
  (ref, planId) => ref.watch(membershipDaoProvider).membershipCountFor(planId),
);
