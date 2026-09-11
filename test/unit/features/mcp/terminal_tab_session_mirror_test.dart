import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/mcp/data/terminal_tab_session_mirror.dart';
import 'package:shellvibe/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';
import 'package:xterm3/xterm.dart';

/// The tab's whole scrollback, one buffer line per line — the same shape the
/// terminal notifier's own tests read.
String _bufferText(Terminal terminal) {
  final lines = terminal.buffer.lines;
  final text = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    text.write('${lines[i]}\n');
  }
  return text.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late AppDatabase database;
  late TerminalTabsNotifier notifier;
  late TerminalTabSessionMirror mirror;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    notifier = container.read(terminalTabsProvider.notifier);
    mirror = TerminalTabSessionMirror(notifier: notifier);
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  Future<String> openTab() async => (await mirror.open(
    sessionId: 'mcp-1',
    hostLabel: 'prod-web-01',
    cwd: '/home/agent',
    clientName: 'Claude Desktop',
    mode: 'guarded',
    onUserClosed: () {},
  ))!;

  test(
    'the tab opens naming the agent, host and mode it is watching',
    () async {
      final tabId = await openTab();

      final buffer = _bufferText(notifier.tabById(tabId)!.terminal);
      expect(buffer, contains('Claude Desktop'));
      expect(buffer, contains('prod-web-01'));
      expect(buffer, contains('guarded'));
      // The tab is the kill switch, so it has to say so.
      expect(buffer, contains('closing this tab ends the session'));
    },
  );

  test('a command and its outcome are both shown', () async {
    final tabId = await openTab();

    mirror.writeCommand(tabId, command: 'df -h', cwd: '/var/log');
    mirror.writeResult(
      tabId,
      stdout: '/dev/sda1  40G  12G  28G  30%\n',
      stderr: '',
      exitCode: 0,
      durationMs: 106,
    );

    final buffer = _bufferText(notifier.tabById(tabId)!.terminal);
    expect(buffer, contains('df -h'));
    expect(buffer, contains('/var/log'));
    expect(buffer, contains('30%'));
    expect(buffer, contains('exit 0'));
    expect(buffer, contains('106ms'));
  });

  test('output keeps one line per line', () async {
    final tabId = await openTab();

    // The MCP channel is PTY-less, so its output arrives with bare newlines.
    // Written through unchanged they would not return the cursor and every
    // line would start where the last one ended.
    mirror.writeResult(
      tabId,
      stdout: 'first\nsecond\nthird\n',
      stderr: '',
      exitCode: 0,
      durationMs: 5,
    );

    final lines = _bufferText(
      notifier.tabById(tabId)!.terminal,
    ).split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
    expect(lines, containsAllInOrder(['first', 'second', 'third']));
  });

  test('a refused command is shown too, with why', () async {
    final tabId = await openTab();

    mirror.writeCommand(tabId, command: 'rm -rf /', cwd: '/');
    mirror.writeNotice(tabId, 'denied by policy');

    final buffer = _bufferText(notifier.tabById(tabId)!.terminal);
    // What the agent tried matters as much as what it managed to run.
    expect(buffer, contains('rm -rf /'));
    expect(buffer, contains('denied by policy'));
  });

  test('closing the session removes its tab', () async {
    final tabId = await openTab();

    await mirror.close(tabId, reason: 'session closed');

    expect(notifier.tabById(tabId), isNull);
  });

  test('writing to a tab the user already closed is a no-op', () async {
    final tabId = await openTab();
    await notifier.closeTab(tabId);

    // The pool can still be mid-command when the user closes the tab; that
    // must not throw its way back into the session teardown.
    expect(
      () => mirror.writeResult(
        tabId,
        stdout: 'late',
        stderr: '',
        exitCode: 0,
        durationMs: 1,
      ),
      returnsNormally,
    );
  });
}
