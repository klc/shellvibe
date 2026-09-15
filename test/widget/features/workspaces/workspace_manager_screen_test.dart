import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/features/workspaces/presentation/screens/workspace_manager_screen.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';
import 'package:shellvibe/shared/providers/workspace_provider.dart';
import 'package:shellvibe/app/widgets/shellvibe_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Widget createTestWidget() {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: ShadTheme(
        data: ShadThemeData(
          colorScheme: const ShadSlateColorScheme.light(),
          brightness: Brightness.light,
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ShadToaster(
            child: const MaterialApp(home: WorkspaceManagerScreen()),
          ),
        ),
      ),
    );
  }

  testWidgets('lists default workspace and protects its delete action', (
    tester,
  ) async {
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('Default Workspace'), findsOneWidget);
    final deleteButton = tester.widget<ShellVibeIconButton>(
      find.byKey(const Key('workspace_delete_default')),
    );
    expect(deleteButton.onPressed, isNull);
  });

  testWidgets('tapping a workspace card switches to it', (tester) async {
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ShadTheme(
          data: ShadThemeData(
            colorScheme: const ShadSlateColorScheme.light(),
            brightness: Brightness.light,
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ShadToaster(
              child: const MaterialApp(home: WorkspaceManagerScreen()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add_workspace_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('workspace_name_input')),
      'Client Operations',
    );
    await tester.tap(find.byKey(const Key('workspace_save_button')));
    await tester.pumpAndSettle();

    final created = (await db.workspacesDao.getAllWorkspaces()).firstWhere(
      (workspace) => workspace.name == 'Client Operations',
    );
    expect(container.read(activeWorkspaceIdProvider), equals('default'));

    // The card is the control: no separate "use workspace" button is offered.
    await tester.tap(find.byKey(Key('workspace_select_${created.id}')));
    await tester.pumpAndSettle();

    expect(container.read(activeWorkspaceIdProvider), equals(created.id));

    // The card of the workspace already in use is not a target.
    final activeCard = tester.widget<InkWell>(
      find.byKey(Key('workspace_select_${created.id}')),
    );
    expect(activeCard.onTap, isNull);
  });

  testWidgets('creates a workspace from the manager screen', (tester) async {
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add_workspace_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('workspace_name_input')),
      'Client Operations',
    );
    await tester.tap(find.byKey(const Key('workspace_save_button')));
    await tester.pumpAndSettle();

    expect(find.text('Client Operations'), findsOneWidget);
    expect(await db.workspacesDao.getWorkspaceById('default'), isNotNull);
    expect(
      (await db.workspacesDao.getAllWorkspaces()).any(
        (workspace) => workspace.name == 'Client Operations',
      ),
      isTrue,
    );
  });
}
