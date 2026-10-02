import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

const bool isSupported = true;

Future<void> share({
  required String csv,
  required String fileName,
  required String subject,
}) async {
  // Written to the temp directory, not app documents: an export is a one-off
  // handoff, not something the app needs to keep.
  final dir = await getTemporaryDirectory();
  final file = File(p.join(dir.path, fileName));
  await file.writeAsString(csv);

  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'text/csv')],
      subject: subject,
    ),
  );
}
