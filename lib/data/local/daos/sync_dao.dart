import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/sync_tables.dart';

part 'sync_dao.g.dart';

/// Access to the two device-only sync bookkeeping tables (brain.md §4).
@DriftAccessor(tables: [SyncQueue, SyncState])
class SyncDao extends DatabaseAccessor<AppDatabase> with _$SyncDaoMixin {
  SyncDao(super.db);

  // --- Queue ---

  Future<void> enqueue({
    required String entityTable,
    required String entityId,
    required String operation,
    String? payloadJson,
  }) async {
    await into(syncQueue).insert(
      SyncQueueCompanion.insert(
        entityTable: entityTable,
        entityId: entityId,
        operation: operation,
        payloadJson: Value(payloadJson),
      ),
    );
  }

  /// The next batch to upload, oldest first.
  ///
  /// Excludes entries the server already rejected — those need user attention,
  /// not another retry (brain.md §10.6).
  Future<List<SyncQueueData>> nextBatch({int limit = 200}) {
    return (select(syncQueue)
          ..where((t) => t.isRejected.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.queuedAt)])
          ..limit(limit))
        .get();
  }

  Future<int> pendingCount() async {
    final count = syncQueue.id.count();
    final query = selectOnly(syncQueue)
      ..addColumns([count])
      ..where(syncQueue.isRejected.equals(false));
    return (await query.getSingle()).read(count) ?? 0;
  }

  /// Removes entries the server accepted.
  Future<void> clearAccepted(Iterable<int> ids) async {
    if (ids.isEmpty) return;
    await (delete(syncQueue)..where((t) => t.id.isIn(ids))).go();
  }

  /// Flags an entry the server refused, with the reason to show the user.
  Future<void> markRejected(int id, String error) async {
    await (update(syncQueue)..where((t) => t.id.equals(id))).write(
      SyncQueueCompanion(
        isRejected: const Value(true),
        lastError: Value(error),
        lastAttemptAt: Value(DateTime.now()),
      ),
    );
  }

  /// Records a failed attempt so the engine can back off.
  Future<void> markAttempted(Iterable<int> ids, {String? error}) async {
    if (ids.isEmpty) return;
    for (final id in ids) {
      await customStatement(
        'UPDATE sync_queue SET attempt_count = attempt_count + 1, '
        'last_attempt_at = ?, last_error = ? WHERE id = ?',
        [DateTime.now().millisecondsSinceEpoch ~/ 1000, error, id],
      );
    }
  }

  Future<List<SyncQueueData>> rejectedEntries() {
    return (select(syncQueue)..where((t) => t.isRejected.equals(true))).get();
  }

  Stream<int> watchPendingCount() {
    final count = syncQueue.id.count();
    final query = selectOnly(syncQueue)
      ..addColumns([count])
      ..where(syncQueue.isRejected.equals(false));
    return query.map((row) => row.read(count) ?? 0).watchSingle();
  }

  // --- Per-table sync state ---

  Future<DateTime?> lastSyncedAt(String entityTable) async {
    final row = await (select(syncState)
          ..where((t) => t.entityTable.equals(entityTable)))
        .getSingleOrNull();
    return row?.lastSyncedAt;
  }

  Future<void> setLastSyncedAt(String entityTable, DateTime at) async {
    await into(syncState).insertOnConflictUpdate(
      SyncStateCompanion.insert(
        entityTable: entityTable,
        lastSyncedAt: Value(at),
        lastAttemptAt: Value(DateTime.now()),
        lastError: const Value(null),
      ),
    );
  }

  Future<void> recordSyncFailure(String entityTable, String error) async {
    await into(syncState).insertOnConflictUpdate(
      SyncStateCompanion.insert(
        entityTable: entityTable,
        lastAttemptAt: Value(DateTime.now()),
        lastError: Value(error),
      ),
    );
  }

  Future<List<SyncStateData>> allSyncState() => select(syncState).get();

  /// The oldest successful pull across all tables — the "last synced" figure
  /// shown in the UI. Null if any table has never synced.
  Future<DateTime?> oldestSyncedAt() async {
    final rows = await select(syncState).get();
    if (rows.isEmpty) return null;

    DateTime? oldest;
    for (final row in rows) {
      final at = row.lastSyncedAt;
      if (at == null) return null;
      if (oldest == null || at.isBefore(oldest)) oldest = at;
    }
    return oldest;
  }
}
