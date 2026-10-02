import 'package:drift/drift.dart';

/// Web fallback.
///
/// `AppDatabase.memory()` exists for tests, which run on the VM. Reaching this
/// on the web means something asked for an in-memory database in a browser,
/// which is a mistake worth surfacing rather than silently working.
QueryExecutor openMemoryDatabase() => throw UnsupportedError(
  'AppDatabase.memory() is for tests and is not available on the web. '
  'Use AppDatabase() instead, which opens the WASM-backed database.',
);
