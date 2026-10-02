import 'package:flutter/material.dart';

/// Web has no receipt capture, so nothing should reach this.
Widget receiptImage(String path, {double? height}) => SizedBox(
  height: height,
  child: const Center(child: Icon(Icons.image_not_supported_outlined)),
);
