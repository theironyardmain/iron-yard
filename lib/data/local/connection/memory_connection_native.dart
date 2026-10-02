import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// In-memory database on platforms with `dart:ffi` (the VM, where tests run).
QueryExecutor openMemoryDatabase() =>
    DatabaseConnection(NativeDatabase.memory());
