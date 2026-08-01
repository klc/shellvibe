import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:terly2/features/workspaces/presentation/screens/workspace_manager_screen.dart';
import 'package:terly2/shared/database/app_database.dart';
import 'package:terly2/shared/providers/database_providers.dart';

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
    final deleteButton = tester.widget<IconButton>(
      find.byKey(const Key('workspace_delete_default')),
    );
    expect(deleteButton.onPressed, isNull);
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
