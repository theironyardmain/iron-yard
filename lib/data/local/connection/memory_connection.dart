import 'package:drift/drift.dart';

import 'memory_connection_stub.dart'
    if (dart.library.ffi) 'memory_connection_native.dart' as impl;

/// An in-memory database for tests.
///
/// Resolved by conditional import: the native implementation pulls in
/// `package:drift/native.dart`, which imports `dart:ffi` and therefore cannot
/// be compiled for the web. Importing it unconditionally breaks
/// `flutter build web` even though it is only ever used by tests.
QueryExecutor openMemoryDatabase() => impl.openMemoryDatabase();
