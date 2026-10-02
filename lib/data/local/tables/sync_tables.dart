import 'package:drift/drift.dart';

/// Pending local writes awaiting upload (brain.md §4).
///
/// Device-only — deliberately not mirrored as a Supabase table (brain.md §5).
/// The sync engine drains this in a single batched request rather than one row
/// at a time.
class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Drift table name the change applies to, e.g. `attendance`.
  TextColumn get entityTable => text()();

  /// UUID of the affected row.
  TextColumn get entityId => text()();

  /// `insert` | `update` | `delete`.
  TextColumn get operation => text()();

  /// Row payload as JSON at the time of queuing.
  TextColumn get payloadJson => text().nullable()();

  DateTimeColumn get queuedAt => dateTime().withDefault(currentDateAndTime)();

  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();

  /// Set when the server rejected this change — a duplicate check-in, or a
  /// class that filled up. Surfaced to the user rather than retried forever.
  TextColumn get lastError => text().nullable()();

  /// Rejected entries are kept, not dropped, so the UI can explain what
  /// happened on the next sync.
  BoolColumn get isRejected => boolean().withDefault(const Constant(false))();
}

/// Per-table high-water mark for incremental pulls (brain.md §4).
///
/// Sync pulls `where updated_at > lastSyncedAt` for each table independently, so
/// a failure syncing one table does not stall the others.
class SyncState extends Table {
  TextColumn get entityTable => text()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {entityTable};
}
