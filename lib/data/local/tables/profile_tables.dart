import 'package:drift/drift.dart';

import 'sync_columns.dart';

/// Every user of the app — admin, trainer, or member (brain.md §2).
///
/// [id] matches the Supabase `auth.users` id for users who can sign in. Members
/// added by staff who have no login yet get a locally generated UUID.
class Profiles extends Table with SyncColumns {
  TextColumn get role => text()();

  TextColumn get fullName => text()();
  TextColumn get email => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get photoUrl => text().nullable()();
  DateTimeColumn get dateOfBirth => dateTime().nullable()();
  TextColumn get gender => text().nullable()();
  TextColumn get address => text().nullable()();

  /// Centimeters. Staff/trainer-entered (brain.md §6.11) — not a
  /// member-facing self-report field in the UI, though RLS does not enforce
  /// that column-level (no column-level RLS exists anywhere in this schema).
  IntColumn get heightCm => integer().nullable()();

  /// Kilograms, one-decimal precision (e.g. 72.5). See brain.md §6.11 for why
  /// metric-only: the app's locale is already en_IN throughout (see
  /// `core/utils/money.dart`), and there is no existing unit-conversion
  /// utility to build a dual-unit display on top of.
  RealColumn get weightKg => real().nullable()();

  /// Staff-only notes about the member. Not visible to the member.
  TextColumn get notes => text().nullable()();

  /// Deactivated members stay in the database for historical reporting; they
  /// simply cannot check in or sign in.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  DateTimeColumn get joinedAt => dateTime().nullable()();
}

/// Emergency contact details.
///
/// Held in its own table because brain.md §6.2 specifies these stay **on the
/// device** and are never synced to Supabase. Keeping them off `Profiles`
/// prevents them being swept up by a future profile sync.
class EmergencyContacts extends Table {
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get name => text()();
  TextColumn get phone => text()();
  TextColumn get relationship => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {profileId};
}

/// Trainer-specific details, extending a profile whose role is `trainer`.
class Trainers extends Table with SyncColumns {
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get specialization => text().nullable()();
  TextColumn get bio => text().nullable()();
  TextColumn get certifications => text().nullable()();
  DateTimeColumn get hiredAt => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

/// A purchasable membership plan (brain.md §6.3).
class MembershipPlans extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  IntColumn get durationDays => integer()();

  /// Stored in the smallest currency unit (paise) as an integer.
  /// Floating-point money accumulates rounding error across revenue reports.
  IntColumn get priceMinor => integer()();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

/// A member's purchase of a plan, with concrete start and expiry dates.
///
/// A member may hold several of these over time; the current one is the row with
/// the latest [endDate].
class Memberships extends Table with SyncColumns {
  TextColumn get memberId => text().references(Profiles, #id)();
  TextColumn get planId => text().references(MembershipPlans, #id)();

  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();

  /// `active` | `expired` | `cancelled`. Derived from dates for display, but
  /// stored so an admin can cancel a membership before its end date.
  TextColumn get status => text().withDefault(const Constant('active'))();

  TextColumn get notes => text().nullable()();
}
