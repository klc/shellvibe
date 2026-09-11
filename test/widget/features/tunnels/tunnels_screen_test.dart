import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/features/tunnels/presentation/screens/tunnels_screen.dart';

void main() {
  group('TunnelsScreen Widget Tests', () {
    testWidgets('renders title and empty rules placeholder when no rules exist', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: const MaterialApp(
              home: TunnelsScreen(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Tunnels'), findsOneWidget);
      expect(find.text('Add tunnel'), findsOneWidget);
    });
  });
}
