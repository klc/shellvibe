import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:xterm3/xterm.dart';

import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/settings/domain/models/app_settings_model.dart';
import 'package:shellvibe/features/settings/presentation/notifiers/settings_notifier.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_tab_session.dart';
import 'package:shellvibe/features/terminal/presentation/screens/terminal_screen.dart';

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

      await container.read(settingsProvider.future);

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

      final settingsNotifier = container.read(settingsProvider.notifier);

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

    testWidgets('Disconnected SSH session shows Reconnect banner', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 100);
      final session = TerminalTabSession(
        id: 'session-reconnect',
        title: 'SSH Host',
        sessionType: TerminalSessionType.ssh,
        host: HostModel(
          id: 'host-1',
          workspaceId: 'ws-1',
          label: 'SSH Host',
          hostname: '127.0.0.1',
          port: 22,
          createdAt: DateTime.now(),
        ),
        terminal: terminal,
        isConnected: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.dark(),
              brightness: Brightness.dark,
            ),
            child: MaterialApp(
              home: Scaffold(
                body: TerminalScreen(session: session),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Connection lost'), findsOneWidget);
      expect(
        find.byKey(const Key('reconnect_session-reconnect')),
        findsOneWidget,
      );
    });

    testWidgets('Remote shell exit shows a neutral banner, not an error', (
      tester,
    ) async {
      final session = TerminalTabSession(
        id: 'session-exit',
        title: 'SSH Host',
        sessionType: TerminalSessionType.ssh,
        host: HostModel(
          id: 'host-1',
          workspaceId: 'ws-1',
          label: 'SSH Host',
          hostname: '127.0.0.1',
          port: 22,
          createdAt: DateTime.now(),
        ),
        terminal: Terminal(maxLines: 100),
        isConnected: false,
        disconnectCause: TerminalDisconnectCause.remoteExit,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.dark(),
              brightness: Brightness.dark,
            ),
            child: MaterialApp(
              home: Scaffold(body: TerminalScreen(session: session)),
            ),
          ),
        ),
      );
      await tester.pump();

      // Typing `exit` is not a failure: same Reconnect affordance, no alarm.
      expect(find.text('Session ended'), findsOneWidget);
      expect(find.text('Connection lost'), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(
        find.byKey(const Key('reconnect_session-exit')),
        findsOneWidget,
      );
    });

    testWidgets('Failed SSH session shows error banner with Reconnect button', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 100);
      final session = TerminalTabSession(
        id: 'session-error',
        title: 'SSH Host',
        sessionType: TerminalSessionType.ssh,
        host: HostModel(
          id: 'host-1',
          workspaceId: 'ws-1',
          label: 'SSH Host',
          hostname: '127.0.0.1',
          port: 22,
          createdAt: DateTime.now(),
        ),
        terminal: terminal,
        isConnected: false,
        errorMessage: 'Authentication failed',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.dark(),
              brightness: Brightness.dark,
            ),
            child: MaterialApp(
              home: Scaffold(
                body: TerminalScreen(session: session),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text('Connection Error: Authentication failed'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('reconnect_session-error')), findsOneWidget);
    });

    testWidgets('Connected SSH session shows no reconnect banner', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 100);
      final session = TerminalTabSession(
        id: 'session-connected',
        title: 'SSH Host',
        sessionType: TerminalSessionType.ssh,
        host: HostModel(
          id: 'host-1',
          workspaceId: 'ws-1',
          label: 'SSH Host',
          hostname: '127.0.0.1',
          port: 22,
          createdAt: DateTime.now(),
        ),
        terminal: terminal,
        isConnected: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.dark(),
              brightness: Brightness.dark,
            ),
            child: MaterialApp(
              home: Scaffold(
                body: TerminalScreen(session: session),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Connection lost'), findsNothing);
      expect(find.textContaining('Connection Error'), findsNothing);
      expect(find.byKey(const Key('reconnect_session-connected')), findsNothing);
    });
  });
}
