import 'dart:math';

import 'package:drift/drift.dart';

/// Generates the UUIDs used as primary keys on every synced table.
///
/// v4 from `Random.secure()`. Ids are generated on-device so a row created
/// offline has a stable identity immediately and never needs remapping on
/// upload.
class Uuid {
  const Uuid._();

  static final Random _rng = Random.secure();

  static String v4() {
    final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));

    // Set version (4) and variant (RFC 4122) bits.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    String hex(int start, int end) => bytes
        .sublist(start, end)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }
}

/// Date helpers for the date-only columns.
///
/// Attendance and exercise completions key on a *day*, not an instant. Storing
/// a normalised local midnight makes "one per day" a plain equality check.
class DayKey {
  const DayKey._();

  /// Local midnight for [instant] (defaults to now).
  static DateTime of([DateTime? instant]) {
    final d = instant ?? DateTime.now();
    return DateTime(d.year, d.month, d.day);
  }

  /// Local midnight tomorrow — the exclusive upper bound for a day range.
  static DateTime nextDay([DateTime? instant]) {
    final d = of(instant);
    return DateTime(d.year, d.month, d.day + 1);
  }
}

/// Shared behaviour for DAOs over tables carrying `SyncColumns`.
///
/// The sync engine pulls `where updated_at > last_sync_time` and uploads rows
/// flagged `is_dirty`, so both must be set on every local write. Centralising
/// that here keeps a feature DAO from forgetting one and silently dropping a
/// change (brain.md §4).
mixin SyncedDaoMixin<DB extends GeneratedDatabase, T extends Table, D>
    on DatabaseAccessor<DB> {
  TableInfo<T, D> get table;

  /// Marks a row dirty and bumps `updated_at` so the next sync picks it up.
  ///
  /// Called by the concrete DAO after any local mutation it performs through a
  /// path that does not already set these columns.
  Future<void> markDirty(String id) async {
    await (update(table)..where((t) => (t as dynamic).id.equals(id))).write(
      RawValuesInsertable({
        'updated_at': Variable(DateTime.now()),
        'is_dirty': const Variable(true),
      }),
    );
  }

  /// Soft-deletes a row. Rows are never hard-deleted locally: a peer device
  /// must be able to learn about the deletion on its next pull.
  Future<void> softDelete(String id) async {
    await (update(table)..where((t) => (t as dynamic).id.equals(id))).write(
      RawValuesInsertable({
        'is_deleted': const Variable(true),
        'updated_at': Variable(DateTime.now()),
        'is_dirty': const Variable(true),
      }),
    );
  }

  /// Rows with local changes the server has not yet accepted.
  Future<List<D>> pendingUpload() {
    return (select(table)
          ..where((t) => (t as dynamic).isDirty.equals(true)))
        .get();
  }

  /// Clears the dirty flag once the server has accepted these rows.
  Future<void> clearDirty(Iterable<String> ids) async {
    if (ids.isEmpty) return;
    await (update(table)..where((t) => (t as dynamic).id.isIn(ids))).write(
      RawValuesInsertable({'is_dirty': const Variable(false)}),
    );
  }
}
