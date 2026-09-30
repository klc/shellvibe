import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/notifications/desktop_notification_host.dart';
import 'package:shellvibe/app/notifications/notification_policy.dart';
import 'package:shellvibe/app/notifications/notification_presenter.dart';
import 'package:shellvibe/app/notifications/notification_providers.dart';
import 'package:shellvibe/core/network/local_pty_manager.dart';
import 'package:shellvibe/core/network/providers/network_providers.dart';
import 'package:shellvibe/features/settings/presentation/notifiers/settings_notifier.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_tab_session.dart';
import 'package:shellvibe/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:shellvibe/features/tunnels/presentation/providers/tunnels_providers.dart';
import 'package:shellvibe/features/vault/presentation/notifiers/vault_notifier.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';
import 'package:xterm3/xterm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _FakePresenter presenter;
  late _FakePresence presence;
  late List<String> windowCalls;

  const hidden = WindowPresence(
    visible: false,
    focused: false,
    minimized: false,
  );
  const inFront = WindowPresence(
    visible: true,
    focused: true,
    minimized: false,
  );

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    presenter = _FakePresenter();
    presence = _FakePresence(hidden);
    windowCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (
          call,
        ) async {
          windowCalls.add(call.method);
          if (call.method == 'isMinimized') return false;
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
    await db.close();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<ProviderContainer> pumpHost(
    WidgetTester tester, {
    VaultState vault = const VaultState(status: VaultStatus.unlocked),
  }) async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        localPtyManagerProvider.overrideWithValue(_NoShellPtyManager()),
        vaultProvider.overrideWith(() => _TestVault(vault)),
        notificationPresenterProvider.overrideWithValue(presenter),
        windowPresenceReaderProvider.overrideWithValue(presence),
      ],
    );
    await container.read(settingsProvider.future);
    await container.read(vaultProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: DesktopNotificationHost(child: SizedBox.shrink()),
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

  /// Opens a local tab (the stand-in pty manager never attaches a shell) and
  /// marks it live, re-emitting the tab list the way the notifier does when a
  /// session connects.
  Future<TerminalTabSession> openLiveTab(
    WidgetTester tester,
    ProviderContainer container, {
    String title = 'build box',
  }) async {
    final tabs = container.read(terminalTabsProvider.notifier);
    tabs.openLocalTab(title: title);
    await settle(tester);
    final tab = container.read(terminalTabsProvider).tabs.last;
    tab.isConnecting = false;
    tab.isConnected = true;
    tabs.setActiveTab(tab.id);
    await settle(tester);
    return tab;
  }

  /// A session dropping, as the connector records it.
  Future<void> drop(
    WidgetTester tester,
    ProviderContainer container,
    TerminalTabSession tab, {
    TerminalDisconnectCause cause = TerminalDisconnectCause.connectionLost,
  }) async {
    tab.isConnected = false;
    tab.disconnectCause = cause;
    final active = container.read(terminalTabsProvider).activeTabId!;
    container.read(terminalTabsProvider.notifier).setActiveTab(active);
    await settle(tester);
  }

  testWidgets('a session that drops while the window is hidden is notified', (
    tester,
  ) async {
    final container = await pumpHost(tester);
    final tab = await openLiveTab(tester, container);

    await drop(tester, container, tab);

    expect(presenter.shown, hasLength(1));
    expect(presenter.shown.single.title, 'Session disconnected');
    expect(presenter.shown.single.body, 'build box lost its connection.');
    expect(presenter.shown.single.payload, 'tab:${tab.id}');
    expect(container.read(trayAttentionProvider), isTrue);

    await unpump(tester, container);
  });

  testWidgets('a shell that exits is a notification but not an error icon', (
    tester,
  ) async {
    final container = await pumpHost(tester);
    final tab = await openLiveTab(tester, container);

    await drop(
      tester,
      container,
      tab,
      cause: TerminalDisconnectCause.remoteExit,
    );

    expect(presenter.shown.single.title, 'Session ended');
    expect(container.read(trayAttentionProvider), isFalse);

    await unpump(tester, container);
  });

  testWidgets('nothing for the tab being looked at in a focused window', (
    tester,
  ) async {
    presence.value = inFront;
    final container = await pumpHost(tester);
    final tab = await openLiveTab(tester, container);

    await drop(tester, container, tab);

    expect(presenter.shown, isEmpty);
    expect(container.read(trayAttentionProvider), isFalse);

    await unpump(tester, container);
  });

  testWidgets('a tab in the background is notified in a focused window, '
      'with no error icon', (tester) async {
    presence.value = inFront;
    final container = await pumpHost(tester);
    final background = await openLiveTab(tester, container, title: 'logs');
    await openLiveTab(tester, container, title: 'editor');

    await drop(tester, container, background);

    expect(presenter.shown.single.body, 'logs lost its connection.');
    expect(container.read(trayAttentionProvider), isFalse);

    await unpump(tester, container);
  });

  testWidgets('while the vault is locked the text names nothing', (
    tester,
  ) async {
    final container = await pumpHost(
      tester,
      vault: const VaultState(status: VaultStatus.locked),
    );
    final tab = await openLiveTab(tester, container, title: 'prod-db');

    await drop(tester, container, tab);

    expect(presenter.shown.single.body, 'A session disconnected');
    expect(
      '${presenter.shown.single.title} ${presenter.shown.single.body}',
      isNot(contains('prod-db')),
    );

    await unpump(tester, container);
  });

  testWidgets(
    'with notifications off nothing is sent, but the icon is raised',
    (tester) async {
      final container = await pumpHost(tester);
      await container
          .read(settingsProvider.notifier)
          .setDesktopNotifications(false);
      final tab = await openLiveTab(tester, container);

      await drop(tester, container, tab);

      expect(presenter.shown, isEmpty);
      expect(container.read(trayAttentionProvider), isTrue);

      await unpump(tester, container);
    },
  );

  group('the terminal asking for attention', () {
    testWidgets('a burst of bells is one notification', (tester) async {
      final container = await pumpHost(tester);
      final tab = await openLiveTab(tester, container);

      for (var i = 0; i < 10; i++) {
        tab.terminal.write('\x07');
        await settle(tester);
      }

      expect(presenter.shown, hasLength(1));
      expect(presenter.shown.single.body, 'The terminal rang the bell.');
      // A bell is a program asking for attention, not a failure.
      expect(container.read(trayAttentionProvider), isFalse);

      await unpump(tester, container);
    });

    testWidgets('OSC 9 carries its message', (tester) async {
      final container = await pumpHost(tester);
      final tab = await openLiveTab(tester, container);

      tab.terminal.write('\x1b]9;build done\x07');
      await settle(tester);

      expect(presenter.shown.single.title, 'build box');
      expect(presenter.shown.single.body, 'build done');

      await unpump(tester, container);
    });

    testWidgets('OSC 777 notify carries its title and body', (tester) async {
      final container = await pumpHost(tester);
      final tab = await openLiveTab(tester, container);

      tab.terminal.write('\x1b]777;notify;CI;all green\x07');
      await settle(tester);

      expect(presenter.shown.single.title, 'CI');
      expect(presenter.shown.single.body, 'all green');

      await unpump(tester, container);
    });

    testWidgets('the tab being looked at is not interrupted', (tester) async {
      presence.value = inFront;
      final container = await pumpHost(tester);
      final tab = await openLiveTab(tester, container);

      tab.terminal.write('\x07\x1b]9;done\x07');
      await settle(tester);

      expect(presenter.shown, isEmpty);

      await unpump(tester, container);
    });

    testWidgets('a tab opened later reports too, and chaining keeps an '
        'existing handler', (tester) async {
      final container = await pumpHost(tester);
      final tabs = container.read(terminalTabsProvider.notifier);
      tabs.openLocalTab(title: 'first');
      await settle(tester);
      final tab = container.read(terminalTabsProvider).tabs.single;

      var ringed = 0;
      final hooked = tab.terminal.onBell!;
      tab.terminal.onBell = () {
        ringed++;
        hooked();
      };
      tab.terminal.write('\x07');
      await settle(tester);

      expect(ringed, 1);
      expect(presenter.shown, hasLength(1));

      await unpump(tester, container);
    });
  });

  group('a failed tunnel', () {
    testWidgets('is notified with its error', (tester) async {
      final container = await pumpHost(tester);

      await container
          .read(tunnelEngineProvider)
          .startRemoteForward(
            ruleId: 'r1',
            hostId: 'h',
            sshClient: _RefusingSshClient(),
            remotePort: 9000,
            localHost: '127.0.0.1',
            localPort: 8000,
          );
      await settle(tester);

      expect(presenter.shown, hasLength(1));
      expect(presenter.shown.single.title, 'Tunnel stopped');
      expect(presenter.shown.single.body, contains('refused by the server'));
      expect(presenter.shown.single.payload, 'tunnels');
      expect(container.read(trayAttentionProvider), isTrue);

      await unpump(tester, container);
    });

    testWidgets('a user stopping a tunnel is not a failure', (tester) async {
      final container = await pumpHost(tester);
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

      await tester.runAsync(() => engine.stopTunnel('r1'));
      await settle(tester);

      expect(presenter.shown, isEmpty);
      expect(container.read(trayAttentionProvider), isFalse);

      await unpump(tester, container);
    });
  });

  group('clicking a notification', () {
    testWidgets('shows the window and selects the tab', (tester) async {
      final container = await pumpHost(tester);
      final first = await openLiveTab(tester, container, title: 'first');
      await openLiveTab(tester, container, title: 'second');
      expect(container.read(terminalTabsProvider).activeTabId, isNot(first.id));
      // A click can only follow a notification, and the first one is what
      // starts listening for it.
      await drop(tester, container, first);
      expect(presenter.shown, hasLength(1));
      windowCalls.clear();

      presenter.click('tab:${first.id}');
      await settle(tester);

      expect(windowCalls, contains('show'));
      expect(container.read(terminalTabsProvider).activeTabId, first.id);

      await unpump(tester, container);
    });

    testWidgets('a tab closed since only shows the window', (tester) async {
      final container = await pumpHost(tester);
      final tab = await openLiveTab(tester, container);
      await drop(tester, container, tab);
      expect(presenter.shown, hasLength(1));
      windowCalls.clear();

      presenter.click('tab:gone');
      await settle(tester);

      expect(windowCalls, contains('show'));
      expect(container.read(terminalTabsProvider).activeTabId, tab.id);

      await unpump(tester, container);
    });

    testWidgets('after a lock only brings the window up', (tester) async {
      final container = await pumpHost(tester);
      final first = await openLiveTab(tester, container, title: 'first');
      await openLiveTab(tester, container, title: 'second');
      final second = container.read(terminalTabsProvider).activeTabId;
      await drop(tester, container, first);
      expect(presenter.shown, hasLength(1));

      // The notification was sent unlocked; the vault locks before the click.
      (container.read(vaultProvider.notifier) as _TestVault).set(
        const VaultState(status: VaultStatus.locked),
      );
      await settle(tester);
      windowCalls.clear();

      presenter.click(presenter.shown.single.payload);
      await settle(tester);

      expect(windowCalls, contains('show'));
      expect(container.read(terminalTabsProvider).activeTabId, second);

      await unpump(tester, container);
    });
  });
}

