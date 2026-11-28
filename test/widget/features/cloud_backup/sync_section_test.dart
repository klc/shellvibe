import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
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
}

final class _NotConfigured extends SyncNotifier {
  @override
  Future<SyncState> build() async =>
      const SyncState(blocker: SyncBlocker.notConfigured);
}
