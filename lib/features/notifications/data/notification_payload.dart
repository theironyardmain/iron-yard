/// Where a tapped notification should take the user (brain.md §6.9).
///
/// Encoded as `type:id` in the notification payload, so tapping a reminder
/// lands on the relevant screen rather than just opening the app.
class NotificationPayload {
  const NotificationPayload({required this.type, required this.id});

  final NotificationTarget type;
  final String id;

  String encode() => '${type.wireValue}:$id';

  /// Parses a payload, or null if it is unrecognised.
  ///
  /// A payload written by an older version must not crash the launch path.
  static NotificationPayload? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;

    final separator = raw.indexOf(':');
    if (separator <= 0 || separator == raw.length - 1) return null;

    final type = NotificationTarget.fromString(raw.substring(0, separator));
    if (type == null) return null;

    return NotificationPayload(
      type: type,
      id: raw.substring(separator + 1),
    );
  }
}

/// What a notification refers to.
enum NotificationTarget {
  membership,
  payment,
  gymClass,
  announcement,
  checkIn;

  static NotificationTarget? fromString(String? value) => switch (value) {
    'membership' => NotificationTarget.membership,
    'payment' => NotificationTarget.payment,
    'class' => NotificationTarget.gymClass,
    'announcement' => NotificationTarget.announcement,
    'checkin' => NotificationTarget.checkIn,
    _ => null,
  };

  String get wireValue => switch (this) {
    NotificationTarget.membership => 'membership',
    NotificationTarget.payment => 'payment',
    // `class` is a Dart keyword, so the enum name differs from the wire value.
    NotificationTarget.gymClass => 'class',
    NotificationTarget.announcement => 'announcement',
    NotificationTarget.checkIn => 'checkin',
  };
}
