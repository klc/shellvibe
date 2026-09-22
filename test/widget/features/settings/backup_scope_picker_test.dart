import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:shellvibe/core/sync/backup_scope.dart';
import 'package:shellvibe/core/sync/backup_scope_store.dart';
import 'package:shellvibe/features/settings/presentation/notifiers/backup_scope_notifier.dart';
import 'package:shellvibe/features/settings/presentation/widgets/backup_scope_picker.dart';

/// The picker is the only place the user learns what a backup will contain.
/// Two things have to be visible there: that a dependency is locked rather
/// than silently repaired, and that a device has stopped taking complete
/// backups.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    BackupScope scope = BackupScope.full,
    DateTime? lastFullBackupAt,
    BackupTarget target = BackupTarget.cloud,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final container = ProviderContainer(
      overrides: [
        for (final t in BackupTarget.values)
          backupScopeProvider(t).overrideWith(() => _StubScope(scope)),
      ],
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
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: BackupScopePicker(
                  target: target,
                  lastFullBackupAt: lastFullBackupAt,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    return container;
  }

  FilterChip chipFor(
    WidgetTester tester,
    BackupCategory category, {
    BackupTarget target = BackupTarget.cloud,
  }) => tester.widget<FilterChip>(
    find.byKey(Key('backup_scope_${target.name}_${category.wireName}')),
  );

  testWidgets('every category is offered', (tester) async {
    await pump(tester);

    for (final category in BackupCategory.values) {
      expect(
        find.byKey(
          Key('backup_scope_${BackupTarget.cloud.name}_${category.wireName}'),
        ),
        findsOneWidget,
        reason: 'A category with no chip cannot be turned off, or back on.',
      );
    }
  });

  testWidgets('port forwards are locked when hosts are off', (tester) async {
    // `port_forward_rules.host_id` is NOT NULL. Offering the combination and
    // then dropping the rows on import would be a worse answer than not
    // offering it.
    await pump(
      tester,
      scope: BackupScope.of(const [BackupCategory.identities]),
    );

    expect(chipFor(tester, BackupCategory.portForwards).onSelected, isNull);
    expect(chipFor(tester, BackupCategory.identities).onSelected, isNotNull);
  });

  testWidgets('turning hosts off takes port forwards with them', (
    tester,
  ) async {
    final container = await pump(tester);

    await tester.tap(
      find.byKey(
        Key(
          'backup_scope_${BackupTarget.cloud.name}_'
          '${BackupCategory.hosts.wireName}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scope = container
        .read(backupScopeProvider(BackupTarget.cloud))
        .value!;

    expect(scope.contains(BackupCategory.hosts), isFalse);
    expect(scope.contains(BackupCategory.portForwards), isFalse);
    expect(scope.unmetDependencies, isEmpty);
  });

  testWidgets('a full scope shows no warning', (tester) async {
    await pump(tester, lastFullBackupAt: null);

    expect(
      find.textContaining('never written a complete backup'),
      findsNothing,
    );
  });

  testWidgets('a narrowed scope with no complete backup warns', (tester) async {
    await pump(
      tester,
      scope: BackupScope.of(const [BackupCategory.hosts]),
      lastFullBackupAt: null,
    );

    expect(
      find.textContaining('never written a complete backup'),
      findsOneWidget,
    );
  });

  testWidgets('a recent complete backup keeps the warning away', (
    tester,
  ) async {
    await pump(
      tester,
      scope: BackupScope.of(const [BackupCategory.hosts]),
      lastFullBackupAt: DateTime.now().subtract(const Duration(days: 3)),
    );

    expect(find.textContaining('Last complete backup'), findsNothing);
  });

  testWidgets('an old complete backup brings it back', (tester) async {
    await pump(
      tester,
      scope: BackupScope.of(const [BackupCategory.hosts]),
      lastFullBackupAt: DateTime.now().subtract(const Duration(days: 45)),
    );

    expect(
      find.textContaining('Last complete backup was 45 days ago'),
      findsOneWidget,
    );
  });
}

class _StubScope extends BackupScopeNotifier {
  _StubScope(this._initial);

  final BackupScope _initial;

  @override
  Future<BackupScope> build(BackupTarget target) async => _initial;

  @override
  Future<void> set(BackupScope scope) async {
    state = AsyncValue.data(scope);
  }
}
