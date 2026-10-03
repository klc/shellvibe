import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/snippets/domain/models/runbook_model.dart';
import 'package:shellvibe/features/snippets/domain/models/runbook_step_model.dart';
import 'package:shellvibe/features/snippets/domain/models/snippet_model.dart';
import 'package:shellvibe/features/snippets/domain/models/variable_declaration.dart';
import 'package:shellvibe/features/snippets/domain/services/runbook_markdown.dart';

RunbookModel import(String md) => RunbookMarkdown.import(md, workspaceId: 'ws');

Object? Function() importError(String md) =>
    () => RunbookMarkdown.import(md, workspaceId: 'ws');

void main() {
  RunbookStepModel step(
    int order,
    String command, {
    StepKind kind = StepKind.command,
    int exit = 0,
    String? pattern,
    StepFailurePolicy onFailure = StepFailurePolicy.stop,
    int retries = 0,
    int timeout = 30,
    String? snippetId,
  }) => RunbookStepModel(
    id: 'id$order',
    runbookId: 'rb',
    stepOrder: order,
    command: command,
    kind: kind,
    expectedExitCode: exit,
    expectedOutputPattern: pattern,
    onFailure: onFailure,
    retries: retries,
    timeoutSeconds: timeout,
    snippetId: snippetId,
  );

  final original = RunbookModel(
    id: 'rb',
    workspaceId: 'w',
    title: 'Release: "v2" — café',
    description: 'Ships it.\nCarefully.',
    createdAt: DateTime(2026),
    tags: const ['ops', 'release'],
    variables: const [
      VariableDeclaration(
        name: 'env',
        type: VariableType.enumeration,
        options: ['staging', 'prod'],
        defaultValue: 'staging',
        description: 'Where it goes',
      ),
      VariableDeclaration(name: 'token', type: VariableType.secret),
    ],
    steps: [
      step(1, r'deploy ${INPUT:env}'),
      step(
        2,
        'systemctl restart app',
        exit: 3,
        onFailure: StepFailurePolicy.continueRun,
        retries: 2,
        timeout: 90,
        pattern: r'active \(running\)',
      ),
      step(3, 'Check the dashboards,\nthen continue', kind: StepKind.approval),
      step(4, 'echo "```" && cat <<EOF\nline\nEOF'),
    ],
  );

  group('export', () {
    test(
      'writes frontmatter, option-carrying sh blocks and an approval quote',
      () {
        final md = RunbookMarkdown.export(original);
        expect(md, startsWith('---\ntitle: '));
        expect(md, contains('tags: ["ops","release"]'));
        expect(md, contains('defaults: {'));
        expect(md, contains('```sh {"name":"step-1"}\n'));
        expect(
          md,
          contains(
            '"name":"step-2","expectedExitCode":3,"onFailure":"continue",'
            '"retries":2,"timeout":90,"expectedOutput":"active \\\\(running\\\\)"',
          ),
        );
        expect(
          md,
          contains('> [!approval] Check the dashboards,\n> then continue'),
        );
      },
    );

    test('a command holding backticks gets a longer fence', () {
      final md = RunbookMarkdown.export(original);
      expect(md, contains('````sh '));
    });

    test('a snippet step is exported inline as its current code, noted', () {
      final book = original.copyWith(
        steps: [
          step(1, '# snippet: Greet', kind: StepKind.snippet, snippetId: 'sn'),
        ],
      );
      final md = RunbookMarkdown.export(
        book,
        snippets: {
          'sn': const SnippetModel(
            id: 'sn',
            workspaceId: 'w',
            title: 'Greet',
            code: 'echo hello',
          ),
        },
      );
      expect(md, contains('<!-- Snippet step, exported inline'));
      expect(md, contains('echo hello'));
      expect(md, isNot(contains('# snippet: Greet')));
      // It comes back as an ordinary command.
      expect(import(md).steps.single.command, 'echo hello');
      expect(import(md).steps.single.kind, StepKind.command);
    });

    test('a deleted snippet falls back to the step\'s own text', () {
      final md = RunbookMarkdown.export(
        original.copyWith(
          steps: [
            step(1, '# snippet: Gone', kind: StepKind.snippet, snippetId: 'x'),
          ],
        ),
      );
      expect(import(md).steps.single.command, '# snippet: Gone');
    });
  });

  group('round trip', () {
    test('export then import gives the same runbook, modulo ids', () {
      final back = import(RunbookMarkdown.export(original));

      expect(back.title, original.title);
      expect(back.description, original.description);
      expect(back.tags, original.tags);
      expect(back.workspaceId, 'ws');
      expect(
        back.variables.map((v) => v.toJson()),
        original.variables.map((v) => v.toJson()),
      );
      expect(back.steps, hasLength(original.steps.length));
      for (final (i, expected) in original.steps.indexed) {
        final got = back.steps[i];
        expect(got.stepOrder, expected.stepOrder);
        expect(got.kind, expected.kind);
        expect(got.command, expected.command);
        expect(got.expectedExitCode, expected.expectedExitCode);
        expect(got.expectedOutputPattern, expected.expectedOutputPattern);
        expect(got.onFailure, expected.onFailure);
        expect(got.retries, expected.retries);
        expect(got.timeoutSeconds, expected.timeoutSeconds);
      }
    });

    test('ids are fresh: an import never collides with the original', () {
      final back = import(RunbookMarkdown.export(original));
      expect(back.id, isNot(original.id));
      expect(
        back.steps
            .map((s) => s.id)
            .toSet()
            .intersection(original.steps.map((s) => s.id).toSet()),
        isEmpty,
      );
      expect(back.steps.every((s) => s.runbookId == back.id), isTrue);
    });
  });

  group('lenient import', () {
    test('plain sh and bash blocks are steps with the defaults', () {
      final book = import('''
# Nightly checks

Some prose that is ignored.

```sh
uptime
```

```bash
df -h
```

```python
print("not a step")
```

```json
{"also": "ignored"}
```
''');
      expect(book.title, 'Nightly checks');
      expect(book.steps.map((s) => s.command), ['uptime', 'df -h']);
      expect(book.steps.every((s) => s.retries == 0), isTrue);
      expect(book.steps.every((s) => s.timeoutSeconds == 30), isTrue);
      expect(
        book.steps.every((s) => s.onFailure == StepFailurePolicy.stop),
        isTrue,
      );
    });

    test('tilde fences and info strings that are not JSON are accepted', () {
      final book = import('~~~sh interactive=false\necho a\n~~~\n');
      expect(book.steps.single.command, 'echo a');
    });

    test('hand-written frontmatter: plain scalars and a block list', () {
      final book = import('''
---
title: Hand written
description: Plain text
tags:
  - ops
  - "release"
---

```sh
echo hi
```
''');
      expect(book.title, 'Hand written');
      expect(book.description, 'Plain text');
      expect(book.tags, ['ops', 'release']);
    });

    test('the file\'s defaults apply to steps that do not override them', () {
      final book = import('''
---
title: D
defaults: {"retries":2,"onFailure":"continue","timeout":120}
---

```sh
echo a
```

```sh {"retries":0}
echo b
```
''');
      expect(book.steps[0].retries, 2);
      expect(book.steps[0].onFailure, StepFailurePolicy.continueRun);
      expect(book.steps[0].timeoutSeconds, 120);
      expect(book.steps[1].retries, 0);
      expect(book.steps[1].timeoutSeconds, 120);
    });

    test('an empty shell block is skipped, not an error', () {
      final book = import('```sh\n\n```\n```sh\necho a\n```\n');
      expect(book.steps.single.command, 'echo a');
    });

    test('a missing title falls back to a name', () {
      expect(import('```sh\necho a\n```\n').title, 'Imported runbook');
    });
  });

  group('errors are shown, not swallowed', () {
    void fails(String md, String contains) {
      expect(
        importError(md),
        throwsA(
          isA<RunbookMarkdownException>().having(
            (e) => e.message,
            'message',
            contains.isEmpty ? isNotEmpty : stringContainsInOrder([contains]),
          ),
        ),
      );
    }

    test('no steps', () => fails('# Just prose\n', 'No steps found'));
    test(
      'an unclosed frontmatter',
      () => fails('---\ntitle: x\n', 'frontmatter'),
    );
    test(
      'an unclosed code block',
      () => fails('```sh\necho a\n', 'never closed'),
    );
    test(
      'options that are not JSON',
      () => fails('```sh {"retries": }\necho a\n```\n', 'Step 1'),
    );
    test(
      'an unknown onFailure',
      () => fails('```sh {"onFailure":"explode"}\necho a\n```\n', 'onFailure'),
    );
    test(
      'retries out of range',
      () => fails('```sh {"retries":9}\necho a\n```\n', 'retries'),
    );
    test(
      'an invalid regular expression',
      () => fails(
        '```sh {"expectedOutput":"[unclosed"}\necho a\n```\n',
        'regular expression',
      ),
    );
    test(
      'an approval with no message',
      () => fails('> [!approval]\n', 'approval needs a message'),
    );
    test(
      'a frontmatter line that is not key: value',
      () => fails('---\nnot a pair\n---\n```sh\necho\n```\n', 'key: value'),
    );
    test(
      'variables that are not a list',
      () => fails('---\nvariables: 3\n---\n```sh\necho\n```\n', 'variables'),
    );

    test('the step in the message is the one at fault', () {
      expect(
        importError('```sh\necho a\n```\n```sh {"retries":9}\necho b\n```\n'),
        throwsA(
          isA<RunbookMarkdownException>().having(
            (e) => e.message,
            'message',
            startsWith('Step 2'),
          ),
        ),
      );
    });
  });
}
