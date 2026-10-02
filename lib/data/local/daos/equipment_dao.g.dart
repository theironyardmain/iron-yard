// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'equipment_dao.dart';

// ignore_for_file: type=lint
mixin _$EquipmentDaoMixin on DatabaseAccessor<AppDatabase> {
  $EquipmentItemsTable get equipmentItems => attachedDatabase.equipmentItems;
  $ProfilesTable get profiles => attachedDatabase.profiles;
  $EquipmentServiceLogsTable get equipmentServiceLogs =>
      attachedDatabase.equipmentServiceLogs;
  EquipmentDaoManager get managers => EquipmentDaoManager(this);
}

class EquipmentDaoManager {
  final _$EquipmentDaoMixin _db;
  EquipmentDaoManager(this._db);
  $$EquipmentItemsTableTableManager get equipmentItems =>
      $$EquipmentItemsTableTableManager(
        _db.attachedDatabase,
        _db.equipmentItems,
      );
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db.attachedDatabase, _db.profiles);
  $$EquipmentServiceLogsTableTableManager get equipmentServiceLogs =>
      $$EquipmentServiceLogsTableTableManager(
        _db.attachedDatabase,
        _db.equipmentServiceLogs,
      );
}
