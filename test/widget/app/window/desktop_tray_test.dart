import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/notifications/notification_providers.dart';
import 'package:shellvibe/app/router/app_router.dart';
import 'package:shellvibe/app/window/desktop_tray.dart';
import 'package:shellvibe/core/network/local_pty_manager.dart';
import 'package:shellvibe/core/network/providers/network_providers.dart';
import 'package:shellvibe/features/bookmarks/presentation/notifiers/bookmarks_notifier.dart';
import 'package:shellvibe/features/hosts/presentation/dialogs/connect_credentials_dialog.dart';
import 'package:shellvibe/features/hosts/presentation/notifiers/hosts_notifier.dart';
import 'package:shellvibe/features/settings/presentation/notifiers/settings_notifier.dart';
import 'package:shellvibe/features/templates/presentation/notifiers/templates_notifier.dart';
import 'package:shellvibe/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:shellvibe/features/tunnels/domain/models/tunnel_rule_model.dart';
import 'package:shellvibe/features/vault/presentation/notifiers/vault_notifier.dart';
import 'package:shellvibe/features/tunnels/presentation/providers/tunnels_providers.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:xterm3/xterm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late List<MethodCall> trayCalls;
  late List<MethodCall> windowCalls;
  late List<MethodCall> platformCalls;

  /// Tray and window calls in the order they were made, across both channels.
  late List<String> log;

  /// What the native side reports for `isPreventClose`: the last value the
  /// app set, which a test may overwrite to stage an intercepted close.
  late bool preventClose;
  late bool failSetIcon;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    trayCalls = [];
    windowCalls = [];
    platformCalls = [];
    log = [];
    preventClose = false;
    failSetIcon = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('tray_manager'), (
      call,
    ) async {
      trayCalls.add(call);
      log.add('tray.${call.method}');
      if (call.method == 'setIcon' && failSetIcon) {
        throw PlatformException(code: 'no_tray_host');
      }
      return null;
    });
    messenger.setMockMethodCallHandler(const MethodChannel('window_manager'), (
      call,
    ) async {
      windowCalls.add(call);
      switch (call.method) {
        case 'setPreventClose':
          preventClose = (call.arguments as Map)['isPreventClose'] as bool;
          log.add('window.setPreventClose($preventClose)');
        case 'isPreventClose':
          return preventClose;
        case 'isMinimized':
          return false;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      platformCalls.add(call);
      return null;
    });
  });

  tearDown(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('tray_manager'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      null,
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    debugTrayInterceptsCloseOverride = null;
    await db.close();
  });

  List<Map> menuItems(Map menu) => [
    for (final item in menu['items'] as List) item as Map,
  ];

  Map lastMenuJson() {
    final call = trayCalls.lastWhere((c) => c.method == 'setContextMenu');
    return (call.arguments as Map)['menu'] as Map;
  }

  int menuUpdates() =>
      trayCalls.where((c) => c.method == 'setContextMenu').length;

  /// Labels of the most recent tray menu, separators left out.
  List<String> lastMenu() => [
    for (final item in menuItems(lastMenuJson()))
      if (item['type'] != 'separator') item['label'] as String,
  ];

  /// Labels of the most recent menu's submenu whose title starts with
  /// [title], separators left out.
  List<String> lastSubmenu(String title) {
    final parent = menuItems(
      lastMenuJson(),
    ).firstWhere((item) => (item['label'] as String).startsWith(title));
    return [
      for (final item in menuItems(parent['submenu'] as Map))
        if (item['type'] != 'separator') item['label'] as String,
    ];
  }

  /// Clicks the item carrying [key], as the plugin reports it: by looking the
  /// item up in the menu last handed over.
  void clickTray(WidgetTester tester, String key) {
    final host = tester.state(find.byType(DesktopTrayHost)) as TrayListener;
    host.onTrayMenuItemClick(MenuItem(key: key));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<ProviderContainer> pumpTray(
    WidgetTester tester, {
    bool withNavigator = false,
    VaultState vault = const VaultState(status: VaultStatus.unlocked),
  }) async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        localPtyManagerProvider.overrideWithValue(_NoShellPtyManager()),
        vaultProvider.overrideWith(() => _TestVault(vault)),
      ],
    );
    await container.read(settingsProvider.future);
    await container.read(vaultProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withNavigator
            // The launcher's dialogs are shadcn ones, and are opened on the
            // root navigator through its key, as in the app.
            ? ShadApp(
                navigatorKey: rootNavigatorKey,
                home: const DesktopTrayHost(child: SizedBox.shrink()),
              )
            : const MaterialApp(
                home: DesktopTrayHost(child: SizedBox.shrink()),
              ),
      ),
    );
    await settle(tester);
    return container;
  }

  Future<void> unpump(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pumpAndSettle();
  }

  testWidgets('the tray shows what runs behind the window, and follows the '
      'setting', (tester) async {
    final container = await pumpTray(tester);

    expect(trayCalls.map((c) => c.method), contains('setIcon'));
    expect(lastMenu(), [
      'Show ShellVibe',
      'Sessions (0)',
      'Tunnels',
      'Favorites',
      'Templates',
      'Quit ShellVibe',
    ]);

    container.read(terminalTabsProvider.notifier).openLocalTab();
    await settle(tester);
    expect(lastMenu(), contains('Sessions (1)'));

    // An intercepted close while the tray is on hides the window; nothing
    // quits.
    preventClose = true;
    final host = tester.state(find.byType(DesktopTrayHost)) as WindowListener;
    host.onWindowClose();
    await settle(tester);
    expect(windowCalls.map((c) => c.method), contains('hide'));
    expect(windowCalls.map((c) => c.method), isNot(contains('destroy')));

    await container.read(settingsProvider.notifier).setKeepRunningInTray(false);
    await settle(tester);
    expect(trayCalls.last.method, 'destroy');

    await unpump(tester, container);
  });

  // window_manager reports every close, including the ones nothing
  // intercepted: on macOS every close, and on Windows or Linux any close with
  // the tray off. Treating those as a request to quit ended the whole app
  // when the red traffic light was clicked.
  testWidgets('a close that was not intercepted is left alone', (tester) async {
    debugTrayInterceptsCloseOverride = true;
    final container = await pumpTray(tester);
    await container.read(settingsProvider.notifier).setKeepRunningInTray(false);
    await settle(tester);
    windowCalls.clear();
    trayCalls.clear();

    preventClose = false;
    final host = tester.state(find.byType(DesktopTrayHost)) as WindowListener;
    host.onWindowClose();
    await settle(tester);

    expect(windowCalls.map((c) => c.method), isNot(contains('hide')));
    expect(windowCalls.map((c) => c.method), isNot(contains('destroy')));
    expect(
      platformCalls.map((c) => c.method),
      isNot(contains('SystemNavigator.pop')),
    );

    await unpump(tester, container);
  });

  testWidgets('the close is intercepted only once the icon is up', (
    tester,
  ) async {
    debugTrayInterceptsCloseOverride = true;
    final container = await pumpTray(tester);

    expect(preventClose, isTrue);
    expect(
      log.indexOf('tray.setIcon'),
      lessThan(log.indexOf('window.setPreventClose(true)')),
    );

    await unpump(tester, container);
  });

  // A desktop with no tray host still has to be closable: hiding the window
  // there leaves nothing on screen to bring it back.
  testWidgets('a tray that cannot show an icon leaves the close alone', (
    tester,
  ) async {
    debugTrayInterceptsCloseOverride = true;
    failSetIcon = true;
    final container = await pumpTray(tester);

    expect(trayCalls.map((c) => c.method), contains('setIcon'));
    expect(preventClose, isFalse);
    expect(
      windowCalls.where(
        (c) =>
            c.method == 'setPreventClose' &&
            (c.arguments as Map)['isPreventClose'] == true,
      ),
      isEmpty,
    );

    await unpump(tester, container);
  });

  group('the icon', () {
    List<String> iconPaths() => [
      for (final call in trayCalls.where((c) => c.method == 'setIcon'))
        (call.arguments as Map)['iconPath'] as String,
    ];

    Future<void> startForward(
      ProviderContainer container,
      String ruleId,
      String hostId,
    ) => container
        .read(tunnelEngineProvider)
        .startRemoteForward(
          ruleId: ruleId,
          hostId: hostId,
          sshClient: _FakeSshClient(),
          remotePort: 9000 + ruleId.length,
          localHost: '127.0.0.1',
          localPort: 8000,
        );

    testWidgets('starts plain, and marks a running tunnel', (tester) async {
      final container = await pumpTray(tester);
      expect(iconPaths(), hasLength(1));
      expect(iconPaths().single, isNot(contains('_tunnel')));
      expect(iconPaths().single, isNot(contains('_error')));

      await startForward(container, 'r1', 'h');
      await settle(tester);

      expect(iconPaths(), hasLength(2));
      expect(iconPaths().last, contains('_tunnel'));

      await unpump(tester, container);
    });

    testWidgets('is not set again for a change that keeps its state', (
      tester,
    ) async {
      final container = await pumpTray(tester);
      await startForward(container, 'r1', 'h');
      await settle(tester);
      final sets = iconPaths().length;

      // A second forward changes the menu, not the icon; a tunnel's transfer
      // ticks land here too.
      await startForward(container, 'r22', 'h');
      await settle(tester);

      expect(iconPaths(), hasLength(sets));

      await unpump(tester, container);
    });

    testWidgets('shows an error until the window is back in front', (
      tester,
    ) async {
      final container = await pumpTray(tester);
      await startForward(container, 'r1', 'h');
      await settle(tester);

      container.read(trayAttentionProvider.notifier).raise();
      await settle(tester);
      expect(iconPaths().last, contains('_error'));

      // Focus returning is what clears it; the tunnel is still up, so the
      // icon falls back to that state rather than to plain.
      final host = tester.state(find.byType(DesktopTrayHost)) as WindowListener;
      host.onWindowFocus();
      await settle(tester);
      expect(container.read(trayAttentionProvider), isFalse);
      expect(iconPaths().last, contains('_tunnel'));

      await unpump(tester, container);
    });

    testWidgets('an error needs no tunnel, and a restore clears it too', (
      tester,
    ) async {
      final container = await pumpTray(tester);
      container.read(trayAttentionProvider.notifier).raise();
      await settle(tester);
      expect(iconPaths().last, contains('_error'));

      final host = tester.state(find.byType(DesktopTrayHost)) as WindowListener;
      host.onWindowRestore();
      await settle(tester);
      expect(iconPaths().last, isNot(contains('_error')));
      expect(iconPaths().last, isNot(contains('_tunnel')));

      await unpump(tester, container);
    });
  });

  group('the menu', () {
    testWidgets('lists the open sessions and marks one that is not live', (
      tester,
    ) async {
      final container = await pumpTray(tester);
      expect(lastSubmenu('Sessions'), ['No open sessions']);

      // The stand-in pty manager never attaches a shell, so this tab is one
      // whose session is not live.
      container.read(terminalTabsProvider.notifier).openLocalTab();
      await settle(tester);

      final sessions = lastSubmenu('Sessions (1)');
      expect(sessions, hasLength(1));
      expect(sessions.single, startsWith('○ '));
      expect(sessions.single, endsWith(' — disconnected'));

      await unpump(tester, container);
    });

    testWidgets('clicking a session shows the window and focuses its tab', (
      tester,
    ) async {
      final container = await pumpTray(tester);
      final tabs = container.read(terminalTabsProvider.notifier);
      tabs.openLocalTab();
      tabs.openLocalTab();
      await settle(tester);
      final ids = [
        for (final tab in container.read(terminalTabsProvider).tabs) tab.id,
      ];
      expect(container.read(terminalTabsProvider).activeTabId, ids.last);
      windowCalls.clear();

      clickTray(tester, 'tab:${ids.first}');
      await settle(tester);

      expect(windowCalls.map((c) => c.method), contains('show'));
      expect(container.read(terminalTabsProvider).activeTabId, ids.first);

      await unpump(tester, container);
    });

    testWidgets('a change the menu does not show does not rebuild it', (
      tester,
    ) async {
      final container = await pumpTray(tester);
      final tabs = container.read(terminalTabsProvider.notifier);
      tabs.openLocalTab();
      tabs.openLocalTab();
      await settle(tester);
      final updates = menuUpdates();

      // Moving the selection re-emits the tab state, but no row changes.
      tabs.setActiveTab(container.read(terminalTabsProvider).tabs.first.id);
      await settle(tester);

      expect(menuUpdates(), updates);

      await unpump(tester, container);
    });

    testWidgets('a running tunnel is stopped from the tray', (tester) async {
      final container = await pumpTray(tester);
      final host = await container
          .read(hostsProvider.notifier)
          .addHost(
            workspaceId: 'default',
            label: 'prod',
            hostname: 'prod.example.com',
          );
      final engine = container.read(tunnelEngineProvider);
      await engine.startRemoteForward(
        ruleId: 'r1',
        hostId: host.id,
        sshClient: _FakeSshClient(),
        remotePort: 9000,
        localHost: '127.0.0.1',
        localPort: 8000,
      );
      await settle(tester);

      expect(lastMenu(), contains('Tunnels (1 active)'));
      expect(lastSubmenu('Tunnels'), ['Stop  prod · R 9000 → 127.0.0.1:8000']);

      clickTray(tester, 'tunnel.stop:r1');
      // Cancelling a subscription hands back a future from the root zone, so
      // its continuation runs on the real event loop rather than the test's.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await settle(tester);

      expect(engine.isTunnelActive('r1'), isFalse);
      expect(lastMenu(), contains('Tunnels'));
      expect(lastSubmenu('Tunnels'), ['No tunnels']);

      await unpump(tester, container);
    });

    testWidgets('a saved tunnel that is not running offers to start', (
      tester,
    ) async {
      final container = await pumpTray(tester);
      final host = await container
          .read(hostsProvider.notifier)
          .addHost(
            workspaceId: 'default',
            label: 'prod',
            hostname: 'prod.example.com',
          );
      await container
          .read(tunnelsProvider.notifier)
          .addRule(
            TunnelRuleModel(
              id: 'r1',
              hostId: host.id,
              type: 'local',
              localPort: 8080,
              remoteHost: 'db',
              remotePort: 5432,
            ),
          );
      await settle(tester);

      expect(lastSubmenu('Tunnels'), ['Start  prod · L 8080 → db:5432']);

      // This host has no stored identity, so starting needs the credential
      // prompt, and a prompt needs the window: it comes up rather than the
      // start failing silently.
      windowCalls.clear();
      clickTray(tester, 'tunnel.start:r1');
      await settle(tester);
      expect(windowCalls.map((c) => c.method), contains('show'));

      await unpump(tester, container);
    });

    testWidgets('favorites and templates follow the bookmarks', (tester) async {
      final container = await pumpTray(tester);
      expect(lastSubmenu('Favorites'), ['No favorites']);
      expect(lastSubmenu('Templates'), ['No templates']);

      final host = await container
          .read(hostsProvider.notifier)
          .addHost(
            workspaceId: 'default',
            label: 'prod',
            hostname: 'prod.example.com',
          );
      container.read(terminalTabsProvider.notifier).openLocalTab();
      final template = await container
          .read(templatesProvider.notifier)
          .saveCurrentLayout(name: 'Dev layout');
      await container.read(bookmarksProvider.future);
      await container.read(bookmarksProvider.notifier).toggleHost(host.id);
      await container
          .read(bookmarksProvider.notifier)
          .toggleTemplate(template!.id);
      await settle(tester);

      expect(lastSubmenu('Favorites'), ['prod', 'Dev layout']);
      expect(lastSubmenu('Templates'), ['Dev layout']);

      await unpump(tester, container);
    });

    testWidgets('a template is replayed from the tray', (tester) async {
      final container = await pumpTray(tester, withNavigator: true);
      container.read(terminalTabsProvider.notifier).openLocalTab();
      final template = await container
          .read(templatesProvider.notifier)
          .saveCurrentLayout(name: 'Dev layout');
      await settle(tester);
      expect(lastSubmenu('Templates'), ['Dev layout']);
      expect(lastMenu(), contains('Sessions (1)'));
      windowCalls.clear();

      clickTray(tester, 'template:${template!.id}');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await settle(tester);

      expect(windowCalls.map((c) => c.method), contains('show'));
      expect(lastMenu(), contains('Sessions (2)'));

      await unpump(tester, container);
    });

    group('while the vault is locked', () {
      /// A host, a session, a favorite, a template and a saved tunnel, all
      /// with names the locked menu must not repeat.
      Future<({String hostId, String templateId, String tabId})> fill(
        ProviderContainer container,
        WidgetTester tester,
      ) async {
        final host = await container
            .read(hostsProvider.notifier)
            .addHost(
              workspaceId: 'default',
              label: 'secret-prod',
              hostname: 'secret.example.com',
            );
        final tabs = container.read(terminalTabsProvider.notifier);
        tabs.openLocalTab(title: 'secret-tab');
        final template = await container
            .read(templatesProvider.notifier)
            .saveCurrentLayout(name: 'secret-layout');
        await container.read(bookmarksProvider.future);
        await container.read(bookmarksProvider.notifier).toggleHost(host.id);
        await container
            .read(tunnelsProvider.notifier)
            .addRule(
              TunnelRuleModel(
                id: 'r1',
                hostId: host.id,
                type: 'local',
                localPort: 48080,
                remoteHost: 'secret-db',
                remotePort: 5432,
              ),
            );
        await settle(tester);
        return (
          hostId: host.id,
          templateId: template!.id,
          tabId: container.read(terminalTabsProvider).tabs.single.id,
        );
      }

      testWidgets('the menu shows counts and nothing that names anything', (
        tester,
      ) async {
        final container = await pumpTray(tester);
        await fill(container, tester);
        expect(lastSubmenu('Favorites'), ['secret-prod']);

        final vault = container.read(vaultProvider.notifier) as _TestVault;
        vault.set(const VaultState(status: VaultStatus.locked));
        await settle(tester);

        expect(lastMenu(), [
          'Unlock ShellVibe…',
          '1 open session',
          '0 active tunnels',
          'Quit ShellVibe',
        ]);
        final dump = jsonEncode(lastMenuJson());
        for (final leak in [
          'secret',
          'prod',
          '48080',
          'tab',
          'layout',
          'Sessions',
          'Tunnels',
          'Favorites',
          'Templates',
        ]) {
          expect(dump, isNot(contains(leak)));
        }

        // Unlocking brings the full menu back.
        vault.set(const VaultState(status: VaultStatus.unlocked));
        await settle(tester);
        expect(lastMenu(), contains('Sessions (1)'));
        expect(lastSubmenu('Favorites'), ['secret-prod']);

        await unpump(tester, container);
      });

      testWidgets('a lock still draining counts as locked', (tester) async {
        final container = await pumpTray(tester);
        final vault = container.read(vaultProvider.notifier) as _TestVault;

        vault.set(
          const VaultState(status: VaultStatus.unlocked, isLocking: true),
        );
        await settle(tester);

        expect(lastMenu().first, 'Unlock ShellVibe…');

        await unpump(tester, container);
      });

      testWidgets('a stale click only brings the window up', (tester) async {
        final container = await pumpTray(tester, withNavigator: true);
        final ids = await fill(container, tester);
        // Another tab, so focusing the first one would be visible.
        container.read(terminalTabsProvider.notifier).openLocalTab();
        await settle(tester);
        final activeBefore = container.read(terminalTabsProvider).activeTabId;
        expect(activeBefore, isNot(ids.tabId));
        final tabCount = container.read(terminalTabsProvider).tabs.length;

        final vault = container.read(vaultProvider.notifier) as _TestVault;
        vault.set(const VaultState(status: VaultStatus.locked));
        await settle(tester);
        windowCalls.clear();

        // Keys of the menu that was on screen before the lock.
        for (final key in [
          'tab:${ids.tabId}',
          'host:${ids.hostId}',
          'template:${ids.templateId}',
          'tunnel.start:r1',
        ]) {
          clickTray(tester, key);
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await settle(tester);
        }

        expect(
          windowCalls.where((c) => c.method == 'show'),
          hasLength(4),
          reason: 'each click lands on the lock screen',
        );
        // Nothing acted: no focus change, no session or template replay, and
        // neither the launcher nor a tunnel start raised its credential
        // prompt.
        expect(container.read(terminalTabsProvider).activeTabId, activeBefore);
        expect(container.read(terminalTabsProvider).tabs, hasLength(tabCount));
        expect(find.byType(ConnectCredentialsDialog), findsNothing);
        expect(container.read(tunnelsProvider).error, isNull);

        await unpump(tester, container);
      });

      testWidgets('a tunnel can still be stopped from a stale menu', (
        tester,
      ) async {
        final container = await pumpTray(tester);
        final engine = container.read(tunnelEngineProvider);
        await engine.startRemoteForward(
          ruleId: 'r1',
          hostId: 'h',
          sshClient: _FakeSshClient(),
          remotePort: 9000,
          localHost: '127.0.0.1',
          localPort: 8000,
        );
        await settle(tester);
        final vault = container.read(vaultProvider.notifier) as _TestVault;
        vault.set(const VaultState(status: VaultStatus.locked));
        await settle(tester);
        expect(lastMenu(), contains('1 active tunnel'));

        clickTray(tester, 'tunnel.stop:r1');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await settle(tester);

        expect(engine.isTunnelActive('r1'), isFalse);

        await unpump(tester, container);
      });
    });

    testWidgets('a favorite host is connected through the launcher', (
      tester,
    ) async {
      final container = await pumpTray(tester, withNavigator: true);
      final host = await container
          .read(hostsProvider.notifier)
          .addHost(
            workspaceId: 'default',
            label: 'prod',
            hostname: 'prod.example.com',
          );
      await settle(tester);
      windowCalls.clear();

      clickTray(tester, 'host:${host.id}');
      await tester.pump(const Duration(milliseconds: 100));

      // No stored identity, so the launcher's credential prompt opens on the
      // root navigator once the window is up.
      expect(windowCalls.map((c) => c.method), contains('show'));
      expect(find.byType(ConnectCredentialsDialog), findsOneWidget);

      await unpump(tester, container);
    });
  });
}

/// Widget tests must not start real shells.
class _NoShellPtyManager extends LocalPtyManager {
  @override
  Future<TerminalLocalPtyBridge?> startAndBridge(
    Terminal terminal, {
    String? executable,
    List<String> arguments = const [],
    String? workingDirectory,
    Map<String, String>? environment,
    int rows = 24,
    int columns = 80,
    void Function(Uint8List bytes)? outputTap,
  }) async => null;
}

class _FakeSshRemoteForward extends Fake implements SSHRemoteForward {
  @override
  Stream<SSHForwardChannel> get connections => const Stream.empty();

  @override
  void close() {}
}

/// Just enough client for a remote forward to come up.
class _FakeSshClient extends Fake implements SSHClient {
  @override
  Future<SSHRemoteForward?> forwardRemote({
    dynamic filter,
    String? host,
    int? port,
  }) async => _FakeSshRemoteForward();
}

/// A vault whose state the test sets directly, with no key service behind it.
class _TestVault extends VaultNotifier {
  _TestVault(this._initial);

  final VaultState _initial;

  @override
  Future<VaultState> build() async => _initial;

  void set(VaultState next) => state = AsyncData(next);
}
