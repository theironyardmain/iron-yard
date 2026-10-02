import '../../../data/local/database.dart';

/// Assigns and renews plans, and creates the invoice each one charges
/// (brain.md §6.5).
///
/// `MembershipDao` stays single-table-focused; this repository is where
/// cross-domain orchestration (membership + invoice together) lives, matching
/// how `PaymentRepository` already sits above `PaymentDao`.
class MembershipRepository {
  MembershipRepository(this._db);

  final AppDatabase _db;

  /// The result of assigning or renewing a plan: the new membership and the
  /// invoice created to charge for it.
  Future<({String membershipId, String invoiceId})> assignPlan({
    required String memberId,
    required String planId,
    DateTime? startDate,
    String? createdBy,
  }) => _db.transaction(() async {
    final membershipId = await _db.membershipDao.assignPlan(
      memberId: memberId,
      planId: planId,
      startDate: startDate,
    );
    final invoiceId = await _chargeFor(
      memberId: memberId,
      membershipId: membershipId,
      planId: planId,
      createdBy: createdBy,
    );
    return (membershipId: membershipId, invoiceId: invoiceId);
  });

  /// Renews the member's current plan, continuing from their existing expiry
  /// when it has not lapsed (see `MembershipDao.renew`), and charges for it.
  Future<({String membershipId, String invoiceId})> renew({
    required String memberId,
    required String planId,
    DateTime? asOf,
    String? createdBy,
  }) => _db.transaction(() async {
    final membershipId = await _db.membershipDao.renew(
      memberId: memberId,
      planId: planId,
      asOf: asOf,
    );
    final invoiceId = await _chargeFor(
      memberId: memberId,
      membershipId: membershipId,
      planId: planId,
      createdBy: createdBy,
    );
    return (membershipId: membershipId, invoiceId: invoiceId);
  });

  Future<String> _chargeFor({
    required String memberId,
    required String membershipId,
    required String planId,
    String? createdBy,
  }) async {
    final plan = await _db.membershipDao.planById(planId);
    if (plan == null) throw StateError('Plan not found: $planId');

    return _db.invoiceDao.createChargeForMembership(
      memberId: memberId,
      membershipId: membershipId,
      amountMinor: plan.priceMinor,
      description: '${plan.name} membership',
      createdBy: createdBy,
    );
  }
}
