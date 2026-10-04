import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/snippets/domain/models/runbook_model.dart';
import 'package:shellvibe/features/snippets/domain/models/runbook_step_model.dart';
import 'package:shellvibe/features/snippets/domain/models/snippet_model.dart';
import 'package:shellvibe/features/snippets/domain/models/variable_declaration.dart';
import 'package:shellvibe/features/snippets/domain/services/run_variables.dart';
import 'package:shellvibe/features/snippets/domain/services/runbook_executor.dart';
import 'package:shellvibe/features/snippets/domain/services/snippet_variable_parser.dart';

void main() {
  group('built-in per-host placeholders', () {
    test(r'only ${SV:...} is one; a shell variable is not', () {
      const code = r'ssh ${SV:USER}@${SV:HOST} ${HOST} ${INPUT:x}';
      expect(SnippetVariableParser.extractBuiltins(code), ['USER', 'HOST']);
      expect(SnippetVariableParser.extractVariables(code), ['x']);
    });

    test('substitutes the known names and leaves others as written', () {
      final out = SnippetVariableParser.substituteBuiltins(
        r'${SV:HOST}:${SV:PORT} ${SV:NOPE} ${HOST}',
        {'HOST': 'web', 'PORT': '2222'},
      );
      expect(out, r'web:2222 ${SV:NOPE} ${HOST}');
    });

    test('a host supplies its own details', () {
      final host = HostModel(
        id: 'h',
        workspaceId: 'w',
        label: 'Web 1',
        hostname: 'deploy@web1.example.com',
        port: 2222,
        createdAt: DateTime(2026),
      );
      expect(builtinValuesFor(host), {
        'HOST': 'web1.example.com',
        'HOST_LABEL': 'Web 1',
        // From the hostname's own user@ prefix when no username is set.
        'USER': 'deploy',
        'PORT': '2222',
      });
      expect(builtinValuesFor(host.copyWith(username: 'root'))['USER'], 'root');
    });
  });

  group('what a run asks for', () {
    final snippet = SnippetModel(
      id: 'sn',
      workspaceId: 'w',
      title: 'Greet',
      code: r'echo ${INPUT:who} ${INPUT:token}',
      variables: const [
        VariableDeclaration(name: 'who', description: 'From the snippet'),
        VariableDeclaration(name: 'token', type: VariableType.secret),
      ],
    );

    RunbookModel runbook(List<VariableDeclaration> own) => RunbookModel(
      id: 'rb',
      workspaceId: 'w',
      title: 'rb',
      createdAt: DateTime(2026),
      variables: own,
      steps: const [
        RunbookStepModel(
          id: 'a',
          runbookId: 'rb',
          stepOrder: 1,
          command: r'deploy ${INPUT:env}',
        ),
        RunbookStepModel(
          id: 'b',
          runbookId: 'rb',
          stepOrder: 2,
          command: '# snippet',
          kind: StepKind.snippet,
          snippetId: 'sn',
        ),
        RunbookStepModel(
          id: 'c',
          runbookId: 'rb',
          stepOrder: 3,
          command: r'text with ${INPUT:ignored}',
          kind: StepKind.approval,
        ),
      ],
    );

    test('includes placeholders from snippet steps, not from approvals', () {
      final vars = collectRunVariables(
        runbook(const []),
        snippets: {'sn': snippet},
      );
      expect(vars.names, ['env', 'who', 'token']);
      expect(vars.declarations[1].description, 'From the snippet');
      expect(vars.declarations[2].type, VariableType.secret);
      // Undeclared: required free text.
      expect(vars.declarations[0].type, VariableType.text);
      expect(vars.declarations[0].required, isTrue);
    });

    test("the runbook's own declaration wins over the snippet's", () {
      final vars = collectRunVariables(
        runbook(const [
          VariableDeclaration(
            name: 'who',
            type: VariableType.enumeration,
            options: ['a'],
          ),
        ]),
        snippets: {'sn': snippet},
      );
      expect(vars.declarations[1].type, VariableType.enumeration);
    });

    test('a deleted snippet adds nothing', () {
      expect(collectRunVariables(runbook(const [])).names, ['env']);
    });

    test('only values of secret variables are secrets', () {
      final secrets = secretValuesOf(
        const [
          VariableDeclaration(name: 'a'),
          VariableDeclaration(name: 'b', type: VariableType.secret),
          VariableDeclaration(name: 'c', type: VariableType.secret),
        ],
        {'a': 'plain', 'b': 's3cret', 'c': ''},
      );
      expect(secrets, {'s3cret'});
    });
  });

  group('redactStepResult', () {
    test('masks a secret everywhere it was echoed, longest first', () {
      const step = RunbookStepModel(
        id: 's',
        runbookId: 'rb',
        stepOrder: 1,
        command: 'x',
      );
      final result = RunbookStepResult(
        step: step,
        success: false,
        exitCode: 1,
        output: 'pw=abcdef and abc',
        errorMessage: 'bad abcdef',
        command: 'login abcdef',
        attempts: 2,
        attemptLog: const [StepAttempt(success: false, output: 'try abcdef')],
      );
      final masked = redactStepResult(result, {'abc', 'abcdef'});
      expect(masked.output, 'pw=[redacted] and [redacted]');
      expect(masked.errorMessage, 'bad [redacted]');
      expect(masked.command, 'login [redacted]');
      expect(masked.attemptLog.single.output, 'try [redacted]');
      expect(masked.attempts, 2);
      expect(masked.exitCode, 1);
    });

    test('with no secrets it is the same object', () {
      const step = RunbookStepModel(
        id: 's',
        runbookId: 'rb',
        stepOrder: 1,
        command: 'x',
      );
      final r = RunbookStepResult(step: step, success: true, output: 'o');
      expect(identical(redactStepResult(r, {''}), r), isTrue);
    });
  });
}
