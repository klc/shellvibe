import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm2/xterm.dart';

import 'package:terly2/features/settings/domain/models/app_settings_model.dart';
import 'package:terly2/features/settings/presentation/notifiers/settings_notifier.dart';
import 'package:terly2/features/terminal/domain/models/terminal_tab_session.dart';
import 'package:terly2/features/terminal/presentation/screens/terminal_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('TerminalScreen Widget Tests', () {
    testWidgets('Renders TerminalView with active session', (tester) async {
      final terminal = Terminal(maxLines: 100);
      final session = TerminalTabSession(
        id: 'session-1',
        title: 'Local Shell',
        sessionType: TerminalSessionType.local,
        terminal: terminal,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: TerminalScreen(session: session),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(TerminalView), findsOneWidget);
      expect(find.byType(TerminalScreen), findsOneWidget);
    });

    testWidgets('Renders terminal using selected palette settings (Catppuccin, Nord, OLED, Dark)', (tester) async {
      final terminal = Terminal(maxLines: 100);
      final session = TerminalTabSession(
        id: 'session-2',
        title: 'SSH Terminal',
        sessionType: TerminalSessionType.ssh,
        terminal: terminal,
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(settingsNotifierProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: TerminalScreen(session: session),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(TerminalView), findsOneWidget);

      final settingsNotifier = container.read(settingsNotifierProvider.notifier);

      await settingsNotifier.setPalette(AppPalette.catppuccin);
      await tester.pump();
      expect(find.byType(TerminalView), findsOneWidget);

      await settingsNotifier.setPalette(AppPalette.nord);
      await tester.pump();
      expect(find.byType(TerminalView), findsOneWidget);

      await settingsNotifier.setPalette(AppPalette.oled);
      await tester.pump();
      expect(find.byType(TerminalView), findsOneWidget);

      await tester.pumpAndSettle();
    });
  });
}
