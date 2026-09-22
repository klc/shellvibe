import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm3/xterm.dart';

import 'package:shellvibe/app/theme/app_theme.dart';
import 'package:shellvibe/features/settings/domain/models/app_settings_model.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_tab_session.dart';
import 'package:shellvibe/features/terminal/presentation/screens/terminal_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<TerminalTabSession> pumpTerminal(
    WidgetTester tester, {
    required String output,
    ThemeData? theme,
  }) async {
    final terminal = Terminal(maxLines: 200);
    final session = TerminalTabSession(
      id: 'search-session',
      title: 'Local Shell',
      sessionType: TerminalSessionType.local,
      terminal: terminal,
    );
    terminal.write(output);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: theme,
          home: Scaffold(body: TerminalScreen(session: session)),
        ),
      ),
    );
    await tester.pump();
    return session;
  }

  /// The bar is opened the way a user opens it, through the terminal's own key
  /// handling, so the test covers the interception and not just the widget.
  Future<void> pressFind(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
  }

  group('Terminal find bar', () {
    testWidgets('⌘F opens it and Esc closes it', (tester) async {
      await pumpTerminal(tester, output: 'hello world\r\n');

      expect(find.byKey(const Key('terminal_search_field')), findsNothing);

      await pressFind(tester);
      expect(find.byKey(const Key('terminal_search_field')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('terminal_search_field')), findsNothing);
    });

    testWidgets('the field is not boxed in a second, smaller frame', (
      tester,
    ) async {
      // The app theme, whose fields are filled and outlined, is what drew the
      // second frame; the default Material theme would hide the bug.
      await pumpTerminal(
        tester,
        output: 'hello world\r\n',
        theme: AppTheme.buildTheme(
          const AppSettingsModel(),
          brightness: Brightness.dark,
        ),
      );
      await pressFind(tester);

      final field = find.byKey(const Key('terminal_search_field'));
      final decorator = tester.widget<InputDecorator>(
        find.descendant(of: field, matching: find.byType(InputDecorator)),
      );
      expect(decorator.decoration.filled, isFalse);
      expect(decorator.decoration.enabledBorder, InputBorder.none);
      expect(decorator.decoration.focusedBorder, InputBorder.none);
      expect(tester.getSize(field).width, greaterThanOrEqualTo(260));
    });

    testWidgets('counts the matches in the scrollback', (tester) async {
      await pumpTerminal(
        tester,
        output: 'alpha\r\nbeta\r\nalpha\r\ngamma\r\nalpha\r\n',
      );
      await pressFind(tester);

      await tester.enterText(
        find.byKey(const Key('terminal_search_field')),
        'alpha',
      );
      await tester.pumpAndSettle();

      // The newest hit is the one selected, so the counter reads last-of-three.
      expect(find.text('3/3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('terminal_search_previous')));
      await tester.pumpAndSettle();
      expect(find.text('2/3'), findsOneWidget);

      // Walking past the first hit wraps to the last rather than sticking.
      await tester.tap(find.byKey(const Key('terminal_search_previous')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('terminal_search_previous')));
      await tester.pumpAndSettle();
      expect(find.text('3/3'), findsOneWidget);
    });

    testWidgets('says so when nothing matches', (tester) async {
      await pumpTerminal(tester, output: 'alpha\r\n');
      await pressFind(tester);

      await tester.enterText(
        find.byKey(const Key('terminal_search_field')),
        'nothing-here',
      );
      await tester.pumpAndSettle();

      expect(find.text('no hits'), findsOneWidget);
    });

    testWidgets('case sensitivity is a toggle, and it re-runs the search', (
      tester,
    ) async {
      await pumpTerminal(tester, output: 'Alpha\r\nalpha\r\n');
      await pressFind(tester);

      await tester.enterText(
        find.byKey(const Key('terminal_search_field')),
        'alpha',
      );
      await tester.pumpAndSettle();
      expect(find.text('2/2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('terminal_search_case')));
      await tester.pumpAndSettle();
      expect(find.text('1/1'), findsOneWidget);
    });

    testWidgets('highlights every hit, and marks the current one', (
      tester,
    ) async {
      final session = await pumpTerminal(
        tester,
        output: 'alpha\r\nbeta\r\nalpha\r\n',
      );
      await pressFind(tester);
      await tester.enterText(
        find.byKey(const Key('terminal_search_field')),
        'alpha',
      );
      await tester.pumpAndSettle();

      final view = tester.widget<TerminalView>(find.byType(TerminalView));
      final controller = view.controller;
      expect(controller, isNotNull);
      expect(controller!.searchHighlights.length, 2);
      expect(controller.currentSearchHighlight, 1);

      // Closing releases them: a stale highlight would keep painting over
      // whatever the shell prints next.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(controller.searchHighlights, isEmpty);
      expect(session.terminal.buffer.lines.length, greaterThan(0));
    });
  });
}
