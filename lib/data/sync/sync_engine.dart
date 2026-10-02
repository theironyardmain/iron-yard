import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/database.dart';
import 'row_mapper.dart';

/// Why a queued change was refused by the server.
///
/// These map to the `hint` values raised by the Postgres triggers in
/// `supabase/migrations/20260920000003_capacity.sql`.
enum RejectionReason {
  duplicateAttendance,
  classFull,
  classCancelled,
  permissionDenied,
  foreignKeyMissing,
  unknown;

  /// What to show the user. Rejections are surfaced, not retried forever
  /// (brain.md §10.6).
  String get message => switch (this) {
    RejectionReason.duplicateAttendance =>
      'Already checked in for that day on another device.',
    RejectionReason.classFull => 'That class filled up before this synced.',
    RejectionReason.classCancelled => 'That class was cancelled.',
    RejectionReason.permissionDenied =>
      'You do not have permission for that change.',
    RejectionReason.foreignKeyMissing =>
      'Related record is missing on the server.',
    RejectionReason.unknown => 'The server refused this change.',
  };

  /// Classifies a Postgres error.
  static RejectionReason fromError(Object error) {
    final code = error is PostgrestException ? error.code : null;
    final text = '$error'.toLowerCase();

    if (code == '23505' || text.contains('uq_attendance_member_day')) {
      return RejectionReason.duplicateAttendance;
    }
    if (text.contains('class_full') || text.contains('class is full')) {
      return RejectionReason.classFull;
    }
    if (text.contains('class_cancelled') ||
        text.contains('class is cancelled')) {
      return RejectionReason.classCancelled;
    }
    if (code == '42501' || text.contains('row-level security')) {
      return RejectionReason.permissionDenied;
    }
    if (code == '23503') return RejectionReason.foreignKeyMissing;
    return RejectionReason.unknown;
  }

  /// Whether retrying could ever succeed.
  ///
  /// A duplicate or a full class will never become valid, so retrying wastes
  /// requests and hides the problem from the user.
  bool get isPermanent => this != RejectionReason.unknown;
}

/// The outcome of one sync run.
class SyncReport {
  const SyncReport({
    this.pulled = 0,
    this.pushed = 0,
    this.rejected = const [],
    this.failures = const {},
    this.startedAt,
    this.finishedAt,
  });

  final int pulled;
  final int pushed;

  /// Changes the server refused, with the reason to show the user.
  final List<({String table, String id, RejectionReason reason})> rejected;

  /// Tables that could not be synced, with the error.
  final Map<String, String> failures;

  final DateTime? startedAt;
  final DateTime? finishedAt;

  bool get hasFailures => failures.isNotEmpty;
  bool get hasRejections => rejected.isNotEmpty;
  bool get isClean => !hasFailures && !hasRejections;
}

/// Moves local changes to Supabase and back (brain.md §4).
///
/// Design constraints from the spec:
///  * Incremental pulls filter on `updated_at > last_sync_time`, per table, so
///    one table failing never stalls the others.
///  * Uploads go in a single batched request per table, not row by row.
///  * Sync runs on explicit triggers only — never on every navigation.
class SyncEngine {
  SyncEngine({required AppDatabase db, required SupabaseClient client})
    : _db = db,
      _client = client;

  final AppDatabase _db;
  final SupabaseClient _client;

  /// Rows per batch. Large enough to be worth batching, small enough that a
  /// failure does not discard a huge amount of work.
  static const int batchSize = 200;

  bool _running = false;
  bool get isRunning => _running;

