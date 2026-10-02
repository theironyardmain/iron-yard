import 'package:flutter/material.dart';

import 'receipt_image_stub.dart'
    if (dart.library.io) 'receipt_image_io.dart' as impl;

/// Displays a receipt photo from a local file path.
///
/// Conditional import: rendering a local file needs `dart:io`, which the web
/// build does not have.
Widget receiptImage(String path, {double? height}) =>
    impl.receiptImage(path, height: height);
