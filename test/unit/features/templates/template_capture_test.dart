import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/features/hosts/domain/models/host_model.dart';
import 'package:terly2/features/templates/domain/services/template_capture.dart';
import 'package:terly2/features/terminal/domain/models/terminal_tab_session.dart';
import 'package:xterm2/xterm.dart';

/// Deterministic id source so the expectations can name panes directly.
String Function() _sequentialIds() {
  var counter = 0;
  return () => 'id_${counter++}';
}

TerminalTabSession _session({
  required String id,
  String title = 'Tab',
  TerminalSessionType sessionType = TerminalSessionType.local,
  HostModel? host,
  String? splitParentId,
  Axis? splitDirection,
  double splitRatio = 0.5,
}) {
  return TerminalTabSession(
    id: id,
    title: title,
    sessionType: sessionType,
    host: host,
    terminal: Terminal(),
    splitParentId: splitParentId,
    splitDirection: splitDirection,
    splitRatio: splitRatio,
  );
}

HostModel _host(String id) => HostModel(
      id: id,
      workspaceId: 'ws_1',
      label: 'Server $id',
      hostname: '$id.example.com',
      createdAt: DateTime(2026),
    );

void main() {
  const capture = TemplateCapture();

  group('TemplateCapture', () {
    test('captures an empty layout as a template with no panes', () {
      final template = capture.capture(
        workspaceId: 'ws_1',
        name: 'Empty',
        tabs: const [],
        idFactory: _sequentialIds(),
      );

      expect(template.panes, isEmpty);
      expect(template.tabCount, equals(0));
      expect(template.activePaneId, isNull);
    });

    test('captures tabs and panes in list order', () {
      final tabs = [
        _session(id: 'live_a', title: 'A'),
        _session(id: 'live_b', title: 'B'),
        _session(
          id: 'live_c',
          title: 'C',
          splitParentId: 'live_a',
          splitDirection: Axis.vertical,
        ),
      ];

      final template = capture.capture(
        workspaceId: 'ws_1',
        name: 'Layout',
        tabs: tabs,
        idFactory: _sequentialIds(),
      );

      expect(template.panes.map((p) => p.paneOrder), [0, 1, 2]);
      expect(template.panes.map((p) => p.title), ['A', 'B', 'C']);
      expect(template.tabCount, equals(2));
    });

    test('remaps live session ids to template-local pane ids', () {
      final tabs = [
        _session(id: 'live_parent'),
        _session(
          id: 'live_child',
          splitParentId: 'live_parent',
          splitDirection: Axis.horizontal,
          splitRatio: 0.3,
        ),
      ];

      final template = capture.capture(
        workspaceId: 'ws_1',
        name: 'Split',
        tabs: tabs,
        activeTabId: 'live_child',
        idFactory: _sequentialIds(),
      );

      final parent = template.panes[0];
      final child = template.panes[1];

      // No live id survives into storage.
      expect(
        template.panes.map((p) => p.id),
        isNot(contains(anyOf('live_parent', 'live_child'))),
      );
      expect(parent.parentPaneId, isNull);
      expect(child.parentPaneId, equals(parent.id));
      expect(child.splitDirection, equals(Axis.horizontal));
      expect(child.splitRatio, equals(0.3));
      expect(template.activePaneId, equals(child.id));
    });

    test('stores only the host id for an SSH pane', () {
      final tabs = [
        _session(
          id: 'live_ssh',
          title: 'prod',
          sessionType: TerminalSessionType.ssh,
          host: _host('host_1'),
        ),
      ];

      final template = capture.capture(
        workspaceId: 'ws_1',
        name: 'SSH',
        tabs: tabs,
        idFactory: _sequentialIds(),
      );

      final pane = template.panes.single;
      expect(pane.sessionType, equals(TerminalSessionType.ssh));
      expect(pane.hostId, equals('host_1'));
    });

    test('local pane carries no host id', () {
      final template = capture.capture(
        workspaceId: 'ws_1',
        name: 'Local',
        tabs: [_session(id: 'live_local')],
        idFactory: _sequentialIds(),
      );

      expect(template.panes.single.hostId, isNull);
      expect(
        template.panes.single.sessionType,
        equals(TerminalSessionType.local),
      );
    });

    test('a root pane never carries a split direction', () {
      final template = capture.capture(
        workspaceId: 'ws_1',
        name: 'Root',
        // A root tab can hold a stale direction from an earlier layout; it must
        // not be saved, or replay would try to split a tab into itself.
        tabs: [_session(id: 'live_root', splitDirection: Axis.vertical)],
        idFactory: _sequentialIds(),
      );

      expect(template.panes.single.splitDirection, isNull);
      expect(template.panes.single.isRoot, isTrue);
    });

    test('a pane whose parent is outside the capture is saved as a root', () {
      final template = capture.capture(
        workspaceId: 'ws_1',
        name: 'Orphan',
        tabs: [
          _session(
            id: 'live_orphan',
            splitParentId: 'gone',
            splitDirection: Axis.horizontal,
          ),
        ],
        idFactory: _sequentialIds(),
      );

      expect(template.panes.single.parentPaneId, isNull);
      expect(template.panes.single.splitDirection, isNull);
    });

    test('active pane id is null when the focused tab was not captured', () {
      final template = capture.capture(
        workspaceId: 'ws_1',
        name: 'No focus',
        tabs: [_session(id: 'live_a')],
        activeTabId: 'live_missing',
        idFactory: _sequentialIds(),
      );

      expect(template.activePaneId, isNull);
    });
  });
}
