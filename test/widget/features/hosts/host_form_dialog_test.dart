import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/features/hosts/data/repositories/hosts_repository.dart';
import 'package:shellvibe/features/hosts/presentation/dialogs/host_form_dialog.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> pumpDialog(
    WidgetTester tester, {
    HostFormDialog dialog = const HostFormDialog(workspaceId: 'default'),
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
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
          child: MaterialApp(home: Material(child: dialog)),
        ),
      ),
    );
    await tester.pump();
  }

  // ShadInput lays out an EditableText of its own, no TextField.
  EditableText fieldOf(WidgetTester tester, String key) => tester.widget(
    find.descendant(
      of: find.byKey(Key(key)),
      matching: find.byType(EditableText),
    ),
  );

  testWidgets('the route summary follows the address as it is typed', (
    tester,
  ) async {
    await pumpDialog(tester);
    expect(find.text('no hostname yet'), findsOneWidget);

    // Typing alone, no focus change and no other setState: the summary used
    // to stay on "no hostname yet" until something else rebuilt the form.
    await tester.enterText(
      find.byKey(const Key('host_hostname_input')),
      '10.0.0.5',
    );
    await tester.pump();
    expect(find.text('10.0.0.5:22'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('host_username_input')),
      'root',
    );
    await tester.pump();
    expect(find.text('root@10.0.0.5:22'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('host_port_input')), '2222');
    await tester.pump();
    expect(find.text('root@10.0.0.5:2222'), findsOneWidget);
  });

  testWidgets('address and user name fields are not autocorrected', (
    tester,
  ) async {
    await pumpDialog(tester);
    for (final key in ['host_hostname_input', 'host_username_input']) {
      final field = fieldOf(tester, key);
      expect(field.autocorrect, isFalse, reason: key);
      expect(field.enableSuggestions, isFalse, reason: key);
    }
  });

  testWidgets('duplicating saves a new host and leaves the original alone', (
    tester,
  ) async {
    final original = await HostsRepository(hostsDao: db.hostsDao).saveHost(
      workspaceId: 'default',
      label: 'web',
      hostname: '10.0.0.5',
      username: 'deploy',
      port: 2222,
      environment: 'prod',
    );
    await pumpDialog(
      tester,
      dialog: HostFormDialog(
        workspaceId: 'default',
        initialHost: original,
        duplicate: true,
      ),
    );
    expect(find.text('Duplicate host'), findsOneWidget);
    expect(fieldOf(tester, 'host_label_input').controller.text, 'web (copy)');

    await tester.enterText(
      find.byKey(const Key('host_hostname_input')),
      '10.0.0.6',
    );
    await tester.tap(find.byKey(const Key('host_save_button')));
    await tester.pumpAndSettle();

    final rows = await db.select(db.hosts).get();
    expect(rows, hasLength(2));
    final kept = rows.singleWhere((h) => h.id == original.id);
    expect(kept.hostname, '10.0.0.5');
    expect(kept.label, 'web');
    final copy = rows.singleWhere((h) => h.id != original.id);
    expect(copy.hostname, '10.0.0.6');
    expect(copy.label, 'web (copy)');
    expect(copy.username, 'deploy');
    expect(copy.port, 2222);
    expect(copy.environment, 'prod');
  });
}
