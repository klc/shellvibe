import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/snippets/domain/models/runbook_model.dart';
import 'package:shellvibe/features/snippets/domain/models/runbook_step_model.dart';
import 'package:shellvibe/features/snippets/domain/services/runbook_executor.dart';

void main() {
  late RunbookExecutor executor;

  setUp(() {
    executor = RunbookExecutor();
  });

  group('RunbookExecutor Unit Tests', () {
    test('Executes all steps successfully when pattern matches', () async {
      final runbook = RunbookModel(
        id: 'rb_1',
        workspaceId: 'ws_1',
        title: 'Deployment Pipeline',
        createdAt: DateTime.now(),
        steps: const [
          RunbookStepModel(
            id: 'step_1',
            runbookId: 'rb_1',
            stepOrder: 1,
            command: 'git pull origin main',
            expectedOutputPattern: r'Already up to date|Updating',
          ),
          RunbookStepModel(
            id: 'step_2',
            runbookId: 'rb_1',
            stepOrder: 2,
            command: 'docker-compose up -d --build',
            expectedOutputPattern: r'Running',
          ),
        ],
      );

      final executedCommands = <String>[];

      final result = await executor.executeRunbook(runbook, (
        command,
        timeoutSeconds,
      ) async {
        executedCommands.add(command);
        if (command.contains('git pull')) return ('Already up to date.', 0);
        if (command.contains('docker-compose')) {
          return ('Container App Running', 0);
        }
        return ('OK', 0);
      });

      expect(result.overallSuccess, isTrue);
      expect(result.stepResults.length, equals(2));
      expect(
        executedCommands,
        equals(['git pull origin main', 'docker-compose up -d --build']),
      );
    });

    test('Stops execution when a step fails pattern match', () async {
      final runbook = RunbookModel(
        id: 'rb_2',
        workspaceId: 'ws_1',
        title: 'Failing Pipeline',
        createdAt: DateTime.now(),
        steps: const [
          RunbookStepModel(
            id: 'step_1',
            runbookId: 'rb_2',
            stepOrder: 1,
            command: 'check_db_status',
            expectedOutputPattern: r'^\s*HEALTHY\s*$',
          ),
          RunbookStepModel(
            id: 'step_2',
            runbookId: 'rb_2',
            stepOrder: 2,
            command: 'deploy_app',
          ),
        ],
      );

      final executedCommands = <String>[];

      final result = await executor.executeRunbook(runbook, (
        command,
        timeout,
      ) async {
        executedCommands.add(command);
        return ('UNHEALTHY - Connection refused', 1);
      });

      expect(result.overallSuccess, isFalse);
      expect(result.failedStep?.id, equals('step_1'));
      expect(result.stepResults.length, equals(1));
      expect(executedCommands.length, equals(1)); // Step 2 never ran
    });

    test('Performs variable substitution across steps', () async {
      final runbook = RunbookModel(
        id: 'rb_3',
        workspaceId: 'ws_1',
        title: 'Parameterized Runbook',
        createdAt: DateTime.now(),
        steps: const [
          RunbookStepModel(
            id: 'step_1',
            runbookId: 'rb_3',
            stepOrder: 1,
            command: r'echo "Deploying ${INPUT:AppName} to ${INPUT:Env}"',
          ),
        ],
      );

      String? actualCommand;

      final result = await executor.executeRunbook(runbook, (
        command,
        timeout,
      ) async {
        actualCommand = command;
        return ('Done', 0);
      }, variableValues: {'AppName': 'AuthService', 'Env': 'production'});

      expect(result.overallSuccess, isTrue);
      expect(
        actualCommand,
        equals('echo "Deploying AuthService to production"'),
      );
    });

    test(
      'Fails a step whose exit code does not match expectedExitCode',
      () async {
        final runbook = RunbookModel(
          id: 'rb_4',
          workspaceId: 'ws_1',
          title: 'Exit Code Gate',
          createdAt: DateTime.now(),
          steps: const [
            RunbookStepModel(
              id: 'step_1',
              runbookId: 'rb_4',
              stepOrder: 1,
              command: 'command_that_fails',
              expectedExitCode: 1,
            ),
          ],
        );

        final result = await executor.executeRunbook(
          runbook,
          (command, timeout) async => ('unused output', 0),
        );

        expect(result.overallSuccess, isFalse);
        expect(result.failedStep?.id, equals('step_1'));
        expect(result.stepResults.single.exitCode, equals(0));
        expect(
          result.stepResults.single.errorMessage,
          contains('does not match expected 1'),
        );
      },
    );

    test(
      'Fails step safely with error message when expectedOutputPattern is invalid regex',
      () async {
        final runbook = RunbookModel(
          id: 'rb_5',
          workspaceId: 'ws_1',
          title: 'Invalid Regex Test',
          createdAt: DateTime.now(),
          steps: const [
            RunbookStepModel(
              id: 'step_1',
              runbookId: 'rb_5',
              stepOrder: 1,
              command: 'echo "test"',
              expectedOutputPattern: r'[unclosed_character_class',
            ),
          ],
        );

        final result = await executor.executeRunbook(
          runbook,
          (command, timeout) async => ('test output', 0),
        );

        expect(result.overallSuccess, isFalse);
        expect(result.failedStep?.id, equals('step_1'));
        expect(
          result.stepResults.single.errorMessage,
          contains('Invalid regex pattern'),
        );
      },
    );

    group('failure policy', () {
      RunbookModel rb(List<RunbookStepModel> steps) => RunbookModel(
        id: 'rb',
        workspaceId: 'w',
        title: 't',
        createdAt: DateTime(2026),
        steps: steps,
      );
      RunbookStepModel step(
        int order, {
        StepFailurePolicy onFailure = StepFailurePolicy.stop,
        int retries = 0,
      }) => RunbookStepModel(
        id: 's$order',
        runbookId: 'rb',
        stepOrder: order,
        command: 'cmd$order',
        onFailure: onFailure,
        retries: retries,
      );
      const fast = RunbookExecutor(retryDelay: Duration(milliseconds: 1));

      test('continue records the failure and runs the next step', () async {
        final ran = <String>[];
        final finished = <RunbookStepResult>[];
        final result = await fast.executeRunbook(
          rb([step(1, onFailure: StepFailurePolicy.continueRun), step(2)]),
          (command, timeout) async {
            ran.add(command);
            return command == 'cmd1' ? ('bad', 1) : ('ok', 0);
          },
          onStepFinished: finished.add,
        );
        expect(ran, ['cmd1', 'cmd2']);
        expect(result.overallSuccess, isFalse);
        expect(result.failedStep!.id, 's1');
        expect(result.stepResults.map((r) => r.success), [false, true]);
        expect(finished, hasLength(2));
      });

      test('stop (the default) ends the run at the failing step', () async {
        final ran = <String>[];
        final result = await fast.executeRunbook(rb([step(1), step(2)]), (
          command,
          timeout,
        ) async {
          ran.add(command);
          return ('bad', 1);
        });
        expect(ran, ['cmd1']);
        expect(result.stepResults, hasLength(1));
      });

      test('retries until success and keeps every attempt', () async {
        var calls = 0;
        final result = await fast.executeRunbook(rb([step(1, retries: 3)]), (
          command,
          timeout,
        ) async {
          calls++;
          return calls < 3 ? ('try $calls', 1) : ('good', 0);
        });
        expect(result.overallSuccess, isTrue);
        final r = result.stepResults.single;
        expect(r.attempts, 3);
        expect(r.attemptLog.map((a) => a.output), ['try 1', 'try 2', 'good']);
        expect(r.output, 'good');
      });

      test('gives up after the retries are spent', () async {
        var calls = 0;
        final result = await fast.executeRunbook(rb([step(1, retries: 2)]), (
          command,
          timeout,
        ) async {
          calls++;
          return ('bad', 1);
        });
        expect(calls, 3);
        expect(result.overallSuccess, isFalse);
        expect(result.stepResults.single.attempts, 3);
      });

      test('a thrown error is retried too', () async {
        var calls = 0;
        final result = await fast.executeRunbook(rb([step(1, retries: 1)]), (
          command,
          timeout,
        ) async {
          calls++;
          if (calls == 1) throw StateError('dropped');
          return ('ok', 0);
        });
        expect(result.overallSuccess, isTrue);
        expect(result.stepResults.single.attempts, 2);
      });

      test('cancel during the retry wait ends it at once', () async {
        final cancel = Completer<void>();
        var cancelled = false;
        const slow = RunbookExecutor(retryDelay: Duration(seconds: 30));
        final statuses = <String>[];
        final future = slow.executeRunbook(
          rb([step(1, retries: 3), step(2)]),
          (command, timeout) async => ('bad', 1),
          isCancelled: () => cancelled,
          cancelSignal: cancel.future,
          onProgress: (step, status) => statuses.add('${step.id}:$status'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        cancelled = true;
        cancel.complete();
        final result = await future.timeout(const Duration(seconds: 2));
        expect(result.cancelled, isTrue);
        expect(statuses, containsAll(['s1:cancelled', 's2:cancelled']));
      });

      test('step results carry the substituted command', () async {
        final result = await fast.executeRunbook(
          rb([
            const RunbookStepModel(
              id: 's1',
              runbookId: 'rb',
              stepOrder: 1,
              command: r'echo ${INPUT:x} ${HOME}',
            ),
          ]),
          (command, timeout) async => ('', 0),
          variableValues: {'x': 'hi'},
        );
        expect(result.stepResults.single.command, r'echo hi ${HOME}');
      });
    });

    group('step kinds', () {
      RunbookModel rb(List<RunbookStepModel> steps) => RunbookModel(
        id: 'rb',
        workspaceId: 'w',
        title: 't',
        createdAt: DateTime(2026),
        steps: steps,
      );
      RunbookStepModel step(
        int order,
        String command, {
        StepKind kind = StepKind.command,
        String? snippetId,
        int retries = 0,
      }) => RunbookStepModel(
        id: 's$order',
        runbookId: 'rb',
        stepOrder: order,
        command: command,
        kind: kind,
        snippetId: snippetId,
        retries: retries,
      );
      const fast = RunbookExecutor(retryDelay: Duration(milliseconds: 1));

      test(
        'a snippet step runs the snippet as it is now, with input values',
        () async {
          final ran = <String>[];
          var code = r'echo v1 ${INPUT:who}';
          final result = await fast.executeRunbook(
            rb([
              step(
                1,
                '# snippet: Greet',
                kind: StepKind.snippet,
                snippetId: 'sn',
              ),
            ]),
            (command, timeout) async {
              ran.add(command);
              return ('', 0);
            },
            variableValues: {'who': 'me'},
            resolveSnippet: (id) async => id == 'sn' ? code : null,
          );
          expect(result.overallSuccess, isTrue);
          expect(ran, ['echo v1 me']);
          expect(result.stepResults.single.command, 'echo v1 me');

          // Edited since: the next run uses the new code.
          code = 'echo v2';
          ran.clear();
          await fast.executeRunbook(
            rb([
              step(
                1,
                '# snippet: Greet',
                kind: StepKind.snippet,
                snippetId: 'sn',
              ),
            ]),
            (command, timeout) async {
              ran.add(command);
              return ('', 0);
            },
            resolveSnippet: (id) async => code,
          );
          expect(ran, ['echo v2']);
        },
      );

      test(
        'a deleted snippet fails the step clearly and runs nothing',
        () async {
          var calls = 0;
          final result = await fast.executeRunbook(
            rb([
              step(
                1,
                '# snippet: Gone',
                kind: StepKind.snippet,
                snippetId: null,
                retries: 3,
              ),
              step(2, 'after'),
            ]),
            (command, timeout) async {
              calls++;
              return ('', 0);
            },
            resolveSnippet: (id) async => null,
          );
          expect(calls, 0);
          expect(result.overallSuccess, isFalse);
          expect(result.stepResults.single.errorMessage, contains('deleted'));
          // Not retried: the snippet will not come back in two seconds.
          expect(result.stepResults.single.attempts, 1);
        },
      );

      test('a snippet id that no longer resolves fails the same way', () async {
        final result = await fast.executeRunbook(
          rb([step(1, '#', kind: StepKind.snippet, snippetId: 'gone')]),
          (command, timeout) async => ('', 0),
          resolveSnippet: (id) async => null,
        );
        expect(result.stepResults.single.errorMessage, contains('deleted'));
      });

      test('an approval step waits until it is approved', () async {
        final gate = Completer<bool>();
        final ran = <String>[];
        final gated = <String>[];
        final future = fast.executeRunbook(
          rb([
            step(1, 'before'),
            step(2, 'Check the dashboards', kind: StepKind.approval),
            step(3, 'after'),
          ]),
          (command, timeout) async {
            ran.add(command);
            return ('', 0);
          },
          awaitApproval: (s) {
            gated.add(s.id);
            return gate.future;
          },
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(ran, ['before']);
        expect(gated, ['s2']);

        gate.complete(true);
        final result = await future;
        expect(ran, ['before', 'after']);
        expect(result.overallSuccess, isTrue);
        expect(result.stepResults[1].success, isTrue);
        expect(result.stepResults[1].command, 'Check the dashboards');
      });

      test(
        'an approval with nobody to approve it fails rather than passing',
        () async {
          final result = await fast.executeRunbook(
            rb([step(1, 'Sure?', kind: StepKind.approval), step(2, 'next')]),
            (command, timeout) async => ('', 0),
          );
          expect(result.overallSuccess, isFalse);
          expect(result.stepResults, hasLength(1));
        },
      );

      test('cancelling while waiting does not hang', () async {
        final gate = Completer<bool>();
        var cancelled = false;
        final statuses = <String>[];
        final future = fast.executeRunbook(
          rb([step(1, 'Sure?', kind: StepKind.approval), step(2, 'next')]),
          (command, timeout) async => ('', 0),
          awaitApproval: (s) => gate.future,
          isCancelled: () => cancelled,
          onProgress: (s, status) => statuses.add('${s.id}:$status'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        cancelled = true;
        gate.complete(false);
        final result = await future.timeout(const Duration(seconds: 2));
        expect(result.cancelled, isTrue);
        expect(statuses, containsAll(['s1:cancelled', 's2:cancelled']));
      });
    });
  });
}
