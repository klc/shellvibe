import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:shellvibe/features/settings/presentation/widgets/known_hosts_settings_section.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seed(
    String id,
    String hostname, {
    int port = 22,
    String fingerprint = 'SHA256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  }) {
    return db.knownHostsDao.insertOrUpdateKnownHost(
      KnownHostsCompanion.insert(
        id: id,
        hostname: hostname,
        port: port,
        keyType: 'ssh-ed25519',
        fingerprintSha256: fingerprint,
        firstSeenAt: DateTime(2026, 3, 4),
      ),
    );
  }

  Future<void> pumpSection(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: ShadTheme(
          data: ShadThemeData(
            colorScheme: const ShadSlateColorScheme.light(),
            brightness: Brightness.light,
          ),
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: KnownHostsSettingsSection()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('KnownHostsSettingsSection', () {
    testWidgets('reports an empty trust store', (tester) async {
      await pumpSection(tester);

      expect(find.byKey(const Key('known_hosts_empty')), findsOneWidget);
    });

    testWidgets('lists stored keys sorted by hostname then port', (
      tester,
    ) async {
      await seed('id-b', 'beta.example.com');
      await seed('id-a2', 'alpha.example.com', port: 2222);
      await seed('id-a1', 'alpha.example.com');
      await pumpSection(tester);

      expect(find.byKey(const Key('known_hosts_empty')), findsNothing);
      expect(find.text('alpha.example.com:22'), findsOneWidget);
      expect(find.text('alpha.example.com:2222'), findsOneWidget);
      expect(find.text('beta.example.com:22'), findsOneWidget);

      final tiles = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((tile) => (tile.title as Text).data)
          .toList();
      expect(tiles, [
        'alpha.example.com:22',
        'alpha.example.com:2222',
        'beta.example.com:22',
      ]);
    });

    testWidgets('cancelling the confirm dialog keeps the key', (tester) async {
      await seed('id-a1', 'alpha.example.com');
      await pumpSection(tester);

      await tester.tap(find.byKey(const Key('forget_known_host_id-a1')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('forget_known_host_cancel_button')),
      );
      await tester.pumpAndSettle();

      expect(
        await db.knownHostsDao.findKnownHost('alpha.example.com', 22),
        isNotNull,
      );
      expect(find.byKey(const Key('known_host_id-a1')), findsOneWidget);
    });

    testWidgets('confirming forgets the key and refreshes the list', (
      tester,
    ) async {
      await seed('id-a1', 'alpha.example.com');
      await seed('id-b', 'beta.example.com');
      await pumpSection(tester);

      await tester.tap(find.byKey(const Key('forget_known_host_id-a1')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('forget_known_host_confirm_button')),
      );
      await tester.pumpAndSettle();

      expect(
        await db.knownHostsDao.findKnownHost('alpha.example.com', 22),
        isNull,
      );
      expect(find.byKey(const Key('known_host_id-a1')), findsNothing);
      expect(find.byKey(const Key('known_host_id-b')), findsOneWidget);
    });
  });
}
