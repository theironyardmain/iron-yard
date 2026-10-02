import 'package:flutter_test/flutter_test.dart';
import 'package:iron_yard/core/constants/app_constants.dart';
import 'package:iron_yard/data/local/database.dart';

void main() {
  late AppDatabase db;
  late String memberId;

  setUp(() async {
    db = AppDatabase.memory();
    memberId = await db.profileDao.createMember(fullName: 'Member');
  });

  tearDown(() async => db.close());

  group('feedback (brain.md §6.2)', () {
    test('a submission starts open and queued for sync', () async {
      await db.announcementDao.submitFeedback(
        memberId: memberId,
        subject: 'Equipment',
        message: 'The treadmill is broken.',
      );

      final mine = await db.announcementDao.watchFeedbackFor(memberId).first;

      expect(mine, hasLength(1));
      expect(mine.single.status, 'open');
      expect(mine.single.adminResponse, isNull);
      expect(mine.single.isDirty, isTrue, reason: 'queued for upload');
    });

    test('a subject is optional', () async {
      await db.announcementDao.submitFeedback(
        memberId: memberId,
        message: 'Just a note.',
      );

      final mine = await db.announcementDao.watchFeedbackFor(memberId).first;
      expect(mine.single.subject, isNull);
      expect(mine.single.message, 'Just a note.');
    });

    test('a member sees only their own messages', () async {
      final other = await db.profileDao.createMember(fullName: 'Other');

      await db.announcementDao.submitFeedback(
        memberId: memberId,
        message: 'Mine',
      );
      await db.announcementDao.submitFeedback(
        memberId: other,
        message: 'Theirs',
      );

      final mine = await db.announcementDao.watchFeedbackFor(memberId).first;
      expect(mine, hasLength(1));
      expect(mine.single.message, 'Mine');
    });

    test('replying records the response and resolves it', () async {
      final id = await db.announcementDao.submitFeedback(
        memberId: memberId,
        message: 'Question',
      );

      await db.announcementDao.respondToFeedback(
        id: id,
        response: 'Fixed, thanks for flagging.',
      );

      final item = (await db.announcementDao.watchAllFeedback().first).single;
      expect(item.status, 'resolved');
      expect(item.adminResponse, 'Fixed, thanks for flagging.');
      expect(item.respondedAt, isNotNull);
    });

    test('the reply is visible to the member who asked', () async {
      final id = await db.announcementDao.submitFeedback(
        memberId: memberId,
        message: 'Question',
      );
      await db.announcementDao.respondToFeedback(id: id, response: 'Answer');

      final mine = await db.announcementDao.watchFeedbackFor(memberId).first;
      expect(mine.single.adminResponse, 'Answer');
    });

    test('the open inbox excludes answered messages', () async {
      final open = await db.announcementDao.submitFeedback(
        memberId: memberId,
        message: 'Still open',
      );
      final answered = await db.announcementDao.submitFeedback(
        memberId: memberId,
        message: 'Answered',
      );
      await db.announcementDao.respondToFeedback(
        id: answered,
        response: 'Done',
      );

      final inbox = await db.announcementDao
          .watchAllFeedback(openOnly: true)
          .first;

      expect(inbox, hasLength(1));
      expect(inbox.single.id, open);

      final all = await db.announcementDao.watchAllFeedback().first;
      expect(all, hasLength(2));
    });
  });

  group('trainers (brain.md §6.3)', () {
    test('creating makes both the profile and the trainer record', () async {
      // Either one alone is useless: a trainer row with no profile is
      // invisible, a profile with no trainer row has no specialisation.
      final trainerId = await db.profileDao.createTrainer(
        fullName: 'Asha Rao',
        specialization: 'Strength',
        bio: 'Ten years coaching.',
      );

      final record = await db.profileDao.trainerById(trainerId);

      expect(record, isNotNull);
      expect(record!.profile.fullName, 'Asha Rao');
      expect(record.profile.role, UserRole.trainer.wireValue);
      expect(record.trainer.specialization, 'Strength');
      expect(record.trainer.isActive, isTrue);
      expect(record.profile.isDirty, isTrue);
      expect(record.trainer.isDirty, isTrue);
    });

    test('a trainer is not listed among members', () async {
      await db.profileDao.createTrainer(fullName: 'Asha Rao');

      final members = await db.profileDao.members();
      expect(members.map((m) => m.fullName), isNot(contains('Asha Rao')));
    });

    test('the roster is sorted by name', () async {
      await db.profileDao.createTrainer(fullName: 'Zara');
      await db.profileDao.createTrainer(fullName: 'Amit');
      await db.profileDao.createTrainer(fullName: 'Meera');

      final trainers = await db.profileDao.watchTrainers().first;
      expect(
        trainers.map((t) => t.profile.fullName),
        ['Amit', 'Meera', 'Zara'],
      );
    });

    test('editing updates both rows', () async {
      final trainerId = await db.profileDao.createTrainer(
        fullName: 'Before',
        specialization: 'Old',
      );
      final record = await db.profileDao.trainerById(trainerId);

      await db.profileDao.updateTrainer(
        trainerId: trainerId,
        profileId: record!.profile.id,
        fullName: 'After',
        specialization: 'New',
        phone: '9000000000',
      );

      final updated = await db.profileDao.trainerById(trainerId);
      expect(updated!.profile.fullName, 'After');
      expect(updated.profile.phone, '9000000000');
      expect(updated.trainer.specialization, 'New');
    });

    test('retiring hides them from members but keeps the record', () async {
      final trainerId = await db.profileDao.createTrainer(fullName: 'Leaver');

      await db.profileDao.setTrainerActive(trainerId, isActive: false);

      expect(await db.profileDao.watchTrainers().first, isEmpty);
      expect(
        await db.profileDao.watchTrainers(activeOnly: false).first,
        hasLength(1),
      );
    });

    test('retiring is reversible', () async {
      final trainerId = await db.profileDao.createTrainer(fullName: 'Returner');

      await db.profileDao.setTrainerActive(trainerId, isActive: false);
      await db.profileDao.setTrainerActive(trainerId, isActive: true);

      expect(await db.profileDao.watchTrainers().first, hasLength(1));
    });

    test('a retired trainer keeps the classes they taught', () async {
      // Past records must stay attributable.
      final trainerId = await db.profileDao.createTrainer(fullName: 'Coach');
      final future = DateTime.now().add(const Duration(days: 2));

      final classId = await db.classDao.createClass(
        name: 'Spin',
        startsAt: future,
        endsAt: future.add(const Duration(hours: 1)),
        capacity: 10,
        trainerId: trainerId,
      );

      await db.profileDao.setTrainerActive(trainerId, isActive: false);

      final gymClass = await db.classDao.classById(classId);
      expect(gymClass!.trainerId, trainerId);
    });

    test('trainerById is null for an unknown id', () async {
      expect(await db.profileDao.trainerById('nope'), isNull);
    });

    test('a trainer can be assigned to a class', () async {
      // The gap from Phase 11: classes took a trainer_id nothing populated.
      final trainerId = await db.profileDao.createTrainer(
        fullName: 'Coach',
        specialization: 'Spin',
      );
      final future = DateTime.now().add(const Duration(days: 1));

      final classId = await db.classDao.createClass(
        name: 'Spin',
        startsAt: future,
        endsAt: future.add(const Duration(hours: 1)),
        capacity: 15,
        trainerId: trainerId,
      );

      final gymClass = await db.classDao.classById(classId);
      expect(gymClass!.trainerId, trainerId);
    });
  });
}
