import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/terminal/presentation/widgets/select_host_panel.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

void main() {
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
  });
  tearDown(() => db.close());

  testWidgets('an empty picker adds a host and connects to it', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final selected = <HostModel>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: ShadTheme(
          data: ShadThemeData(
            colorScheme: const ShadSlateColorScheme.light(),
            brightness: Brightness.light,
          ),
          child: MaterialApp(
            home: Material(
              child: SelectHostPanel(
                onSelected: (host) async => selected.add(host),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byKey(const Key('select_host_add_host')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('host_hostname_input')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('host_label_input')), 'Box');
    await tester.enterText(
      find.byKey(const Key('host_hostname_input')),
      '10.0.0.5',
    );
    await tester.tap(find.byKey(const Key('host_save_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The saved host goes straight to the caller, which connects to it, as
    // the Hosts screen's "Save and connect" does.
    expect(selected.map((h) => h.hostname), ['10.0.0.5']);
  });
}
