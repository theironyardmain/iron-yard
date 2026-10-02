import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../local/database.dart';
import 'sync_engine.dart';

/// Why a sync run was started, for logging and for deciding whether to skip.
enum SyncTrigger {
  /// Right after signing in.
  login,

  /// Opening a major section.
  section,

  /// The user pulled to refresh.
  manual,

  /// Connectivity returned.
  connectivity,
}

/// What the UI needs to show about sync.
class SyncStatus {
  const SyncStatus({
    this.isSyncing = false,
    this.lastSyncedAt,
    this.lastReport,
    this.consecutiveFailures = 0,
  });

  final bool isSyncing;
  final DateTime? lastSyncedAt;
  final SyncReport? lastReport;
  final int consecutiveFailures;

  bool get hasNeverSynced => lastSyncedAt == null;

  SyncStatus copyWith({
    bool? isSyncing,
    DateTime? lastSyncedAt,
    SyncReport? lastReport,
    int? consecutiveFailures,
  }) => SyncStatus(
    isSyncing: isSyncing ?? this.isSyncing,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    lastReport: lastReport ?? this.lastReport,
    consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
  );
}

/// Decides *when* to sync (brain.md §4).
///
/// The spec is explicit that sync runs on triggers, never on every navigation:
/// after login, on opening a major section, on pull-to-refresh, and when
/// connectivity returns. A section trigger is additionally throttled, so
/// tabbing back and forth does not hammer the server.
class SyncController {
  SyncController({
    required SyncEngine engine,
    required AppDatabase db,
    Connectivity? connectivity,
  }) : _engine = engine,
       _db = db,
       _connectivity = connectivity ?? Connectivity();

  final SyncEngine _engine;
  final AppDatabase _db;
  final Connectivity _connectivity;

  /// Minimum gap between automatic section syncs.
  static const Duration sectionThrottle = Duration(minutes: 5);

  /// Backoff schedule after consecutive failures, capped so a long outage does
  /// not push the next attempt hours away.
  static const List<Duration> backoff = [
    Duration(seconds: 30),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];

  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;

  SyncStatus _status = const SyncStatus();
  SyncStatus get status => _status;

  DateTime? _lastSectionSync;
  DateTime? _nextAllowedAttempt;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  /// Starts watching for connectivity returning.
  void start() {
    _connectivitySubscription ??= _connectivity.onConnectivityChanged.listen((
      results,
    ) {
      final isOnline = results.any(
        (r) => r != ConnectivityResult.none,
      );
      if (isOnline) {
        // Fire and forget: reconnecting should not block anything.
        unawaited(sync(trigger: SyncTrigger.connectivity));
      }
    });
  }

  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    await _statusController.close();
  }

  /// Runs a sync if the trigger allows it.
  ///
  /// Returns null when the run was skipped — throttled, backing off, or
  /// already running.
  Future<SyncReport?> sync({required SyncTrigger trigger}) async {
    if (_engine.isRunning) return null;

    final now = DateTime.now();

    // A manual pull-to-refresh always runs: the user asked for it, and making
    // them wait out a backoff window with no explanation is worse than one
    // extra request.
    if (trigger != SyncTrigger.manual) {
      final nextAllowed = _nextAllowedAttempt;
      if (nextAllowed != null && now.isBefore(nextAllowed)) return null;

      if (trigger == SyncTrigger.section) {
        final last = _lastSectionSync;
        if (last != null && now.difference(last) < sectionThrottle) {
          return null;
        }
      }
    }

    if (trigger == SyncTrigger.section) _lastSectionSync = now;

    _emit(_status.copyWith(isSyncing: true));

    final report = await _engine.sync();

    final failed = report.hasFailures;
    final failures = failed ? _status.consecutiveFailures + 1 : 0;

    _nextAllowedAttempt = failed
        ? now.add(backoff[(failures - 1).clamp(0, backoff.length - 1)])
        : null;

    _emit(
      SyncStatus(
        isSyncing: false,
        // Only a clean run advances the timestamp, so the UI never claims
        // everything is current when a table failed.
        lastSyncedAt: failed
            ? _status.lastSyncedAt
            : (report.finishedAt ?? now),
        lastReport: report,
        consecutiveFailures: failures,
      ),
    );

    if (failed) {
      debugPrint('Sync completed with failures: ${report.failures}');
    }

    return report;
  }

  /// Loads the last sync time from the database, for a fresh app start.
  Future<void> restoreStatus() async {
    final oldest = await _db.syncDao.oldestSyncedAt();
    if (oldest != null) {
      _emit(_status.copyWith(lastSyncedAt: oldest));
    }
  }

  void _emit(SyncStatus status) {
    _status = status;
    if (!_statusController.isClosed) _statusController.add(status);
  }
}
