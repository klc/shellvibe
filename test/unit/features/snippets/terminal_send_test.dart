import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/snippets/domain/models/run_target.dart';
import 'package:shellvibe/features/snippets/presentation/widgets/terminal_send.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_tab_session.dart';
import 'package:shellvibe/features/terminal/presentation/notifiers/terminal_tabs_state.dart';
import 'package:xterm3/xterm.dart';

TerminalTabSession tab(String id, {HostModel? host, bool prod = false}) =>
    TerminalTabSession(
      id: id,
      title: id,
      sessionType: host == null
          ? TerminalSessionType.local
          : TerminalSessionType.ssh,
      host: host,
      terminal: Terminal(),
    );

HostModel host(String id, {String environment = 'dev'}) => HostModel(
  id: id,
  workspaceId: 'w',
  label: 'Host $id',
  hostname: '$id.example.com',
  username: 'ops',
  port: 2200,
  environment: environment,
  createdAt: DateTime(2026),
);

void main() {
  group('fillPaneBuiltins', () {
    test("fills \${SV:...} from the active pane's host", () {
      final state = TerminalTabsState(
        tabs: [
          tab('a', host: host('a')),
          tab('b', host: host('b')),
        ],
        activeTabId: 'b',
      );
      final filled = fillPaneBuiltins(
        state,
        r'ssh ${SV:USER}@${SV:HOST} -p ${SV:PORT}',
      );
      expect(filled.code, 'ssh ops@b.example.com -p 2200');
      expect(filled.unresolved, isFalse);
    });

    test('leaves them as written when the pane has no host, and says so', () {
      final state = TerminalTabsState(
        tabs: [tab('local')],
        activeTabId: 'local',
      );
      final filled = fillPaneBuiltins(state, r'echo ${SV:HOST}');
      expect(filled.code, r'echo ${SV:HOST}');
      expect(filled.unresolved, isTrue);
    });

    test('code without them is untouched and not flagged', () {
      final state = TerminalTabsState(
        tabs: [tab('local')],
        activeTabId: 'local',
      );
      final filled = fillPaneBuiltins(state, r'echo ${HOME}');
      expect(filled.code, r'echo ${HOME}');
      expect(filled.unresolved, isFalse);
    });
  });

  group('terminalTargetHosts', () {
    final state = TerminalTabsState(
      tabs: [
        tab('a', host: host('a')),
        tab('b', host: host('b', environment: 'prod')),
        tab('local'),
      ],
      activeTabId: 'b',
      selectedPaneIds: const {'a', 'b', 'local'},
    );

    test('the active pane', () {
      expect(
        terminalTargetHosts(
          state,
          const ActivePaneRunTarget(),
        ).map((h) => h.id),
        ['b'],
      );
    });

    test('every selected pane that has a host', () {
      expect(
        terminalTargetHosts(
          state,
          const SelectedPanesRunTarget(),
        ).map((h) => h.id),
        ['a', 'b'],
      );
    });
  });
}
