import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shellvibe/app/quick_actions/app_shortcuts.dart';
import 'package:shellvibe/app/quick_actions/quick_actions_controller.dart';
import 'package:shellvibe/app/quick_actions/quick_actions_host.dart';
import 'package:shellvibe/app/router/app_router.dart';
import 'package:shellvibe/core/utils/platform_capabilities.dart';
import 'package:shellvibe/features/bookmarks/domain/models/bookmark_model.dart';
import 'package:shellvibe/features/bookmarks/presentation/notifiers/bookmarks_notifier.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/hosts/presentation/notifiers/hosts_notifier.dart';
import 'package:shellvibe/features/vault/presentation/notifiers/vault_notifier.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

class _FakeGateway implements QuickActionsGateway {
  void Function(String type)? onType;
  final List<List<AppShortcut>> sets = [];

  @override
  Future<void> initialize(void Function(String type) onType) async {
    this.onType = onType;
  }

  @override
  Future<void> setShortcuts(List<AppShortcut> shortcuts) async {
    sets.add(shortcuts);
  }

  List<String> get lastTypes => [for (final s in sets.last) s.type];
}

class _TestVault extends VaultNotifier {
  _TestVault(this.initial);

  final VaultStatus initial;

  @override
  Future<VaultState> build() async => VaultState(status: initial);

  void setStatus(VaultStatus status) =>
      state = AsyncData(VaultState(status: status));
}

class _TestHosts extends HostsNotifier {
  _TestHosts(this.initial);

  final List<HostModel> initial;

  @override
  Future<List<HostModel>> build() async => initial;

  void replace(List<HostModel> hosts) => state = AsyncData(hosts);
}

class _TestBookmarks extends BookmarksNotifier {
  _TestBookmarks(this.initial);

  final List<BookmarkModel> initial;

  @override
  Future<List<BookmarkModel>> build() async => initial;

  void replace(List<BookmarkModel> bookmarks) => state = AsyncData(bookmarks);
}

HostModel _host(String id) => HostModel(
  id: id,
  workspaceId: 'default',
  label: 'Host $id',
  hostname: '$id.example.com',
  createdAt: DateTime(2026),
);

BookmarkModel _bookmark(String hostId) => BookmarkModel(
  id: 'b-$hostId',
  workspaceId: 'default',
  hostId: hostId,
  createdAt: DateTime(2026),
);

void main() {
  late _FakeGateway gateway;
  late _TestVault vault;
  late _TestHosts hosts;
  late _TestBookmarks bookmarks;

  // The host only exists on a phone, where there is no local shell to offer.
  setUp(() => debugPlatformCapabilitiesOverride = TargetPlatform.iOS);
  tearDown(() => debugPlatformCapabilitiesOverride = null);

  Future<void> pumpHost(
    WidgetTester tester, {
    VaultStatus status = VaultStatus.unlocked,
    List<HostModel>? initialHosts,
    List<BookmarkModel>? initialBookmarks,
    List<Override> extraOverrides = const [],
  }) async {
    gateway = _FakeGateway();
    vault = _TestVault(status);
    hosts = _TestHosts(initialHosts ?? [_host('a'), _host('b')]);
    bookmarks = _TestBookmarks(initialBookmarks ?? [_bookmark('b')]);

    final router = GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: '/terminal',
      routes: [
        GoRoute(
          path: '/terminal',
          builder: (_, _) => const Scaffold(body: Text('terminal')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          quickActionsGatewayProvider.overrideWithValue(gateway),
          vaultProvider.overrideWith(() => vault),
          hostsProvider.overrideWith(() => hosts),
          bookmarksProvider.overrideWith(() => bookmarks),
          ...extraOverrides,
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) =>
              QuickActionsHost(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Past the debounce.
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('registers bookmarked hosts and Quick connect once loaded', (
    tester,
  ) async {
    await pumpHost(tester);

    expect(gateway.sets, hasLength(1));
    expect(gateway.lastTypes, ['host:b', kQuickConnectShortcutType]);
    expect(gateway.sets.last.first.title, 'Host b');
  });

  testWidgets('follows bookmark and host changes, debounced', (tester) async {
    await pumpHost(tester);

    bookmarks.replace([_bookmark('a'), _bookmark('b')]);
    await tester.pump();
    hosts.replace([_host('a'), _host('b'), _host('c')]);
    await tester.pump();
    expect(gateway.sets, hasLength(1), reason: 'waits for the burst to end');

    await tester.pump(const Duration(seconds: 1));
    expect(gateway.sets, hasLength(2));
    expect(gateway.lastTypes, ['host:a', 'host:b', kQuickConnectShortcutType]);
  });

  testWidgets('a locked vault registers only the generic shortcut', (
    tester,
  ) async {
    await pumpHost(tester, status: VaultStatus.locked);

    expect(gateway.sets, hasLength(1));
    expect(gateway.lastTypes, [kQuickConnectShortcutType]);
  });

  testWidgets('locking pulls host names off the menu at once', (tester) async {
    await pumpHost(tester);
    expect(gateway.lastTypes, contains('host:b'));

    vault.setStatus(VaultStatus.locked);
    await tester.pump();
    await tester.pump(); // the platform call is asynchronous, not debounced

    expect(gateway.lastTypes, [kQuickConnectShortcutType]);

    vault.setStatus(VaultStatus.unlocked);
    await tester.pump(const Duration(seconds: 1));
    expect(gateway.lastTypes, ['host:b', kQuickConnectShortcutType]);
  });

  testWidgets('a press on an unlocked app runs straight away', (tester) async {
    await pumpHost(tester);

    gateway.onType!(kQuickConnectShortcutType);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('select_host_search_input')), findsOneWidget);
    expect(find.text('Host a'), findsOneWidget);
  });

  testWidgets(
    'a cold-start press waits behind the lock and runs after unlock',
    (tester) async {
      await pumpHost(tester, status: VaultStatus.locked);

      gateway.onType!(kQuickConnectShortcutType);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('select_host_search_input')),
        findsNothing,
        reason: 'the lock must not be bypassed',
      );

      vault.setStatus(VaultStatus.unlocked);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('select_host_search_input')), findsOneWidget);
    },
  );

  testWidgets('a press for a deleted host is ignored', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await pumpHost(
      tester,
      extraOverrides: [appDatabaseProvider.overrideWithValue(db)],
    );

    gateway.onType!('host:deleted-long-ago');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('select_host_search_input')), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('types this build does not know are dropped', (tester) async {
    await pumpHost(tester);

    gateway.onType!('host:');
    gateway.onType!('not_a_shortcut');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('select_host_search_input')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
