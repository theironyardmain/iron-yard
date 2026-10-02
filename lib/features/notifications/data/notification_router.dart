import 'package:flutter/foundation.dart';

import 'notification_payload.dart';

/// Holds a tapped notification until something can act on it.
///
/// A tap can arrive at three awkward moments:
///
///  * **Cold start** — the app was launched by the notification, so no router
///    exists yet and the callback never fires. `Notifications.launchPayload()`
///    recovers it, and it waits here until the first screen is ready.
///  * **While signed out** — the session is still being restored, or the user
///    is at the login screen. Navigating then would be thrown away by the
///    router's redirect, so it waits.
///  * **While running** — the normal case; it is consumed immediately.
///
/// Holding rather than dropping is the point: a member who taps "membership
/// expiring" should land on their membership, not the home screen.
class NotificationRouter extends ChangeNotifier {
  NotificationPayload? _pending;

  /// The payload waiting to be handled, if any.
  NotificationPayload? get pending => _pending;

  bool get hasPending => _pending != null;

  /// Records a tapped payload. Unparseable input is ignored.
  void handle(String? raw) {
    final payload = NotificationPayload.tryParse(raw);
    if (payload == null) {
      if (raw != null && raw.isNotEmpty) {
        debugPrint('Ignoring unrecognised notification payload: $raw');
      }
      return;
    }

    _pending = payload;
    notifyListeners();
  }

  /// Takes the pending payload, clearing it.
  ///
  /// Returns null when there is nothing waiting. Clearing on read means a
  /// payload is acted on once, not re-navigated on every rebuild.
  NotificationPayload? consume() {
    final payload = _pending;
    if (payload == null) return null;

    _pending = null;
    return payload;
  }

  /// Drops anything waiting — used on sign-out, where the payload refers to
  /// data this device is about to purge.
  void clear() {
    if (_pending == null) return;
    _pending = null;
    notifyListeners();
  }
}

/// Which member tab a payload belongs to.
///
/// Indices match `MemberShell`'s destinations: Home, Plans, Classes, News.
/// Returned as data rather than performed as navigation, so the mapping stays
/// testable without a widget tree.
/// Declaration order gives the tab index directly — `index` is already
/// provided by `Enum`, so no explicit value is needed.
enum MemberTab { home, plans, classes, news }

/// The member tab a tapped notification should open.
///
/// Every reminder currently targets the member area: expiry, payment and
/// check-in are all things the member acts on, and staff receive announcements
/// through their own shell.
MemberTab tabFor(NotificationPayload payload) => switch (payload.type) {
  // The home tab carries the QR card, membership status and check-in card.
  NotificationTarget.membership => MemberTab.home,
  NotificationTarget.payment => MemberTab.home,
  NotificationTarget.checkIn => MemberTab.home,
  NotificationTarget.gymClass => MemberTab.classes,
  NotificationTarget.announcement => MemberTab.news,
};
