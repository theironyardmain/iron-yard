import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/local/daos/announcement_dao.dart';
import '../../../data/local/database.dart';

/// Live announcement delivery (brain.md §4).
///
/// Announcements are one of only two things pushed over Realtime; everything
/// else is pull-based sync. The point is that an urgent notice reaches members
/// without waiting for their next sync.
///
/// **Realtime is an accelerator, never a dependency.** The subscription can
/// fail, the device can be offline, and the app must still work — the same rows
/// arrive through normal sync later. Every failure here is therefore swallowed
/// after logging rather than surfaced as an error.
class AnnouncementRealtime {
  AnnouncementRealtime({
    required SupabaseClient client,
    required AnnouncementDao dao,
    this.onNewAnnouncement,
  }) : _client = client,
       _dao = dao;

  final SupabaseClient _client;
  final AnnouncementDao _dao;

  /// Called when a genuinely new announcement arrives, so the caller can raise
  /// a local notification (brain.md §6.9).
  final void Function(Announcement announcement)? onNewAnnouncement;

  RealtimeChannel? _channel;

  bool get isSubscribed => _channel != null;

  /// Starts listening for new announcements.
  ///
  /// Safe to call repeatedly; a second call is a no-op.
  Future<void> subscribe() async {
    if (_channel != null) return;

    try {
      final channel = _client
          .channel('public:announcements')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'announcements',
            callback: _handleInsert,
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'announcements',
            callback: _handleInsert,
          );

      channel.subscribe();
      _channel = channel;
    } catch (error, stack) {
      // Never fatal: sync still delivers these rows.
      debugPrint('Announcement realtime unavailable: $error\n$stack');
    }
  }

  Future<void> unsubscribe() async {
    final channel = _channel;
    _channel = null;
    if (channel == null) return;

    try {
      await _client.removeChannel(channel);
    } catch (error) {
      debugPrint('Failed to remove announcement channel: $error');
    }
  }

  Future<void> _handleInsert(PostgresChangePayload payload) async {
    try {
      final row = payload.newRecord;
      final announcement = _parse(row);
      if (announcement == null) return;

      // Drafts are not member-visible, so they raise nothing.
      if (announcement.publishedAt == null) return;

      final existing = await _dao.byId(announcement.id);

      // Already known: an edit or an echo of our own write. Update the row but
      // do not re-notify, or editing a typo would ping every member again.
      final isNew = existing == null;

      await _dao.upsertFromRemote(announcement, wasRead: existing?.isRead);

      if (isNew) onNewAnnouncement?.call(announcement);
    } catch (error, stack) {
      debugPrint('Failed to handle announcement payload: $error\n$stack');
    }
  }

  /// Maps a Supabase row to the local model.
  ///
  /// Returns null on anything unrecognised rather than throwing — a payload
  /// from a newer server schema must not break the listener.
  Announcement? _parse(Map<String, dynamic> row) {
    final id = row['id'];
    final title = row['title'];
    final body = row['body'];

    if (id is! String || title is! String || body is! String) return null;

    DateTime? parseTime(Object? value) =>
        value is String ? DateTime.tryParse(value)?.toLocal() : null;

    return Announcement(
      id: id,
      title: title,
      body: body,
      authorId: row['author_id'] as String?,
      publishedAt: parseTime(row['published_at']),
      isUrgent: row['is_urgent'] == true,
      // Local-only columns: a row from the server is unread by definition, and
      // is clean because it came from the server.
      isRead: false,
      createdAt: parseTime(row['created_at']) ?? DateTime.now(),
      updatedAt: parseTime(row['updated_at']) ?? DateTime.now(),
      isDeleted: row['is_deleted'] == true,
      isDirty: false,
    );
  }
}

/// Applies a server row without clobbering local-only state.
extension RemoteAnnouncementWrite on AnnouncementDao {
  /// Inserts or updates [announcement], preserving the device's read flag.
  ///
  /// [wasRead] is the existing local value; null for a row not seen before.
  Future<void> upsertFromRemote(
    Announcement announcement, {
    bool? wasRead,
  }) async {
    await into(announcements).insertOnConflictUpdate(
      announcement.copyWith(isRead: wasRead ?? false, isDirty: false),
    );
  }
}
