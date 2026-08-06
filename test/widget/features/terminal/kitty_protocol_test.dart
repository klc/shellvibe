import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm3/xterm.dart';

import 'package:terly2/features/terminal/domain/models/terminal_tab_session.dart';
import 'package:terly2/features/terminal/presentation/screens/terminal_screen.dart';

/// Reproduces the omp CLI handshake: it queries the kitty keyboard protocol
/// (`ESC[?u`) and, when the terminal replies, pushes flags (`ESC[>5u` or
/// `ESC[>7u`) and switches to CSI-u input. Terminal.app never replies, so omp
/// stays in plain mode there — that is why the same CLI works in Terminal.app
/// but misbehaves inside this app's terminal.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(List<String>, Terminal)> pumpTerminal(WidgetTester tester) async {
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
    return (outputs, terminal);
  }

  testWidgets('kitty handshake reply announces mode 0', (tester) async {
    final (outputs, terminal) = await pumpTerminal(tester);
    terminal.write('\x1b[?u');
    expect(outputs, ['\x1b[?0u']);
  });

  testWidgets('plain "/" is sent exactly once in kitty mode', (tester) async {
    final (outputs, terminal) = await pumpTerminal(tester);
    // omp startup handshake, observed via `script` capture of the real CLI.
    terminal.write('\x1b[?u');
    terminal.write('\x1b[>5u'); // push: disambiguate + report event types
    outputs.clear();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.slash,
        character: '/', platform: 'macos');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.slash, platform: 'macos');

    expect(outputs, ['/']);
  });

  testWidgets('Option+Q still types @ in kitty mode', (tester) async {
    final (outputs, terminal) = await pumpTerminal(tester);
    terminal.write('\x1b[?u');
    terminal.write('\x1b[>5u');
    outputs.clear();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft,
        platform: 'macos');
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.keyQ,
      character: '@',
      platform: 'macos',
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyQ, platform: 'macos');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft, platform: 'macos');

    // Option composes text on macOS, so the keystroke is the character — not a
    // CSI-u alt+q report — and the Option key press itself is not reported at
    // this flag level.
    expect(outputs, ['@']);
  });
}
