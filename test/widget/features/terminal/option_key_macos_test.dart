import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm3/xterm.dart';

import 'package:shellvibe/features/terminal/domain/models/terminal_tab_session.dart';
import 'package:shellvibe/features/terminal/presentation/screens/terminal_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Turkish Q layout types @ with Option+Q (⌥Q). The terminal must send the
  // composed character ("@") as text, not an ESC-prefixed key sequence —
  // otherwise the shell receives `^[@` and the @ never appears.
  testWidgets('Option+Q composed @ is sent as text on macOS', (tester) async {
    // Mirrors the app's construction (terminal_tabs_notifier.dart), which
    // passes the runtime platform so Option composes text on macOS.
    final terminal = Terminal(
      maxLines: 100,
      platform: TerminalTargetPlatform.macos,
    );
    final outputs = <String>[];
    terminal.onOutput = outputs.add;

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

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft,
        platform: 'macos');
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.keyQ,
      character: '@',
      platform: 'macos',
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyQ, platform: 'macos');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft, platform: 'macos');

    expect(outputs, contains('@'));
  });

  // Claude Code and other Ink apps turn on xterm's modifyOtherKeys mode 2,
  // under which Option+Q used to go out as `CSI 27;3;64~`, Alt+@, and the @
  // could not be typed in them at all (fixed in xterm3 6.3.2).
  testWidgets('Option+Q types @ under modifyOtherKeys mode 2 on macOS', (
    tester,
  ) async {
    final terminal = Terminal(
      maxLines: 100,
      platform: TerminalTargetPlatform.macos,
    );
    final outputs = <String>[];
    terminal.onOutput = outputs.add;
    terminal.write('\x1b[>4;2m');

    final session = TerminalTabSession(
      id: 'session-1',
      title: 'Local Shell',
      sessionType: TerminalSessionType.local,
      terminal: terminal,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: TerminalScreen(session: session)),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.altLeft,
      platform: 'macos',
    );
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.keyQ,
      character: '@',
      platform: 'macos',
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyQ, platform: 'macos');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft, platform: 'macos');

    expect(outputs, ['@']);
  });
}
