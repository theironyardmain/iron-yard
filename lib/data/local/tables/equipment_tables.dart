import 'package:drift/drift.dart';

import 'profile_tables.dart';
import 'sync_columns.dart';

/// A piece of gym equipment (brain.md §6.10).
///
/// Named `EquipmentItems`, not `Equipment`, purely so Drift's generated row
/// class (stripping the trailing 's') is `EquipmentItem` rather than
/// colliding with this table class's own name.
///
/// [status] is staff-set, not derived: a treadmill can be `working` right up
/// until it breaks, so there is no date-based rule that would predict it.
/// "Due for service" is a *separate*, derived signal from
/// [lastServicedAt]/[serviceIntervalDays], not folded into [status] — a
/// machine can be working fine and still be due for its scheduled service.
class EquipmentItems extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get category => text().nullable()();
  IntColumn get quantity => integer().withDefault(const Constant(1))();
  TextColumn get location => text().nullable()();
  DateTimeColumn get purchaseDate => dateTime().nullable()();

  /// Paise, as an integer — see `MembershipPlans.priceMinor`.
  IntColumn get costMinor => integer().nullable()();

  /// `working` | `under_repair` | `retired`.
  TextColumn get status =>
      text().withDefault(const Constant('working'))();

  /// Days between scheduled services. Null means no schedule is tracked for
  /// this item.
  IntColumn get serviceIntervalDays => integer().nullable()();

  /// Set from the most recent `EquipmentServiceLogs` row; denormalized so the
  /// "due for service" list can filter without a join.
  DateTimeColumn get lastServicedAt => dateTime().nullable()();

  TextColumn get notes => text().nullable()();
}

/// One service/repair event for a piece of equipment (brain.md §6.10).
class EquipmentServiceLogs extends Table with SyncColumns {
  @ReferenceName('serviceLogsAsEquipment')
  TextColumn get equipmentId => text().references(EquipmentItems, #id)();

  DateTimeColumn get servicedAt => dateTime()();
  TextColumn get description => text()();

  /// Paise, nullable — not every service event costs money (e.g. a routine
  /// inspection).
  IntColumn get costMinor => integer().nullable()();

  @ReferenceName('serviceLogsAsPerformer')
  TextColumn get performedBy =>
      text().nullable().references(Profiles, #id)();
}
