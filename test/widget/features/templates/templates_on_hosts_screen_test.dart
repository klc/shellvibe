import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:terly2/features/hosts/presentation/screens/hosts_screen.dart';
import 'package:terly2/features/templates/data/repositories/templates_repository.dart';
import 'package:terly2/features/templates/domain/models/template_model.dart';
import 'package:terly2/features/templates/domain/models/template_pane_model.dart';
import 'package:terly2/features/terminal/domain/models/terminal_tab_session.dart';
import 'package:terly2/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:terly2/shared/database/app_database.dart';
import 'package:terly2/shared/providers/database_providers.dart';

/// The hosts screen is the second surface templates hang off, so it gets the
/// same run-it-for-real check as the terminal toolbar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.workspacesDao.insertWorkspace(
      WorkspacesCompanion.insert(
        id: 'default',
        name: 'Default Workspace',
        createdAt: DateTime.now(),
      ),
    );
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<TemplateModel> seedTemplate() async {
    final template = TemplateModel(
      id: 'tpl_1',
      workspaceId: 'default',
      name: 'Morning check',
      createdAt: DateTime(2026, 8, 5),
      panes: const [
        TemplatePaneModel(
          id: 'pane_root',
          templateId: 'tpl_1',
          paneOrder: 0,
          sessionType: TerminalSessionType.local,
          title: 'Local Shell',
        ),
        TemplatePaneModel(
          id: 'pane_split',
          templateId: 'tpl_1',
          paneOrder: 1,
          parentPaneId: 'pane_root',
          splitDirection: Axis.vertical,
          splitRatio: 0.4,
          sessionType: TerminalSessionType.local,
        ),
      ],
      activePaneId: 'pane_root',
    );
    await TemplatesRepository(db.templatesDao).addTemplate(template);
    return template;
  }

  Widget harness() {
    return UncontrolledProviderScope(
      container: container,
      child: ShadTheme(
        data: ShadThemeData(
          colorScheme: const ShadSlateColorScheme.light(),
          brightness: Brightness.light,
        ),
        child: MaterialApp(
          builder: (context, child) => Material(child: child!),
          home: const HostsScreen(),
        ),
      ),
    );
  }

  /// The context column that carries the template list only renders at desktop
  /// widths, so the surface under test needs one.
  void useDesktopWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('Templates on the hosts screen', () {
    testWidgets('lists saved templates in the context column', (tester) async {
      await seedTemplate();
      useDesktopWindow(tester);

      await tester.pumpWidget(harness());
      await settle(tester);

      // TerlySectionLabel upper-cases its label.
      expect(find.text('TEMPLATES'), findsOneWidget);
      expect(find.text('Morning check'), findsOneWidget);
      expect(find.byKey(const Key('run_template_tpl_1')), findsOneWidget);
      expect(find.byKey(const Key('template_menu_tpl_1')), findsOneWidget);
    });

    testWidgets('shows no template section when there are none', (
      tester,
    ) async {
      useDesktopWindow(tester);

      await tester.pumpWidget(harness());
      await settle(tester);

      expect(find.text('TEMPLATES'), findsNothing);
    });

    testWidgets('tapping a template opens its layout', (tester) async {
      await seedTemplate();
      useDesktopWindow(tester);

      await tester.pumpWidget(harness());
      await settle(tester);

      expect(container.read(terminalTabsProvider).tabs, isEmpty);

      await tester.tap(find.byKey(const Key('run_template_tpl_1')));
      await settle(tester);

      final tabs = container.read(terminalTabsProvider).tabs;
      expect(tabs.length, equals(2));
      expect(tabs[0].splitParentId, isNull);
      expect(tabs[1].splitParentId, equals(tabs[0].id));
      expect(tabs[1].splitDirection, equals(Axis.vertical));
      expect(tabs[1].splitRatio, closeTo(0.4, 1e-9));
      // The captured focus was the root pane, not the last one created.
      expect(container.read(terminalTabsProvider).activeTabId, equals(tabs[0].id));
    });

    testWidgets('deleting a template removes it from the column', (
      tester,
    ) async {
      await seedTemplate();
      useDesktopWindow(tester);

      await tester.pumpWidget(harness());
      await settle(tester);

      await tester.tap(find.byKey(const Key('template_menu_tpl_1')));
      await settle(tester);
      await tester.tap(find.text('Delete template'));
      await settle(tester);
      await tester.tap(find.text('Delete'));
      await settle(tester);

      expect(find.byKey(const Key('run_template_tpl_1')), findsNothing);
      expect(find.text('TEMPLATES'), findsNothing);
    });
  });
}
