import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/features/tunnels/presentation/screens/tunnels_screen.dart';

void main() {
  group('TunnelsScreen Widget Tests', () {
    testWidgets('renders title and empty rules placeholder when no rules exist', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: TunnelsScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Port Forwarding & Tunnels Matrix'), findsOneWidget);
      expect(find.text('Add Tunnel Rule'), findsOneWidget);
    });
  });
}
