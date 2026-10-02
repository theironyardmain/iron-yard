import 'package:flutter_test/flutter_test.dart';
import 'package:iron_yard/data/local/database.dart';
import 'package:iron_yard/data/sync/row_mapper.dart';
import 'package:iron_yard/data/sync/sync_controller.dart';
import 'package:iron_yard/data/sync/sync_engine.dart';

void main() {
  group('RowMapper.forUpload', () {
    test('strips is_dirty', () {
      // Upload bookkeeping: sending it would mark rows dirty on every device.
      final row = RowMapper.forUpload({
        'id': 'a',
        'is_dirty': true,
        'title': 'Notice',
      });

      expect(row.containsKey('is_dirty'), isFalse);
      expect(row['title'], 'Notice');
    });

    test('strips announcements.is_read', () {
      // Per-device read state. Uploading it would mark one member's
      // announcement read for everyone.
      final row = RowMapper.forUpload({'id': 'a', 'is_read': true});
      expect(row.containsKey('is_read'), isFalse);
    });

    test('strips payments.receipt_local_path', () {
      // A path on this phone, meaningless anywhere else.
      final row = RowMapper.forUpload({
        'id': 'p',
        'receipt_local_path': '/data/user/0/files/r.jpg',
        'receipt_url': 'https://storage/r.jpg',
      });

      expect(row.containsKey('receipt_local_path'), isFalse);
      expect(row['receipt_url'], 'https://storage/r.jpg');
    });

    test('encodes DateTime as ISO-8601 UTC', () {
      final row = RowMapper.forUpload({
        'id': 'a',
        'updated_at': DateTime.utc(2026, 3, 10, 12, 30),
      });

      expect(row['updated_at'], '2026-03-10T12:30:00.000Z');
    });

    test('keeps every other column', () {
      final row = RowMapper.forUpload({
        'id': 'x',
        'amount_minor': 150000,
        'is_deleted': false,
        'notes': null,
      });

      expect(row.keys, containsAll(['id', 'amount_minor', 'is_deleted', 'notes']));
    });

    test('local-only column list matches the migrations', () {
      // supabase/README.md documents exactly these three as absent
      // server-side. A mismatch here silently drops or corrupts data.
      expect(
        RowMapper.localOnlyColumns,
        {'is_dirty', 'is_read', 'receipt_local_path'},
      );
    });
  });

  group('RowMapper.fromRemote', () {
    test('drops columns this client does not know', () {
      // A server on a newer schema must not break an older client.
      final row = RowMapper.fromRemote(
        {'id': 'a', 'title': 'T', 'brand_new_column': 'surprise'},
        {'id', 'title'},
      );

      expect(row.keys, {'id', 'title'});
    });

    test('never lets the server set a local-only column', () {
      final row = RowMapper.fromRemote(
        {'id': 'a', 'is_read': true, 'is_dirty': true},
        {'id', 'is_read', 'is_dirty'},
      );

      expect(row.keys, {'id'});
    });
  });

  group('RowMapper.decodeValue', () {
    test('parses a timestamp into local time', () {
      final value = RowMapper.decodeValue(
        column: 'updated_at',
        value: '2026-03-10T12:30:00.000Z',
        type: SyncColumnType.dateTime,
      );

      expect(value, isA<DateTime>());
      expect((value! as DateTime).toUtc().hour, 12);
    });

    test('parses a date-only column without shifting the day', () {
      // Parsing "2026-03-10" as a timestamp would apply the device's UTC
      // offset and could move a check-in to the previous or next day.
      final value = RowMapper.decodeValue(
        column: 'attendance_date',
        value: '2026-03-10',
        type: SyncColumnType.dateTime,
      ) as DateTime;

      expect(value.year, 2026);
      expect(value.month, 3);
      expect(value.day, 10);
      expect(value.hour, 0);
    });

    test('handles both date-only columns', () {
      for (final column in ['attendance_date', 'completed_on']) {
        final value =
            RowMapper.decodeValue(
                  column: column,
                  value: '2026-12-31',
                  type: SyncColumnType.dateTime,
                )
                as DateTime;
        expect(value.day, 31, reason: column);
      }
    });

    test('coerces booleans from Postgres and SQLite forms', () {
      for (final input in [true, 1, 'true']) {
        expect(
          RowMapper.decodeValue(
            column: 'is_deleted',
            value: input,
            type: SyncColumnType.boolean,
          ),
          isTrue,
          reason: '$input',
        );
      }

      expect(
        RowMapper.decodeValue(
          column: 'is_deleted',
          value: 0,
          type: SyncColumnType.boolean,
        ),
        isFalse,
      );
    });

    test('passes null straight through', () {
      expect(
        RowMapper.decodeValue(
          column: 'notes',
          value: null,
          type: SyncColumnType.other,
        ),
        isNull,
      );
    });

    test('coerces a numeric string to int', () {
      expect(
        RowMapper.decodeValue(
          column: 'amount_minor',
          value: '150000',
          type: SyncColumnType.integer,
        ),
        150000,
      );
    });
  });

  group('sync table order', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.memory());
    tearDown(() async => db.close());

    test('covers exactly the tables the database says are synced', () {
      final names = syncTablesFor(db).map((t) => t.name).toList();
      expect(names.toSet(), AppDatabase.syncedTableNames.toSet());
      expect(names, hasLength(AppDatabase.syncedTableNames.length));
    });

    test('parents come before their children', () {
      // Upload order matters: a payment referencing a membership must not
      // reach the server first, or the foreign key rejects it.
      final order = syncTablesFor(db).map((t) => t.name).toList();

      void expectBefore(String parent, String child) {
        expect(
          order.indexOf(parent),
          lessThan(order.indexOf(child)),
          reason: '$parent must sync before $child',
        );
      }

      expectBefore('profiles', 'memberships');
      expectBefore('membership_plans', 'memberships');
      expectBefore('memberships', 'invoices');
      expectBefore('invoices', 'payments');
      expectBefore('memberships', 'payments');
      expectBefore('profiles', 'attendance');
      expectBefore('workout_plans', 'workout_exercises');
      expectBefore('workout_exercises', 'exercise_completions');
      expectBefore('trainers', 'classes');
      expectBefore('classes', 'class_bookings');
      expectBefore('equipment_items', 'equipment_service_logs');
      expectBefore('profiles', 'equipment_service_logs');
      expectBefore('diet_plans', 'diet_meals');
      expectBefore('diet_meals', 'diet_food_items');
    });

    test('excludes device-only tables', () {
      final names = syncTablesFor(db).map((t) => t.name).toSet();

      expect(names, isNot(contains('emergency_contacts')));
      expect(names, isNot(contains('sync_queue')));
      expect(names, isNot(contains('sync_state')));
    });

    test('every table exposes an id column', () {
      for (final table in syncTablesFor(db)) {
        expect(
          table.columnNames,
          contains('id'),
          reason: '${table.name} is upserted on id',
        );
      }
    });

    test('every table exposes updated_at for incremental pulls', () {
      for (final table in syncTablesFor(db)) {
        expect(
          table.columnNames,
          contains('updated_at'),
          reason: '${table.name} pulls on updated_at',
        );
      }
    });
  });

  group('RejectionReason', () {
    test('classifies a duplicate attendance conflict', () {
      expect(
        RejectionReason.fromError(
          Exception('duplicate key value violates unique constraint '
              '"uq_attendance_member_day"'),
        ),
        RejectionReason.duplicateAttendance,
      );
    });

    test('classifies a full class from the trigger hint', () {
      expect(
        RejectionReason.fromError(Exception('Class is full (2 of 2 booked)')),
        RejectionReason.classFull,
      );
    });

    test('classifies a cancelled class', () {
      expect(
        RejectionReason.fromError(Exception('Class is cancelled')),
        RejectionReason.classCancelled,
      );
    });

    test('classifies an RLS refusal', () {
      expect(
        RejectionReason.fromError(
          Exception('new row violates row-level security policy'),
        ),
        RejectionReason.permissionDenied,
      );
    });

    test('an unknown error is not permanent, so it will be retried', () {
      final reason = RejectionReason.fromError(Exception('socket closed'));
      expect(reason, RejectionReason.unknown);
      expect(reason.isPermanent, isFalse);
    });

    test('known refusals are permanent and will not be retried', () {
      // A duplicate or a full class never becomes valid; retrying forever
      // would hide the problem from the user.
      for (final reason in [
        RejectionReason.duplicateAttendance,
        RejectionReason.classFull,
        RejectionReason.classCancelled,
        RejectionReason.permissionDenied,
      ]) {
        expect(reason.isPermanent, isTrue, reason: reason.name);
      }
    });

    test('every reason has a message fit to show a user', () {
      for (final reason in RejectionReason.values) {
        expect(reason.message, isNotEmpty);
        expect(reason.message, isNot(contains('Exception')));
        expect(reason.message, isNot(contains('_')));
      }
    });
  });

  group('SyncReport', () {
    test('is clean only with no failures and no rejections', () {
      expect(const SyncReport(pushed: 5, pulled: 3).isClean, isTrue);
      expect(
        const SyncReport(failures: {'payments': 'boom'}).isClean,
        isFalse,
      );
    });
  });

  group('SyncController backoff', () {
    test('grows with consecutive failures and is capped', () {
      expect(SyncController.backoff.first, const Duration(seconds: 30));

      for (var i = 1; i < SyncController.backoff.length; i++) {
        expect(
          SyncController.backoff[i],
          greaterThan(SyncController.backoff[i - 1]),
        );
      }

      // Capped, so a long outage does not push the next attempt hours away.
      expect(
        SyncController.backoff.last,
        lessThanOrEqualTo(const Duration(minutes: 15)),
      );
    });

    test('section syncs are throttled to minutes, not seconds', () {
      // brain.md §4: never on every navigation.
      expect(
        SyncController.sectionThrottle,
        greaterThanOrEqualTo(const Duration(minutes: 1)),
      );
    });
  });

  group('SyncStatus', () {
    test('starts having never synced', () {
      expect(const SyncStatus().hasNeverSynced, isTrue);
    });

    test('copyWith preserves untouched fields', () {
      final status = SyncStatus(
        lastSyncedAt: DateTime(2026, 3, 10),
        consecutiveFailures: 2,
      );

      final updated = status.copyWith(isSyncing: true);

      expect(updated.isSyncing, isTrue);
      expect(updated.lastSyncedAt, DateTime(2026, 3, 10));
      expect(updated.consecutiveFailures, 2);
    });
  });
}
