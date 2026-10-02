import 'package:flutter_test/flutter_test.dart';
import 'package:iron_yard/data/local/daos/equipment_dao.dart';
import 'package:iron_yard/data/local/database.dart';

void main() {
  late AppDatabase db;
  late EquipmentDao dao;

  setUp(() {
    db = AppDatabase.memory();
    dao = db.equipmentDao;
  });

  tearDown(() async => db.close());

  group('create/update', () {
    test('creates equipment with defaults', () async {
      final id = await dao.create(name: 'Treadmill');

      final item = await dao.byId(id);
      expect(item!.name, 'Treadmill');
      expect(item.quantity, 1);
      expect(item.status, 'working');
      expect(item.isDirty, isTrue, reason: 'must sync');
    });

    test('creates equipment with full details', () async {
      final id = await dao.create(
        name: 'Bench press',
        category: 'Strength',
        quantity: 3,
        location: 'Floor 1',
        purchaseDate: DateTime(2025, 1, 1),
        costMinor: 500000,
        serviceIntervalDays: 90,
        notes: 'Heavy duty',
      );

      final item = await dao.byId(id);
      expect(item!.category, 'Strength');
      expect(item.quantity, 3);
      expect(item.location, 'Floor 1');
      expect(item.purchaseDate, DateTime(2025, 1, 1));
      expect(item.costMinor, 500000);
      expect(item.serviceIntervalDays, 90);
      expect(item.notes, 'Heavy duty');
    });

    test('updateItem changes fields', () async {
      final id = await dao.create(name: 'Treadmill', quantity: 1);

      await dao.updateItem(
        id: id,
        name: 'Treadmill Pro',
        quantity: 2,
        location: 'Floor 2',
      );

      final item = await dao.byId(id);
      expect(item!.name, 'Treadmill Pro');
      expect(item.quantity, 2);
      expect(item.location, 'Floor 2');
    });
  });

  group('status', () {
    test('setStatus changes status', () async {
      final id = await dao.create(name: 'Treadmill');
      await dao.setStatus(id, 'under_repair');

      expect((await dao.byId(id))!.status, 'under_repair');
    });

    test('retire soft-deletes', () async {
      final id = await dao.create(name: 'Old rower');
      await dao.retire(id);

      final raw = await (db.select(
        db.equipmentItems,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(raw.isDeleted, isTrue);
      expect(raw.isDirty, isTrue, reason: 'the retirement must sync');
    });
  });

  group('watchAll', () {
    test('excludes retired items by default', () async {
      await dao.create(name: 'Active item');
      final retiredId = await dao.create(name: 'Retired item');
      await dao.setStatus(retiredId, 'retired');

      final list = await dao.watchAll().first;
      expect(list.map((e) => e.name), ['Active item']);
    });

    test('includeRetired shows everything', () async {
      await dao.create(name: 'Active item');
      final retiredId = await dao.create(name: 'Retired item');
      await dao.setStatus(retiredId, 'retired');

      final list = await dao.watchAll(includeRetired: true).first;
      expect(list, hasLength(2));
    });

    test('a soft-deleted (retired-and-purged) item never reappears', () async {
      final id = await dao.create(name: 'Gone');
      await dao.retire(id);

      final list = await dao.watchAll(includeRetired: true).first;
      expect(list, isEmpty);
    });
  });

  group('dueForService', () {
    test('an item never serviced with a schedule is due', () async {
      await dao.create(name: 'Treadmill', serviceIntervalDays: 30);

      final due = await dao.dueForService();
      expect(due, hasLength(1));
    });

    test('an item with no schedule is never due', () async {
      await dao.create(name: 'Yoga mat');

      expect(await dao.dueForService(), isEmpty);
    });

    test('excludes an item serviced within its interval', () async {
      final id = await dao.create(name: 'Treadmill', serviceIntervalDays: 30);
      await dao.logService(
        equipmentId: id,
        description: 'Routine check',
        servicedAt: DateTime.now().subtract(const Duration(days: 5)),
      );

      expect(await dao.dueForService(), isEmpty);
    });

    test('includes an item serviced longer ago than its interval', () async {
      final id = await dao.create(name: 'Treadmill', serviceIntervalDays: 30);
      await dao.logService(
        equipmentId: id,
        description: 'Last service',
        servicedAt: DateTime.now().subtract(const Duration(days: 40)),
      );

      final due = await dao.dueForService();
      expect(due.map((e) => e.id), [id]);
    });

    test('excludes retired equipment even if overdue', () async {
      final id = await dao.create(name: 'Old', serviceIntervalDays: 30);
      await dao.setStatus(id, 'retired');

      expect(await dao.dueForService(), isEmpty);
    });

    test('orders by longest overdue first', () async {
      final recent = await dao.create(name: 'Recent', serviceIntervalDays: 10);
      await dao.logService(
        equipmentId: recent,
        description: 's',
        servicedAt: DateTime.now().subtract(const Duration(days: 15)),
      );

      final overdue = await dao.create(
        name: 'Overdue',
        serviceIntervalDays: 10,
      );
      await dao.logService(
        equipmentId: overdue,
        description: 's',
        servicedAt: DateTime.now().subtract(const Duration(days: 60)),
      );

      final due = await dao.dueForService();
      expect(due.map((e) => e.name), ['Overdue', 'Recent']);
    });
  });

  group('logService', () {
    test('records the event and updates lastServicedAt', () async {
      final id = await dao.create(name: 'Treadmill');
      final when = DateTime(2026, 3, 10);

      await dao.logService(
        equipmentId: id,
        description: 'Belt replaced',
        servicedAt: when,
        costMinor: 20000,
      );

      final item = await dao.byId(id);
      expect(item!.lastServicedAt, when);

      final history = await dao.serviceHistoryFor(id);
      expect(history, hasLength(1));
      expect(history.single.description, 'Belt replaced');
      expect(history.single.costMinor, 20000);
    });

    test('does not move lastServicedAt backwards for an older log entry',
        () async {
      final id = await dao.create(name: 'Treadmill');
      await dao.logService(
        equipmentId: id,
        description: 'Recent',
        servicedAt: DateTime(2026, 3, 10),
      );
      await dao.logService(
        equipmentId: id,
        description: 'Backdated entry',
        servicedAt: DateTime(2026, 1, 1),
      );

      expect((await dao.byId(id))!.lastServicedAt, DateTime(2026, 3, 10));
    });

    test('attributes the log to the staff member who performed it',
        () async {
      final staffId = await db.profileDao.createMember(fullName: 'Tech');
      final id = await dao.create(name: 'Treadmill');

      await dao.logService(
        equipmentId: id,
        description: 'Fixed',
        performedBy: staffId,
      );

      final history = await dao.serviceHistoryFor(id);
      expect(history.single.performedBy, staffId);
    });

    test('history is newest first', () async {
      final id = await dao.create(name: 'Treadmill');
      await dao.logService(
        equipmentId: id,
        description: 'First',
        servicedAt: DateTime(2026, 1, 1),
      );
      await dao.logService(
        equipmentId: id,
        description: 'Second',
        servicedAt: DateTime(2026, 3, 1),
      );

      final history = await dao.serviceHistoryFor(id);
      expect(history.map((h) => h.description), ['Second', 'First']);
    });

    test('is scoped to the equipment item', () async {
      final a = await dao.create(name: 'A');
      final b = await dao.create(name: 'B');
      await dao.logService(equipmentId: a, description: 'For A');

      expect(await dao.serviceHistoryFor(b), isEmpty);
      expect(await dao.serviceHistoryFor(a), hasLength(1));
    });
  });
}
