import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/snippets/domain/models/runbook_model.dart';
import 'package:shellvibe/features/snippets/domain/models/runbook_step_model.dart';
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

TerminalTabSession tab({HostModel? host, String? override, String? runbook}) =>
    TerminalTabSession(
        id: 't',
        title: 'web',
        sessionType: TerminalSessionType.ssh,
        host: host,
        terminal: Terminal(),
      )
      ..startupSnippetOverrideId = override
      ..startupRunbookId = runbook;

RunbookStepModel step(
  int order,
  String command, {
  StepKind kind = StepKind.command,
  String? snippetId,
}) => RunbookStepModel(
  id: 's$order',
  runbookId: 'rb',
  stepOrder: order,
  command: command,
  kind: kind,
  snippetId: snippetId,
);

RunbookModel runbook(String id, List<RunbookStepModel> steps) => RunbookModel(
  id: id,
  workspaceId: 'w',
  title: 'Book $id',
  steps: steps,
  createdAt: DateTime(2026),
);

SnippetModel snippet(String id, String code) =>
    SnippetModel(id: id, workspaceId: 'w', title: 'Snip $id', code: code);

class Harness {
  final snippets = {
    'host': snippet('host', 'cd /srv'),
    'pane': snippet('pane', 'htop'),
    'input': snippet('input', r'cd ${INPUT:dir}'),
    'shell': snippet('shell', r'echo ${HOME}'),
  };
  final runbooks = {
    // Out of order on purpose: steps go out by stepOrder.
    'logs': runbook('logs', [
      step(1, r'tail -f ${SV:HOST}.log'),
      step(0, 'cd /var/www/app'),
    ]),
    'via-snippet': runbook('via-snippet', [
      step(0, 'stale', kind: StepKind.snippet, snippetId: 'pane'),
    ]),
    'gone-snippet': runbook('gone-snippet', [
      step(0, '', kind: StepKind.snippet, snippetId: 'gone'),
    ]),
    'gate': runbook('gate', [
      step(0, 'uptime'),
      step(1, '', kind: StepKind.approval),
    ]),
    'input': runbook('input', [step(0, r'cd ${INPUT:dir}')]),
  };
  final sent = <String>[];
  final notices = <String>[];
  int loads = 0;

  late final sender = StartupSnippetSender(
    loadSnippet: (id) async {
      loads++;
      return snippets[id];
    },
    loadRunbook: (id) async => runbooks[id],
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

  group('startup runbook', () {
    test(
      'replaces the startup snippet, steps in order, one per line',
      () async {
        final h = Harness();
        final outcome = await h.sender.onSessionLive(
          tab(
            host: host(startup: 'host'),
            override: 'pane',
            runbook: 'logs',
          ),
        );
        expect(outcome, StartupSnippetOutcome.sent);
        expect(h.sent, ['cd /var/www/app\ntail -f web.example.com.log']);
      },
    );

    test('a snippet step types the snippet as it is now', () async {
      final h = Harness();
      await h.sender.onSessionLive(tab(host: host(), runbook: 'via-snippet'));
      expect(h.sent, ['htop']);
    });

    test('a deleted runbook falls back to the startup snippet', () async {
      final h = Harness();
      await h.sender.onSessionLive(
        tab(
          host: host(startup: 'host'),
          runbook: 'gone',
        ),
      );
      expect(h.sent, ['cd /srv']);
    });

    for (final (id, why) in [
      ('gate', 'approval'),
      ('gone-snippet', 'deleted'),
    ]) {
      test('$why step: nothing is typed, and the user is told', () async {
        final h = Harness();
        expect(
          await h.sender.onSessionLive(tab(host: host(), runbook: id)),
          StartupSnippetOutcome.blocked,
        );
        expect(h.sent, isEmpty);
        expect(h.notices.single, contains(why));
      });
    }

    test('input is never typed blank', () async {
      final h = Harness();
      expect(
        await h.sender.onSessionLive(tab(host: host(), runbook: 'input')),
        StartupSnippetOutcome.needsInput,
      );
      expect(h.sent, isEmpty);
      expect(h.notices.single, contains('needs input'));
    });
  });
}
