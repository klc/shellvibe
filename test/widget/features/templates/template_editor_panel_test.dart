import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/core/utils/platform_capabilities.dart';
import 'package:shellvibe/features/templates/data/repositories/templates_repository.dart';
import 'package:shellvibe/features/templates/domain/models/template_model.dart';
import 'package:shellvibe/features/templates/domain/models/template_pane_model.dart';
import 'package:shellvibe/features/templates/presentation/notifiers/templates_notifier.dart';
import 'package:shellvibe/features/templates/presentation/widgets/template_editor_panel.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_tab_session.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

class _FailingTemplates extends TemplatesRepository {
  _FailingTemplates(AppDatabase db) : super(db.templatesDao);

  @override
  Future<void> updateTemplate(TemplateModel template) async =>
      throw StateError('disk full');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async {
    debugPlatformCapabilitiesOverride = null;
    await db.close();
  });

  /// One tab split four levels deep: the widest the rows get.
  TemplateModel deepTemplate() => TemplateModel(
    id: 'tpl',
    workspaceId: 'default',
    name: 'Deep',
    panes: [
      for (var i = 0; i < 5; i++)
        TemplatePaneModel(
          id: 'p$i',
          templateId: 'tpl',
          paneOrder: i,
          parentPaneId: i == 0 ? null : 'p${i - 1}',
          splitDirection: i == 0 ? null : Axis.horizontal,
          sessionType: TerminalSessionType.local,
          title: 'A local shell with a long title $i',
        ),
    ],
    createdAt: DateTime(2026),
  );

  testWidgets('the editor lays out on a phone without overflowing', (
    tester,
  ) async {
    debugPlatformCapabilitiesOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: ShadTheme(
          data: ShadThemeData(
            colorScheme: const ShadSlateColorScheme.dark(),
            brightness: Brightness.dark,
          ),
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      TemplateEditorPanel.show(context, deepTemplate()),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('template_pane_p4')), findsOneWidget);
    expect(find.text('Edit Template'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a save that fails keeps the editor open and says so', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          templatesRepositoryProvider.overrideWithValue(_FailingTemplates(db)),
        ],
        child: ShadTheme(
          data: ShadThemeData(
            colorScheme: const ShadSlateColorScheme.dark(),
            brightness: Brightness.dark,
          ),
          child: MaterialApp(
            builder: (context, child) => ShadToaster(child: child!),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      TemplateEditorPanel.show(context, deepTemplate()),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('template_editor_save')));
    await tester.pumpAndSettle();

    expect(find.text('Edit Template'), findsOneWidget);
    expect(find.textContaining('Could not save the template'), findsOneWidget);
  });
}
