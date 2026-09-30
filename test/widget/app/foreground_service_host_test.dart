import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/foreground_service/foreground_service_gateway.dart';
import 'package:shellvibe/app/foreground_service/foreground_service_host.dart';
import 'package:shellvibe/core/network/tunnel_engine.dart';
import 'package:shellvibe/core/utils/platform_capabilities.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_tab_session.dart';
import 'package:shellvibe/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:shellvibe/features/tunnels/presentation/providers/tunnels_providers.dart';
import 'package:xterm3/xterm.dart';

class _FakeGateway implements ForegroundServiceGateway {
  final List<String> calls = [];
  void Function()? onDisconnectAll;
  bool running = false;

  @override
  Future<void> initialize({required void Function() onDisconnectAll}) async {
    this.onDisconnectAll = onDisconnectAll;
    calls.add('initialize');
  }

  @override
  Future<void> requestNotificationPermission() async => calls.add('permission');

  @override
  Future<void> start(ServiceNotificationContent content) async {
    running = true;
    calls.add('start:${content.text}');
  }

  @override
  Future<void> update(ServiceNotificationContent content) async =>
      calls.add('update:${content.text}');

  @override
  Future<void> stop() async {
    if (!running) return;
    running = false;
    calls.add('stop');
  }

  @override
  void dispose() {}

  List<String> get serviceCalls =>
      calls.where((c) => c != 'initialize' && c != 'permission').toList();
}

/// Tabs without the connector, database and sockets the real notifier builds.
/// Closing follows the real one's cascade: a root takes its split panes along.
class _FakeTabs extends TerminalTabsNotifier {
  _FakeTabs(this.initial);

  final List<TerminalTabSession> initial;
  final List<String> closed = [];

  @override
  TerminalTabsState build() => TerminalTabsState(tabs: initial);

  void setTabs(List<TerminalTabSession> tabs) =>
      state = state.copyWith(tabs: tabs);

  @override
  Future<void> closeTab(String tabId) async {
    closed.add(tabId);
    state = state.copyWith(
      tabs: [
        for (final tab in state.tabs)
          if (tab.id != tabId && tab.splitParentId != tabId) tab,
      ],
    );
  }
}

class _FakeTunnels extends TunnelsNotifier {
  final List<String> stopped = [];

  @override
  TunnelsState build() => const TunnelsState();

  @override
  Future<void> stopRule(String id) async => stopped.add(id);
}

TerminalTabSession _tab(
  String id, {
  bool connected = true,
  String? splitParentId,
}) => TerminalTabSession(
  id: id,
  title: 'secret-host-$id',
  sessionType: TerminalSessionType.ssh,
  terminal: Terminal(),
  isConnected: connected,
  splitParentId: splitParentId,
);

ActiveTunnel _tunnel(String id, {int speed = 0}) => ActiveTunnel(
  ruleId: id,
  hostId: 'host',
  type: 'local',
  localPort: 8080,
  speedBytesPerSec: speed,
);

