import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/snippets/data/run_providers.dart';
import 'package:shellvibe/features/snippets/domain/services/remote_command_session.dart';
import 'package:shellvibe/features/snippets/presentation/screens/snippets_screen.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

class _FakeSession implements RemoteCommandSession {
  final Future<(String, int)> Function(String command) handler;
  final List<String> ran;
  int closes = 0;

  _FakeSession(this.handler, this.ran);

  @override
  Future<(String, int)> run(String command, Duration timeout) {
    ran.add(command);
    return handler(command);
  }

  @override
  Future<void> interrupt() async {}

  @override
  Future<void> close() async => closes++;
}

class _FakeFactory implements RemoteCommandSessionFactory {
  final Future<(String, int)> Function(String hostId, String command)? handler;
  final String? openError;
  final List<String> ran = [];
  final List<_FakeSession> sessions = [];

  _FakeFactory({this.handler, this.openError});

  @override
  Future<RemoteCommandSession> open(HostModel host) async {
    if (openError != null) throw RemoteCommandException(openError!);
    final session = _FakeSession(
      (command) => handler?.call(host.id, command) ?? Future.value(('ok\n', 0)),
      ran,
    );
    sessions.add(session);
    return session;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.workspacesDao.insertWorkspace(
      WorkspacesCompanion.insert(
        id: 'default',
        name: 'Default Workspace',
        createdAt: DateTime.now(),
      ),
    );
    for (final (id, label, protocol) in [
      ('h1', 'web-1', 'ssh'),
      ('h2', 'web-2', 'ssh'),
      ('hl', 'This Mac', 'local'),
    ]) {
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: id,
          workspaceId: 'default',
          label: label,
          hostname: '$id.example.com',
          protocol: Value.absentIfNull(protocol),
          createdAt: DateTime.now(),
        ),
      );
    }
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedRunbook({String command = 'uptime'}) async {
    await db.runbooksDao.insertRunbook(
      RunbooksCompanion.insert(
        id: 'rb',
        workspaceId: 'default',
        title: 'Health check',
        createdAt: DateTime.now(),
      ),
    );
    await db.runbooksDao.replaceSteps('rb', [
      RunbookStepsCompanion.insert(
        id: 'rs1',
        runbookId: 'rb',
        stepOrder: 1,
        command: command,
      ),
    ]);
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    _FakeFactory factory, {
    AutomationSection section = AutomationSection.runbooks,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          remoteCommandSessionFactoryProvider.overrideWithValue(factory),
        ],
        child: ShadTheme(
          data: ShadThemeData(
            colorScheme: const ShadSlateColorScheme.light(),
            brightness: Brightness.light,
          ),
          child: MaterialApp(home: SnippetsScreen(initialSection: section)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pickHosts(WidgetTester tester, List<String> ids) async {
    for (final id in ids) {
      await tester.tap(find.byKey(Key('run_target_host_$id')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('run_target_confirm')));
    await tester.pumpAndSettle();
  }

  group('Runbook run flow', () {
    testWidgets('runs on the chosen hosts and reports each one', (
      tester,
    ) async {
      await seedRunbook();
      final factory = _FakeFactory();
      await pumpScreen(tester, factory);

      await tester.tap(find.byKey(const Key('runbook_execute_rb')));
      await tester.pumpAndSettle();
      await pickHosts(tester, ['h1', 'h2']);

      expect(find.byKey(const Key('run_result_dialog')), findsOneWidget);
      expect(find.text('2 of 2 hosts succeeded'), findsOneWidget);
      expect(find.byKey(const Key('run_host_h1')), findsOneWidget);
      expect(find.byKey(const Key('run_host_h2')), findsOneWidget);
      expect(factory.ran, ['uptime', 'uptime']);
      expect(factory.sessions.every((s) => s.closes == 1), isTrue);
    });

    testWidgets('a failing exit code is reported as a failure', (tester) async {
      await seedRunbook();
      final factory = _FakeFactory(
        handler: (hostId, command) async => ('boom\n', 3),
      );
      await pumpScreen(tester, factory);

      await tester.tap(find.byKey(const Key('runbook_execute_rb')));
      await tester.pumpAndSettle();
      await pickHosts(tester, ['h1']);

      expect(find.text('0 of 1 host succeeded'), findsOneWidget);
      expect(find.text('failed'), findsWidgets);

      // The host's output is one tap away, with the real exit code.
      await tester.tap(find.byKey(const Key('run_host_open_h1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('run_output_dialog')), findsOneWidget);
      expect(find.text('Exit code 3'), findsOneWidget);
      expect(find.textContaining('boom'), findsOneWidget);
    });

    testWidgets('an unreachable host is reported, never faked as success', (
      tester,
    ) async {
      await seedRunbook();
      final factory = _FakeFactory(openError: 'connection refused');
      await pumpScreen(tester, factory);

      await tester.tap(find.byKey(const Key('runbook_execute_rb')));
      await tester.pumpAndSettle();
      await pickHosts(tester, ['h1']);

      expect(find.text('0 of 1 host succeeded'), findsOneWidget);
      expect(find.text('connection refused'), findsOneWidget);
      expect(find.textContaining('Executed:'), findsNothing);
      expect(factory.ran, isEmpty);
    });

    testWidgets('local hosts cannot be selected and nothing starts without '
        'a host', (tester) async {
      await seedRunbook();
      final factory = _FakeFactory();
      await pumpScreen(tester, factory);

      await tester.tap(find.byKey(const Key('runbook_execute_rb')));
      await tester.pumpAndSettle();

      final confirm = tester.widget<CheckboxListTile>(
        find.byKey(const Key('run_target_host_hl')),
      );
      expect(confirm.onChanged, isNull);
      expect(find.textContaining('Local shell'), findsOneWidget);
      expect(find.text('Choose hosts'), findsOneWidget);

      // Dismissing the sheet starts nothing.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('run_result_dialog')), findsNothing);
      expect(factory.sessions, isEmpty);
    });

    testWidgets('the confirm button states the scope', (tester) async {
      await seedRunbook();
      await pumpScreen(tester, _FakeFactory());

      await tester.tap(find.byKey(const Key('runbook_execute_rb')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('run_target_select_all')));
      await tester.pump();

      // Two SSH hosts; the local one is skipped by select-all.
      expect(find.text('Run on 2 hosts'), findsOneWidget);
    });

    testWidgets('prompts for INPUT variables after the target', (tester) async {
      await seedRunbook(command: r'echo ${INPUT:who} ${HOME}');
      final factory = _FakeFactory();
      await pumpScreen(tester, factory);

      await tester.tap(find.byKey(const Key('runbook_execute_rb')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('run_target_host_h1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('run_target_confirm')));
      await tester.pumpAndSettle();

      // Only INPUT is prompted; ${HOME} is the shell's.
      expect(find.byKey(const Key('variable_input_who')), findsOneWidget);
      expect(find.byKey(const Key('variable_input_HOME')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('variable_input_who')),
        'world',
      );
      await tester.tap(find.byKey(const Key('variable_input_confirm_button')));
      await tester.pumpAndSettle();

      expect(factory.ran, [r'echo world ${HOME}']);
    });
  });

  group('Snippet run flow', () {
    Future<void> seedSnippet() => db.snippetsDao.insertSnippet(
      SnippetsCompanion.insert(
        id: 'sn',
        workspaceId: 'default',
        title: 'Show home',
        code: r'echo ${HOME}',
      ),
    );

    testWidgets('runs on a host target and shows the result', (tester) async {
      await seedSnippet();
      final factory = _FakeFactory(
        handler: (hostId, command) async => ('/root\n', 0),
      );
      await pumpScreen(tester, factory, section: AutomationSection.snippets);

      await tester.tap(find.byKey(const Key('snippet_run_sn')));
      await tester.pumpAndSettle();
      // No terminal is open, so the terminal section is not offered.
      expect(find.byKey(const Key('run_target_active_pane')), findsNothing);
      await pickHosts(tester, ['h1']);

      expect(find.byKey(const Key('run_result_dialog')), findsOneWidget);
      expect(find.text('1 of 1 host succeeded'), findsOneWidget);
      // A shell variable is sent as written, with no prompt in between.
      expect(factory.ran, [r'echo ${HOME}']);

      await tester.tap(find.byKey(const Key('run_host_open_h1')));
      await tester.pumpAndSettle();
      expect(find.text('/root\n'), findsOneWidget);
    });
  });
}
