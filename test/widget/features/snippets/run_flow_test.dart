import 'dart:convert';

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
  final List<String> openedHosts = [];

  _FakeFactory({this.handler, this.openError});

  @override
  Future<RemoteCommandSession> open(HostModel host) async {
    if (openError != null) throw RemoteCommandException(openError!);
    openedHosts.add(host.id);
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

  Future<void> seedRunbook({
    String command = 'uptime',
    List<String>? commands,
    String? defaultHostIds,
  }) async {
    await db.runbooksDao.insertRunbook(
      RunbooksCompanion.insert(
        id: 'rb',
        workspaceId: 'default',
        title: 'Health check',
        createdAt: DateTime.now(),
        defaultHostIds: Value(defaultHostIds),
      ),
    );
    final all = commands ?? [command];
    await db.runbooksDao.replaceSteps('rb', [
      for (var i = 0; i < all.length; i++)
        RunbookStepsCompanion.insert(
          id: 'rs${i + 1}',
          runbookId: 'rb',
          stepOrder: i + 1,
          command: all[i],
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
      expect(find.text('2 succeeded'), findsOneWidget);
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

      expect(find.text('1 failed'), findsOneWidget);
      expect(find.text('failed'), findsWidgets);

      // The host's output is one tap away, with the real exit code.
      await tester.tap(find.byKey(const Key('run_host_open_h1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('run_output_dialog')), findsOneWidget);
      expect(find.textContaining('failed · Exit code 3'), findsOneWidget);
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

      expect(find.text('1 failed'), findsOneWidget);
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
      expect(find.text('1 succeeded'), findsOneWidget);
      // A shell variable is sent as written, with no prompt in between.
      expect(factory.ran, [r'echo ${HOME}']);

      await tester.tap(find.byKey(const Key('run_host_open_h1')));
      await tester.pumpAndSettle();
      expect(find.text('/root\n'), findsOneWidget);
    });
  });

  group('Run view, strategy, history and defaults', () {
    Future<void> runOn(WidgetTester tester, List<String> ids) async {
      await tester.tap(find.byKey(const Key('runbook_execute_rb')));
      await tester.pumpAndSettle();
      await pickHosts(tester, ids);
    }

    testWidgets('a multi-step multi-host run renders the matrix and a cell '
        'opens that step\'s output', (tester) async {
      await seedRunbook(commands: ['uptime', 'df -h']);
      final factory = _FakeFactory(
        handler: (hostId, command) async => ('output of $command\n', 0),
      );
      await pumpScreen(tester, factory);
      await runOn(tester, ['h1', 'h2']);

      expect(find.byKey(const Key('run_matrix')), findsOneWidget);
      expect(find.text('2 succeeded'), findsOneWidget);
      for (final host in ['h1', 'h2']) {
        for (final step in ['rs1', 'rs2']) {
          expect(find.byKey(Key('run_cell_${host}_$step')), findsOneWidget);
        }
      }
      // Status is spoken, not just coloured.
      expect(find.bySemanticsLabel('web-1, step 2: succeeded'), findsOneWidget);

      await tester.tap(find.byKey(const Key('run_cell_h1_rs2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('run_output_dialog')), findsOneWidget);
      expect(find.textContaining('output of df -h'), findsOneWidget);
      expect(find.textContaining('Exit code 0'), findsOneWidget);
      expect(find.byKey(const Key('run_output_copy')), findsOneWidget);
    });

    testWidgets('at phone width the matrix falls back to the host list '
        'without overflowing', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await seedRunbook(commands: ['uptime', 'df -h']);
      await pumpScreen(tester, _FakeFactory());
      await runOn(tester, ['h1', 'h2']);

      expect(find.byKey(const Key('run_result_dialog')), findsOneWidget);
      expect(find.byKey(const Key('run_matrix')), findsNothing);
      expect(find.byKey(const Key('run_host_h1')), findsOneWidget);
      expect(find.byKey(const Key('run_step_h1_rs2')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('re-run failed hosts targets only the failed ones', (
      tester,
    ) async {
      await seedRunbook();
      final factory = _FakeFactory(
        handler: (hostId, command) async =>
            hostId == 'h1' ? ('bad', 1) : ('ok', 0),
      );
      await pumpScreen(tester, factory);
      await runOn(tester, ['h1', 'h2']);
      expect(find.text('1 succeeded · 1 failed'), findsOneWidget);
      expect(factory.openedHosts, ['h1', 'h2']);

      await tester.tap(find.byKey(const Key('run_rerun_failed')));
      await tester.pumpAndSettle();

      expect(factory.openedHosts, ['h1', 'h2', 'h1']);
      expect(find.text('1 failed'), findsOneWidget);
    });

    testWidgets('run again repeats every host', (tester) async {
      await seedRunbook();
      final factory = _FakeFactory();
      await pumpScreen(tester, factory);
      await runOn(tester, ['h1', 'h2']);
      await tester.tap(find.byKey(const Key('run_run_again')));
      await tester.pumpAndSettle();
      expect(factory.openedHosts, ['h1', 'h2', 'h1', 'h2']);
    });

    testWidgets('a rolling run stops at the first failure and says so', (
      tester,
    ) async {
      await seedRunbook();
      final factory = _FakeFactory(
        handler: (hostId, command) async => ('bad', 1),
      );
      await pumpScreen(tester, factory);

      await tester.tap(find.byKey(const Key('runbook_execute_rb')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('run_target_host_h1')));
      await tester.tap(find.byKey(const Key('run_target_host_h2')));
      await tester.pump();
      // The strategy picker appears with more than one host.
      expect(find.byKey(const Key('run_concurrency_value')), findsOneWidget);
      await tester.tap(find.byKey(const Key('run_concurrency_inc')));
      await tester.pump();
      expect(find.text('5'), findsOneWidget);
      await tester.tap(find.byKey(const Key('run_strategy_rolling')));
      await tester.pump();
      expect(find.byKey(const Key('run_concurrency_value')), findsNothing);
      await tester.tap(find.byKey(const Key('run_target_confirm')));
      await tester.pumpAndSettle();

      expect(find.text('1 failed · 1 skipped'), findsOneWidget);
      expect(find.text('Stopped after web-1 failed'), findsOneWidget);
      expect(factory.openedHosts, ['h1']);
    });

    testWidgets('the run is stored; history lists it and opens it read-only, '
        'and the row shows a last-run badge', (tester) async {
      await seedRunbook();
      final factory = _FakeFactory(
        handler: (hostId, command) async => ('stored output\n', 0),
      );
      await pumpScreen(tester, factory);
      await runOn(tester, ['h1', 'h2']);
      await tester.tap(find.byKey(const Key('run_result_close')));
      await tester.pumpAndSettle();

      // Last-run badge on the list row.
      expect(find.textContaining('✓ just now'), findsOneWidget);

      await tester.tap(find.byKey(const Key('runbook_tile_rb')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('run_history_section')),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('runbook_detail_drawer')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.byKey(const Key('run_history_section')), findsOneWidget);
      final entry = find.byWidgetPredicate((w) {
        final key = w.key;
        return key is ValueKey<String> &&
            RegExp(r'^run_history_[0-9a-f-]{36}$').hasMatch(key.value);
      });
      expect(entry, findsOneWidget);
      expect(find.text('2 of 2 hosts succeeded'), findsWidgets);

      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('run_history_dialog')), findsOneWidget);
      // The detail panel behind it also shows the live run, so look inside
      // the dialog.
      Finder inDialog(Finder f) => find.descendant(
        of: find.byKey(const Key('run_history_dialog')),
        matching: f,
      );
      expect(inDialog(find.text('2 succeeded')), findsOneWidget);
      // Read-only: nothing to stop.
      expect(inDialog(find.byKey(const Key('run_stop_button'))), findsNothing);

      await tester.tap(inDialog(find.byKey(const Key('run_host_open_h1'))));
      await tester.pumpAndSettle();
      expect(find.textContaining('stored output'), findsOneWidget);
      await tester.tap(find.text('Close').last);
      await tester.pumpAndSettle();

      // Run again with the stored hosts; a deleted one is dropped.
      await db.hostsDao.deleteHost('h2');
      await tester.tap(inDialog(find.byKey(const Key('run_run_again'))));
      await tester.pumpAndSettle();
      expect(factory.openedHosts, ['h1', 'h2', 'h1']);
    });

    testWidgets('history never stores input values, and running again from '
        'it asks for them again', (tester) async {
      await seedRunbook(command: r'echo ${INPUT:who}');
      final factory = _FakeFactory(
        handler: (hostId, command) async => ('said $command\n', 0),
      );
      await pumpScreen(tester, factory);

      await tester.tap(find.byKey(const Key('runbook_execute_rb')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('run_target_host_h1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('run_target_confirm')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('variable_input_who')),
        'hunter2-s3cret',
      );
      await tester.tap(find.byKey(const Key('variable_input_confirm_button')));
      await tester.pumpAndSettle();
      expect(factory.ran, ['echo hunter2-s3cret']);

      // Nothing on disk holds the value, not even the echoed output.
      for (final table in [
        'runbook_runs',
        'runbook_run_hosts',
        'runbook_run_steps',
      ]) {
        final rows = await db.customSelect('SELECT * FROM $table').get();
        expect(rows, isNotEmpty);
        for (final row in rows) {
          for (final value in row.data.values) {
            expect('$value', isNot(contains('hunter2-s3cret')), reason: table);
          }
        }
      }

      await tester.tap(find.byKey(const Key('run_result_close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('runbook_tile_rb')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('run_history_section')),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('runbook_detail_drawer')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(
        find.byWidgetPredicate((w) {
          final key = w.key;
          return key is ValueKey<String> &&
              RegExp(r'^run_history_[0-9a-f-]{36}$').hasMatch(key.value);
        }),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('run_history_dialog')),
          matching: find.byKey(const Key('run_run_again')),
        ),
      );
      await tester.pumpAndSettle();

      // Asked again, with nothing prefilled, and nothing ran yet.
      final field = find.byKey(const Key('variable_input_who'));
      expect(field, findsOneWidget);
      expect(tester.widget<ShadInput>(field).controller?.text ?? '', isEmpty);
      expect(factory.ran, hasLength(1));

      await tester.enterText(field, 'again');
      await tester.tap(find.byKey(const Key('variable_input_confirm_button')));
      await tester.pumpAndSettle();
      expect(factory.ran, ['echo hunter2-s3cret', 'echo again']);
    });

    testWidgets('re-running a live run reuses its in-memory values', (
      tester,
    ) async {
      await seedRunbook(command: r'echo ${INPUT:who}');
      final factory = _FakeFactory();
      await pumpScreen(tester, factory);
      await tester.tap(find.byKey(const Key('runbook_execute_rb')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('run_target_host_h1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('run_target_confirm')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('variable_input_who')), 'x1');
      await tester.tap(find.byKey(const Key('variable_input_confirm_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('run_run_again')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('variable_input_who')), findsNothing);
      expect(factory.ran, ['echo x1', 'echo x1']);
    });

    testWidgets('clearing the history removes the section', (tester) async {
      await seedRunbook();
      await pumpScreen(tester, _FakeFactory());
      await runOn(tester, ['h1']);
      await tester.tap(find.byKey(const Key('run_result_close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('runbook_tile_rb')));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('run_history_clear')),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('runbook_detail_drawer')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(const Key('run_history_clear')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('run_history_clear_confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('run_history_section')), findsNothing);
    });

    testWidgets('default targets are preselected (missing hosts ignored) and '
        'can be saved from the sheet', (tester) async {
      await seedRunbook(defaultHostIds: '["h2","gone"]');
      await pumpScreen(tester, _FakeFactory());

      await tester.tap(find.byKey(const Key('runbook_execute_rb')));
      await tester.pumpAndSettle();
      bool checked(String id) => tester
          .widget<CheckboxListTile>(find.byKey(Key('run_target_host_$id')))
          .value!;
      expect(checked('h2'), isTrue);
      expect(checked('h1'), isFalse);
      expect(find.text('Run on 1 host'), findsOneWidget);

      await tester.tap(find.byKey(const Key('run_target_host_h1')));
      await tester.tap(find.byKey(const Key('run_target_save_default')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('run_target_confirm')));
      await tester.pumpAndSettle();

      final saved = (await db.runbooksDao.getAllRunbooks()).single;
      expect((jsonDecode(saved.defaultHostIds!) as List).toSet(), {'h1', 'h2'});
    });

    testWidgets('without Save as default, the defaults are left alone', (
      tester,
    ) async {
      await seedRunbook(defaultHostIds: '["h2"]');
      await pumpScreen(tester, _FakeFactory());
      await tester.tap(find.byKey(const Key('runbook_execute_rb')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('run_target_host_h1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('run_target_confirm')));
      await tester.pumpAndSettle();
      final saved = (await db.runbooksDao.getAllRunbooks()).single;
      expect(saved.defaultHostIds, '["h2"]');
    });
  });
}
