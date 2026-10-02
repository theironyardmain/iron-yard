import 'package:drift/drift.dart';

import '../local/database.dart';

/// Translates rows between Drift and Supabase (brain.md §4).
///
/// Sync maps field for field, so anything wrong here loses data silently rather
/// than raising. Two rules hold throughout:
///
///  * **Local-only columns never go up.** `is_dirty` is upload bookkeeping and
///    `announcements.is_read` is per-device state; sending either would corrupt
///    other devices. `payments.receipt_local_path` is a path on this phone and
///    is meaningless anywhere else.
///  * **Local-only columns never get clobbered coming down.** A pulled row must
///    not reset a read flag or a pending receipt the device still holds.
class RowMapper {
  const RowMapper._();

  /// Columns that exist locally but must never be uploaded.
  static const Set<String> localOnlyColumns = {
    'is_dirty',
    'is_read',
    'receipt_local_path',
  };

  /// Strips local-only keys from a row before upload.
  static Map<String, dynamic> forUpload(Map<String, dynamic> row) {
    return {
      for (final entry in row.entries)
        if (!localOnlyColumns.contains(entry.key))
          entry.key: _encodeValue(entry.value),
    };
  }

  /// Postgres wants ISO-8601 for timestamps; Drift hands back [DateTime].
  static Object? _encodeValue(Object? value) {
    if (value is DateTime) return value.toUtc().toIso8601String();
    return value;
  }

  /// Converts a Supabase row into values Drift can insert.
  ///
  /// Unknown keys are dropped rather than throwing: a server running a newer
  /// schema must not break an older client's sync.
  static Map<String, dynamic> fromRemote(
    Map<String, dynamic> row,
    Set<String> knownColumns,
  ) {
    return {
      for (final entry in row.entries)
        if (knownColumns.contains(entry.key) &&
            !localOnlyColumns.contains(entry.key))
          entry.key: entry.value,
    };
  }

  /// Date-only columns, which Postgres returns as `YYYY-MM-DD`.
  ///
  /// Parsing these as full timestamps would shift them by the device's UTC
  /// offset and move a check-in to the wrong day.
  static const Set<String> dateOnlyColumns = {
    'attendance_date',
    'completed_on',
  };

  /// Parses a value from Supabase into the type Drift expects.
  static Object? decodeValue({
    required String column,
    required Object? value,
    required SyncColumnType type,
  }) {
    if (value == null) return null;

    return switch (type) {
      SyncColumnType.dateTime => _decodeDateTime(column, value),
      SyncColumnType.boolean =>
        value is bool ? value : value == 1 || value == 'true',
      SyncColumnType.integer => value is int ? value : int.tryParse('$value'),
      SyncColumnType.real =>
        value is double ? value : double.tryParse('$value'),
      SyncColumnType.other => value,
    };
  }

  static DateTime? _decodeDateTime(String column, Object value) {
    if (value is DateTime) return value;
    if (value is! String) return null;

    if (dateOnlyColumns.contains(column)) {
      // Parse as a local calendar date, with no timezone conversion.
      final parts = value.split('-');
      if (parts.length < 3) return DateTime.tryParse(value);

      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final day = int.tryParse(parts[2].substring(0, 2));
      if (year == null || month == null || day == null) return null;

      return DateTime(year, month, day);
    }

    return DateTime.tryParse(value)?.toLocal();
  }
}

/// The column kinds sync needs to distinguish when decoding.
enum SyncColumnType {
  dateTime,
  boolean,
  integer,
  real,
  other;

  static SyncColumnType of(Object type) {
    if (type == DriftSqlType.dateTime) return SyncColumnType.dateTime;
    if (type == DriftSqlType.bool) return SyncColumnType.boolean;
    if (type == DriftSqlType.int) return SyncColumnType.integer;
    if (type == DriftSqlType.double) return SyncColumnType.real;
    return SyncColumnType.other;
  }
}

/// Describes one syncable table so the engine can work generically.
class SyncTable {
  const SyncTable({
    required this.name,
    required this.table,
  });

  /// Postgres and Drift table name — they are identical by design.
  final String name;

  final TableInfo<Table, dynamic> table;

  Set<String> get columnNames =>
      table.$columns.map((c) => c.name).toSet();

  /// Column types, for decoding pulled values.
  ///
  /// Drift hides `BaseSqlType` from its public API, so the type is captured as
  /// a [SyncColumnType] the mapper can switch on.
  Map<String, SyncColumnType> get columnTypes => {
    for (final column in table.$columns)
      column.name: SyncColumnType.of(column.type),
  };
}

/// Every table that participates in sync, in dependency order.
///
/// Order matters on upload: a payment referencing a membership must not reach
/// the server before that membership, or the foreign key rejects it.
List<SyncTable> syncTablesFor(AppDatabase db) => [
  SyncTable(name: 'profiles', table: db.profiles),
  SyncTable(name: 'trainers', table: db.trainers),
  SyncTable(name: 'membership_plans', table: db.membershipPlans),
  SyncTable(name: 'memberships', table: db.memberships),
  SyncTable(name: 'attendance', table: db.attendance),
  SyncTable(name: 'invoices', table: db.invoices),
  SyncTable(name: 'payments', table: db.payments),
  SyncTable(name: 'workout_plans', table: db.workoutPlans),
  SyncTable(name: 'workout_exercises', table: db.workoutExercises),
  SyncTable(name: 'exercise_completions', table: db.exerciseCompletions),
  SyncTable(name: 'diet_plans', table: db.dietPlans),
  SyncTable(name: 'diet_meals', table: db.dietMeals),
  SyncTable(name: 'diet_food_items', table: db.dietFoodItems),
  SyncTable(name: 'classes', table: db.classes),
  SyncTable(name: 'class_bookings', table: db.classBookings),
  SyncTable(name: 'announcements', table: db.announcements),
  SyncTable(name: 'feedback', table: db.feedback),
  SyncTable(name: 'equipment_items', table: db.equipmentItems),
  SyncTable(
    name: 'equipment_service_logs',
    table: db.equipmentServiceLogs,
  ),
];
