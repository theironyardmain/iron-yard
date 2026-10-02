import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../auth/providers/auth_providers.dart';
import '../data/scan_result.dart';
import '../providers/attendance_providers.dart';
import '../widgets/scan_feedback.dart';

/// Staff QR attendance scanner (brain.md §6.4).
///
/// Writes locally first; sync uploads the batch later.
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );

  ScanOutcome? _outcome;
  bool _processing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    // The camera fires continuously; ignore frames while a scan is in flight
    // or its result is still on screen, so one card is not recorded twice.
    if (_processing || _outcome != null) return;

    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    setState(() => _processing = true);

    final session = ref.read(currentSessionProvider);
    final outcome = await ref
        .read(attendanceRepositoryProvider)
        .handleScan(raw, recordedBy: session?.userId);

    ref.invalidate(todayAttendanceCountProvider);

    if (!mounted) return;
    setState(() {
      _outcome = outcome;
      _processing = false;
    });
  }

  void _reset() => setState(() => _outcome = null);

  @override
  Widget build(BuildContext context) {
    // mobile_scanner needs a real camera. The web build exists only as a
    // development preview (see README), so it says so rather than failing.
    if (kIsWeb) return const _ScannerUnavailable();

    return Stack(
      children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),

        // Aiming frame.
        IgnorePointer(
          child: Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),

        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _TodayCountBadge(),
                IconButton.filledTonal(
                  icon: const Icon(Icons.flashlight_on_outlined),
                  tooltip: 'Torch',
                  onPressed: () => _controller.toggleTorch(),
                ),
              ],
            ),
          ),
        ),

        if (_processing)
          const Positioned.fill(
            child: ColoredBox(
              color: Colors.black38,
              child: Center(child: CircularProgressIndicator()),
            ),
          ),

        if (_outcome != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ScanFeedback(outcome: _outcome!, onDismiss: _reset),
          ),
      ],
    );
  }
}

/// Live count of today's verified check-ins.
class _TodayCountBadge extends ConsumerWidget {
  const _TodayCountBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(todayAttendanceCountProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.people, size: 18, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            count.maybeWhen(
              data: (value) => 'Today: $value',
              orElse: () => 'Today: —',
            ),
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

/// Shown on web, where there is no camera to scan with.
class _ScannerUnavailable extends StatelessWidget {
  const _ScannerUnavailable();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.no_photography_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Scanning needs the app',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'QR attendance runs on the Android app, not the browser preview.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
