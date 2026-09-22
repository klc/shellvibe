import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/templates/domain/models/template_model.dart';
import 'package:shellvibe/features/templates/domain/models/template_pane_model.dart';
import 'package:shellvibe/features/templates/domain/services/template_runner.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_tab_session.dart';
import 'package:shellvibe/features/vault/domain/models/identity_model.dart';

/// Records every call the runner makes, in order, and hands back a live id for
/// each pane it "creates" — the notifier contract the runner relies on.
class _RecordingTarget implements TemplateRunnerTarget {
  final List<String> calls = [];
  final Set<String> failingHostIds;
  var _counter = 0;
  String? _activeTabId;

  /// When set, every connection hangs on this until the test releases it.
  final Completer<void>? connectionGate;

  _RecordingTarget({this.failingHostIds = const {}, this.connectionGate});

  void _created(String kind) {
    _activeTabId = 'live_${_counter++}';
    calls.add('$kind -> $_activeTabId');
  }

  @override
  String? get activeTabId => _activeTabId;

  @override
  Future<void> openTabForHost(HostModel host, {IdentityModel? identity}) async {
    if (failingHostIds.contains(host.id)) {
      // Mirrors a connect that never produces a pane.
      _activeTabId = null;
      calls.add('openTabForHost(${host.id}) -> failed');
      return;
    }
    _created('openTabForHost(${host.id})');
    await connectionGate?.future;
  }

  @override
  void openLocalTab({String? title}) => _created('openLocalTab($title)');

  @override
  Future<void> splitTab(
    String parentTabId, {
    required Axis direction,
    HostModel? host,
    IdentityModel? identity,
  }) async {
    final axis = direction == Axis.horizontal ? 'h' : 'v';
    _created('splitTab($parentTabId, $axis, host=${host?.id})');
    await connectionGate?.future;
  }

  @override
  void setSplitRatio(String tabId, double ratio) =>
      calls.add('setSplitRatio($tabId, $ratio)');

  @override
  void setActiveTab(String tabId) => calls.add('setActiveTab($tabId)');
}

HostModel _host(String id, {String? identityId}) => HostModel(
  id: id,
  workspaceId: 'ws_1',
  identityId: identityId,
  label: 'Server $id',
  hostname: '$id.example.com',
  createdAt: DateTime(2026),
);

TemplatePaneModel _pane({
  required String id,
  required int order,
  String? parentPaneId,
  Axis? splitDirection,
  double splitRatio = 0.5,
  TerminalSessionType sessionType = TerminalSessionType.local,
  String? hostId,
  String? title,
}) {
  return TemplatePaneModel(
    id: id,
    templateId: 'tpl_1',
    paneOrder: order,
    parentPaneId: parentPaneId,
    splitDirection: splitDirection,
    splitRatio: splitRatio,
    sessionType: sessionType,
    hostId: hostId,
    title: title,
  );
}

TemplateModel _template(List<TemplatePaneModel> panes, {String? activePaneId}) {
  return TemplateModel(
    id: 'tpl_1',
    workspaceId: 'ws_1',
    name: 'Template',
    panes: panes,
    activePaneId: activePaneId,
    createdAt: DateTime(2026),
  );
}

Future<({bool ok, IdentityModel? identity})> _resolveOk(HostModel host) async =>
    (ok: true, identity: null);

Future<({bool ok, IdentityModel? identity})> _resolveFails(
  HostModel host,
) async => (ok: false, identity: null);

