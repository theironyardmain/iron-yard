import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../shared/providers/database_provider.dart';
import '../data/attendance_repository.dart';
import '../data/qr_payload.dart';

final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => AttendanceRepository(ref.watch(databaseProvider)),
);

/// Today's verified attendance count, for the admin home (brain.md §6.4).
final todayAttendanceCountProvider = FutureProvider<int>(
  (ref) => ref.watch(attendanceRepositoryProvider).todayCount(),
);

/// A member's attendance history, updating live.
final attendanceHistoryProvider =
    StreamProvider.family<List<AttendanceData>, String>(
      (ref, memberId) =>
          ref.watch(attendanceRepositoryProvider).watchHistoryFor(memberId),
    );

/// The QR payload for a member's card.
final memberCardProvider = FutureProvider.family<QrPayload?, String>(
  (ref, memberId) => ref.watch(attendanceRepositoryProvider).cardFor(memberId),
);
