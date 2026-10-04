import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/snippets/domain/models/runbook_model.dart';
import 'package:shellvibe/features/snippets/domain/models/runbook_step_model.dart';
import 'package:shellvibe/features/templates/domain/models/template_model.dart';
import 'package:shellvibe/features/templates/domain/models/template_pane_model.dart';
import 'package:shellvibe/features/templates/domain/services/template_on_open.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_tab_session.dart';

HostModel host(String id) => HostModel(
  id: id,
  workspaceId: 'w',
  label: id,
  hostname: '$id.example.com',
  createdAt: DateTime(2026),
);

RunbookModel runbook(String command) => RunbookModel(
  id: 'rb',
  workspaceId: 'w',
  title: 'Check',
  createdAt: DateTime(2026),
  steps: [
    RunbookStepModel(id: 's', runbookId: 'rb', stepOrder: 1, command: command),
  ],
);

TemplateModel template({
  String? runbookId = 'rb',
  bool confirm = true,
  List<String> hostIds = const ['a', 'b'],
}) => TemplateModel(
  id: 't',
  workspaceId: 'w',
  name: 'Layout',
  createdAt: DateTime(2026),
  onOpenRunbookId: runbookId,
  onOpenConfirm: confirm,
  panes: [
    for (var i = 0; i < hostIds.length; i++)
      TemplatePaneModel(
        id: 'p$i',
        templateId: 't',
        paneOrder: i,
        sessionType: TerminalSessionType.ssh,
        hostId: hostIds[i],
      ),
  ],
);

class Harness {
  bool running = false;
  bool confirmAnswer = true;
  Map<String, String>? inputAnswer = const {'who': 'me'};
  final confirms = <List<String>>[];
  final prompts = <List<String>>[];
  final starts = <(RunbookModel, List<String>, Map<String, String>)>[];
  final notices = <(String, bool)>[];
  void Function()? duringPrompt;

  late final TemplateOnOpen onOpen = TemplateOnOpen(
    isRunning: () => running,
    confirm: (rb, hosts) async {
      confirms.add([for (final h in hosts) h.id]);
      return confirmAnswer;
    },
    promptVariables: (rb, variables) async {
      prompts.add(variables.names);
      duringPrompt?.call();
      return inputAnswer;
    },
    start: (rb, hosts, values) =>
        starts.add((rb, [for (final h in hosts) h.id], values)),
    notify: (message, {offerRunView = false}) =>
        notices.add((message, offerRunView)),
  );

  Future<OnOpenOutcome> run(TemplateModel t, {List<RunbookModel>? runbooks}) =>
      onOpen.run(
        t,
        runbooks: runbooks ?? [runbook('uptime')],
        hostsById: {'a': host('a'), 'b': host('b')},
      );
}

void main() {
  test('a template without an on-open runbook does nothing', () async {
    final h = Harness();
    expect(await h.run(template(runbookId: null)), OnOpenOutcome.notConfigured);
    expect(h.starts, isEmpty);
    expect(h.confirms, isEmpty);
    expect(h.notices, isEmpty);
  });

  test('a runbook that no longer exists is skipped quietly', () async {
    final h = Harness();
    expect(
      await h.run(template(), runbooks: const []),
      OnOpenOutcome.runbookMissing,
    );
    expect(h.starts, isEmpty);
    expect(h.notices, isEmpty);
  });

  test(
    'without an SSH host there is nothing to run on, and it says so',
    () async {
      final h = Harness();
      expect(await h.run(template(hostIds: const [])), OnOpenOutcome.noHosts);
      expect(h.starts, isEmpty);
      expect(h.notices.single.$1, contains('no SSH host'));
    },
  );

  test('a run already in progress is skipped with a notice', () async {
    final h = Harness()..running = true;
    expect(await h.run(template()), OnOpenOutcome.busy);
    expect(h.starts, isEmpty);
    expect(h.confirms, isEmpty);
    expect(h.notices.single.$1, contains('another run is in progress'));
  });

  test('with confirm on, it asks first and a no starts nothing', () async {
    final h = Harness()..confirmAnswer = false;
    expect(await h.run(template()), OnOpenOutcome.declined);
    expect(h.confirms, [
      ['a', 'b'],
    ]);
    expect(h.starts, isEmpty);
  });

  test(
    'confirmed, it starts on the distinct hosts and offers the run view',
    () async {
      final h = Harness();
      expect(
        await h.run(template(hostIds: const ['a', 'b', 'a'])),
        OnOpenOutcome.started,
      );
      expect(h.starts.single.$2, ['a', 'b']);
      expect(h.starts.single.$3, isEmpty);
      expect(h.notices.single.$2, isTrue);
    },
  );

  test('with confirm off it does not ask', () async {
    final h = Harness();
    expect(await h.run(template(confirm: false)), OnOpenOutcome.started);
    expect(h.confirms, isEmpty);
    expect(h.starts, hasLength(1));
  });

  test(
    'a runbook with input variables always prompts, even unconfirmed',
    () async {
      final h = Harness();
      expect(
        await h.run(
          template(confirm: false),
          runbooks: [runbook(r'echo ${INPUT:who}')],
        ),
        OnOpenOutcome.started,
      );
      expect(h.prompts, [
        ['who'],
      ]);
      expect(h.starts.single.$3, {'who': 'me'});
    },
  );

  test('cancelling the prompt starts nothing: never blanks', () async {
    final h = Harness()..inputAnswer = null;
    expect(
      await h.run(template(), runbooks: [runbook(r'echo ${INPUT:who}')]),
      OnOpenOutcome.inputCancelled,
    );
    expect(h.starts, isEmpty);
  });

  test('a run that began while the prompts were up wins', () async {
    final h = Harness();
    h.duringPrompt = () => h.running = true;
    expect(
      await h.run(template(), runbooks: [runbook(r'echo ${INPUT:who}')]),
      OnOpenOutcome.busy,
    );
    expect(h.starts, isEmpty);
  });

  test('a production host asks even when ask-first is off', () async {
    final h = Harness();
    final prod = host('a').copyWith(environment: 'prod');
    final outcome = await h.onOpen.run(
      template(confirm: false),
      runbooks: [runbook('uptime')],
      hostsById: {'a': prod, 'b': host('b')},
    );
    expect(outcome, OnOpenOutcome.started);
    expect(h.confirms, [
      ['a', 'b'],
    ]);
  });

  test('and declining that stops it', () async {
    final h = Harness()..confirmAnswer = false;
    final outcome = await h.onOpen.run(
      template(confirm: false),
      runbooks: [runbook('uptime')],
      hostsById: {
        'a': host('a').copyWith(environment: 'prod'),
        'b': host('b'),
      },
    );
    expect(outcome, OnOpenOutcome.declined);
    expect(h.starts, isEmpty);
  });
}
