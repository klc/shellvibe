import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/snippets/domain/models/snippet_model.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_tab_session.dart';
import 'package:shellvibe/features/terminal/domain/services/startup_snippet_sender.dart';
import 'package:xterm3/xterm.dart';

HostModel host({String? startup}) => HostModel(
  id: 'h',
  workspaceId: 'w',
  label: 'web',
  hostname: 'web.example.com',
  startupSnippetId: startup,
  createdAt: DateTime(2026),
);

TerminalTabSession tab({HostModel? host, String? override}) =>
    TerminalTabSession(
      id: 't',
      title: 'web',
      sessionType: TerminalSessionType.ssh,
      host: host,
      terminal: Terminal(),
    )..startupSnippetOverrideId = override;

SnippetModel snippet(String id, String code) =>
    SnippetModel(id: id, workspaceId: 'w', title: 'Snip $id', code: code);

class Harness {
  final snippets = {
    'host': snippet('host', 'cd /srv'),
    'pane': snippet('pane', 'htop'),
    'input': snippet('input', r'cd ${INPUT:dir}'),
    'shell': snippet('shell', r'echo ${HOME}'),
  };
  final sent = <String>[];
  final notices = <String>[];
  int loads = 0;

  late final sender = StartupSnippetSender(
    loadSnippet: (id) async {
      loads++;
      return snippets[id];
    },
    send: (tab, code) => sent.add(code),
    notify: notices.add,
  );
}

void main() {
  group('which snippet applies', () {
    test('a pane override beats the host default', () {
      expect(
        StartupSnippetSender.effectiveSnippetId(
          tab(
            host: host(startup: 'host'),
            override: 'pane',
          ),
        ),
        'pane',
      );
    });

    test('with no override the host default applies', () {
      expect(
        StartupSnippetSender.effectiveSnippetId(
          tab(host: host(startup: 'host')),
        ),
        'host',
      );
    });

    test('with neither there is none', () {
      expect(
        StartupSnippetSender.effectiveSnippetId(tab(host: host())),
        isNull,
      );
      expect(StartupSnippetSender.effectiveSnippetId(tab()), isNull);
    });
  });

  group('sending', () {
    test('sends the pane override, not the host default', () async {
      final h = Harness();
      final outcome = await h.sender.onSessionLive(
        tab(
          host: host(startup: 'host'),
          override: 'pane',
        ),
      );
      expect(outcome, StartupSnippetOutcome.sent);
      expect(h.sent, ['htop']);
    });

    test('sends the host default when the pane has none', () async {
      final h = Harness();
      await h.sender.onSessionLive(tab(host: host(startup: 'host')));
      expect(h.sent, ['cd /srv']);
    });

    test('sends nothing when no snippet applies', () async {
      final h = Harness();
      expect(
        await h.sender.onSessionLive(tab(host: host())),
        StartupSnippetOutcome.none,
      );
      expect(h.sent, isEmpty);
      expect(h.loads, 0);
    });

    test(
      'only the first live moment of a tab sends: a reconnect does not',
      () async {
        final h = Harness();
        final t = tab(host: host(startup: 'host'));
        expect(await h.sender.onSessionLive(t), StartupSnippetOutcome.sent);
        // The session drops and comes back on the same tab.
        expect(
          await h.sender.onSessionLive(t),
          StartupSnippetOutcome.alreadyHandled,
        );
        expect(h.sent, ['cd /srv']);
        expect(h.loads, 1);
      },
    );

    test('a new tab for the same host sends again', () async {
      final h = Harness();
      await h.sender.onSessionLive(tab(host: host(startup: 'host')));
      await h.sender.onSessionLive(tab(host: host(startup: 'host')));
      expect(h.sent, ['cd /srv', 'cd /srv']);
    });

    test('a snippet that was deleted is skipped quietly', () async {
      final h = Harness();
      expect(
        await h.sender.onSessionLive(tab(host: host(startup: 'gone'))),
        StartupSnippetOutcome.none,
      );
      expect(h.sent, isEmpty);
      expect(h.notices, isEmpty);
    });

    test(
      'a snippet that needs input is not sent, and the user is told',
      () async {
        final h = Harness();
        final t = tab(host: host(startup: 'input'));
        expect(
          await h.sender.onSessionLive(t),
          StartupSnippetOutcome.needsInput,
        );
        expect(h.sent, isEmpty);
        expect(h.notices.single, contains('needs input'));
        expect(h.notices.single, contains('Snip input'));
        // Told once: the reconnect does not repeat it.
        await h.sender.onSessionLive(t);
        expect(h.notices, hasLength(1));
      },
    );

    test('a shell variable is not input', () async {
      final h = Harness();
      await h.sender.onSessionLive(tab(host: host(startup: 'shell')));
      expect(h.sent, [r'echo ${HOME}']);
    });
  });
}
