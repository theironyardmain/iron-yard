import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../shared/providers/database_provider.dart';
import '../data/csv_exporter.dart';
import '../data/dashboard_repository.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(ref.watch(databaseProvider)),
);

final csvExporterProvider = Provider<CsvExporter>(
  (ref) => CsvExporter(ref.watch(databaseProvider)),
);

/// The admin home figures.
///
/// Watches the underlying tables so the numbers refresh after a scan, a
/// payment or a sync, without a manual reload.
final dashboardSummaryProvider = StreamProvider<DashboardSummary>((ref) {
  final db = ref.watch(databaseProvider);
  final repository = ref.watch(dashboardRepositoryProvider);

  return db
      .customSelect(
        'SELECT 1',
        readsFrom: {
          db.attendance,
          db.memberships,
          db.payments,
          db.profiles,
          db.classes,
        },
      )
      .watch()
      .asyncMap((_) => repository.summary());
});

/// Daily attendance for the trend strip.
final attendanceTrendProvider = FutureProvider<List<AttendancePoint>>(
  (ref) => ref.watch(dashboardRepositoryProvider).attendanceTrend(),
);

/// Members expiring or already lapsed.
final needsAttentionProvider =
    FutureProvider<List<({Profile member, Membership membership})>>(
      (ref) => ref.watch(dashboardRepositoryProvider).needsAttention(),
    );

/// Revenue by month.
final revenueTrendProvider =
    FutureProvider<List<({DateTime month, int revenueMinor})>>(
      (ref) => ref.watch(dashboardRepositoryProvider).revenueTrend(),
    );
