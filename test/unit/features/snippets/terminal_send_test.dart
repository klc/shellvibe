import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/snippets/presentation/widgets/terminal_send.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_tab_session.dart';
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

HostModel host(String id) => HostModel(
  id: id,
  workspaceId: 'w',
  label: 'Host $id',
  hostname: '$id.example.com',
  username: 'ops',
  port: 2200,
  createdAt: DateTime(2026),
);

void main() {
  group('fillBuiltinsFor', () {
    test("fills \${SV:...} from the pane's own host", () {
      const code = r'ssh ${SV:USER}@${SV:HOST} -p ${SV:PORT}';
      // Each broadcast pane is filled from itself, not from the active one.
      expect(
        fillBuiltinsFor(tab('a', host: host('a')), code).code,
        'ssh ops@a.example.com -p 2200',
      );
      final filled = fillBuiltinsFor(tab('b', host: host('b')), code);
      expect(filled.code, 'ssh ops@b.example.com -p 2200');
      expect(filled.unresolved, isFalse);
    });

    test('leaves them as written when the pane has no host, and says so', () {
      final filled = fillBuiltinsFor(tab('local'), r'echo ${SV:HOST}');
      expect(filled.code, r'echo ${SV:HOST}');
      expect(filled.unresolved, isTrue);
    });

    test('code without them is untouched and not flagged', () {
      final filled = fillBuiltinsFor(tab('local'), r'echo ${HOME}');
      expect(filled.code, r'echo ${HOME}');
      expect(filled.unresolved, isFalse);
    });
  });
}
