import 'package:drift/drift.dart';

import 'profile_tables.dart';
import 'sync_columns.dart';

/// A scheduled class (brain.md §6.8).
class Classes extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get trainerId => text().nullable().references(Trainers, #id)();

  DateTimeColumn get startsAt => dateTime()();
  DateTimeColumn get endsAt => dateTime()();

  /// Maximum bookings. Enforced locally before queuing a booking and again
  /// server-side on upload (brain.md §6.8).
  IntColumn get capacity => integer()();

  TextColumn get location => text().nullable()();

  /// `scheduled` | `cancelled`. Cancellation is one of the only two events
  /// pushed over Realtime (brain.md §4).
  TextColumn get status => text().withDefault(const Constant('scheduled'))();

  BoolColumn get isRecurring => boolean().withDefault(const Constant(false))();
}

/// A member's booking for a class.
///
/// Bookings made offline are queued and may be rejected on upload if the class
/// filled up meanwhile — see [status] and brain.md §10.6.
class ClassBookings extends Table with SyncColumns {
  TextColumn get classId => text().references(Classes, #id)();
  TextColumn get memberId => text().references(Profiles, #id)();

  DateTimeColumn get bookedAt => dateTime().withDefault(currentDateAndTime)();

  /// `booked` | `cancelled` | `rejected`.
  ///
  /// `rejected` is set by the sync engine when the server refuses a queued
  /// booking because the class was already full. The member is told on their
  /// next sync rather than silently losing the booking.
  TextColumn get status => text().withDefault(const Constant('booked'))();

  BoolColumn get attended => boolean().withDefault(const Constant(false))();
}

/// Gym-wide announcements (brain.md §6.9).
class Announcements extends Table with SyncColumns {
  TextColumn get title => text()();
  TextColumn get body => text()();
  TextColumn get authorId => text().nullable().references(Profiles, #id)();

  DateTimeColumn get publishedAt => dateTime().nullable()();
  BoolColumn get isUrgent => boolean().withDefault(const Constant(false))();

  /// Local-only read state. Never uploaded.
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
}

/// Member-submitted feedback or support requests (brain.md §6.2).
class Feedback extends Table with SyncColumns {
  TextColumn get memberId => text().references(Profiles, #id)();
  TextColumn get subject => text().nullable()();
  TextColumn get message => text()();

  /// `open` | `resolved`.
  TextColumn get status => text().withDefault(const Constant('open'))();

  TextColumn get adminResponse => text().nullable()();
  DateTimeColumn get respondedAt => dateTime().nullable()();
}
