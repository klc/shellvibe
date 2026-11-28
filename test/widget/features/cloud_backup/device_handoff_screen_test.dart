import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/features/account/presentation/notifiers/account_notifier.dart';
import 'package:shellvibe/features/cloud_backup/presentation/widgets/device_handoff_screen.dart';
import 'package:shellvibe/shared/database/app_database.dart';

import '../../../support/fake_sync_server.dart';
import '../../../support/signed_in_container.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a desktop being added shows a code another device can scan', (
    tester,
  ) async {
    // The test host is a desktop, which has no camera plugin: the screen has
    // to get to the code without touching one.
    FlutterSecureStorage.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    final server = FakeSyncServer();
    final container = signedInContainer(db: db, server: server);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    await tester.runAsync(() => container.read(accountProvider.future));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ShadTheme(
          data: ShadThemeData(
            colorScheme: const ShadSlateColorScheme.light(),
            brightness: Brightness.light,
          ),
          child: const MaterialApp(home: DeviceHandoffScreen(gives: false)),
        ),
      ),
    );
    // The mailbox is opened and the one-time key made off the test clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();

    expect(server.handoffs, hasLength(1));
    expect(find.byKey(const Key('device_handoff_qr')), findsOneWidget);
    expect(
      find.byKey(const Key('device_handoff_scan_instead_button')),
      findsNothing,
    );

    // Leaving the screen stops the wait and closes the mailbox.
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(server.handoffs, isEmpty);
  });
}
