// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payment_dao.dart';

// ignore_for_file: type=lint
mixin _$PaymentDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProfilesTable get profiles => attachedDatabase.profiles;
  $MembershipPlansTable get membershipPlans => attachedDatabase.membershipPlans;
  $MembershipsTable get memberships => attachedDatabase.memberships;
  $InvoicesTable get invoices => attachedDatabase.invoices;
  $PaymentsTable get payments => attachedDatabase.payments;
  PaymentDaoManager get managers => PaymentDaoManager(this);
}

class PaymentDaoManager {
  final _$PaymentDaoMixin _db;
  PaymentDaoManager(this._db);
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db.attachedDatabase, _db.profiles);
  $$MembershipPlansTableTableManager get membershipPlans =>
      $$MembershipPlansTableTableManager(
        _db.attachedDatabase,
        _db.membershipPlans,
      );
  $$MembershipsTableTableManager get memberships =>
      $$MembershipsTableTableManager(_db.attachedDatabase, _db.memberships);
  $$InvoicesTableTableManager get invoices =>
      $$InvoicesTableTableManager(_db.attachedDatabase, _db.invoices);
  $$PaymentsTableTableManager get payments =>
      $$PaymentsTableTableManager(_db.attachedDatabase, _db.payments);
}
