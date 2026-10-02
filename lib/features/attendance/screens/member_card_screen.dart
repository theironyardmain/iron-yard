import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/daos/membership_dao.dart';
import '../../auth/providers/auth_providers.dart';
import '../../checkin/widgets/check_in_card.dart';
import '../../feedback/screens/my_feedback_screen.dart';
import '../../trainers/screens/trainer_list_screen.dart';
import '../../members/providers/member_providers.dart';
import '../providers/attendance_providers.dart';
import '../widgets/member_qr_card.dart';

/// The member's own membership card (brain.md §6.2).
///
/// Renders from cached data so it works with no connection.
class MemberCardScreen extends ConsumerWidget {
  const MemberCardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    if (session == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final card = ref.watch(memberCardProvider(session.userId));
    final summary = ref.watch(memberSummaryProvider(session.userId));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            children: [
              const CheckInCard(),
              const SizedBox(height: 16),
              card.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(48),
              child: CircularProgressIndicator(),
            ),
            error: (error, _) => _CardUnavailable(detail: '$error'),
            data: (payload) {
              if (payload == null) {
                return const _CardUnavailable(
                  detail: 'Your profile has not synced to this device yet.',
                );
              }

              final member = summary.valueOrNull;
              return MemberQrCard(
                payload: payload,
                status: member?.status ?? MembershipStatus.none,
                expiresOn: member?.expiresOn,
              );
            },
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.sports_outlined),
                      title: const Text('Trainers'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              const TrainerListScreen(isAdmin: false),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.forum_outlined),
                      title: const Text('Feedback & support'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const MyFeedbackScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardUnavailable extends StatelessWidget {
  const _CardUnavailable({required this.detail});

  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(
            Icons.badge_outlined,
            size: 48,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text('Card unavailable', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
