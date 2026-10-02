import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'connection/memory_connection.dart';

import '../../core/constants/app_constants.dart';
import 'daos/announcement_dao.dart';
import 'daos/attendance_dao.dart';
import 'daos/class_dao.dart';
import 'daos/equipment_dao.dart';
import 'daos/invoice_dao.dart';
import 'daos/membership_dao.dart';
import 'daos/payment_dao.dart';
import 'daos/plan_dao.dart';
import 'daos/profile_dao.dart';
import 'daos/sync_dao.dart';
import 'tables/attendance_tables.dart';
import 'tables/class_tables.dart';
import 'tables/equipment_tables.dart';
import 'tables/invoice_tables.dart';
import 'tables/plan_tables.dart';
import 'tables/profile_tables.dart';
import 'tables/sync_tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Profiles,
    EmergencyContacts,
    Trainers,
    MembershipPlans,
    Memberships,
    Attendance,
    Payments,
    Invoices,
    WorkoutPlans,
    WorkoutExercises,
    ExerciseCompletions,
    DietPlans,
    Classes,
    ClassBookings,
    Announcements,
    Feedback,
    EquipmentItems,
    EquipmentServiceLogs,
    DietMeals,
    DietFoodItems,
    SyncQueue,
    SyncState,
  ],
  daos: [
    ProfileDao,
    MembershipDao,
    AttendanceDao,
    PaymentDao,
    InvoiceDao,
    PlanDao,
    AnnouncementDao,
    ClassDao,
    EquipmentDao,
    SyncDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? _open());

  /// In-memory database for tests.
  AppDatabase.memory() : super(_openMemory());

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createIndexes();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Invoicing (brain.md §6.5): adds the ledger of what a member owes,
        // settled by one or more Payments rows. No local backfill — existing
        // Payments/Memberships rows predate invoicing and stay as historical
        // records with no linked invoice; the Supabase-side backfill
        // migration is authoritative for reconstructing history server-side.
        await m.createTable(invoices);
        await m.addColumn(payments, payments.invoiceId);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_invoices_member '
          'ON invoices (member_id, status)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_invoices_status '
          "ON invoices (status) WHERE is_deleted = 0 AND status != 'paid'",
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_payments_invoice '
          'ON payments (invoice_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_invoices_updated_at '
          'ON invoices (updated_at)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_invoices_dirty '
          'ON invoices (is_dirty) WHERE is_dirty = 1',
        );
        await batch((b) {
          b.insertAll(syncState, [
            SyncStateCompanion.insert(entityTable: 'invoices'),
          ]);
        });
      }
      if (from < 3) {
        // Equipment tracking (brain.md §6.10): inventory plus a service log.
        await m.createTable(equipmentItems);
        await m.createTable(equipmentServiceLogs);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_equipment_items_updated_at '
          'ON equipment_items (updated_at)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_equipment_items_dirty '
          'ON equipment_items (is_dirty) WHERE is_dirty = 1',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_equipment_service_logs_updated_at '
          'ON equipment_service_logs (updated_at)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_equipment_service_logs_dirty '
          'ON equipment_service_logs (is_dirty) WHERE is_dirty = 1',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_equipment_service_logs_equipment '
          'ON equipment_service_logs (equipment_id, serviced_at)',
        );
        await batch((b) {
          b.insertAll(syncState, [
            SyncStateCompanion.insert(entityTable: 'equipment_items'),
            SyncStateCompanion.insert(entityTable: 'equipment_service_logs'),
          ]);
        });
      }
      if (from < 4) {
        // Body metrics and structured diet plans (brain.md §6.11): height/
        // weight on the profile, snapshotted onto plans at assignment time,
        // bodyweight-relative exercise loads, and diet plans move from a
        // single mealsJson blob to structured meals/food-items. Old diet
        // plans are not migrated — mealsJson stays as a read-only fallback
        // (brain.md §6.11: their free-text lines have no quantity/calorie/
        // macro fields to migrate into).
        await m.addColumn(profiles, profiles.heightCm);
        await m.addColumn(profiles, profiles.weightKg);
        await m.addColumn(workoutPlans, workoutPlans.snapshotHeightCm);
        await m.addColumn(workoutPlans, workoutPlans.snapshotWeightKg);
        await m.addColumn(dietPlans, dietPlans.snapshotHeightCm);
        await m.addColumn(dietPlans, dietPlans.snapshotWeightKg);
        await m.addColumn(dietPlans, dietPlans.activityLevel);
        await m.addColumn(
          workoutExercises,
          workoutExercises.bodyweightPercent,
        );
        await m.createTable(dietMeals);
        await m.createTable(dietFoodItems);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_diet_meals_updated_at '
          'ON diet_meals (updated_at)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_diet_meals_dirty '
          'ON diet_meals (is_dirty) WHERE is_dirty = 1',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_diet_meals_plan '
          'ON diet_meals (plan_id, position)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_diet_food_items_updated_at '
          'ON diet_food_items (updated_at)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_diet_food_items_dirty '
          'ON diet_food_items (is_dirty) WHERE is_dirty = 1',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_diet_food_items_meal '
          'ON diet_food_items (meal_id, position)',
        );
        await batch((b) {
          b.insertAll(syncState, [
            SyncStateCompanion.insert(entityTable: 'diet_meals'),
            SyncStateCompanion.insert(entityTable: 'diet_food_items'),
          ]);
        });
      }
    },
    beforeOpen: (details) async {
      // Drift disables foreign keys by default; without this the references
      // declared on the tables are not actually enforced at runtime.
      await customStatement('PRAGMA foreign_keys = ON');

      if (details.wasCreated) {
        await _seedSyncState();
      }
    },
  );

  /// Indexes for the queries the app actually runs.
  ///
  /// The unique index on attendance is the local half of the duplicate-check-in
  /// rule (brain.md §6.4); the server enforces the same constraint so a batch
  /// arriving from another device cannot create a duplicate either.
  Future<void> _createIndexes() async {
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_member_day '
      'ON attendance (member_id, attendance_date) WHERE is_deleted = 0',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_booking_class_member '
      'ON class_bookings (class_id, member_id) WHERE is_deleted = 0',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_completion_exercise_day '
      'ON exercise_completions (exercise_id, member_id, completed_on) '
      'WHERE is_deleted = 0',
    );

    // Sync pulls filter on updated_at for every table.
    for (final table in syncedTableNames) {
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_${table}_updated_at '
        'ON $table (updated_at)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_${table}_dirty '
        'ON $table (is_dirty) WHERE is_dirty = 1',
      );
    }

    // Foreign-key lookups used on hot screens.
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_memberships_member '
      'ON memberships (member_id, end_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_payments_member '
      'ON payments (member_id, paid_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_payments_invoice '
      'ON payments (invoice_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_invoices_member '
      'ON invoices (member_id, status)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_invoices_status '
      "ON invoices (status) WHERE is_deleted = 0 AND status != 'paid'",
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_attendance_date '
      'ON attendance (attendance_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_classes_starts_at '
      'ON classes (starts_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_equipment_service_logs_equipment '
      'ON equipment_service_logs (equipment_id, serviced_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_diet_meals_plan '
      'ON diet_meals (plan_id, position)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_diet_food_items_meal '
      'ON diet_food_items (meal_id, position)',
    );
  }

  /// Seeds one sync-state row per synced table so the sync engine can iterate
  /// them without null checks.
  Future<void> _seedSyncState() async {
    await batch((b) {
      b.insertAll(syncState, [
        for (final table in syncedTableNames)
          SyncStateCompanion.insert(entityTable: table),
      ]);
    });
  }

  /// Tables that participate in server sync.
  ///
  /// Excludes `emergency_contacts` (device-only by design, brain.md §6.2) and
  /// the two sync bookkeeping tables.
  static const List<String> syncedTableNames = [
    'profiles',
    'trainers',
    'membership_plans',
    'memberships',
    'attendance',
    'payments',
    'invoices',
    'workout_plans',
    'workout_exercises',
    'exercise_completions',
    'diet_plans',
    'classes',
    'class_bookings',
    'announcements',
    'feedback',
    'equipment_items',
    'equipment_service_logs',
    'diet_meals',
    'diet_food_items',
  ];

  /// Wipes every local table.
  ///
  /// Called on sign-out (tasks.md 3.7, owner decision 2026-09-20): the app runs
  /// on a shared front-desk tablet, so member data must not survive a sign-out
  /// for the next person to read.
  ///
  /// Destroys unsynced changes, so callers must check [hasUnsyncedChanges]
  /// first and warn the user.
  Future<void> wipeAllData() async {
    await transaction(() async {
      // Children before parents: foreign keys are enforced.
      for (final table in const [
        'exercise_completions',
        'workout_exercises',
        'workout_plans',
        'diet_food_items',
        'diet_meals',
        'diet_plans',
        'class_bookings',
        'classes',
        'payments',
        'invoices',
        'attendance',
        'memberships',
        'membership_plans',
        'feedback',
        'announcements',
        'equipment_service_logs',
        'equipment_items',
        'trainers',
        'emergency_contacts',
        'profiles',
        'sync_queue',
        'sync_state',
      ]) {
        await customStatement('DELETE FROM $table');
      }
      await _seedSyncState();
    });
  }

  /// Whether any local change has not yet been accepted by the server.
  ///
  /// Checked before [wipeAllData] so a sign-out cannot silently discard an
  /// attendance scan or payment recorded while offline.
  Future<bool> hasUnsyncedChanges() async {
    final pending = await syncDao.pendingCount();
    if (pending > 0) return true;

    for (final table in syncedTableNames) {
      final row = await customSelect(
        'SELECT 1 FROM $table WHERE is_dirty = 1 LIMIT 1',
      ).getSingleOrNull();
      if (row != null) return true;
    }
    return false;
  }

  static QueryExecutor _open() => driftDatabase(
    name: AppConstants.dbName,
    // Web support exists so the app can be previewed with `flutter run -d
    // chrome` without installing an APK. Android remains the shipping target
    // (brain.md §3): local notifications do not work on web at all, so the
    // reminders and daily check-in in §6.7/§6.9 are Android-only.
    //
    // Both files are served from web/ and must stay in step with the drift and
    // sqlite3 versions in pubspec.lock — see README.
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    ),
  );

  static QueryExecutor _openMemory() => openMemoryDatabase();
}
