import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:terly2/features/sftp/presentation/screens/sftp_dual_pane_screen.dart';

void main() {
  group('SftpDualPaneScreen Widget Tests', () {
    testWidgets('renders local workstation and remote sftp panes', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: const MaterialApp(
              home: SftpDualPaneScreen(hostLabel: 'Test Server'),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('SFTP: Test Server'), findsOneWidget);
      expect(find.text('Local Workstation'), findsOneWidget);
      expect(find.text('Remote (Disconnected)'), findsOneWidget);
    });

    testWidgets('renders segmented tab control on narrow screens (< 600px)', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: const MaterialApp(
              home: SftpDualPaneScreen(hostLabel: 'Test Server'),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(SegmentedButton<int>), findsOneWidget);
    });
  });
}