  /// Runs a full sync: push local changes, then pull remote ones.
  ///
  /// Pushing first means a row this device just created is on the server before
  /// the pull, so it is not re-fetched and compared against itself.
  ///
  /// Concurrent calls are ignored rather than queued: two engines racing would
  /// double-upload the same rows.
  Future<SyncReport> sync() async {
    if (_running) {
      return const SyncReport(failures: {'_engine': 'Sync already running'});
    }

    _running = true;
    final startedAt = DateTime.now();

    var pushed = 0;
    var pulled = 0;
    final rejected =
        <({String table, String id, RejectionReason reason})>[];
    final failures = <String, String>{};

    try {
      if (_client.auth.currentSession == null) {
        return SyncReport(
          startedAt: startedAt,
          finishedAt: DateTime.now(),
          failures: const {'_auth': 'Not signed in'},
        );
      }

      for (final table in syncTablesFor(_db)) {
        try {
          final result = await _pushTable(table);
          pushed += result.pushed;
          rejected.addAll(result.rejected);
        } catch (error, stack) {
          // Per-table isolation: one failure must not stall the rest.
          failures[table.name] = '$error';
          await _db.syncDao.recordSyncFailure(table.name, '$error');
          debugPrint('Push failed for ${table.name}: $error\n$stack');
        }
      }

      for (final table in syncTablesFor(_db)) {
        try {
          pulled += await _pullTable(table);
        } catch (error, stack) {
          failures[table.name] = '$error';
          await _db.syncDao.recordSyncFailure(table.name, '$error');
          debugPrint('Pull failed for ${table.name}: $error\n$stack');
        }
      }
    } finally {
      _running = false;
    }

    return SyncReport(
      pulled: pulled,
      pushed: pushed,
      rejected: rejected,
      failures: failures,
      startedAt: startedAt,
      finishedAt: DateTime.now(),
    );
  }

  // --- Push ---

  Future<({int pushed, List<({String table, String id, RejectionReason reason})> rejected})>
  _pushTable(SyncTable table) async {
    final dirty = await _dirtyRows(table);
    if (dirty.isEmpty) {
      return (
        pushed: 0,
        rejected: <({String table, String id, RejectionReason reason})>[],
      );
    }

    final rejected =
        <({String table, String id, RejectionReason reason})>[];
    var pushed = 0;

    for (var start = 0; start < dirty.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, dirty.length);
      final batch = dirty.sublist(start, end);
      final payload = batch.map(RowMapper.forUpload).toList();

      try {
        // One request for the whole batch (brain.md §4), not one per row.
        await _client.from(table.name).upsert(payload);
        await _clearDirty(table, batch.map((r) => r['id'] as String));
        pushed += batch.length;
      } catch (error) {
        final reason = RejectionReason.fromError(error);

        if (!reason.isPermanent) rethrow;

        // A permanent rejection for the batch could be caused by one row, so
        // retry individually to isolate it rather than discarding all of them.
        final outcome = await _pushIndividually(table, batch);
        pushed += outcome.pushed;
        rejected.addAll(outcome.rejected);
      }
    }

