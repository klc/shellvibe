import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/features/tunnels/presentation/widgets/tunnel_form_dialog.dart';

void main() {
  group('TunnelFormDialog Widget Tests', () {
    testWidgets('renders form fields for creating new port forwarding rule', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: const MaterialApp(
              home: Scaffold(
                body: TunnelFormDialog(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('New Port Forwarding Rule'), findsOneWidget);
      expect(find.text('Local (-L)'), findsOneWidget);
      expect(find.text('Remote (-R)'), findsOneWidget);
      expect(find.text('Dynamic (-D)'), findsOneWidget);
      expect(find.text('Create Rule'), findsOneWidget);
    });
  });
}

