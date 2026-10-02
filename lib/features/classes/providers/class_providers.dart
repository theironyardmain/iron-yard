import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/daos/class_dao.dart';
import '../../../data/local/database.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../data/remote/supabase_client.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/class_realtime.dart';

final classDaoProvider = Provider<ClassDao>(
  (ref) => ref.watch(databaseProvider).classDao,
);

/// The week being viewed, as a day offset from this week.
final weekOffsetProvider = StateProvider<int>((ref) => 0);

/// Start of the displayed week (Monday).
DateTime startOfWeek(int offset, [DateTime? now]) {
  final today = now ?? DateTime.now();
  final monday = today.subtract(Duration(days: today.weekday - 1));
  return DateTime(monday.year, monday.month, monday.day + offset * 7);
}

/// Classes in the displayed week.
final weekClassesProvider = StreamProvider<List<ClassesData>>((ref) {
  final offset = ref.watch(weekOffsetProvider);
  final from = startOfWeek(offset);
  final to = from.add(const Duration(days: 7));

  return ref.watch(classDaoProvider).watchInRange(from: from, to: to);
});

/// Upcoming classes, for the member home.
final upcomingClassesProvider = StreamProvider<List<ClassesData>>(
  (ref) => ref.watch(classDaoProvider).watchUpcoming(),
);

/// The week's classes with booking counts and the viewer's own booking.
final weekScheduleProvider = FutureProvider<List<ClassWithBookings>>((
  ref,
) async {
  final classes = await ref.watch(weekClassesProvider.future);
  final memberId = ref.watch(currentSessionProvider)?.userId;

  return ref
      .watch(classDaoProvider)
      .withBookings(forClasses: classes, memberId: memberId);
});

/// The signed-in member's bookings.
final myBookingsProvider = StreamProvider<List<ClassBooking>>((ref) {
  final memberId = ref.watch(currentSessionProvider)?.userId;
  if (memberId == null) return Stream.value(const []);
  return ref.watch(classDaoProvider).watchBookingsFor(memberId);
});

/// Bookings the server refused, so the member can be told (brain.md §10.6).
final rejectedBookingsProvider = StreamProvider<List<ClassBooking>>((ref) {
  final memberId = ref.watch(currentSessionProvider)?.userId;
  if (memberId == null) return Stream.value(const []);
  return ref.watch(classDaoProvider).watchRejectedBookings(memberId);
});

/// Live class-cancellation delivery (brain.md §4).
final classRealtimeProvider = Provider<ClassRealtime>((ref) {
  final service = ClassRealtime(
    client: SupabaseService.client,
    dao: ref.watch(classDaoProvider),
    memberId: ref.watch(currentSessionProvider)?.userId,
  );

  ref.onDispose(service.unsubscribe);
  return service;
});
