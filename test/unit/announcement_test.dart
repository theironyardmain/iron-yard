import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:iron_yard/core/notifications/notification_service.dart';
import 'package:iron_yard/data/local/database.dart';

void main() {
  late AppDatabase db;
  late String adminId;
  late String memberId;

  setUp(() async {
    db = AppDatabase.memory();
    adminId = await db.profileDao.createMember(fullName: 'Admin');
    memberId = await db.profileDao.createMember(fullName: 'Member');
  });

  tearDown(() async => db.close());

  group('publishing', () {
    test('a published announcement reaches the member feed', () async {
      await db.announcementDao.create(
        title: 'Closed Monday',
        body: 'The gym is closed for maintenance.',
        authorId: adminId,
      );

      final feed = await db.announcementDao.watchPublished().first;
      expect(feed, hasLength(1));
      expect(feed.single.publishedAt, isNotNull);
      expect(feed.single.isDirty, isTrue, reason: 'must sync');
    });

    test('a draft is hidden from members but visible to staff', () async {
      await db.announcementDao.create(
        title: 'Draft notice',
        body: 'Not ready yet.',
        publish: false,
      );

      expect(await db.announcementDao.watchPublished().first, isEmpty);
      expect(await db.announcementDao.watchAll().first, hasLength(1));
    });

    test('publishing a draft moves it into the feed', () async {
      final id = await db.announcementDao.create(
        title: 'Draft',
        body: 'Body',
        publish: false,
      );

      await db.announcementDao.publish(id);

      expect(await db.announcementDao.watchPublished().first, hasLength(1));
    });

    test('publishing an already-published row keeps its timestamp', () async {
      // Otherwise editing a typo would push an old notice back to the top of
      // every member's feed.
      final id = await db.announcementDao.create(
        title: 'Original',
        body: 'Body',
      );
      final original = (await db.announcementDao.byId(id))!.publishedAt;

      await db.announcementDao.publish(id);

      expect((await db.announcementDao.byId(id))!.publishedAt, original);
    });

    test('the feed is newest first', () async {
      // Explicit timestamps a day apart. Drift stores DateTime as Unix
      // seconds, so rows created milliseconds apart would tie and the order
      // would be undefined — not a realistic feed.
      for (final (index, title) in ['First', 'Second', 'Third'].indexed) {
        await db.into(db.announcements).insert(
          AnnouncementsCompanion.insert(
            id: 'feed-$index',
            title: title,
            body: 'x',
            publishedAt: Value(DateTime(2026, 3, 10 + index)),
          ),
        );
      }

      final feed = await db.announcementDao.watchPublished().first;
      expect(feed.map((a) => a.title), ['Third', 'Second', 'First']);
    });

    test('a deleted announcement leaves the feed', () async {
      final id = await db.announcementDao.create(title: 'Gone', body: 'x');

      await db.announcementDao.remove(id);

      expect(await db.announcementDao.watchPublished().first, isEmpty);

      // Soft-deleted, so the removal propagates on the next sync.
      final raw = await db.select(db.announcements).get();
      expect(raw.single.isDeleted, isTrue);
      expect(raw.single.isDirty, isTrue);
    });
  });

  group('read state (local only)', () {
    test('an announcement from someone else starts unread', () async {
      // Simulates a row arriving from sync rather than being authored here.
      await db.into(db.announcements).insert(
        AnnouncementsCompanion.insert(
          id: 'remote-1',
          title: 'From the gym',
          body: 'Body',
          publishedAt: Value(DateTime.now()),
          isRead: const Value(false),
        ),
      );

      expect(await db.announcementDao.watchUnreadCount().first, 1);
    });

    test('the author has already read their own announcement', () async {
      await db.announcementDao.create(title: 'Mine', body: 'x');
      expect(await db.announcementDao.watchUnreadCount().first, 0);
    });

    test('marking read clears the count', () async {
      await db.into(db.announcements).insert(
        AnnouncementsCompanion.insert(
          id: 'remote-2',
          title: 'Unread',
          body: 'x',
          publishedAt: Value(DateTime.now()),
          isRead: const Value(false),
        ),
      );

      await db.announcementDao.markRead('remote-2');

      expect(await db.announcementDao.watchUnreadCount().first, 0);
    });

    test('marking read does NOT mark the row dirty', () async {
      // Read state is per-device. Uploading it would mark one member's row
      // read for everyone.
      await db.into(db.announcements).insert(
        AnnouncementsCompanion.insert(
          id: 'remote-3',
          title: 'Unread',
          body: 'x',
          publishedAt: Value(DateTime.now()),
          isRead: const Value(false),
          isDirty: const Value(false),
        ),
      );

      await db.announcementDao.markRead('remote-3');

      final row = await db.announcementDao.byId('remote-3');
      expect(row!.isRead, isTrue);
      expect(
        row.isDirty,
        isFalse,
        reason: 'read state must never be uploaded',
      );
    });

    test('markAllRead clears every unread row', () async {
      for (var i = 0; i < 3; i++) {
        await db.into(db.announcements).insert(
          AnnouncementsCompanion.insert(
            id: 'remote-all-$i',
            title: 'Notice $i',
            body: 'x',
            publishedAt: Value(DateTime.now()),
            isRead: const Value(false),
          ),
        );
      }

      expect(await db.announcementDao.watchUnreadCount().first, 3);
      await db.announcementDao.markAllRead();
      expect(await db.announcementDao.watchUnreadCount().first, 0);
    });

    test('drafts are not counted as unread', () async {
      await db.into(db.announcements).insert(
        AnnouncementsCompanion.insert(
          id: 'draft-1',
          title: 'Draft',
          body: 'x',
          isRead: const Value(false),
        ),
      );

      expect(await db.announcementDao.watchUnreadCount().first, 0);
    });

    test('a deleted announcement is not counted as unread', () async {
      await db.into(db.announcements).insert(
        AnnouncementsCompanion.insert(
          id: 'gone-1',
          title: 'Removed',
          body: 'x',
          publishedAt: Value(DateTime.now()),
          isRead: const Value(false),
          isDeleted: const Value(true),
        ),
      );

      expect(await db.announcementDao.watchUnreadCount().first, 0);
    });
  });

  group('editing', () {
    test('updates title and body', () async {
      final id = await db.announcementDao.create(title: 'Old', body: 'Old');

      await db.announcementDao.edit(id: id, title: 'New', body: 'New body');

      final row = await db.announcementDao.byId(id);
      expect(row!.title, 'New');
      expect(row.body, 'New body');
    });

    test('can raise and lower urgency', () async {
      final id = await db.announcementDao.create(title: 'T', body: 'B');

      await db.announcementDao.edit(
        id: id,
        title: 'T',
        body: 'B',
        isUrgent: true,
      );
      expect((await db.announcementDao.byId(id))!.isUrgent, isTrue);

      await db.announcementDao.edit(
        id: id,
        title: 'T',
        body: 'B',
        isUrgent: false,
      );
      expect((await db.announcementDao.byId(id))!.isUrgent, isFalse);
    });
  });

  group('feedback (brain.md §6.2)', () {
    test('a member can submit and see their own feedback', () async {
      await db.announcementDao.submitFeedback(
        memberId: memberId,
        subject: 'Equipment',
        message: 'The treadmill is broken.',
      );

      final mine = await db.announcementDao.watchFeedbackFor(memberId).first;
      expect(mine, hasLength(1));
      expect(mine.single.status, 'open');
      expect(mine.single.isDirty, isTrue);
    });

    test('feedback is scoped to its member', () async {
      final other = await db.profileDao.createMember(fullName: 'Other');

      await db.announcementDao.submitFeedback(
        memberId: memberId,
        message: 'Mine',
      );

      expect(await db.announcementDao.watchFeedbackFor(other).first, isEmpty);
    });

    test('responding resolves the item', () async {
      final id = await db.announcementDao.submitFeedback(
        memberId: memberId,
        message: 'Question',
      );

      await db.announcementDao.respondToFeedback(
        id: id,
        response: 'Fixed, thanks.',
      );

      final item = (await db.announcementDao.watchAllFeedback().first).single;
      expect(item.status, 'resolved');
      expect(item.adminResponse, 'Fixed, thanks.');
      expect(item.respondedAt, isNotNull);
    });

    test('the open-only inbox excludes resolved items', () async {
      final open = await db.announcementDao.submitFeedback(
        memberId: memberId,
        message: 'Still open',
      );
      final resolved = await db.announcementDao.submitFeedback(
        memberId: memberId,
        message: 'Done',
      );
      await db.announcementDao.respondToFeedback(
        id: resolved,
        response: 'Sorted',
      );

      final inbox = await db.announcementDao
          .watchAllFeedback(openOnly: true)
          .first;

      expect(inbox, hasLength(1));
      expect(inbox.single.id, open);
    });
  });

  group('notification ids', () {
    test('are stable for the same announcement', () {
      // An unstable id would stack duplicate notifications on re-delivery.
      expect(
        Notifications.idForAnnouncement('abc-123'),
        Notifications.idForAnnouncement('abc-123'),
      );
    });

    test('differ between announcements', () {
      expect(
        Notifications.idForAnnouncement('abc-123'),
        isNot(Notifications.idForAnnouncement('def-456')),
      );
    });

    test('fit in a 32-bit positive int', () {
      // Android rejects ids outside this range.
      for (final id in ['a', 'long-uuid-value-here', '', '12345']) {
        final value = Notifications.idForAnnouncement(id);
        expect(value, greaterThanOrEqualTo(0));
        expect(value, lessThan(1 << 31));
      }
    });
  });
}
