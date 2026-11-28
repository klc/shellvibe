import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/features/cloud_backup/presentation/notifiers/cloud_backup_notifier.dart';
import 'package:shellvibe/features/cloud_backup/presentation/notifiers/sync_notifier.dart';
import 'package:shellvibe/features/cloud_backup/presentation/widgets/sync_section.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a phone with no passphrase is shown the way to Cloud Backup', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      'shellvibe_sync_enabled': 'true',
    });
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // A layout that overflows at this width fails the test on its own.
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncProvider.overrideWith(_NotConfigured.new),
          cloudBackupProvider.overrideWith(
            () => _Backup(
              const CloudBackupState(blocker: CloudBackupBlocker.notConfigured),
            ),
          ),
        ],
        child: ShadTheme(
          data: ShadThemeData(
            colorScheme: const ShadSlateColorScheme.light(),
            brightness: Brightness.light,
          ),
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: SyncSection(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('sync_open_cloud_backup_button')),
      findsOneWidget,
    );
  });

  Future<void> pumpSection(WidgetTester tester, CloudBackupState backup) async {
    FlutterSecureStorage.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncProvider.overrideWith(_Disabled.new),
          cloudBackupProvider.overrideWith(() => _Backup(backup)),
        ],
        child: ShadTheme(
          data: ShadThemeData(
            colorScheme: const ShadSlateColorScheme.light(),
            brightness: Brightness.light,
          ),
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: SyncSection(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool switchEnabled(WidgetTester tester) =>
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('auto_sync_enabled_switch')),
          )
          .onChanged !=
      null;

  testWidgets('sync cannot be switched on before Cloud Backup is set up', (
    tester,
  ) async {
    await pumpSection(
      tester,
      const CloudBackupState(blocker: CloudBackupBlocker.notConfigured),
    );

    expect(switchEnabled(tester), isFalse);
    expect(find.byKey(const Key('sync_set_up_backup_first')), findsOneWidget);
    expect(
      find.byKey(const Key('sync_open_cloud_backup_button')),
      findsOneWidget,
    );
  });

  testWidgets(
    'once Cloud Backup is set up the switch opens and the hint goes',
    (tester) async {
      await pumpSection(tester, const CloudBackupState());

      expect(switchEnabled(tester), isTrue);
      expect(find.byKey(const Key('sync_set_up_backup_first')), findsNothing);
    },
  );
}

final class _NotConfigured extends SyncNotifier {
  @override
  Future<SyncState> build() async =>
      const SyncState(blocker: SyncBlocker.notConfigured);
}

final class _Disabled extends SyncNotifier {
  @override
  Future<SyncState> build() async => const SyncState();
}

final class _Backup extends CloudBackupNotifier {
  _Backup(this._state);

  final CloudBackupState _state;

  @override
  Future<CloudBackupState> build() async => _state;
}
