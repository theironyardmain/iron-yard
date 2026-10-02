// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile_dao.dart';

// ignore_for_file: type=lint
mixin _$ProfileDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProfilesTable get profiles => attachedDatabase.profiles;
  $EmergencyContactsTable get emergencyContacts =>
      attachedDatabase.emergencyContacts;
  $TrainersTable get trainers => attachedDatabase.trainers;
  ProfileDaoManager get managers => ProfileDaoManager(this);
}

class ProfileDaoManager {
  final _$ProfileDaoMixin _db;
  ProfileDaoManager(this._db);
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db.attachedDatabase, _db.profiles);
  $$EmergencyContactsTableTableManager get emergencyContacts =>
      $$EmergencyContactsTableTableManager(
        _db.attachedDatabase,
        _db.emergencyContacts,
      );
  $$TrainersTableTableManager get trainers =>
      $$TrainersTableTableManager(_db.attachedDatabase, _db.trainers);
}
