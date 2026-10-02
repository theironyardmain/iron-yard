import 'receipt_store_stub.dart'
    if (dart.library.io) 'receipt_store_io.dart' as impl;

/// Stores receipt photos on the device until sync uploads them.
///
/// Resolved by conditional import: the real implementation uses `dart:io`,
/// which does not exist on web. The browser preview therefore has no receipt
/// capture, which is stated in the UI rather than failing at runtime.
abstract final class ReceiptStore {
  /// Copies [sourcePath] into app storage and returns the stored path.
  ///
  /// The picker's own temp file can be cleared by the OS at any moment, which
  /// would lose the receipt before it ever uploads.
  static Future<String> store(String sourcePath) => impl.store(sourcePath);

  /// Deletes a stored receipt. Missing files are ignored.
  static Future<void> delete(String storedPath) => impl.delete(storedPath);

  /// Whether receipt capture works on this platform.
  static bool get isSupported => impl.isSupported;
}
