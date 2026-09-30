import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/foreground_service/disconnect_all.dart';
import 'package:shellvibe/app/foreground_service/foreground_service_state.dart';
import 'package:shellvibe/core/network/tunnel_engine.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_tab_session.dart';
import 'package:xterm3/xterm.dart';

TerminalTabSession _tab(
  String id, {
  bool connected = true,
  bool connecting = false,
  String? splitParentId,
  String title = 'prod-db-01',
}) => TerminalTabSession(
  id: id,
  title: title,
  sessionType: TerminalSessionType.ssh,
  terminal: Terminal(),
  isConnected: connected,
  isConnecting: connecting,
  splitParentId: splitParentId,
);

ActiveTunnel _tunnel(
  String ruleId, {
  bool active = true,
  String? error,
  int speed = 0,
}) => ActiveTunnel(
  ruleId: ruleId,
  hostId: 'host-$ruleId',
  type: 'local',
  localPort: 8080,
  isActive: active,
  error: error,
  speedBytesPerSec: speed,
);

void main() {
  group('deriveServiceCounts', () {
    test('counts connected root tabs only', () {
      final counts = deriveServiceCounts(
        tabs: [
          _tab('a'),
          _tab('b', connected: false),
          _tab('c', connected: false, connecting: true),
        ],
        tunnels: const [],
      );
      expect(counts, const ServiceCounts(sessions: 1));
    });

    test('leaves split panes out: a split is one tab', () {
      final counts = deriveServiceCounts(
        tabs: [
          _tab('a'),
          _tab('a-split', splitParentId: 'a'),
          _tab('a-split-2', splitParentId: 'a-split'),
          _tab('b'),
        ],
        tunnels: const [],
      );
      expect(counts.sessions, 2);
    });

    test('counts active tunnels, not failed ones', () {
      final counts = deriveServiceCounts(
        tabs: const [],
        tunnels: [
          _tunnel('up'),
          _tunnel('refused', active: false, error: 'refused'),
          _tunnel('bind-failed', active: true, error: 'in use'),
          _tunnel('stopped', active: false),
        ],
      );
      expect(counts, const ServiceCounts(tunnels: 1));
    });

    test('a tunnel speed tick leaves the counts equal', () {
      final before = deriveServiceCounts(
        tabs: [_tab('a')],
        tunnels: [_tunnel('t', speed: 0)],
      );
      final after = deriveServiceCounts(
        tabs: [_tab('a')],
        tunnels: [_tunnel('t', speed: 48213)],
      );
      expect(after, before);
      expect(after.hashCode, before.hashCode);
    });

    test('nothing open is idle', () {
      expect(
        deriveServiceCounts(tabs: const [], tunnels: const []).isIdle,
        isTrue,
      );
    });
  });

  group('buildServiceNotificationText', () {
    String text(int sessions, int tunnels) => buildServiceNotificationText(
      ServiceCounts(sessions: sessions, tunnels: tunnels),
    );

    test('uses singular for one and plural otherwise', () {
      expect(text(1, 1), '1 session · 1 tunnel');
      expect(text(2, 1), '2 sessions · 1 tunnel');
      expect(text(1, 3), '1 session · 3 tunnels');
      expect(text(12, 10), '12 sessions · 10 tunnels');
    });

    test('leaves out a part that is zero', () {
      expect(text(3, 0), '3 sessions');
      expect(text(0, 1), '1 tunnel');
      expect(text(0, 2), '2 tunnels');
    });

    test('is total for the idle case it is never shown for', () {
      expect(text(0, 0), 'No active connections');
    });

    test('carries no host or tab title, only counts', () {
      // The derivation reads the tab's title and the tunnel's host; none of it
      // may reach the text.
      final counts = deriveServiceCounts(
        tabs: [_tab('a', title: 'prod-db-01.internal')],
        tunnels: [_tunnel('t')],
      );
      final body = buildServiceNotificationText(counts);
      expect(body, isNot(contains('prod')));
      expect(body, isNot(contains('host-')));
      expect(kServiceNotificationTitle, 'ShellVibe');
    });
  });

  group('planServiceCommand', () {
    const one = ServiceCounts(sessions: 1);
    const two = ServiceCounts(sessions: 2);

    test('starts when something is running and the service is not', () {
      final command = planServiceCommand(shown: null, wanted: one);
      expect(command, isA<StartService>());
      expect((command! as StartService).counts, one);
    });

    test('updates when the counts differ', () {
      final command = planServiceCommand(shown: one, wanted: two);
      expect(command, isA<UpdateService>());
      expect((command! as UpdateService).counts, two);
    });

    test('does nothing for equal counts', () {
      expect(planServiceCommand(shown: one, wanted: one), isNull);
      expect(
        planServiceCommand(
          shown: const ServiceCounts(sessions: 1, tunnels: 1),
          wanted: const ServiceCounts(sessions: 1, tunnels: 1),
        ),
        isNull,
      );
    });

    test('stops when nothing is left', () {
      expect(
        planServiceCommand(shown: two, wanted: ServiceCounts.idle),
        isA<StopService>(),
      );
    });

    test('does nothing when idle and already stopped', () {
      expect(
        planServiceCommand(shown: null, wanted: ServiceCounts.idle),
        isNull,
      );
    });
  });

  group('Disconnect all', () {
    test('picks connected and connecting roots, never a split pane', () {
      final ids = tabIdsToDisconnect([
        _tab('live'),
        _tab('dialling', connected: false, connecting: true),
        _tab('dropped', connected: false),
        _tab('live-split', splitParentId: 'live'),
      ]);
      expect(ids, ['live', 'dialling']);
    });

    test('picks the tunnels that are counted', () {
      final ids = tunnelRuleIdsToStop([
        _tunnel('up'),
        _tunnel('failed', active: false, error: 'boom'),
        _tunnel('up-too'),
      ]);
      expect(ids, ['up', 'up-too']);
    });

    test('closes every tab and stops every tunnel, tabs first', () async {
      final calls = <String>[];
      await disconnectAll(
        tabIds: ['a', 'b'],
        ruleIds: ['t1', 't2'],
        closeTab: (id) async => calls.add('close:$id'),
        stopTunnel: (id) async => calls.add('stop:$id'),
      );
      expect(calls, ['close:a', 'close:b', 'stop:t1', 'stop:t2']);
    });

    test('one failure does not spare the rest', () async {
      final calls = <String>[];
      await disconnectAll(
        tabIds: ['a', 'b'],
        ruleIds: ['t1', 't2'],
        closeTab: (id) async {
          calls.add('close:$id');
          if (id == 'a') throw StateError('already gone');
        },
        stopTunnel: (id) async {
          calls.add('stop:$id');
          if (id == 't1') throw StateError('already gone');
        },
      );
      expect(calls, ['close:a', 'close:b', 'stop:t1', 'stop:t2']);
    });
  });
}
