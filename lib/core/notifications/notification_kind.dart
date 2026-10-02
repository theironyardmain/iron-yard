/// The categories of notification the app raises (brain.md §6.9).
///
/// Each owns a disjoint id range so a whole category can be cancelled and
/// rescheduled without disturbing the others. Android identifies notifications
/// by a single int, so without this a membership reminder could silently
/// replace a class reminder.
enum NotificationKind {
  /// Membership expiry (brain.md §6.9).
  membershipExpiry(base: 1000000, channel: 'reminders'),

  /// Payment due.
  paymentDue(base: 2000000, channel: 'reminders'),

  /// An upcoming class the member booked.
  classReminder(base: 3000000, channel: 'reminders'),

  /// The daily "did you go to the gym?" prompt (brain.md §6.7).
  dailyCheckIn(base: 4000000, channel: 'reminders'),

  /// Generic reminder, for callers without a category.
  reminder(base: 5000000, channel: 'reminders'),

  /// Gym announcements.
  announcement(base: 6000000, channel: 'announcements'),

  /// Time-critical notices — closures, cancellations.
  urgent(base: 7000000, channel: 'announcements_urgent');

  const NotificationKind({required this.base, required this.channel});

  /// Start of this kind's id range.
  final int base;

  /// Android channel, so a member can silence reminders without losing
  /// urgent notices.
  final String channel;

  /// Size of each range. Comfortably larger than any gym's membership count.
  static const int rangeSize = 1000000;

  int get rangeEnd => base + rangeSize;

  bool get isUrgent => this == NotificationKind.urgent;

  /// A stable id for [key] inside this kind's range.
  ///
  /// Derived from the key so rescheduling replaces the existing notification
  /// rather than stacking a duplicate.
  int idFor(String key) => base + (key.hashCode.toUnsigned(31) % rangeSize);

  /// Whether [id] belongs to this kind.
  bool owns(int id) => id >= base && id < rangeEnd;
}
