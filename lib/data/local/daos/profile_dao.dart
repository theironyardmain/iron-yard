import 'package:drift/drift.dart';

import '../../../core/constants/app_constants.dart';
import '../database.dart';
import '../tables/profile_tables.dart';
import 'synced_dao.dart';

part 'profile_dao.g.dart';

@DriftAccessor(tables: [Profiles, EmergencyContacts, Trainers])
class ProfileDao extends DatabaseAccessor<AppDatabase>
    with _$ProfileDaoMixin, SyncedDaoMixin<AppDatabase, $ProfilesTable, Profile> {
  ProfileDao(super.db);

  @override
  $ProfilesTable get table => profiles;

  Future<Profile?> byId(String id) {
    return (select(profiles)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// All members, newest first. Excludes soft-deleted rows.
  ///
  /// [activeOnly] hides deactivated members; they remain in the database for
  /// historical reporting.
  Future<List<Profile>> members({bool activeOnly = true}) {
    return (select(profiles)
          ..where(
            (t) =>
                t.role.equals(UserRole.member.wireValue) &
                t.isDeleted.equals(false) &
                (activeOnly ? t.isActive.equals(true) : const Constant(true)),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.fullName)]))
        .get();
  }

  Stream<List<Profile>> watchMembers({bool activeOnly = true}) {
    return (select(profiles)
          ..where(
            (t) =>
                t.role.equals(UserRole.member.wireValue) &
                t.isDeleted.equals(false) &
                (activeOnly ? t.isActive.equals(true) : const Constant(true)),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.fullName)]))
        .watch();
  }

  /// Name/phone/email search for the member list (brain.md §6.3).
  Future<List<Profile>> searchMembers(String query) {
    final term = '%${query.trim()}%';
    return (select(profiles)
          ..where(
            (t) =>
                t.role.equals(UserRole.member.wireValue) &
                t.isDeleted.equals(false) &
                (t.fullName.like(term) |
                    t.phone.like(term) |
                    t.email.like(term)),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.fullName)]))
        .get();
  }

  Future<List<Profile>> byRole(UserRole role) {
    return (select(profiles)
          ..where(
            (t) => t.role.equals(role.wireValue) & t.isDeleted.equals(false),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.fullName)]))
        .get();
  }

  /// Creates a profile and returns its generated id.
  Future<String> createMember({
    required String fullName,
    String? email,
    String? phone,
    UserRole role = UserRole.member,
    DateTime? dateOfBirth,
    String? gender,
    String? address,
    int? heightCm,
    double? weightKg,
    String? notes,
  }) async {
    final id = Uuid.v4();
    await into(profiles).insert(
      ProfilesCompanion.insert(
        id: id,
        role: role.wireValue,
        fullName: fullName,
        email: Value(email),
        phone: Value(phone),
        dateOfBirth: Value(dateOfBirth),
        gender: Value(gender),
        address: Value(address),
        heightCm: Value(heightCm),
        weightKg: Value(weightKg),
        notes: Value(notes),
        joinedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
    return id;
  }

  Future<void> updateProfile(String id, ProfilesCompanion changes) async {
    await (update(profiles)..where((t) => t.id.equals(id))).write(
      changes.copyWith(
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }

  /// Deactivates rather than deletes, so history is preserved (brain.md §6.3).
  Future<void> setActive(String id, {required bool isActive}) async {
    await (update(profiles)..where((t) => t.id.equals(id))).write(
      ProfilesCompanion(
        isActive: Value(isActive),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }

  // --- Trainers (brain.md §6.3) ---

  /// Trainers with their profile, for the member-facing list and admin
  /// management.
  ///
  /// A trainer is a profile with `role = 'trainer'` plus a `trainers` row
  /// holding the gym-specific detail.
  Stream<List<({Profile profile, Trainer trainer})>> watchTrainers({
    bool activeOnly = true,
  }) {
    final query =
        select(trainers).join([
          innerJoin(profiles, profiles.id.equalsExp(trainers.profileId)),
        ])..where(
          trainers.isDeleted.equals(false) &
              profiles.isDeleted.equals(false) &
              (activeOnly ? trainers.isActive.equals(true) : const Constant(true)),
        );

    return query.watch().map(
      (rows) => [
        for (final row in rows)
          (profile: row.readTable(profiles), trainer: row.readTable(trainers)),
      ]..sort((a, b) => a.profile.fullName.compareTo(b.profile.fullName)),
    );
  }

  Future<({Profile profile, Trainer trainer})?> trainerById(String id) async {
    final row =
        await (select(trainers).join([
              innerJoin(profiles, profiles.id.equalsExp(trainers.profileId)),
            ])..where(trainers.id.equals(id)))
            .getSingleOrNull();

    if (row == null) return null;
    return (profile: row.readTable(profiles), trainer: row.readTable(trainers));
  }

  /// Creates a trainer: the profile and its trainer record together.
  ///
  /// Both in one transaction — a trainer row without its profile would be
  /// invisible everywhere, and a profile without the trainer row would have no
  /// specialisation or bio.
  Future<String> createTrainer({
    required String fullName,
    String? email,
    String? phone,
    String? specialization,
    String? bio,
    String? certifications,
  }) async {
    return transaction(() async {
      final profileId = Uuid.v4();
      final trainerId = Uuid.v4();
      final now = DateTime.now();

      await into(profiles).insert(
        ProfilesCompanion.insert(
          id: profileId,
          role: UserRole.trainer.wireValue,
          fullName: fullName,
          email: Value(email),
          phone: Value(phone),
          joinedAt: Value(now),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      );

      await into(trainers).insert(
        TrainersCompanion.insert(
          id: trainerId,
          profileId: profileId,
          specialization: Value(specialization),
          bio: Value(bio),
          certifications: Value(certifications),
          hiredAt: Value(now),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      );

      return trainerId;
    });
  }

  Future<void> updateTrainer({
    required String trainerId,
    required String profileId,
    required String fullName,
    String? email,
    String? phone,
    String? specialization,
    String? bio,
    String? certifications,
  }) async {
    await transaction(() async {
      final now = DateTime.now();

      await (update(profiles)..where((t) => t.id.equals(profileId))).write(
        ProfilesCompanion(
          fullName: Value(fullName),
          email: Value(email),
          phone: Value(phone),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      );

      await (update(trainers)..where((t) => t.id.equals(trainerId))).write(
        TrainersCompanion(
          specialization: Value(specialization),
          bio: Value(bio),
          certifications: Value(certifications),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      );
    });
  }

  /// Retires or reinstates a trainer.
  ///
  /// Never deletes: classes they taught keep referencing them, and past
  /// records should stay attributable.
  Future<void> setTrainerActive(
    String trainerId, {
    required bool isActive,
  }) async {
    await (update(trainers)..where((t) => t.id.equals(trainerId))).write(
      TrainersCompanion(
        isActive: Value(isActive),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }

  // --- Emergency contacts (device-only, never synced — brain.md §6.2) ---

  Future<EmergencyContact?> emergencyContactFor(String profileId) {
    return (select(emergencyContacts)
          ..where((t) => t.profileId.equals(profileId)))
        .getSingleOrNull();
  }

  Future<void> setEmergencyContact({
    required String profileId,
    required String name,
    required String phone,
    String? relationship,
  }) async {
    await into(emergencyContacts).insertOnConflictUpdate(
      EmergencyContactsCompanion.insert(
        profileId: profileId,
        name: name,
        phone: phone,
        relationship: Value(relationship),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
