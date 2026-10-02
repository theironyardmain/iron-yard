import 'package:drift/drift.dart';

/// Columns every synced table carries (brain.md §4).
///
/// Sync pulls `where updated_at > last_sync_time`, so [updatedAt] must be set on
/// every local write — see `SyncedDao.touch`.
///
/// [id] is a UUID string generated on-device rather than a server autoincrement,
/// so rows created offline keep a stable identity from the moment they exist and
/// never need a local-to-server id remap on upload.
mixin SyncColumns on Table {
  TextColumn get id => text()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// Soft delete. Rows are never hard-deleted locally: a peer device must be
  /// able to learn about the deletion on its next pull.
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  /// True when the row has local changes not yet accepted by the server.
  ///
  /// Local-only; never uploaded. Cleared once the server confirms the write.
  BoolColumn get isDirty => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
