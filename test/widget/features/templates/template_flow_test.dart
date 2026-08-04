import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:terly2/core/network/tunnel_engine.dart';
import 'package:terly2/features/templates/presentation/notifiers/templates_notifier.dart';
import 'package:terly2/features/tunnels/presentation/providers/tunnels_providers.dart';
import 'package:terly2/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:terly2/features/terminal/presentation/views/terminal_tab_view.dart';
import 'package:terly2/shared/database/app_database.dart';
import 'package:terly2/shared/providers/database_providers.dart';

/// End-to-end check of the template surface as a user meets it: open a layout
/// in the terminal, save it from the toolbar, then run it back from the picker.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        // The status bar under an open tab watches this, which would spin up a
        // real TunnelEngine and leave its periodic timer pending at teardown.
        activeTunnelsStreamProvider.overrideWith(
          (ref) => Stream.value(const <ActiveTunnel>[]),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// The default 800x600 test surface is narrower than the terminal's own
  /// chrome once several panes are open, which overflows the status bar. Give
  /// the layout a desktop-sized window instead.
  void useDesktopWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Widget harness() {
    return UncontrolledProviderScope(
      container: container,
      child: ShadTheme(
        data: ShadThemeData(
          colorScheme: const ShadSlateColorScheme.dark(),
          brightness: Brightness.dark,
        ),
        child: MaterialApp(
          home: const TerminalTabView(),
          builder: (context, child) => ShadToaster(child: child!),
        ),
      ),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Opens a tab with one split pane, the smallest layout worth saving.
  ///
  /// The toolbar's "split vertically" is the side-by-side split, which is
  /// `Axis.horizontal` in the session model — the expectations below follow the
  /// model, not the button label.
  Future<void> buildLayout(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('empty_open_local_button')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('split_vertical_button')));
    await settle(tester);
  }

  Future<void> saveTemplate(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(const Key('save_template_button')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const Key('template_name_input')),
      name,
    );
    await tester.tap(find.byKey(const Key('template_save_button')));
    await settle(tester);
    // The confirmation toast overlays the screen and would swallow the next
    // tap, so let it expire before the test carries on.
    await tester.pump(const Duration(seconds: 8));
  }

  group('Template save and run flow', () {
    testWidgets('saves the open tabs and panes from the toolbar',
        (tester) async {
      useDesktopWindow(tester);
      await tester.pumpWidget(harness());
      await settle(tester);

      // Nothing open yet, so there is nothing to save.
      expect(find.byKey(const Key('save_template_button')), findsNothing);
      expect(find.byKey(const Key('run_template_button')), findsOneWidget);

      await buildLayout(tester);
      expect(container.read(terminalTabsProvider).tabs.length, equals(2));
      expect(find.byKey(const Key('save_template_button')), findsOneWidget);

      await saveTemplate(tester, 'Morning check');

      final templates = container.read(templatesProvider).value!;
      expect(templates.length, equals(1));

      final template = templates.single;
      expect(template.name, equals('Morning check'));
      expect(template.panes.length, equals(2));
      expect(template.tabCount, equals(1));
      expect(template.panes[1].parentPaneId, equals(template.panes[0].id));
      expect(template.panes[1].splitDirection, equals(Axis.horizontal));
      // The split pane was focused when it was created, so it is the one the
      // template restores focus to.
      expect(template.activePaneId, equals(template.panes[1].id));
    });

    testWidgets('running a template opens its layout alongside the current one',
        (tester) async {
      useDesktopWindow(tester);
      await tester.pumpWidget(harness());
      await settle(tester);

      await buildLayout(tester);
      await saveTemplate(tester, 'Morning check');

      final before = container.read(terminalTabsProvider).tabs;
      expect(before.length, equals(2));

      final templateId = container.read(templatesProvider).value!.single.id;

      await tester.tap(find.byKey(const Key('run_template_button')));
      await settle(tester);
      await tester.tap(find.byKey(Key('run_template_$templateId')));
      await settle(tester);

      final after = container.read(terminalTabsProvider).tabs;
      // Additive: the panes that were open are untouched.
      expect(after.length, equals(4));
      expect(
        after.take(2).map((t) => t.id),
        equals(before.map((t) => t.id)),
      );

      final opened = after.skip(2).toList();
      final root = opened[0];
      final split = opened[1];
      expect(root.splitParentId, isNull);
      expect(split.splitParentId, equals(root.id));
      expect(split.splitDirection, equals(Axis.horizontal));

      // Focus lands on the pane the template captured, not the last one built.
      expect(container.read(terminalTabsProvider).activeTabId, equals(split.id));
    });

    testWidgets('restores the saved split ratio', (tester) async {
      useDesktopWindow(tester);
      await tester.pumpWidget(harness());
      await settle(tester);

      await buildLayout(tester);

      final splitPaneId = container.read(terminalTabsProvider).tabs[1].id;
      container
          .read(terminalTabsProvider.notifier)
          .setSplitRatio(splitPaneId, 0.25);
      await settle(tester);

      await saveTemplate(tester, 'Narrow pane');
      final templateId = container.read(templatesProvider).value!.single.id;

      await tester.tap(find.byKey(const Key('run_template_button')));
      await settle(tester);
      await tester.tap(find.byKey(Key('run_template_$templateId')));
      await settle(tester);

      final opened = container.read(terminalTabsProvider).tabs.skip(2).toList();
      expect(opened[1].splitRatio, closeTo(0.25, 1e-9));
    });

    testWidgets('the picker explains itself when there are no templates',
        (tester) async {
      useDesktopWindow(tester);
      await tester.pumpWidget(harness());
      await settle(tester);

      await tester.tap(find.byKey(const Key('run_template_button')));
      await settle(tester);

      expect(
        find.textContaining('No templates yet'),
        findsOneWidget,
      );
    });
  });
}
