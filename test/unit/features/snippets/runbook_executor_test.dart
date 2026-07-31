import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/features/snippets/domain/models/runbook_model.dart';
import 'package:terly2/features/snippets/domain/models/runbook_step_model.dart';
import 'package:terly2/features/snippets/domain/services/runbook_executor.dart';

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

      final result = await executor.executeRunbook(
        runbook,
        (command, timeoutSeconds) async {
          executedCommands.add(command);
          if (command.contains('git pull')) return 'Already up to date.';
          if (command.contains('docker-compose')) return 'Container App Running';
          return 'OK';
        },
      );

      expect(result.overallSuccess, isTrue);
      expect(result.stepResults.length, equals(2));
      expect(executedCommands, equals(['git pull origin main', 'docker-compose up -d --build']));
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

      final result = await executor.executeRunbook(
        runbook,
        (command, timeout) async {
          executedCommands.add(command);
          return 'UNHEALTHY - Connection refused';
        },
      );

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

      final result = await executor.executeRunbook(
        runbook,
        (command, timeout) async {
          actualCommand = command;
          return 'Done';
        },
        variableValues: {
          'AppName': 'AuthService',
          'Env': 'production',
        },
      );

      expect(result.overallSuccess, isTrue);
      expect(actualCommand, equals('echo "Deploying AuthService to production"'));
    });
  });
}
