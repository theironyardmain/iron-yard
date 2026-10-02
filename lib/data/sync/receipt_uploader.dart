import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/database.dart';
import 'receipt_file.dart';

/// Uploads receipt photos captured offline (brain.md §6.5).
///
/// Runs after the row sync: the payment must exist on the server before its
/// receipt URL is attached to it.
class ReceiptUploader {
  ReceiptUploader({required AppDatabase db, required SupabaseClient client})
    : _db = db,
      _client = client;

  final AppDatabase _db;
  final SupabaseClient _client;

  /// Bucket created in `20260920000005_storage.sql`.
  static const String bucket = 'receipts';

  /// Uploads every pending receipt. Returns how many succeeded.
  ///
  /// Failures are logged and left pending rather than discarded — a receipt is
  /// a financial record and must not be lost because one upload failed.
  Future<int> uploadPending() async {
    if (!ReceiptFile.isSupported) return 0;

    final pending = await _db.paymentDao.awaitingReceiptUpload();
    if (pending.isEmpty) return 0;

    var uploaded = 0;

    for (final payment in pending) {
      final localPath = payment.receiptLocalPath;
      if (localPath == null) continue;

      try {
        final bytes = await ReceiptFile.read(localPath);
        if (bytes == null) {
          // The file vanished — clear the pointer so the app stops retrying a
          // receipt that no longer exists.
          await _db.paymentDao.attachReceiptUrl(payment.id, '');
          debugPrint('Receipt file missing for ${payment.id}');
          continue;
        }

        // Path convention from the storage policies: the first segment is the
        // member id, so ownership is checked without a join.
        final extension = ReceiptFile.extensionOf(localPath);
        final objectPath = '${payment.memberId}/${payment.id}$extension';

        await _client.storage
            .from(bucket)
            .uploadBinary(
              objectPath,
              bytes,
              fileOptions: const FileOptions(upsert: true),
            );

        await _db.paymentDao.attachReceiptUrl(payment.id, objectPath);
        await ReceiptFile.delete(localPath);
        uploaded++;
      } catch (error) {
        debugPrint('Receipt upload failed for ${payment.id}: $error');
      }
    }

    return uploaded;
  }
}
