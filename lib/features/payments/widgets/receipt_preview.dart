import 'package:flutter/material.dart';

import 'receipt_image.dart';

/// Capture, preview and remove a receipt photo (brain.md §6.5).
class ReceiptPreview extends StatelessWidget {
  const ReceiptPreview({
    required this.onCapture,
    required this.onPick,
    required this.onRemove,
    this.path,
    this.enabled = true,
    super.key,
  });

  final String? path;
  final bool enabled;
  final VoidCallback onCapture;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = path;

    if (current == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                Icons.receipt_long_outlined,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Receipt photo',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.photo_camera_outlined),
                tooltip: 'Take photo',
                onPressed: enabled ? onCapture : null,
              ),
              IconButton(
                icon: const Icon(Icons.photo_library_outlined),
                tooltip: 'Choose from gallery',
                onPressed: enabled ? onPick : null,
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: receiptImage(current, height: 180),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Receipt attached',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: enabled ? onRemove : null,
                  child: const Text('Remove'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
