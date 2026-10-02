const bool isSupported = false;

Future<String> store(String sourcePath) async => throw UnsupportedError(
  'Receipt capture needs the Android app; it is not available on web.',
);

Future<void> delete(String storedPath) async {
  // Nothing is stored on web, so there is nothing to remove.
}
