import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:shellvibe/features/snippets/data/services/runbook_file_service.dart';
import 'package:shellvibe/features/snippets/domain/services/runbook_markdown.dart';
import 'package:shellvibe/features/snippets/presentation/screens/snippets_screen.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

class _FakeFiles extends RunbookFileService {
  final bool save;
  final String? picked;
  final bool saveFails;
  String? savedName;
  String? savedContent;

  _FakeFiles({this.save = true, this.picked, this.saveFails = false});

  @override
  bool get canSave => save;

  @override
  Future<String?> saveMarkdown(String suggestedName, String content) async {
    if (saveFails) throw StateError('dialog failed');
    savedName = suggestedName;
    savedContent = content;
    return '/tmp/$suggestedName';
  }

  @override
  Future<String?> pickMarkdown() async => picked;
}

const _markdown = '''
---
title: "Imported checks"
tags: ["ops"]
---

```sh
uptime
```

```sh {"retries":2,"onFailure":"continue"}
df -h
```

> [!approval] Look at the graphs
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  String? clipboard;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    await db.close();
  });

  Future<void> pump(WidgetTester tester, _FakeFiles files) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          runbookFileServiceProvider.overrideWithValue(files),
        ],
        child: ShadTheme(
          data: ShadThemeData(
            colorScheme: const ShadSlateColorScheme.light(),
            brightness: Brightness.light,
          ),
          child: const MaterialApp(
            home: SnippetsScreen(initialSection: AutomationSection.runbooks),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> seed() async {
    await db.runbooksDao.insertRunbook(
      RunbooksCompanion.insert(
        id: 'rb',
        workspaceId: 'default',
        title: 'Deploy API',
        createdAt: DateTime(2026),
        tags: const Value('["ops"]'),
      ),
    );
    await db.runbooksDao.replaceSteps('rb', [
      RunbooksStepFor.command('s1', 1, 'systemctl restart api'),
    ]);
  }

  Future<void> importText(WidgetTester tester, String text) async {
    await tester.tap(find.byKey(const Key('import_runbook_button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('runbook_import_text')), text);
    await tester.tap(find.byKey(const Key('runbook_import_confirm')));
    await tester.pumpAndSettle();
  }

  group('import', () {
    testWidgets('pasted Markdown becomes a new runbook beside the old one', (
      tester,
    ) async {
      await seed();
      await pump(tester, _FakeFiles());
      await importText(tester, _markdown);

      final all = await db.select(db.runbooks).get();
      expect(all.map((r) => r.title).toSet(), {
        'Deploy API',
        'Imported checks',
      });
      final imported = all.firstWhere((r) => r.title == 'Imported checks');
      expect(imported.id, isNot('rb'));
      expect(imported.tags, '["ops"]');
      final steps = await db.runbooksDao.getStepsForRunbook(imported.id);
      expect(steps.map((s) => s.command), [
        'uptime',
        'df -h',
        'Look at the graphs',
      ]);
      expect(steps[1].retries, 2);
      expect(steps[1].onFailure, 'continue');
      expect(steps[2].kind, 'approval');
      // The original is untouched.
      expect(
        (await db.runbooksDao.getStepsForRunbook('rb')).single.command,
        'systemctl restart api',
      );
      expect(find.byKey(const Key('runbook_tile_${'rb'}')), findsOneWidget);
    });

    testWidgets('a mistake is shown in the dialog and nothing is created', (
      tester,
    ) async {
      await seed();
      await pump(tester, _FakeFiles());
      await importText(tester, '```sh {"retries":9}\necho a\n```\n');

      expect(
        tester.widget<Text>(find.byKey(const Key('runbook_import_error'))).data,
        startsWith('Step 1'),
      );
      expect(find.byKey(const Key('runbook_import_confirm')), findsOneWidget);
      expect(await db.select(db.runbooks).get(), hasLength(1));

      // Fixing the text clears the message.
      await tester.enterText(
        find.byKey(const Key('runbook_import_text')),
        '```sh\necho a\n```\n',
      );
      await tester.pump();
      expect(find.byKey(const Key('runbook_import_error')), findsNothing);
    });

    testWidgets('text with no steps is refused with a reason', (tester) async {
      await seed();
      await pump(tester, _FakeFiles());
      await importText(tester, 'just some notes');
      expect(
        tester.widget<Text>(find.byKey(const Key('runbook_import_error'))).data,
        contains('No steps found'),
      );
    });

    testWidgets('Choose file fills the box from the picked file', (
      tester,
    ) async {
      await seed();
      await pump(tester, _FakeFiles(picked: _markdown));
      await tester.tap(find.byKey(const Key('import_runbook_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('runbook_import_choose_file')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Imported checks'), findsWidgets);
      await tester.tap(find.byKey(const Key('runbook_import_confirm')));
      await tester.pumpAndSettle();
      expect(await db.select(db.runbooks).get(), hasLength(2));
    });

    testWidgets('a cancelled file dialog changes nothing', (tester) async {
      await seed();
      await pump(tester, _FakeFiles());
      await tester.tap(find.byKey(const Key('import_runbook_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('runbook_import_choose_file')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('runbook_import_error')), findsNothing);
    });

    testWidgets('an empty library offers Import in its empty state', (
      tester,
    ) async {
      await pump(tester, _FakeFiles());
      await tester.tap(find.byKey(const Key('empty_import_runbook_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('runbook_import_text')),
        '```sh\nuptime\n```\n',
      );
      await tester.tap(find.byKey(const Key('runbook_import_confirm')));
      await tester.pumpAndSettle();
      expect(await db.select(db.runbooks).get(), hasLength(1));
    });
  });

  group('export', () {
    Future<void> exportIt(WidgetTester tester) async {
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('runbook_menu_export')));
      await tester.pumpAndSettle();
    }

    testWidgets('the actions menu saves a file that imports back', (
      tester,
    ) async {
      await seed();
      final files = _FakeFiles();
      await pump(tester, files);
      await exportIt(tester);

      expect(files.savedName, 'deploy-api.md');
      final back = RunbookMarkdown.import(
        files.savedContent!,
        workspaceId: 'default',
      );
      expect(back.title, 'Deploy API');
      expect(back.tags, ['ops']);
      expect(back.steps.single.command, 'systemctl restart api');
      expect(clipboard, isNull);
    });

    testWidgets('where a file cannot be saved it is copied instead', (
      tester,
    ) async {
      await seed();
      final files = _FakeFiles(save: false);
      await pump(tester, files);
      await exportIt(tester);

      expect(files.savedContent, isNull);
      expect(clipboard, contains('title: "Deploy API"'));
      expect(clipboard, contains('systemctl restart api'));
    });

    testWidgets('a save dialog that fails falls back to the clipboard', (
      tester,
    ) async {
      await seed();
      await pump(tester, _FakeFiles(saveFails: true));
      await exportIt(tester);
      expect(clipboard, contains('Deploy API'));
    });
  });
}

/// A command step companion, spelled once.
class RunbooksStepFor {
  static RunbookStepsCompanion command(String id, int order, String command) =>
      RunbookStepsCompanion.insert(
        id: id,
        runbookId: 'rb',
        stepOrder: order,
        command: command,
      );
}
