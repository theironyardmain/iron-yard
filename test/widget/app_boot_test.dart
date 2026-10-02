import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iron_yard/main.dart';

void main() {
  testWidgets('shows a configuration screen when startup failed', (
    tester,
  ) async {
    // The only path that renders without Supabase or the router: a build with
    // no credentials must say so rather than failing opaquely.
    await tester.pumpWidget(
      const ProviderScope(
        child: IronYardApp(startupError: 'Missing Supabase configuration.'),
      ),
    );

    expect(find.text('Configuration required'), findsOneWidget);
    expect(find.textContaining('Missing Supabase'), findsOneWidget);
  });

  testWidgets('the configuration message is selectable for copying', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: IronYardApp(startupError: 'flutter run --dart-define=...'),
      ),
    );

    expect(find.byType(SelectableText), findsOneWidget);
  });
}