class _FakePresenter implements NotificationPresenter {
  final shown = <NotificationRequest>[];
  final _clicks = StreamController<String?>.broadcast();

  void click(String? payload) => _clicks.add(payload);

  @override
  Stream<String?> get clicks => _clicks.stream;

  @override
  Future<bool> ensurePermission() async => true;

  @override
  Future<void> show(NotificationRequest request) async => shown.add(request);

  @override
  Future<void> dispose() => _clicks.close();
}

class _FakePresence implements WindowPresenceReader {
  _FakePresence(this.value);

  WindowPresence value;

  @override
  Future<WindowPresence> read() async => value;
}

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

class _FakeSshClient extends Fake implements SSHClient {
  @override
  Future<SSHRemoteForward?> forwardRemote({
    dynamic filter,
    String? host,
    int? port,
  }) async => _FakeSshRemoteForward();
}

/// A server that refuses the remote forward, which the engine records as a
/// stopped tunnel with an error.
class _RefusingSshClient extends Fake implements SSHClient {
  @override
  Future<SSHRemoteForward?> forwardRemote({
    dynamic filter,
    String? host,
    int? port,
  }) async => null;
}

class _TestVault extends VaultNotifier {
  _TestVault(this._initial);

  final VaultState _initial;

  @override
  Future<VaultState> build() async => _initial;

  void set(VaultState next) => state = AsyncData(next);
}
