const bool isSupported = false;

Future<void> share({
  required String csv,
  required String fileName,
  required String subject,
}) async => throw UnsupportedError(
  'CSV export needs the Android app; it is not available in the browser '
  'preview.',
);
