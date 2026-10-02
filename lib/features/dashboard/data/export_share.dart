import 'export_share_stub.dart'
    if (dart.library.io) 'export_share_io.dart' as impl;

/// Hands a generated CSV to the user (brain.md §6.3).
///
/// Conditional import: writing a temp file needs `dart:io`. On web the browser
/// downloads it instead.
abstract final class ExportShare {
  static bool get isSupported => impl.isSupported;

  /// Saves [csv] and opens the system share sheet.
  static Future<void> share({
    required String csv,
    required String fileName,
    required String subject,
  }) => impl.share(csv: csv, fileName: fileName, subject: subject);
}
