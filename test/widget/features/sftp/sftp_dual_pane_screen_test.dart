import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/features/sftp/presentation/screens/sftp_dual_pane_screen.dart';

void main() {
  group('SftpDualPaneScreen Widget Tests', () {
    testWidgets('renders local workstation and remote sftp panes', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SftpDualPaneScreen(hostLabel: 'Test Server'),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('SFTP: Test Server'), findsOneWidget);
      expect(find.text('Local Workstation'), findsOneWidget);
      expect(find.text('Remote (Disconnected)'), findsOneWidget);
    });
  });
}
