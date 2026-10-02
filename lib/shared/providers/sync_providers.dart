import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/remote/supabase_client.dart';
import '../../data/sync/receipt_uploader.dart';
import '../../data/sync/sync_controller.dart';
import '../../data/sync/sync_engine.dart';
import 'database_provider.dart';

final syncEngineProvider = Provider<SyncEngine>(
  (ref) => SyncEngine(
    db: ref.watch(databaseProvider),
    client: SupabaseService.client,
  ),
);

final receiptUploaderProvider = Provider<ReceiptUploader>(
  (ref) => ReceiptUploader(
    db: ref.watch(databaseProvider),
    client: SupabaseService.client,
  ),
);

final syncControllerProvider = Provider<SyncController>((ref) {
  final controller = SyncController(
    engine: ref.watch(syncEngineProvider),
    db: ref.watch(databaseProvider),
  );

  controller.start();
  ref.onDispose(controller.dispose);
  return controller;
});

/// Live sync status for the indicator.
final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final controller = ref.watch(syncControllerProvider);
  return controller.statusStream;
});

/// Count of local changes waiting to upload.
final pendingChangesProvider = StreamProvider<int>(
  (ref) => ref.watch(syncDaoProvider).watchPendingCount(),
);

/// Runs a sync and then uploads any pending receipts.
///
/// Receipts go after the rows: the payment must exist on the server before its
/// receipt path is attached.
///
/// Takes a [SyncController] and [ReceiptUploader] directly so it can be called
/// from a widget (`WidgetRef`) or a provider (`Ref`) alike.
Future<SyncReport?> runSyncThenReceipts({
  required SyncController controller,
  required ReceiptUploader uploader,
  required SyncTrigger trigger,
}) async {
  final report = await controller.sync(trigger: trigger);
  if (report != null && !report.hasFailures) {
    await uploader.uploadPending();
  }
  return report;
}