void main() {
  const runner = TemplateRunner();

  group('TemplateRunner', () {
    test('recreates panes in capture order', () async {
      final target = _RecordingTarget();

      final result = await runner.run(
        _template([
          _pane(id: 'p0', order: 0, title: 'A'),
          _pane(
            id: 'p1',
            order: 1,
            parentPaneId: 'p0',
            splitDirection: Axis.vertical,
            title: 'B',
          ),
          _pane(id: 'p2', order: 2, title: 'C'),
        ]),
        target: target,
        hostsById: const {},
        resolveIdentity: _resolveOk,
      );

      expect(result.openedPanes, equals(3));
      expect(result.isComplete, isTrue);
      expect(target.calls.take(3), [
        'openLocalTab(A) -> live_0',
        'splitTab(live_0, v, host=null) -> live_1',
        'openLocalTab(C) -> live_2',
      ]);
    });

    test('places every pane without waiting for any to connect', () async {
      final gate = Completer<void>();
      final target = _RecordingTarget(connectionGate: gate);
      final hosts = {
        for (final id in ['host_1', 'host_2', 'host_3']) id: _host(id),
      };

      final result = await runner.run(
        _template([
          _pane(
            id: 'p0',
            order: 0,
            sessionType: TerminalSessionType.ssh,
            hostId: 'host_1',
          ),
          _pane(
            id: 'p1',
            order: 1,
            parentPaneId: 'p0',
            splitDirection: Axis.horizontal,
            sessionType: TerminalSessionType.ssh,
            hostId: 'host_2',
          ),
          _pane(
            id: 'p2',
            order: 2,
            sessionType: TerminalSessionType.ssh,
            hostId: 'host_3',
          ),
        ]),
        target: target,
        hostsById: hosts,
        resolveIdentity: _resolveOk,
      );

      // The run is over with nothing connected, and the whole layout is on
      // screen in capture order: the caller can show the terminal now.
      expect(target.calls.where((call) => call.contains('->')), [
        'openTabForHost(host_1) -> live_0',
        'splitTab(live_0, h, host=host_2) -> live_1',
        'openTabForHost(host_3) -> live_2',
      ]);
      expect(result.openedPanes, 3);
      expect(result.isComplete, isTrue);
      gate.complete();
    });

    test('applies split ratios only after every pane exists', () async {
      final target = _RecordingTarget();

      await runner.run(
        _template([
          _pane(id: 'p0', order: 0),
          _pane(
            id: 'p1',
            order: 1,
            parentPaneId: 'p0',
            splitDirection: Axis.horizontal,
            splitRatio: 0.3,
          ),
          _pane(
            id: 'p2',
            order: 2,
            parentPaneId: 'p1',
            splitDirection: Axis.vertical,
            splitRatio: 0.7,
          ),
        ]),
        target: target,
        hostsById: const {},
        resolveIdentity: _resolveOk,
      );

      final firstRatioCall = target.calls.indexWhere(
        (c) => c.startsWith('setSplitRatio'),
      );
      final lastCreateCall = target.calls.lastIndexWhere(
        (c) => c.contains(' -> live_'),
      );

      expect(firstRatioCall, greaterThan(lastCreateCall));
      expect(target.calls.where((c) => c.startsWith('setSplitRatio')), [
        'setSplitRatio(live_1, 0.3)',
        'setSplitRatio(live_2, 0.7)',
      ]);
    });

    test('root panes get no ratio call', () async {
      final target = _RecordingTarget();

      await runner.run(
        _template([_pane(id: 'p0', order: 0)]),
        target: target,
        hostsById: const {},
        resolveIdentity: _resolveOk,
      );

      expect(target.calls.any((c) => c.startsWith('setSplitRatio')), isFalse);
    });

    test('restores the captured focus last', () async {
      final target = _RecordingTarget();

      await runner.run(
        _template([
          _pane(id: 'p0', order: 0),
          _pane(id: 'p1', order: 1),
        ], activePaneId: 'p0'),
        target: target,
        hostsById: const {},
        resolveIdentity: _resolveOk,
      );

      expect(target.calls.last, equals('setActiveTab(live_0)'));
    });

    test('leaves focus alone when the template captured none', () async {
      final target = _RecordingTarget();

      await runner.run(
        _template([_pane(id: 'p0', order: 0)]),
        target: target,
        hostsById: const {},
        resolveIdentity: _resolveOk,
      );

      expect(target.calls.any((c) => c.startsWith('setActiveTab')), isFalse);
    });

    test('passes the host explicitly for an SSH pane', () async {
      final target = _RecordingTarget();

      await runner.run(
        _template([
          _pane(
            id: 'p0',
            order: 0,
            sessionType: TerminalSessionType.ssh,
            hostId: 'host_1',
          ),
          _pane(
            id: 'p1',
            order: 1,
            parentPaneId: 'p0',
            splitDirection: Axis.horizontal,
            sessionType: TerminalSessionType.ssh,
            hostId: 'host_2',
          ),
        ]),
        target: target,
        hostsById: {'host_1': _host('host_1'), 'host_2': _host('host_2')},
        resolveIdentity: _resolveOk,
      );

      expect(target.calls.take(2), [
        'openTabForHost(host_1) -> live_0',
        'splitTab(live_0, h, host=host_2) -> live_1',
      ]);
    });

    test('skips a pane whose host was deleted, and its subtree', () async {
      final target = _RecordingTarget();

      final result = await runner.run(
        _template([
          _pane(id: 'p0', order: 0, title: 'Kept'),
          _pane(
            id: 'p1',
            order: 1,
            sessionType: TerminalSessionType.ssh,
            hostId: 'gone',
            title: 'Orphan root',
          ),
          _pane(
            id: 'p2',
            order: 2,
            parentPaneId: 'p1',
            splitDirection: Axis.horizontal,
            title: 'Child of orphan',
          ),
        ]),
        target: target,
        hostsById: const {},
        resolveIdentity: _resolveOk,
      );

      expect(result.openedPanes, equals(1));
      // The subtree drops out on the parent's warning, not one per pane.
      expect(result.warnings, ['Orphan root: host no longer exists.']);
      expect(target.calls, ['openLocalTab(Kept) -> live_0']);
    });

    test('skips a pane whose credentials cannot be read', () async {
      final target = _RecordingTarget();

      final result = await runner.run(
        _template([
          _pane(
            id: 'p0',
            order: 0,
            sessionType: TerminalSessionType.ssh,
            hostId: 'host_1',
            title: 'prod',
          ),
        ]),
        target: target,
        hostsById: {'host_1': _host('host_1', identityId: 'id_1')},
        resolveIdentity: _resolveFails,
      );

      expect(result.openedPanes, equals(0));
      expect(result.warnings, ['prod: stored credentials could not be read.']);
      expect(target.calls, isEmpty);
    });

    test('skips local panes where the platform has no local shell', () async {
      final target = _RecordingTarget();

      final result = await runner.run(
        _template([
          _pane(id: 'p0', order: 0, title: 'Local'),
          _pane(
            id: 'p1',
            order: 1,
            sessionType: TerminalSessionType.ssh,
            hostId: 'host_1',
            title: 'prod',
          ),
        ]),
        target: target,
        hostsById: {'host_1': _host('host_1')},
        resolveIdentity: _resolveOk,
        supportsLocalShell: false,
      );

      expect(result.openedPanes, equals(1));
      expect(result.warnings, [
        'Local: local shells are not available on this platform.',
      ]);
      expect(target.calls.first, equals('openTabForHost(host_1) -> live_0'));
    });

    test('skips a subtree whose parent failed to open', () async {
      final target = _RecordingTarget(failingHostIds: {'host_1'});

      final result = await runner.run(
        _template([
          _pane(
            id: 'p0',
            order: 0,
            sessionType: TerminalSessionType.ssh,
            hostId: 'host_1',
            title: 'prod',
          ),
          _pane(
            id: 'p1',
            order: 1,
            parentPaneId: 'p0',
            splitDirection: Axis.horizontal,
            title: 'child',
          ),
        ]),
        target: target,
        hostsById: {'host_1': _host('host_1')},
        resolveIdentity: _resolveOk,
      );

      expect(result.openedPanes, equals(0));
      expect(result.warnings, ['prod: could not be opened.']);
      expect(target.calls, ['openTabForHost(host_1) -> failed']);
    });

    test(
      'a local pane under an SSH parent is skipped, not silently SSH',
      () async {
        final target = _RecordingTarget();

        final result = await runner.run(
          _template([
            _pane(
              id: 'p0',
              order: 0,
              sessionType: TerminalSessionType.ssh,
              hostId: 'host_1',
              title: 'prod',
            ),
            _pane(
              id: 'p1',
              order: 1,
              parentPaneId: 'p0',
              splitDirection: Axis.horizontal,
              title: 'shell',
            ),
          ]),
          target: target,
          hostsById: {'host_1': _host('host_1')},
          resolveIdentity: _resolveOk,
        );

        expect(result.openedPanes, equals(1));
        expect(result.warnings, [
          'shell: a local pane cannot be split out of an SSH pane.',
        ]);
      },
    );

    test('replays panes stored out of order by paneOrder', () async {
      final target = _RecordingTarget();

      await runner.run(
        _template([
          _pane(
            id: 'p1',
            order: 1,
            parentPaneId: 'p0',
            splitDirection: Axis.horizontal,
            title: 'B',
          ),
          _pane(id: 'p0', order: 0, title: 'A'),
        ]),
        target: target,
        hostsById: const {},
        resolveIdentity: _resolveOk,
      );

      expect(target.calls.first, equals('openLocalTab(A) -> live_0'));
    });

    test(
      'requiresUnlockedVault is true only for hosts with an identity',
      () async {
        final withIdentity = _template([
          _pane(
            id: 'p0',
            order: 0,
            sessionType: TerminalSessionType.ssh,
            hostId: 'host_1',
          ),
        ]);
        final withoutIdentity = _template([
          _pane(
            id: 'p0',
            order: 0,
            sessionType: TerminalSessionType.ssh,
            hostId: 'host_2',
          ),
        ]);
        final localOnly = _template([_pane(id: 'p0', order: 0)]);

        final hosts = {
          'host_1': _host('host_1', identityId: 'id_1'),
          'host_2': _host('host_2'),
        };

        expect(runner.requiresUnlockedVault(withIdentity, hosts), isTrue);
        expect(runner.requiresUnlockedVault(withoutIdentity, hosts), isFalse);
        expect(runner.requiresUnlockedVault(localOnly, hosts), isFalse);
      },
    );
  });
}
