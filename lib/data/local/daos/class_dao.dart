import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/class_tables.dart';
import 'synced_dao.dart';

part 'class_dao.g.dart';

/// The outcome of attempting a booking (brain.md §6.8).
enum BookingResult {
  booked,

  /// The member already holds a booking for this class.
  alreadyBooked,

  /// Locally the class looks full. The server decides definitively on upload.
  full,

  /// The class has been cancelled.
  cancelled,

  /// The class has already started or finished.
  past,
}

/// A class with the booking figures the UI needs.
class ClassWithBookings {
  const ClassWithBookings({
    required this.gymClass,
    required this.bookedCount,
    this.myBooking,
  });

  final ClassesData gymClass;
  final int bookedCount;

  /// The signed-in member's booking, if they hold one.
  final ClassBooking? myBooking;

  int get spacesLeft => (gymClass.capacity - bookedCount).clamp(0, gymClass.capacity);
  bool get isFull => bookedCount >= gymClass.capacity;
  bool get isCancelled => gymClass.status == 'cancelled';
  bool get isBookedByMe => myBooking != null && myBooking!.status == 'booked';
  bool get hasStarted => gymClass.startsAt.isBefore(DateTime.now());
}

/// Classes and bookings (brain.md §6.8).
@DriftAccessor(tables: [Classes, ClassBookings])
class ClassDao extends DatabaseAccessor<AppDatabase>
    with _$ClassDaoMixin, SyncedDaoMixin<AppDatabase, $ClassesTable, ClassesData> {
  ClassDao(super.db);

  @override
  $ClassesTable get table => classes;

  // --- Classes ---

  Future<ClassesData?> classById(String id) {
    return (select(classes)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Upcoming classes, soonest first.
  Stream<List<ClassesData>> watchUpcoming({DateTime? from}) {
    final since = from ?? DateTime.now();
    return (select(classes)
          ..where(
            (t) => t.isDeleted.equals(false) &
                t.startsAt.isBiggerOrEqualValue(since),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.startsAt)]))
        .watch();
  }

  /// Classes in a date range — the weekly schedule view.
  Stream<List<ClassesData>> watchInRange({
    required DateTime from,
    required DateTime to,
  }) {
    return (select(classes)
          ..where(
            (t) => t.isDeleted.equals(false) &
                t.startsAt.isBetweenValues(from, to),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.startsAt)]))
        .watch();
  }

  Future<String> createClass({
    required String name,
    required DateTime startsAt,
    required DateTime endsAt,
    required int capacity,
    String? description,
    String? trainerId,
    String? location,
  }) async {
    final id = Uuid.v4();
    await into(classes).insert(
      ClassesCompanion.insert(
        id: id,
        name: name,
        startsAt: startsAt,
        endsAt: endsAt,
        capacity: capacity,
        description: Value(description),
        trainerId: Value(trainerId),
        location: Value(location),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
    return id;
  }

  Future<void> updateClass({
    required String id,
    required String name,
    required DateTime startsAt,
    required DateTime endsAt,
    required int capacity,
    String? description,
    String? trainerId,
    String? location,
  }) async {
    await (update(classes)..where((t) => t.id.equals(id))).write(
      ClassesCompanion(
        name: Value(name),
        startsAt: Value(startsAt),
        endsAt: Value(endsAt),
        capacity: Value(capacity),
        description: Value(description),
        trainerId: Value(trainerId),
        location: Value(location),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }

  /// Cancels a class.
  ///
  /// Bookings are left as they are rather than deleted: a member needs to see
  /// that the class they booked was cancelled, not find it silently gone.
  /// Cancellation is one of only two Realtime events (brain.md §4).
  Future<void> cancelClass(String id) async {
    await (update(classes)..where((t) => t.id.equals(id))).write(
      ClassesCompanion(
        status: const Value('cancelled'),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }

  /// Applies a cancellation that came from the server.
  ///
  /// Unlike [cancelClass] this leaves the row clean: the server already knows,
  /// and marking it dirty would push its own decision straight back.
  Future<void> applyRemoteCancellation(String id) async {
    await (update(classes)..where((t) => t.id.equals(id))).write(
      ClassesCompanion(
        status: const Value('cancelled'),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(false),
      ),
    );
  }

  Future<void> restoreClass(String id) async {
    await (update(classes)..where((t) => t.id.equals(id))).write(
      ClassesCompanion(
        status: const Value('scheduled'),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }

  Future<void> deleteClass(String id) => softDelete(id);

  // --- Bookings ---

  /// Live booking count for a class.
  Future<int> bookedCount(String classId) async {
    final count = classBookings.id.count();
    final query = selectOnly(classBookings)
      ..addColumns([count])
      ..where(
        classBookings.classId.equals(classId) &
            classBookings.status.equals('booked') &
            classBookings.isDeleted.equals(false),
      );

    return (await query.getSingle()).read(count) ?? 0;
  }

  Future<ClassBooking?> bookingFor({
    required String classId,
    required String memberId,
  }) {
    return (select(classBookings)
          ..where(
            (t) => t.classId.equals(classId) &
                t.memberId.equals(memberId) &
                t.isDeleted.equals(false),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  /// Books a member onto a class.
  ///
  /// The capacity check here is a **fast local answer**, not the decision: two
  /// devices booking offline both see a space, and the server's trigger
  /// serialises them on upload (brain.md §6.8). The loser is surfaced as a
  /// rejection rather than silently dropped.
  Future<BookingResult> book({
    required String classId,
    required String memberId,
    DateTime? at,
  }) async {
    return transaction(() async {
      final gymClass = await classById(classId);
      if (gymClass == null || gymClass.isDeleted) return BookingResult.cancelled;
      if (gymClass.status == 'cancelled') return BookingResult.cancelled;

      final now = at ?? DateTime.now();
      if (gymClass.startsAt.isBefore(now)) return BookingResult.past;

      final existing = await bookingFor(classId: classId, memberId: memberId);

      if (existing != null && existing.status == 'booked') {
        return BookingResult.alreadyBooked;
      }

      final count = await bookedCount(classId);
      if (count >= gymClass.capacity) return BookingResult.full;

      if (existing != null) {
        // Re-book: revive the cancelled row rather than inserting, so the
        // unique (class, member) index is not violated.
        await (update(classBookings)..where((t) => t.id.equals(existing.id)))
            .write(
              ClassBookingsCompanion(
                status: const Value('booked'),
                bookedAt: Value(now),
                updatedAt: Value(DateTime.now()),
                isDirty: const Value(true),
              ),
            );
        return BookingResult.booked;
      }

      await into(classBookings).insert(
        ClassBookingsCompanion.insert(
          id: Uuid.v4(),
          classId: classId,
          memberId: memberId,
          bookedAt: Value(now),
          updatedAt: Value(DateTime.now()),
          isDirty: const Value(true),
        ),
      );
      return BookingResult.booked;
    });
  }

  /// Cancels a member's booking, freeing the space.
  Future<void> cancelBooking({
    required String classId,
    required String memberId,
  }) async {
    final existing = await bookingFor(classId: classId, memberId: memberId);
    if (existing == null) return;

    await (update(classBookings)..where((t) => t.id.equals(existing.id))).write(
      ClassBookingsCompanion(
        status: const Value('cancelled'),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }

  /// A member's bookings, newest class first.
  Stream<List<ClassBooking>> watchBookingsFor(String memberId) {
    return (select(classBookings)
          ..where(
            (t) => t.memberId.equals(memberId) & t.isDeleted.equals(false),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.bookedAt)]))
        .watch();
  }

  /// Everyone booked onto a class — the attendance roster.
  Future<List<ClassBooking>> rosterFor(String classId) {
    return (select(classBookings)
          ..where(
            (t) => t.classId.equals(classId) &
                t.status.equals('booked') &
                t.isDeleted.equals(false),
          ))
        .get();
  }

  /// Bookings the server refused, so the member can be told (brain.md §10.6).
  Stream<List<ClassBooking>> watchRejectedBookings(String memberId) {
    return (select(classBookings)
          ..where(
            (t) => t.memberId.equals(memberId) &
                t.status.equals('rejected') &
                t.isDeleted.equals(false),
          ))
        .watch();
  }

  /// Marks a queued booking as refused by the server.
  Future<void> markBookingRejected(String bookingId) async {
    await (update(classBookings)..where((t) => t.id.equals(bookingId))).write(
      ClassBookingsCompanion(
        status: const Value('rejected'),
        updatedAt: Value(DateTime.now()),
        // Local record of a server decision; nothing to upload.
        isDirty: const Value(false),
      ),
    );
  }

  /// Classes with their booking counts, for the schedule.
  Future<List<ClassWithBookings>> withBookings({
    required List<ClassesData> forClasses,
    String? memberId,
  }) async {
    final result = <ClassWithBookings>[];

    for (final gymClass in forClasses) {
      result.add(
        ClassWithBookings(
          gymClass: gymClass,
          bookedCount: await bookedCount(gymClass.id),
          myBooking: memberId == null
              ? null
              : await bookingFor(classId: gymClass.id, memberId: memberId),
        ),
      );
    }

    return result;
  }
}
