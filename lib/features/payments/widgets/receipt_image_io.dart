import 'dart:io';

import 'package:flutter/material.dart';

Widget receiptImage(String path, {double? height}) {
  return Image.file(
    File(path),
    height: height,
    fit: BoxFit.cover,
    // The stored file can go missing if the device is cleaned up between
    // capture and upload; show a placeholder rather than a red error box.
    errorBuilder: (context, error, stack) => Container(
      height: height,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.broken_image_outlined)),
    ),
  );
}
