import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../shared/providers/database_provider.dart';

/// Active equipment, updating live — what admins/trainers see by default.
final equipmentListProvider = StreamProvider<List<EquipmentItem>>(
  (ref) => ref.watch(equipmentDaoProvider).watchAll(),
);

/// Every item including retired ones, for admin management.
final allEquipmentProvider = StreamProvider<List<EquipmentItem>>(
  (ref) => ref.watch(equipmentDaoProvider).watchAll(includeRetired: true),
);

/// Equipment overdue for its scheduled service.
final equipmentDueForServiceProvider = FutureProvider<List<EquipmentItem>>(
  (ref) => ref.watch(equipmentDaoProvider).dueForService(),
);

/// One item's service history, newest first.
final serviceHistoryProvider =
    StreamProvider.family<List<EquipmentServiceLog>, String>(
      (ref, equipmentId) => ref
          .watch(equipmentDaoProvider)
          .watchServiceHistoryFor(equipmentId),
    );