void main() {
  late _FakeGateway gateway;
  late _FakeTabs tabs;
  late _FakeTunnels tunnels;
  late StreamController<List<ActiveTunnel>> tunnelFeed;

  setUp(() => debugPlatformCapabilitiesOverride = TargetPlatform.android);
  tearDown(() => debugPlatformCapabilitiesOverride = null);

  Future<void> pumpHost(
    WidgetTester tester, {
    List<TerminalTabSession> initialTabs = const [],
  }) async {
    gateway = _FakeGateway();
    tabs = _FakeTabs(initialTabs);
    tunnels = _FakeTunnels();
    // Broadcast: closing a single-subscription controller nobody listens to
    // never completes, which would hang the tear-down.
    tunnelFeed = StreamController<List<ActiveTunnel>>.broadcast();
    addTearDown(() => unawaited(tunnelFeed.close()));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          foregroundServiceGatewayProvider.overrideWithValue(gateway),
          terminalTabsProvider.overrideWith(() => tabs),
          tunnelsProvider.overrideWith(() => tunnels),
          activeTunnelsStreamProvider.overrideWith((ref) => tunnelFeed.stream),
        ],
        child: const MaterialApp(
          home: ForegroundServiceHost(child: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pump();
  }

  /// Pushes a tunnel list through the stream. Two pumps: the provider hands a
  /// stream event on a turn later than it does a notifier's state.
  Future<void> feedTunnels(
    WidgetTester tester,
    List<ActiveTunnel> list, [
    Duration step = Duration.zero,
  ]) async {
    tunnelFeed.add(list);
    await tester.pump(step);
    await tester.pump();
  }

  Future<void> pastDebounce(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 1));

  group('supportsForegroundService', () {
    test('is true on Android only', () {
      for (final platform in TargetPlatform.values) {
        debugPlatformCapabilitiesOverride = platform;
        expect(
          supportsForegroundService,
          platform == TargetPlatform.android,
          reason: '$platform',
        );
      }
    });
  });

  group('ForegroundServiceHost', () {
    testWidgets('does nothing while nothing is open', (tester) async {
      await pumpHost(tester);
      await pastDebounce(tester);
      expect(gateway.calls, ['initialize']);
    });

    testWidgets('starts when a session connects and stops when it is gone', (
      tester,
    ) async {
      await pumpHost(tester);

      tabs.setTabs([_tab('a')]);
      await tester.pump();
      expect(gateway.calls, ['initialize', 'permission', 'start:1 session']);

      tabs.setTabs([]);
      await pastDebounce(tester);
      expect(gateway.serviceCalls, ['start:1 session', 'stop']);
    });

    testWidgets('starts for sessions already open when it mounts', (
      tester,
    ) async {
      await pumpHost(tester, initialTabs: [_tab('a'), _tab('b')]);
      await tester.pump();
      expect(gateway.serviceCalls, ['start:2 sessions']);
    });

    testWidgets('a tunnel alone keeps it up; speed ticks are not updates', (
      tester,
    ) async {
      await pumpHost(tester);

      await feedTunnels(tester, [_tunnel('t')]);
      expect(gateway.serviceCalls, ['start:1 tunnel']);

      for (var speed = 1; speed <= 10; speed++) {
        await feedTunnels(tester, [
          _tunnel('t', speed: speed * 1000),
        ], const Duration(milliseconds: 100));
      }
      await pastDebounce(tester);
      expect(gateway.serviceCalls, ['start:1 tunnel']);
    });

    testWidgets('follows sessions and tunnels together', (tester) async {
      await pumpHost(tester, initialTabs: [_tab('a')]);
      await tester.pump();

      await feedTunnels(tester, [_tunnel('t')]);
      tabs.setTabs([_tab('a'), _tab('b'), _tab('b-split', splitParentId: 'b')]);
      await pastDebounce(tester);

      expect(gateway.serviceCalls, [
        'start:1 session',
        'update:2 sessions · 1 tunnel',
      ]);
    });

    testWidgets('the notification never carries a host or tab title', (
      tester,
    ) async {
      await pumpHost(tester, initialTabs: [_tab('a')]);
      await feedTunnels(tester, [_tunnel('t')]);
      await pastDebounce(tester);
      expect(gateway.calls.join('\n'), isNot(contains('secret-host')));
    });

    testWidgets('Disconnect all closes every tab and stops every tunnel', (
      tester,
    ) async {
      await pumpHost(
        tester,
        initialTabs: [
          _tab('a'),
          _tab('a-split', splitParentId: 'a'),
          _tab('dropped', connected: false),
          _tab('b'),
        ],
      );
      await feedTunnels(tester, [
        _tunnel('t1'),
        ActiveTunnel(
          ruleId: 'failed',
          hostId: 'host',
          type: 'local',
          localPort: 9,
          isActive: false,
          error: 'refused',
        ),
        _tunnel('t2'),
      ]);

      gateway.onDisconnectAll!();
      await tester.pump();

      // The split rides with its root, a dropped tab is not a session, and a
      // tunnel that never came up has nothing to stop.
      expect(tabs.closed, ['a', 'b']);
      expect(tunnels.stopped, ['t1', 't2']);

      // What the engine would now report, and so what stops the service.
      await feedTunnels(tester, []);
      await pastDebounce(tester);
      expect(gateway.serviceCalls.last, 'stop');
    });

    testWidgets('stops the service when the app goes away', (tester) async {
      await pumpHost(tester, initialTabs: [_tab('a')]);
      await tester.pump();
      expect(gateway.running, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(gateway.running, isFalse);
    });
  });
}
