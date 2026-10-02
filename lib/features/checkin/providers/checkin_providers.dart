import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../shared/providers/database_provider.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/checkin_repository.dart';
import '../data/checkin_settings.dart';

final checkInSettingsStoreProvider = Provider<CheckInSettingsStore>(
  (ref) => CheckInSettingsStore(ref.watch(sharedPreferencesProvider)),
);

final checkInRepositoryProvider = Provider<CheckInRepository>(
  (ref) => CheckInRepository(
    db: ref.watch(databaseProvider),
    settings: ref.watch(checkInSettingsStoreProvider),
  ),
);

/// The member's reminder preference, held in memory for the UI.
class CheckInSettingsController extends StateNotifier<CheckInSettings> {
  CheckInSettingsController(this._repository)
    : super(_repository.readSettings());

  final CheckInRepository _repository;

  Future<void> setEnabled({required bool enabled}) async {
    final next = state.copyWith(enabled: enabled);
    state = next;
    await _repository.updateSettings(next);
  }

  Future<void> setTime({required int hour, required int minute}) async {
    final next = state.copyWith(hour: hour, minute: minute);
    state = next;
    await _repository.updateSettings(next);
  }
}

final checkInSettingsProvider =
    StateNotifierProvider<CheckInSettingsController, CheckInSettings>(
      (ref) => CheckInSettingsController(ref.watch(checkInRepositoryProvider)),
    );

/// Today's attendance record for the signed-in member, if any.
final todaysCheckInProvider = FutureProvider<AttendanceData?>((ref) async {
  final memberId = ref.watch(currentSessionProvider)?.userId;
  if (memberId == null) return null;

  // Rebuild when attendance changes, so logging a session updates the card.
  final db = ref.watch(databaseProvider);
  await db.customSelect(
    'SELECT 1',
    readsFrom: {db.attendance},
  ).watch().first;

  return ref.watch(checkInRepositoryProvider).todaysRecord(memberId);
});
