// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'class_dao.dart';

// ignore_for_file: type=lint
mixin _$ClassDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProfilesTable get profiles => attachedDatabase.profiles;
  $TrainersTable get trainers => attachedDatabase.trainers;
  $ClassesTable get classes => attachedDatabase.classes;
  $ClassBookingsTable get classBookings => attachedDatabase.classBookings;
  ClassDaoManager get managers => ClassDaoManager(this);
}

class ClassDaoManager {
  final _$ClassDaoMixin _db;
  ClassDaoManager(this._db);
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db.attachedDatabase, _db.profiles);
  $$TrainersTableTableManager get trainers =>
      $$TrainersTableTableManager(_db.attachedDatabase, _db.trainers);
  $$ClassesTableTableManager get classes =>
      $$ClassesTableTableManager(_db.attachedDatabase, _db.classes);
  $$ClassBookingsTableTableManager get classBookings =>
      $$ClassBookingsTableTableManager(_db.attachedDatabase, _db.classBookings);
}
