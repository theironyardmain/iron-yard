// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invoice_dao.dart';

// ignore_for_file: type=lint
mixin _$InvoiceDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProfilesTable get profiles => attachedDatabase.profiles;
  $MembershipPlansTable get membershipPlans => attachedDatabase.membershipPlans;
  $MembershipsTable get memberships => attachedDatabase.memberships;
  $InvoicesTable get invoices => attachedDatabase.invoices;
  $PaymentsTable get payments => attachedDatabase.payments;
  InvoiceDaoManager get managers => InvoiceDaoManager(this);
}

class InvoiceDaoManager {
  final _$InvoiceDaoMixin _db;
  InvoiceDaoManager(this._db);
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
