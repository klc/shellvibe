import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:shellvibe/core/utils/platform_capabilities.dart';
import 'package:shellvibe/features/tunnels/presentation/screens/tunnels_screen.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

/// A rule card is one line of fixed columns on a wide screen. On a phone that
/// line ran 204px past the edge, so a narrow card stacks the route under the
/// header row instead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    await db.hostsDao.insertHost(
      HostsCompanion.insert(
        id: 'h1',
        workspaceId: 'default',
        label: 'prod-db-01',
        hostname: 'db.example.com',
        createdAt: DateTime.now(),
      ),
    );
    await db.tunnelsDao.insertRule(
      PortForwardRulesCompanion.insert(
        id: 'r1',
        hostId: 'h1',
        type: 'local',
        localPort: 5432,
        remoteHost: const Value('127.0.0.1'),
        remotePort: const Value(5432),
      ),
    );
  });

  tearDown(() async {
    debugPlatformCapabilitiesOverride = null;
    await db.close();
  });

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    debugPlatformCapabilitiesOverride = TargetPlatform.android;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: ShadTheme(
          data: ShadThemeData(
            colorScheme: const ShadSlateColorScheme.dark(),
            brightness: Brightness.dark,
          ),
          child: const MaterialApp(home: TunnelsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a phone-width card fits', (tester) async {
    await pumpAt(tester, const Size(412, 915));
    expect(find.text('prod-db-01'), findsOneWidget);
    expect(find.text('127.0.0.1:5432'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tablet-width card keeps one line and fits', (tester) async {
    await pumpAt(tester, const Size(1280, 800));
    expect(find.text('prod-db-01'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
