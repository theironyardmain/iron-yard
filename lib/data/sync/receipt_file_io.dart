import 'dart:io';
import 'dart:typed_data';

const bool isSupported = true;

Future<Uint8List?> read(String path) async {
  final file = File(path);
  if (!file.existsSync()) return null;
  return file.readAsBytes();
}

Future<void> delete(String path) async {
  final file = File(path);
  if (file.existsSync()) await file.delete();
}
