import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../data/local/daos/class_dao.dart';

/// Live class-cancellation delivery (brain.md §4).
///
/// The second and last sanctioned Realtime use: a member who has booked needs
/// to know a class was cancelled before they travel to the gym for it.
///
/// Like announcements, this is an accelerator rather than a dependency — the
/// same change arrives through normal sync, so every failure is logged and
/// swallowed.
class ClassRealtime {
  ClassRealtime({
    required SupabaseClient client,
    required ClassDao dao,
    required String? memberId,
  }) : _client = client,
       _dao = dao,
       _memberId = memberId;

  final SupabaseClient _client;
  final ClassDao _dao;
  final String? _memberId;

  RealtimeChannel? _channel;

  bool get isSubscribed => _channel != null;

  Future<void> subscribe() async {
    if (_channel != null) return;

    try {
      final channel = _client
          .channel('public:classes')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'classes',
            callback: _handleUpdate,
          );

      channel.subscribe();
      _channel = channel;
    } catch (error, stack) {
      debugPrint('Class realtime unavailable: $error\n$stack');
    }
  }

  Future<void> unsubscribe() async {
    final channel = _channel;
    _channel = null;
    if (channel == null) return;

    try {
      await _client.removeChannel(channel);
    } catch (error) {
      debugPrint('Failed to remove class channel: $error');
    }
  }

  Future<void> _handleUpdate(PostgresChangePayload payload) async {
    try {
      final row = payload.newRecord;
      final id = row['id'];
      final status = row['status'];

      if (id is! String || status != 'cancelled') return;

      // Only notify someone who actually holds a booking; everyone else picks
      // the change up silently on their next sync.
      final memberId = _memberId;
      if (memberId == null) return;

      final booking = await _dao.bookingFor(classId: id, memberId: memberId);
      if (booking == null || booking.status != 'booked') return;

      final local = await _dao.classById(id);
      final name = local?.name ?? row['name'] as String? ?? 'A class';

      await _dao.applyRemoteCancellation(id);

      await Notifications.show(
        id: Notifications.idForAnnouncement('class-cancel-$id'),
        title: 'Class cancelled',
        body: '$name has been cancelled.',
        payload: id,
        urgent: true,
      );
    } catch (error, stack) {
      debugPrint('Failed to handle class payload: $error\n$stack');
    }
  }
}
