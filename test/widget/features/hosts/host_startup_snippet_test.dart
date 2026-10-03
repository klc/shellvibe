import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/features/hosts/data/repositories/hosts_repository.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/hosts/presentation/dialogs/host_form_dialog.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.snippetsDao.insertSnippet(
      SnippetsCompanion.insert(
        id: 'sn',
        workspaceId: 'default',
        title: 'Greet',
        code: 'echo hi',
      ),
    );
  });

  tearDown(() => db.close());

  Future<void> pumpForm(WidgetTester tester, {HostModel? host}) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
              child: HostFormDialog(workspaceId: 'default', initialHost: host),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pick(
    WidgetTester tester,
    String title, {
    required String current,
  }) async {
    final dropdown = find.byKey(const Key('host_startup_snippet_dropdown'));
    await tester.scrollUntilVisible(
      dropdown,
      120,
      scrollable: find
          .descendant(
            of: find.byType(HostFormDialog),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    // Tapped through the value it shows, not the field's centre: the field is
    // as wide as the form and its middle is empty padding.
    await tester.tap(
      find.descendant(of: dropdown, matching: find.text(current)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(title).last);
    await tester.pumpAndSettle();
  }

  testWidgets('a new host saves the chosen startup snippet', (tester) async {
    await pumpForm(tester);
    await tester.enterText(find.byKey(const Key('host_label_input')), 'web');
    await tester.enterText(
      find.byKey(const Key('host_hostname_input')),
      'web.example.com',
    );
    await pick(tester, 'Greet', current: '(None)');

    await tester.tap(find.byKey(const Key('host_save_button')));
    await tester.pumpAndSettle();

    final saved = (await db.select(db.hosts).get()).single;
    expect(saved.startupSnippetId, 'sn');
  });

  testWidgets('editing shows the current snippet and (None) clears it', (
    tester,
  ) async {
    final saved = await HostsRepository(hostsDao: db.hostsDao).saveHost(
      workspaceId: 'default',
      label: 'web',
      hostname: 'web.example.com',
      startupSnippetId: 'sn',
    );
    await pumpForm(tester, host: saved);
    expect(find.text('Greet'), findsOneWidget);

    await pick(tester, '(None)', current: 'Greet');
    await tester.tap(find.byKey(const Key('host_save_button')));
    await tester.pumpAndSettle();

    expect((await db.select(db.hosts).get()).single.startupSnippetId, isNull);
  });
}
