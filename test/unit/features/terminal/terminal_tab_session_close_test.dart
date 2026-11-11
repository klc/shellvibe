import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/network/ssh_session_manager.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_tab_session.dart';
import 'package:xterm3/xterm.dart';

void main() {
  test('a reconnect during an unfinished closeSessions keeps its new '
      'connection, and the old one still closes', () async {
    final tab = TerminalTabSession(
      id: 'tab-1',
      title: 'web',
      sessionType: TerminalSessionType.ssh,
      terminal: Terminal(),
    );
    final oldJump = _Manager();
    final old = _Manager();
    tab
      ..sshSessionManager = old
      ..jumpSessionManagers = [oldJump];

    // The drop's teardown runs unawaited, so a Reconnect can land in between.
    final closing = tab.closeSessions();
    final fresh = _Manager();
    final freshJump = _Manager();
    tab
      ..sshSessionManager = fresh
      ..jumpSessionManagers = [freshJump];
    await closing;

    expect(old.closed, isTrue);
    expect(oldJump.closed, isTrue);
    expect(tab.sshSessionManager, same(fresh));
    expect(tab.jumpSessionManagers, [freshJump]);
    expect(fresh.closed, isFalse);
    expect(freshJump.closed, isFalse);
  });
}

class _Manager implements SSHSessionManager {
  bool closed = false;

  @override
  Future<void> close() async => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
