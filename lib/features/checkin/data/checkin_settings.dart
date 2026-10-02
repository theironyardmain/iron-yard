import 'package:shared_preferences/shared_preferences.dart';

/// The member's daily check-in reminder preferences (brain.md §6.7).
///
/// Device-local: a reminder time is a personal setting, not gym data, and
/// syncing it would let one device change another's alarm.
class CheckInSettings {
  const CheckInSettings({
    required this.enabled,
    required this.hour,
    required this.minute,
  });

  /// Default: early evening, after most people have trained but before bed.
  static const CheckInSettings defaults = CheckInSettings(
    enabled: false,
    hour: 20,
    minute: 0,
  );

  final bool enabled;
  final int hour;
  final int minute;

  String get formattedTime =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  CheckInSettings copyWith({bool? enabled, int? hour, int? minute}) =>
      CheckInSettings(
        enabled: enabled ?? this.enabled,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
      );
}

/// Reads and writes [CheckInSettings].
class CheckInSettingsStore {
  const CheckInSettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static const _kEnabled = 'checkin.enabled';
  static const _kHour = 'checkin.hour';
  static const _kMinute = 'checkin.minute';

  CheckInSettings read() {
    // Opt-in: the app must not start notifying a member who never asked.
    return CheckInSettings(
      enabled: _prefs.getBool(_kEnabled) ?? CheckInSettings.defaults.enabled,
      hour: _prefs.getInt(_kHour) ?? CheckInSettings.defaults.hour,
      minute: _prefs.getInt(_kMinute) ?? CheckInSettings.defaults.minute,
    );
  }

  Future<void> write(CheckInSettings settings) async {
    await _prefs.setBool(_kEnabled, settings.enabled);
    await _prefs.setInt(_kHour, settings.hour);
    await _prefs.setInt(_kMinute, settings.minute);
  }
}
