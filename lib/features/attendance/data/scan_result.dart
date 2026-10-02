import '../../../data/local/daos/attendance_dao.dart';
import '../../../data/local/daos/membership_dao.dart';

/// The outcome of scanning a membership card (brain.md §6.4).
///
/// Every case carries what the scanner should say, so the UI never has to
/// reconstruct the reason from a bare boolean.
sealed class ScanOutcome {
  const ScanOutcome();

  /// The member's name, where one is known.
  String? get memberName => null;

  /// Whether this outcome recorded attendance.
  bool get recorded => false;
}

/// Attendance recorded.
class ScanAccepted extends ScanOutcome {
  const ScanAccepted({
    required this.name,
    required this.status,
    required this.result,
    this.expiresOn,
  });

  final String name;
  final MembershipStatus status;
  final CheckInResult result;
  final DateTime? expiresOn;

  @override
  String? get memberName => name;

  @override
  bool get recorded => true;

  /// True when this scan replaced a self-reported entry for the same day.
  bool get upgraded => result == CheckInResult.upgradedFromSelfReport;

  /// True when the member is let in but should be warned about expiry.
  bool get warnsAboutExpiry => status == MembershipStatus.expiringSoon;
}

/// The member already has attendance for today.
///
/// Not an error: staff scanning a second time should see confirmation, not a
/// failure (brain.md §6.4).
class ScanAlreadyCheckedIn extends ScanOutcome {
  const ScanAlreadyCheckedIn({required this.name, this.checkedInAt});

  final String name;
  final DateTime? checkedInAt;

  @override
  String? get memberName => name;
}

/// Scanned successfully, but the membership has lapsed.
///
/// Attendance is still recorded — the person did visit, and refusing to record
/// it would leave the gym with no trace of an entry that happened.
class ScanExpired extends ScanOutcome {
  const ScanExpired({
    required this.name,
    required this.expiredOn,
    required this.wasRecorded,
  });

  final String name;
  final DateTime? expiredOn;
  final bool wasRecorded;

  @override
  String? get memberName => name;

  @override
  bool get recorded => wasRecorded;
}

/// The member exists but has been deactivated.
class ScanDeactivated extends ScanOutcome {
  const ScanDeactivated({required this.name});

  final String name;

  @override
  String? get memberName => name;
}

/// The card is valid but the member is not in this device's cache.
///
/// Happens on a device that has not synced since the member was added. The
/// scanner says so rather than blaming the card.
class ScanUnknownMember extends ScanOutcome {
  const ScanUnknownMember({required this.scannedName});

  final String scannedName;

  @override
  String? get memberName => scannedName.isEmpty ? null : scannedName;
}

/// The code is not an Iron Yard membership card.
class ScanNotACard extends ScanOutcome {
  const ScanNotACard();
}
