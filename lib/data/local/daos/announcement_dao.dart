import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/class_tables.dart';
import 'synced_dao.dart';

part 'announcement_dao.g.dart';

/// Gym announcements and member feedback (brain.md §6.9, §6.2).
@DriftAccessor(tables: [Announcements, Feedback])
class AnnouncementDao extends DatabaseAccessor<AppDatabase>
    with
        _$AnnouncementDaoMixin,
        SyncedDaoMixin<AppDatabase, $AnnouncementsTable, Announcement> {
  AnnouncementDao(super.db);

  @override
  $AnnouncementsTable get table => announcements;

  // --- Reading ---

  /// Published announcements, newest first — the member feed.
  ///
  /// Unpublished drafts are excluded; staff see them via [watchAll].
  Stream<List<Announcement>> watchPublished() {
    return (select(announcements)
          ..where(
            (t) => t.isDeleted.equals(false) & t.publishedAt.isNotNull(),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.publishedAt)]))
        .watch();
  }

  /// Everything including drafts, for the admin list.
  Stream<List<Announcement>> watchAll() {
    return (select(announcements)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([
            (t) => OrderingTerm.desc(t.publishedAt),
            (t) => OrderingTerm.desc(t.createdAt),
          ]))
        .watch();
  }

  Future<Announcement?> byId(String id) {
    return (select(announcements)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Count of published announcements the member has not opened.
  ///
  /// `is_read` is local-only (never synced), so this is per device.
  Stream<int> watchUnreadCount() {
    final count = announcements.id.count();
    final query = selectOnly(announcements)
      ..addColumns([count])
      ..where(
        announcements.isDeleted.equals(false) &
            announcements.publishedAt.isNotNull() &
            announcements.isRead.equals(false),
      );

    return query.map((row) => row.read(count) ?? 0).watchSingle();
  }

  // --- Writing ---

  /// Creates an announcement.
  ///
  /// [publish] false saves a draft, which members never see.
  Future<String> create({
    required String title,
    required String body,
    String? authorId,
    bool isUrgent = false,
    bool publish = true,
  }) async {
    final id = Uuid.v4();
    await into(announcements).insert(
      AnnouncementsCompanion.insert(
        id: id,
        title: title,
        body: body,
        authorId: Value(authorId),
        isUrgent: Value(isUrgent),
        publishedAt: Value(publish ? DateTime.now() : null),
        // The author has obviously seen their own announcement.
        isRead: const Value(true),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
    return id;
  }

  /// Named `edit` rather than `update` so it does not shadow Drift's own
  /// `update()` on DatabaseAccessor.
  Future<void> edit({
    required String id,
    required String title,
    required String body,
    bool? isUrgent,
  }) async {
    await (update(announcements)..where((t) => t.id.equals(id))).write(
      AnnouncementsCompanion(
        title: Value(title),
        body: Value(body),
        isUrgent: isUrgent == null ? const Value.absent() : Value(isUrgent),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }

  /// Publishes a draft. Already-published rows keep their original timestamp,
  /// so editing a published announcement does not push it back to the top.
  Future<void> publish(String id) async {
    final existing = await byId(id);
    if (existing == null || existing.publishedAt != null) return;

    await (update(announcements)..where((t) => t.id.equals(id))).write(
      AnnouncementsCompanion(
        publishedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }

  Future<void> remove(String id) => softDelete(id);

  // --- Read state (local only, never synced) ---

  Future<void> markRead(String id) async {
    await (update(announcements)..where((t) => t.id.equals(id))).write(
      // Deliberately does not touch updated_at or is_dirty: read state is a
      // per-device convenience and must not be uploaded.
      const AnnouncementsCompanion(isRead: Value(true)),
    );
  }

  Future<void> markAllRead() async {
    await (update(announcements)..where((t) => t.isRead.equals(false))).write(
      const AnnouncementsCompanion(isRead: Value(true)),
    );
  }

  /// Rows arriving from sync default to unread, which is what a member expects.
  ///
  /// Exposed so the sync layer (Phase 10) can insert without clobbering the
  /// local read flag on rows the member already opened.
  Future<void> preserveReadState(String id, {required bool wasRead}) async {
    await (update(announcements)..where((t) => t.id.equals(id))).write(
      AnnouncementsCompanion(isRead: Value(wasRead)),
    );
  }

  // --- Feedback (brain.md §6.2) ---

  Future<String> submitFeedback({
    required String memberId,
    required String message,
    String? subject,
  }) async {
    final id = Uuid.v4();
    await into(feedback).insert(
      FeedbackCompanion.insert(
        id: id,
        memberId: memberId,
        message: message,
        subject: Value(subject),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
    return id;
  }

  Stream<List<FeedbackData>> watchFeedbackFor(String memberId) {
    return (select(feedback)
          ..where((t) => t.memberId.equals(memberId) & t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  /// All feedback, newest first — the admin inbox.
  Stream<List<FeedbackData>> watchAllFeedback({bool openOnly = false}) {
    return (select(feedback)
          ..where(
            (t) =>
                t.isDeleted.equals(false) &
                (openOnly ? t.status.equals('open') : const Constant(true)),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<void> respondToFeedback({
    required String id,
    required String response,
  }) async {
    await (update(feedback)..where((t) => t.id.equals(id))).write(
      FeedbackCompanion(
        adminResponse: Value(response),
        respondedAt: Value(DateTime.now()),
        status: const Value('resolved'),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }
}
