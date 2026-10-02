// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'membership_dao.dart';

// ignore_for_file: type=lint
mixin _$MembershipDaoMixin on DatabaseAccessor<AppDatabase> {
  $MembershipPlansTable get membershipPlans => attachedDatabase.membershipPlans;
  $ProfilesTable get profiles => attachedDatabase.profiles;
  $MembershipsTable get memberships => attachedDatabase.memberships;
  MembershipDaoManager get managers => MembershipDaoManager(this);
}

class MembershipDaoManager {
  final _$MembershipDaoMixin _db;
  MembershipDaoManager(this._db);
  $$MembershipPlansTableTableManager get membershipPlans =>
      $$MembershipPlansTableTableManager(
        _db.attachedDatabase,
        _db.membershipPlans,
      );
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db.attachedDatabase, _db.profiles);
  $$MembershipsTableTableManager get memberships =>
      $$MembershipsTableTableManager(_db.attachedDatabase, _db.memberships);
}
