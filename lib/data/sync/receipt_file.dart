import 'dart:typed_data';

import 'receipt_file_stub.dart'
    if (dart.library.io) 'receipt_file_io.dart' as impl;

/// Reads receipt files for upload.
///
/// Conditional import: file access needs `dart:io`, absent on web.
abstract final class ReceiptFile {
  static bool get isSupported => impl.isSupported;

  /// Reads a stored receipt, or null if the file is gone.
  static Future<Uint8List?> read(String path) => impl.read(path);

  static Future<void> delete(String path) => impl.delete(path);

  /// File extension including the dot, defaulting to `.jpg`.
  static String extensionOf(String path) {
    final index = path.lastIndexOf('.');
    if (index < 0 || index == path.length - 1) return '.jpg';
    return path.substring(index);
  }
}
