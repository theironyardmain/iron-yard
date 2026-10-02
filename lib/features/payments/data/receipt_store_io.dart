import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const bool isSupported = true;

/// Where receipts wait for upload.
const String _dirName = 'pending_receipts';

Future<String> store(String sourcePath) async {
  final source = File(sourcePath);
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(base.path, _dirName));

  if (!dir.existsSync()) {
    await dir.create(recursive: true);
  }

  final extension = p.extension(sourcePath).isEmpty
      ? '.jpg'
      : p.extension(sourcePath);
  final name = '${DateTime.now().microsecondsSinceEpoch}$extension';
  final destination = p.join(dir.path, name);

  await source.copy(destination);
  return destination;
}

Future<void> delete(String storedPath) async {
  final file = File(storedPath);
  if (file.existsSync()) {
    await file.delete();
  }
}
