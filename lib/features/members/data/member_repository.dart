import 'package:drift/drift.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/local/daos/membership_dao.dart';
import '../../../data/local/database.dart';
import '../models/member_summary.dart';

/// Reads and writes members, local-first (brain.md §6.3).
///
/// Every query hits Drift only — the screens work offline, and sync fills the
/// cache separately (Phase 10).
class MemberRepository {
  MemberRepository(this._db);

  final AppDatabase _db;

  /// Live list of members with their current membership status.
  ///
  /// Joins in one query rather than per row: a gym with several hundred members
  /// would otherwise issue a membership lookup per list item on every rebuild.
  Stream<List<MemberSummary>> watchMembers() {
    final profiles = _db.profiles;
    final memberships = _db.memberships;

    // Left join so members with no membership still appear.
    final query =
        _db.select(profiles).join([
          leftOuterJoin(
            memberships,
            memberships.memberId.equalsExp(profiles.id) &
                memberships.isDeleted.equals(false),
          ),
        ])..where(
          profiles.role.equals(UserRole.member.wireValue) &
              profiles.isDeleted.equals(false),
        );

    return query.watch().map((rows) {
      // A member may hold several memberships over time; keep the one with the
      // latest end date, matching MembershipDao.currentFor.
      final latest = <String, ({Profile profile, Membership? membership})>{};

      for (final row in rows) {
        final profile = row.readTable(profiles);
        final membership = row.readTableOrNull(memberships);
        final existing = latest[profile.id];

        if (existing == null) {
          latest[profile.id] = (profile: profile, membership: membership);
          continue;
        }

        final currentEnd = existing.membership?.endDate;
        final candidateEnd = membership?.endDate;
        if (candidateEnd != null &&
            (currentEnd == null || candidateEnd.isAfter(currentEnd))) {
          latest[profile.id] = (profile: profile, membership: membership);
        }
      }

      final summaries = [
        for (final entry in latest.values)
          MemberSummary(
            profile: entry.profile,
            membership: entry.membership,
            status: MembershipDao.statusOf(entry.membership),
          ),
      ];

      summaries.sort(
        (a, b) =>
            a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
      );
      return summaries;
    });
  }

  /// Applies the search term and filter in memory.
  ///
  /// The full member list is already in the local cache and a gym's roster is
  /// small, so filtering here avoids rebuilding the stream on every keystroke.
  static List<MemberSummary> applySearch(
    List<MemberSummary> members, {
    String query = '',
    MemberFilter filter = MemberFilter.all,
  }) {
    final term = query.trim().toLowerCase();

    return members.where((member) {
      if (!filter.matches(member)) return false;
      if (term.isEmpty) return true;

      return member.fullName.toLowerCase().contains(term) ||
          (member.phone?.toLowerCase().contains(term) ?? false) ||
          (member.email?.toLowerCase().contains(term) ?? false);
    }).toList();
  }

  /// One member with their current membership, for the detail screen.
  Future<MemberSummary?> summaryFor(String memberId) async {
    final profile = await _db.profileDao.byId(memberId);
    if (profile == null || profile.isDeleted) return null;

    final membership = await _db.membershipDao.currentFor(memberId);
    return MemberSummary(
      profile: profile,
      membership: membership,
      status: MembershipDao.statusOf(membership),
    );
  }

  Future<String> create({
    required String fullName,
    String? email,
    String? phone,
    DateTime? dateOfBirth,
    String? gender,
    String? address,
    int? heightCm,
    double? weightKg,
    String? notes,
  }) {
    return _db.profileDao.createMember(
      fullName: fullName,
      email: email,
      phone: phone,
      dateOfBirth: dateOfBirth,
      gender: gender,
      address: address,
      heightCm: heightCm,
      weightKg: weightKg,
      notes: notes,
    );
  }

  Future<void> update({
    required String id,
    required String fullName,
    String? email,
    String? phone,
    DateTime? dateOfBirth,
    String? gender,
    String? address,
    int? heightCm,
    double? weightKg,
    String? notes,
  }) {
    return _db.profileDao.updateProfile(
      id,
      ProfilesCompanion(
        fullName: Value(fullName),
        email: Value(email),
        phone: Value(phone),
        dateOfBirth: Value(dateOfBirth),
        gender: Value(gender),
        address: Value(address),
        heightCm: Value(heightCm),
        weightKg: Value(weightKg),
        notes: Value(notes),
      ),
    );
  }

  /// Deactivates or reactivates a member.
  ///
  /// Never deletes: history (attendance, payments) must survive, and a
  /// deactivated member can be restored (brain.md §6.3).
  Future<void> setActive(String id, {required bool isActive}) =>
      _db.profileDao.setActive(id, isActive: isActive);

  // --- Emergency contact (device-only, brain.md §6.2) ---

  Future<EmergencyContact?> emergencyContactFor(String memberId) =>
      _db.profileDao.emergencyContactFor(memberId);

  Future<void> setEmergencyContact({
    required String memberId,
    required String name,
    required String phone,
    String? relationship,
  }) {
    return _db.profileDao.setEmergencyContact(
      profileId: memberId,
      name: name,
      phone: phone,
      relationship: relationship,
    );
  }
}
