import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../data/local/daos/announcement_dao.dart';
import '../../../data/local/database.dart';
import '../../../data/remote/supabase_client.dart';
import '../../../shared/providers/database_provider.dart';
import '../data/announcement_realtime.dart';

final announcementDaoProvider = Provider<AnnouncementDao>(
  (ref) => ref.watch(databaseProvider).announcementDao,
);

/// Published announcements — the member feed.
final publishedAnnouncementsProvider = StreamProvider<List<Announcement>>(
  (ref) => ref.watch(announcementDaoProvider).watchPublished(),
);

/// Everything including drafts — the admin list.
final allAnnouncementsProvider = StreamProvider<List<Announcement>>(
  (ref) => ref.watch(announcementDaoProvider).watchAll(),
);

/// Unread count for the navigation badge. Local to this device.
final unreadAnnouncementsProvider = StreamProvider<int>(
  (ref) => ref.watch(announcementDaoProvider).watchUnreadCount(),
);

/// Live announcement delivery (brain.md §4).
///
/// Subscribes on creation and tears down with the provider. Failures are
/// swallowed inside the service: sync still delivers the rows.
final announcementRealtimeProvider = Provider<AnnouncementRealtime>((ref) {
  final service = AnnouncementRealtime(
    client: SupabaseService.client,
    dao: ref.watch(announcementDaoProvider),
    onNewAnnouncement: (announcement) {
      Notifications.show(
        id: Notifications.idForAnnouncement(announcement.id),
        title: announcement.title,
        body: announcement.body,
        payload: announcement.id,
        urgent: announcement.isUrgent,
      );
    },
  );

  ref.onDispose(service.unsubscribe);
  return service;
});

/// Member feedback for the admin inbox.
final allFeedbackProvider = StreamProvider.family<List<FeedbackData>, bool>(
  (ref, openOnly) =>
      ref.watch(announcementDaoProvider).watchAllFeedback(openOnly: openOnly),
);

/// One member's own feedback submissions.
final myFeedbackProvider = StreamProvider.family<List<FeedbackData>, String>(
  (ref, memberId) =>
      ref.watch(announcementDaoProvider).watchFeedbackFor(memberId),
);
