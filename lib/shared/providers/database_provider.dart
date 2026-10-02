import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/daos/attendance_dao.dart';
import '../../data/local/daos/equipment_dao.dart';
import '../../data/local/daos/invoice_dao.dart';
import '../../data/local/daos/membership_dao.dart';
import '../../data/local/daos/payment_dao.dart';
import '../../data/local/daos/profile_dao.dart';
import '../../data/local/daos/sync_dao.dart';
import '../../data/local/database.dart';

/// The single app-wide Drift database.
///
/// Overridden in tests with `AppDatabase.memory()`:
/// ```dart
/// ProviderScope(
///   overrides: [databaseProvider.overrideWithValue(AppDatabase.memory())],
///   child: ...,
/// )
/// ```
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final profileDaoProvider = Provider<ProfileDao>(
  (ref) => ref.watch(databaseProvider).profileDao,
);

final membershipDaoProvider = Provider<MembershipDao>(
  (ref) => ref.watch(databaseProvider).membershipDao,
);

final attendanceDaoProvider = Provider<AttendanceDao>(
  (ref) => ref.watch(databaseProvider).attendanceDao,
);

final paymentDaoProvider = Provider<PaymentDao>(
  (ref) => ref.watch(databaseProvider).paymentDao,
);

final invoiceDaoProvider = Provider<InvoiceDao>(
  (ref) => ref.watch(databaseProvider).invoiceDao,
);

final equipmentDaoProvider = Provider<EquipmentDao>(
  (ref) => ref.watch(databaseProvider).equipmentDao,
);

final syncDaoProvider = Provider<SyncDao>(
  (ref) => ref.watch(databaseProvider).syncDao,
);

/// Count of local changes waiting to upload — drives the sync indicator.
final pendingSyncCountProvider = StreamProvider<int>(
  (ref) => ref.watch(syncDaoProvider).watchPendingCount(),
);