    return (pushed: pushed, rejected: rejected);
  }

  Future<({int pushed, List<({String table, String id, RejectionReason reason})> rejected})>
  _pushIndividually(
    SyncTable table,
    List<Map<String, dynamic>> batch,
  ) async {
    final rejected =
        <({String table, String id, RejectionReason reason})>[];
    var pushed = 0;

    for (final row in batch) {
      final id = row['id'] as String;
      try {
        await _client.from(table.name).upsert(RowMapper.forUpload(row));
        await _clearDirty(table, [id]);
        pushed++;
      } catch (error) {
        final reason = RejectionReason.fromError(error);

        if (!reason.isPermanent) rethrow;

        // Kept, not dropped: the user is told what happened rather than
        // silently losing the change (brain.md §10.6).
        await _recordRejection(
          table: table.name,
          id: id,
          reason: reason,
        );

        // Clear the dirty flag so the engine stops retrying a change that can
        // never succeed; the queue entry preserves the record of it.
        await _clearDirty(table, [id]);

        rejected.add((table: table.name, id: id, reason: reason));
        debugPrint('Rejected ${table.name}/$id: ${reason.message}');
      }
    }

    return (pushed: pushed, rejected: rejected);
  }

  /// Records a permanently refused change so the UI can explain it.
  Future<void> _recordRejection({
    required String table,
    required String id,
    required RejectionReason reason,
  }) async {
    await _db.syncDao.enqueue(
      entityTable: table,
      entityId: id,
      operation: 'upsert',
    );

    // enqueue() autoincrements, so the entry just added is the newest one for
    // this row.
    final queued = await _db.syncDao.nextBatch();
    final entry = queued.lastWhere(
      (e) => e.entityId == id && e.entityTable == table,
      orElse: () => queued.last,
    );

    await _db.syncDao.markRejected(entry.id, reason.message);
  }

  Future<List<Map<String, dynamic>>> _dirtyRows(SyncTable table) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM ${table.name} WHERE is_dirty = 1 LIMIT 5000',
          readsFrom: {table.table},
        )
        .get();

    return rows.map((row) => row.data).toList();
  }

  Future<void> _clearDirty(SyncTable table, Iterable<String> ids) async {
    if (ids.isEmpty) return;

    final placeholders = List.filled(ids.length, '?').join(', ');
    await _db.customStatement(
      'UPDATE ${table.name} SET is_dirty = 0 WHERE id IN ($placeholders)',
      ids.toList(),
    );
  }

  // --- Pull ---

  Future<int> _pullTable(SyncTable table) async {
    final since = await _db.syncDao.lastSyncedAt(table.name);

    var query = _client.from(table.name).select();
    if (since != null) {
      // Incremental: only what changed since the last successful pull.
      query = query.gt('updated_at', since.toUtc().toIso8601String());
    }

    final rows = await query.order('updated_at').limit(5000);
    if (rows.isEmpty) {
      await _db.syncDao.setLastSyncedAt(table.name, DateTime.now());
      return 0;
    }

    final columns = table.columnNames;
    final types = table.columnTypes;
    var applied = 0;
    DateTime? newest;

    await _db.transaction(() async {
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['id'];
        if (id is! String) continue;

        final serverUpdatedAt = RowMapper.decodeValue(
          column: 'updated_at',
          value: row['updated_at'],
          type: SyncColumnType.dateTime,
        );
        if (serverUpdatedAt is DateTime) {
          if (newest == null || serverUpdatedAt.isAfter(newest!)) {
            newest = serverUpdatedAt;
          }
        }

        // Conflict resolution: a row still dirty locally has changes the
        // server has not seen, so the local copy wins and will be pushed on
        // the next run. Overwriting it here would discard the user's work.
        final localDirty = await _isDirty(table, id);
        if (localDirty) continue;

        final values = <String, Expression<Object>>{};
        final mapped = RowMapper.fromRemote(row, columns);

        for (final entry in mapped.entries) {
          final decoded = RowMapper.decodeValue(
            column: entry.key,
            value: entry.value,
            type: types[entry.key] ?? SyncColumnType.other,
          );
          values[entry.key] = Variable(decoded);
        }

        if (values.isEmpty) continue;

        await _upsertRaw(table, id, values);
        applied++;
      }
    });

    // Use the newest server timestamp rather than the device clock: a skewed
    // clock would otherwise skip rows on the next pull.
    await _db.syncDao.setLastSyncedAt(
      table.name,
      newest ?? DateTime.now(),
    );

    return applied;
  }

  Future<bool> _isDirty(SyncTable table, String id) async {
    final row = await _db
        .customSelect(
          'SELECT is_dirty FROM ${table.name} WHERE id = ?',
          variables: [Variable(id)],
        )
        .getSingleOrNull();

    return row?.data['is_dirty'] == 1 || row?.data['is_dirty'] == true;
  }

  Future<void> _upsertRaw(
    SyncTable table,
    String id,
    Map<String, Expression<Object>> values,
  ) async {
    final columns = values.keys.toList();
    final placeholders = List.filled(columns.length, '?').join(', ');
    final updates = columns.map((c) => '$c = excluded.$c').join(', ');

    final args = <Variable<Object>>[
      for (final column in columns) values[column]! as Variable<Object>,
    ];

    await _db.customStatement(
      'INSERT INTO ${table.name} (${columns.join(', ')}) '
      'VALUES ($placeholders) '
      'ON CONFLICT(id) DO UPDATE SET $updates',
      args.map((v) => v.value).toList(),
    );
  }
}
