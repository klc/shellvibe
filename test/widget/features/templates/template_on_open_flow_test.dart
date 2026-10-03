import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/snippets/data/run_providers.dart';
import 'package:shellvibe/features/snippets/domain/services/remote_command_session.dart';
import 'package:shellvibe/features/templates/data/repositories/templates_repository.dart';
import 'package:shellvibe/features/templates/domain/services/template_on_open.dart';
import 'package:shellvibe/features/templates/presentation/template_launch.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

class _Session implements RemoteCommandSession {
  final List<String> ran;
  _Session(this.ran);

  @override
  Future<(String, int)> run(String command, Duration timeout) async {
    ran.add(command);
    return ('ok', 0);
  }

  @override
  Future<void> interrupt() async {}

  @override
  Future<void> close() async {}
}

class _Factory implements RemoteCommandSessionFactory {
  final opened = <String>[];
  final ran = <String>[];

  @override
  Future<RemoteCommandSession> open(HostModel host) async {
    opened.add(host.id);
    return _Session(ran);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _Factory factory;
  OnOpenOutcome? outcome;

  Future<void> seed({required bool confirm, String command = 'uptime'}) async {
    await db.runbooksDao.insertRunbook(
      RunbooksCompanion.insert(
        id: 'rb',
        workspaceId: 'default',
        title: 'Health check',
        createdAt: DateTime(2026),
      ),
    );
    await db.runbooksDao.replaceSteps('rb', [
      RunbookStepsCompanion.insert(
        id: 's1',
        runbookId: 'rb',
        stepOrder: 1,
        command: command,
      ),
    ]);
    for (final id in ['h1', 'h2']) {
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: id,
          workspaceId: 'default',
          label: 'web-$id',
          hostname: '$id.example.com',
          createdAt: DateTime(2026),
        ),
      );
    }
    await db.templatesDao.insertTemplate(
      TemplatesCompanion.insert(
        id: 'tpl',
        workspaceId: 'default',
        name: 'Prod triage',
        createdAt: DateTime(2026),
        onOpenRunbookId: const Value('rb'),
        onOpenConfirm: Value(confirm),
      ),
    );
    await db.templatesDao.replacePanes('tpl', [
      for (final (i, id) in ['h1', 'h2'].indexed)
        TemplatePanesCompanion.insert(
          id: 'p$i',
          templateId: 'tpl',
          paneOrder: i,
          sessionType: 'ssh',
          hostId: Value(id),
        ),
    ]);
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    factory = _Factory();
    outcome = null;
  });

  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    final template = (await TemplatesRepository(
      db.templatesDao,
    ).getAllTemplates()).single;
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
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () async =>
                      outcome = await runTemplateOnOpen(context, ref, template),
                  child: const Text('opened'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('opened'));
    await tester.pumpAndSettle();
  }

  testWidgets('asks first, lists runbook and hosts, then runs on them', (
    tester,
  ) async {
    await seed(confirm: true);
    await pump(tester);

    expect(find.byKey(const Key('on_open_confirm_dialog')), findsOneWidget);
    expect(find.textContaining('web-h1'), findsOneWidget);
    expect(find.textContaining('web-h2'), findsOneWidget);
    expect(factory.opened, isEmpty);

    await tester.tap(find.byKey(const Key('on_open_confirm_run')));
    await tester.pumpAndSettle();

    expect(outcome, OnOpenOutcome.started);
    expect(factory.opened.toSet(), {'h1', 'h2'});
    expect(factory.ran, ['uptime', 'uptime']);
  });

  testWidgets('skipping the confirmation runs nothing', (tester) async {
    await seed(confirm: true);
    await pump(tester);
    await tester.tap(find.byKey(const Key('on_open_confirm_skip')));
    await tester.pumpAndSettle();
    expect(outcome, OnOpenOutcome.declined);
    expect(factory.opened, isEmpty);
  });

  testWidgets('without ask-first it just runs', (tester) async {
    await seed(confirm: false);
    await pump(tester);
    expect(find.byKey(const Key('on_open_confirm_dialog')), findsNothing);
    expect(outcome, OnOpenOutcome.started);
    expect(factory.opened.toSet(), {'h1', 'h2'});
  });

  testWidgets('a runbook with input variables prompts, never runs blank', (
    tester,
  ) async {
    await seed(confirm: false, command: r'echo ${INPUT:who}');
    await pump(tester);

    expect(find.byKey(const Key('variable_input_who')), findsOneWidget);
    expect(factory.opened, isEmpty);
    await tester.enterText(find.byKey(const Key('variable_input_who')), 'me');
    await tester.tap(find.byKey(const Key('variable_input_confirm_button')));
    await tester.pumpAndSettle();
    expect(factory.ran, ['echo me', 'echo me']);
  });
}
