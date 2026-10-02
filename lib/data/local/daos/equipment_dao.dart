import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/equipment_tables.dart';
import 'synced_dao.dart';

part 'equipment_dao.g.dart';

/// Gym equipment and its service history (brain.md §6.10).
@DriftAccessor(tables: [EquipmentItems, EquipmentServiceLogs])
class EquipmentDao extends DatabaseAccessor<AppDatabase>
    with
        _$EquipmentDaoMixin,
        SyncedDaoMixin<AppDatabase, $EquipmentItemsTable, EquipmentItem> {
  EquipmentDao(super.db);

  @override
  $EquipmentItemsTable get table => equipmentItems;

  // --- Equipment ---

  Future<String> create({
    required String name,
    String? category,
    int quantity = 1,
    String? location,
    DateTime? purchaseDate,
    int? costMinor,
    int? serviceIntervalDays,
    String? notes,
  }) async {
    final id = Uuid.v4();
    await into(equipmentItems).insert(
      EquipmentItemsCompanion.insert(
        id: id,
        name: name,
        category: Value(category),
        quantity: Value(quantity),
        location: Value(location),
        purchaseDate: Value(purchaseDate),
        costMinor: Value(costMinor),
        serviceIntervalDays: Value(serviceIntervalDays),
        notes: Value(notes),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
    return id;
  }

  Future<void> updateItem({
    required String id,
    required String name,
    String? category,
    required int quantity,
    String? location,
    DateTime? purchaseDate,
    int? costMinor,
    int? serviceIntervalDays,
    String? notes,
  }) async {
    await (update(equipmentItems)..where((t) => t.id.equals(id))).write(
      EquipmentItemsCompanion(
        name: Value(name),
        category: Value(category),
        quantity: Value(quantity),
        location: Value(location),
        purchaseDate: Value(purchaseDate),
        costMinor: Value(costMinor),
        serviceIntervalDays: Value(serviceIntervalDays),
        notes: Value(notes),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }

  Future<void> setStatus(String id, String status) async {
    await (update(equipmentItems)..where((t) => t.id.equals(id))).write(
      EquipmentItemsCompanion(
        status: Value(status),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }

  Future<EquipmentItem?> byId(String id) {
    return (select(
      equipmentItems,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// All equipment, excluding retired unless [includeRetired].
  Stream<List<EquipmentItem>> watchAll({bool includeRetired = false}) {
    return (select(equipmentItems)
          ..where(
            (t) =>
                t.isDeleted.equals(false) &
                (includeRetired
                    ? const Constant(true)
                    : t.status.equals('retired').not()),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  /// Equipment due for a scheduled service: never serviced (or serviced more
  /// than [serviceIntervalDays] ago), excluding retired items.
  Future<List<EquipmentItem>> dueForService({DateTime? asOf}) async {
    final today = asOf ?? DateTime.now();
    final all = await (select(equipmentItems)
          ..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.status.equals('retired').not() &
                t.serviceIntervalDays.isNotNull(),
          ))
        .get();

    return all.where((item) {
      final interval = item.serviceIntervalDays!;
      final last = item.lastServicedAt;
      if (last == null) return true;
      final due = DateTime(last.year, last.month, last.day + interval);
      return !due.isAfter(today);
    }).toList()
      ..sort((a, b) {
        final aLast = a.lastServicedAt ?? DateTime(1970);
        final bLast = b.lastServicedAt ?? DateTime(1970);
        return aLast.compareTo(bLast);
      });
  }

  /// Retires equipment. Soft-deletes so it drops off every list but its
  /// service history stays intact for reference.
  Future<void> retire(String id) => softDelete(id);

  // --- Service log ---

  /// Logs a service event and updates the equipment's
  /// [EquipmentItems.lastServicedAt].
  Future<String> logService({
    required String equipmentId,
    required String description,
    DateTime? servicedAt,
    int? costMinor,
    String? performedBy,
  }) async {
    final id = Uuid.v4();
    final when = servicedAt ?? DateTime.now();

    await into(equipmentServiceLogs).insert(
      EquipmentServiceLogsCompanion.insert(
        id: id,
        equipmentId: equipmentId,
        servicedAt: when,
        description: description,
        costMinor: Value(costMinor),
        performedBy: Value(performedBy),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );

    final current = await byId(equipmentId);
    final currentLast = current?.lastServicedAt;
    if (currentLast == null || when.isAfter(currentLast)) {
      await (update(
        equipmentItems,
      )..where((t) => t.id.equals(equipmentId))).write(
        EquipmentItemsCompanion(
          lastServicedAt: Value(when),
          updatedAt: Value(DateTime.now()),
          isDirty: const Value(true),
        ),
      );
    }

    return id;
  }

  Future<List<EquipmentServiceLog>> serviceHistoryFor(String equipmentId) {
    return (select(equipmentServiceLogs)
          ..where(
            (t) =>
                t.equipmentId.equals(equipmentId) & t.isDeleted.equals(false),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.servicedAt)]))
        .get();
  }

  Stream<List<EquipmentServiceLog>> watchServiceHistoryFor(
    String equipmentId,
  ) {
    return (select(equipmentServiceLogs)
          ..where(
            (t) =>
                t.equipmentId.equals(equipmentId) & t.isDeleted.equals(false),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.servicedAt)]))
        .watch();
  }
}
