import 'package:flutter_test/flutter_test.dart';
import 'package:iron_yard/data/local/daos/class_dao.dart';
import 'package:iron_yard/data/local/database.dart';

void main() {
  late AppDatabase db;
  late String memberId;

  /// Comfortably in the future, so nothing trips the "already started" guard.
  final future = DateTime.now().add(const Duration(days: 2));

  setUp(() async {
    db = AppDatabase.memory();
    memberId = await db.profileDao.createMember(fullName: 'Booker');
  });

  tearDown(() async => db.close());

  Future<String> makeClass({int capacity = 10, DateTime? startsAt}) {
    final start = startsAt ?? future;
    return db.classDao.createClass(
      name: 'Yoga',
      startsAt: start,
      endsAt: start.add(const Duration(hours: 1)),
      capacity: capacity,
    );
  }

  group('classes', () {
    test('creating stores the schedule and marks it for sync', () async {
      final id = await makeClass(capacity: 12);

      final gymClass = await db.classDao.classById(id);
      expect(gymClass!.name, 'Yoga');
      expect(gymClass.capacity, 12);
      expect(gymClass.status, 'scheduled');
      expect(gymClass.isDirty, isTrue);
    });

    test('upcoming excludes classes that have already started', () async {
      await makeClass(startsAt: DateTime.now().subtract(const Duration(days: 1)));
      await makeClass();

      final upcoming = await db.classDao.watchUpcoming().first;
      expect(upcoming, hasLength(1));
    });

    test('upcoming is soonest first', () async {
      await makeClass(startsAt: future.add(const Duration(days: 3)));
      await makeClass(startsAt: future.add(const Duration(days: 1)));
      await makeClass(startsAt: future.add(const Duration(days: 2)));

      final upcoming = await db.classDao.watchUpcoming().first;
      final starts = upcoming.map((c) => c.startsAt).toList();
      final sorted = [...starts]..sort();
      expect(starts, sorted);
    });

    test('a date range returns only classes inside it', () async {
      await makeClass(startsAt: future);
      await makeClass(startsAt: future.add(const Duration(days: 30)));

      final week = await db.classDao
          .watchInRange(from: future, to: future.add(const Duration(days: 7)))
          .first;

      expect(week, hasLength(1));
    });
  });

  group('booking', () {
    test('books a member onto a class', () async {
      final classId = await makeClass();

      final result = await db.classDao.book(
        classId: classId,
        memberId: memberId,
      );

      expect(result, BookingResult.booked);
      expect(await db.classDao.bookedCount(classId), 1);
    });

    test('a second booking by the same member is reported, not duplicated',
        () async {
      final classId = await makeClass();
      await db.classDao.book(classId: classId, memberId: memberId);

      final second = await db.classDao.book(
        classId: classId,
        memberId: memberId,
      );

      expect(second, BookingResult.alreadyBooked);
      expect(await db.classDao.bookedCount(classId), 1);
    });

    test('refuses once local capacity is reached', () async {
      final classId = await makeClass(capacity: 2);

      for (var i = 0; i < 2; i++) {
        final other = await db.profileDao.createMember(fullName: 'M$i');
        await db.classDao.book(classId: classId, memberId: other);
      }

      final result = await db.classDao.book(
        classId: classId,
        memberId: memberId,
      );

      expect(result, BookingResult.full);
      expect(await db.classDao.bookedCount(classId), 2);
    });

    test('refuses a cancelled class', () async {
      final classId = await makeClass();
      await db.classDao.cancelClass(classId);

      expect(
        await db.classDao.book(classId: classId, memberId: memberId),
        BookingResult.cancelled,
      );
    });

    test('refuses a class that has already started', () async {
      final classId = await makeClass(
        startsAt: DateTime.now().subtract(const Duration(hours: 1)),
      );

      expect(
        await db.classDao.book(classId: classId, memberId: memberId),
        BookingResult.past,
      );
    });

    test('cancelling frees a space', () async {
      final classId = await makeClass(capacity: 1);
      await db.classDao.book(classId: classId, memberId: memberId);

      final other = await db.profileDao.createMember(fullName: 'Waiting');
      expect(
        await db.classDao.book(classId: classId, memberId: other),
        BookingResult.full,
      );

      await db.classDao.cancelBooking(classId: classId, memberId: memberId);

      expect(await db.classDao.bookedCount(classId), 0);
      expect(
        await db.classDao.book(classId: classId, memberId: other),
        BookingResult.booked,
      );
    });

    test('re-booking revives the cancelled row rather than inserting',
        () async {
      // A second insert would violate the unique (class, member) index that
      // both the local schema and the server enforce.
      final classId = await makeClass();

      await db.classDao.book(classId: classId, memberId: memberId);
      await db.classDao.cancelBooking(classId: classId, memberId: memberId);
      await db.classDao.book(classId: classId, memberId: memberId);

      final rows = await db.select(db.classBookings).get();
      expect(rows, hasLength(1), reason: 'one booking row per member per class');
      expect(rows.single.status, 'booked');
    });

    test('a cancelled booking still marks the row dirty so it syncs', () async {
      final classId = await makeClass();
      await db.classDao.book(classId: classId, memberId: memberId);

      final booked = await db.classDao.bookingFor(
        classId: classId,
        memberId: memberId,
      );
      await db.classDao.clearDirty([booked!.id]);

      await db.classDao.cancelBooking(classId: classId, memberId: memberId);

      final rows = await db.select(db.classBookings).get();
      expect(rows.single.isDirty, isTrue);
    });

    test('bookings are scoped to their member', () async {
      final classId = await makeClass();
      final other = await db.profileDao.createMember(fullName: 'Other');

      await db.classDao.book(classId: classId, memberId: memberId);

      expect(await db.classDao.watchBookingsFor(other).first, isEmpty);
      expect(await db.classDao.watchBookingsFor(memberId).first, hasLength(1));
    });

    test('the roster lists only active bookings', () async {
      final classId = await makeClass();
      final other = await db.profileDao.createMember(fullName: 'Other');

      await db.classDao.book(classId: classId, memberId: memberId);
      await db.classDao.book(classId: classId, memberId: other);
      await db.classDao.cancelBooking(classId: classId, memberId: other);

      final roster = await db.classDao.rosterFor(classId);
      expect(roster, hasLength(1));
      expect(roster.single.memberId, memberId);
    });
  });

  group('cancellation', () {
    test('cancelling a class keeps its bookings visible', () async {
      // A member must see that the class they booked was cancelled, not find
      // it silently gone.
      final classId = await makeClass();
      await db.classDao.book(classId: classId, memberId: memberId);

      await db.classDao.cancelClass(classId);

      final bookings = await db.classDao.watchBookingsFor(memberId).first;
      expect(bookings, hasLength(1));
      expect(bookings.single.status, 'booked');

      final gymClass = await db.classDao.classById(classId);
      expect(gymClass!.status, 'cancelled');
    });

    test('a cancelled class can be restored', () async {
      final classId = await makeClass();
      await db.classDao.cancelClass(classId);
      await db.classDao.restoreClass(classId);

      expect(
        await db.classDao.book(classId: classId, memberId: memberId),
        BookingResult.booked,
      );
    });

    test('a cancellation from the server is not pushed back', () async {
      // The server already knows. Marking the row dirty would upload its own
      // decision straight back to it.
      final classId = await makeClass();
      await db.classDao.clearDirty([classId]);

      await db.classDao.applyRemoteCancellation(classId);

      final gymClass = await db.classDao.classById(classId);
      expect(gymClass!.status, 'cancelled');
      expect(gymClass.isDirty, isFalse);
    });

    test('a local cancellation IS pushed', () async {
      final classId = await makeClass();
      await db.classDao.clearDirty([classId]);

      await db.classDao.cancelClass(classId);

      final gymClass = await db.classDao.classById(classId);
      expect(gymClass!.isDirty, isTrue);
    });

    test('a server rejection is recorded without re-uploading', () async {
      // The row records a decision the server already made, so marking it
      // dirty would push that decision straight back.
      final classId = await makeClass();
      await db.classDao.book(classId: classId, memberId: memberId);
      final booking = await db.classDao.bookingFor(
        classId: classId,
        memberId: memberId,
      );

      await db.classDao.markBookingRejected(booking!.id);

      final rows = await db.select(db.classBookings).get();
      expect(rows.single.status, 'rejected');
      expect(rows.single.isDirty, isFalse);

      final rejected = await db.classDao
          .watchRejectedBookings(memberId)
          .first;
      expect(rejected, hasLength(1));
    });

    test('a rejected booking does not occupy a space', () async {
      final classId = await makeClass(capacity: 1);
      await db.classDao.book(classId: classId, memberId: memberId);
      final booking = await db.classDao.bookingFor(
        classId: classId,
        memberId: memberId,
      );

      await db.classDao.markBookingRejected(booking!.id);

      expect(await db.classDao.bookedCount(classId), 0);
    });
  });

  group('ClassWithBookings', () {
    test('reports spaces left and fullness', () async {
      final classId = await makeClass(capacity: 3);
      await db.classDao.book(classId: classId, memberId: memberId);

      final gymClass = await db.classDao.classById(classId);
      final view = (await db.classDao.withBookings(
        forClasses: [gymClass!],
        memberId: memberId,
      )).single;

      expect(view.bookedCount, 1);
      expect(view.spacesLeft, 2);
      expect(view.isFull, isFalse);
      expect(view.isBookedByMe, isTrue);
    });

    test('spacesLeft never goes negative', () async {
      // Defensive: a pull could deliver more bookings than the local capacity
      // if an admin reduced it after members booked.
      final classId = await makeClass(capacity: 1);
      final other = await db.profileDao.createMember(fullName: 'Other');
      await db.classDao.book(classId: classId, memberId: memberId);

      await db.classDao.updateClass(
        id: classId,
        name: 'Yoga',
        startsAt: future,
        endsAt: future.add(const Duration(hours: 1)),
        capacity: 0,
      );

      final gymClass = await db.classDao.classById(classId);
      final view = (await db.classDao.withBookings(
        forClasses: [gymClass!],
      )).single;

      expect(view.spacesLeft, 0);
      expect(view.isFull, isTrue);
      expect(other, isNotEmpty);
    });

    test('a cancelled booking is not "booked by me"', () async {
      final classId = await makeClass();
      await db.classDao.book(classId: classId, memberId: memberId);
      await db.classDao.cancelBooking(classId: classId, memberId: memberId);

      final gymClass = await db.classDao.classById(classId);
      final view = (await db.classDao.withBookings(
        forClasses: [gymClass!],
        memberId: memberId,
      )).single;

      expect(view.isBookedByMe, isFalse);
    });
  });
}
