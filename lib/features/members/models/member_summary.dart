import '../../../data/local/daos/membership_dao.dart';
import '../../../data/local/database.dart';

/// A member row as the list and detail screens need it (brain.md §6.3).
///
/// Carries the derived membership state alongside the profile so the list can
/// render a status chip without a per-row query.
class MemberSummary {
  const MemberSummary({
    required this.profile,
    required this.membership,
    required this.status,
  });

  final Profile profile;

  /// The member's current membership, or null if they have never had one.
  final Membership? membership;

  final MembershipStatus status;

  String get id => profile.id;
  String get fullName => profile.fullName;
  String? get phone => profile.phone;
  String? get email => profile.email;
  bool get isActive => profile.isActive;

  DateTime? get expiresOn => membership?.endDate;

  /// Days until expiry; negative once expired. Null without a membership.
  int? get daysRemaining {
    final end = membership?.endDate;
    if (end == null) return null;
    final today = DateTime.now();
    return DateTime(end.year, end.month, end.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
  }
}

/// Which members the list should show (brain.md §6.3).
enum MemberFilter {
  all,
  active,
  expiringSoon,
  expired,
  noMembership,
  inactive;

  String get label => switch (this) {
    MemberFilter.all => 'All',
    MemberFilter.active => 'Active',
    MemberFilter.expiringSoon => 'Expiring soon',
    MemberFilter.expired => 'Expired',
    MemberFilter.noMembership => 'No plan',
    MemberFilter.inactive => 'Deactivated',
  };

  /// Whether [summary] belongs in this filter.
  bool matches(MemberSummary summary) => switch (this) {
    // "All" still hides deactivated members; they have their own filter so a
    // deactivated member cannot be mistaken for a current one.
    MemberFilter.all => summary.isActive,
    MemberFilter.active =>
      summary.isActive && summary.status == MembershipStatus.active,
    MemberFilter.expiringSoon =>
      summary.isActive && summary.status == MembershipStatus.expiringSoon,
    MemberFilter.expired =>
      summary.isActive && summary.status == MembershipStatus.expired,
    MemberFilter.noMembership =>
      summary.isActive && summary.status == MembershipStatus.none,
    MemberFilter.inactive => !summary.isActive,
  };
}
