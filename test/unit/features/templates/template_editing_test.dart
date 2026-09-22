import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/templates/domain/models/template_model.dart';
import 'package:shellvibe/features/templates/domain/models/template_pane_model.dart';
import 'package:shellvibe/features/templates/domain/services/template_editing.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_tab_session.dart';

TemplatePaneModel _pane(
  String id,
  int order, {
  String? parent,
  Axis? direction,
  double ratio = 0.5,
  String? hostId,
}) => TemplatePaneModel(
  id: id,
  templateId: 'tpl',
  paneOrder: order,
  parentPaneId: parent,
  splitDirection: direction,
  splitRatio: ratio,
  sessionType: hostId == null
      ? TerminalSessionType.local
      : TerminalSessionType.ssh,
  hostId: hostId,
  title: hostId == null ? id : null,
);

/// Two tabs: `a` split into `a1` (which is split into `a2`), and `b` alone.
TemplateModel _template({String? activePaneId}) => TemplateModel(
  id: 'tpl',
  workspaceId: 'ws',
  name: 'Layout',
  panes: [
    _pane('a', 0, hostId: 'web'),
    _pane(
      'a1',
      1,
      parent: 'a',
      direction: Axis.horizontal,
      ratio: 0.3,
      hostId: 'db',
    ),
    _pane(
      'a2',
      2,
      parent: 'a1',
      direction: Axis.vertical,
      ratio: 0.7,
      hostId: 'cache',
    ),
    _pane('b', 3),
  ],
  activePaneId: activePaneId,
  createdAt: DateTime(2026),
);

List<String> _ids(TemplateModel template) => [
  for (final pane in template.orderedPanes) pane.id,
];

TemplatePaneModel _find(TemplateModel template, String id) =>
    template.panes.firstWhere((pane) => pane.id == id);

/// Every pane follows its parent in replay order, and the order is dense.
void _expectReplayable(TemplateModel template) {
  final ordered = template.orderedPanes;
  expect(
    [for (final pane in ordered) pane.paneOrder],
    [for (var i = 0; i < ordered.length; i++) i],
  );
  final seen = <String>{};
  for (final pane in ordered) {
    if (pane.parentPaneId != null) {
      expect(seen, contains(pane.parentPaneId), reason: '${pane.id} parent');
    }
    seen.add(pane.id);
  }
}

void main() {
  group('TemplateEditing', () {
    test('withPaneHost turns a pane local and back', () {
      final local = _template().withPaneHost('a1', null);
      final pane = _find(local, 'a1');
      expect(pane.sessionType, TerminalSessionType.local);
      expect(pane.hostId, isNull);
      expect(pane.title, 'Local Shell');

      final ssh = local.withPaneHost('a1', 'other');
      expect(_find(ssh, 'a1').sessionType, TerminalSessionType.ssh);
      expect(_find(ssh, 'a1').hostId, 'other');
      // The layout is untouched.
      expect(_find(ssh, 'a1').splitRatio, 0.3);
      expect(_ids(ssh), _ids(_template()));
    });

    test('withSplitDirection changes a split and ignores a root', () {
      final edited = _template()
          .withSplitDirection('a1', Axis.vertical)
          .withSplitDirection('a', Axis.vertical);
      expect(_find(edited, 'a1').splitDirection, Axis.vertical);
      expect(_find(edited, 'a').splitDirection, isNull);
    });

    test('addTab and addSplit append panes in replay order', () {
      final edited = _template()
          .addTab(newPaneId: 'c', hostId: 'web')
          .addSplit('b', newPaneId: 'b1', direction: Axis.vertical);
      expect(_ids(edited), ['a', 'a1', 'a2', 'b', 'c', 'b1']);
      expect(_find(edited, 'c').isRoot, isTrue);
      expect(_find(edited, 'b1').parentPaneId, 'b');
      expect(_find(edited, 'b1').sessionType, TerminalSessionType.local);
      _expectReplayable(edited);

      expect(
        _template().addSplit(
          'missing',
          newPaneId: 'x',
          direction: Axis.vertical,
        ),
        isA<TemplateModel>().having((t) => t.panes.length, 'panes', 4),
      );
    });

    test('removeTab drops the whole subtree and a focus inside it', () {
      final edited = _template(activePaneId: 'a2').removeTab('a');
      expect(_ids(edited), ['b']);
      expect(edited.activePaneId, isNull);
      _expectReplayable(edited);

      expect(_template(activePaneId: 'b').removeTab('a').activePaneId, 'b');
    });

    test('removePane promotes its last split into its slot', () {
      final edited = _template(activePaneId: 'a1').removePane('a1');
      expect(_ids(edited), ['a', 'a2', 'b']);
      final heir = _find(edited, 'a2');
      expect(heir.parentPaneId, 'a');
      expect(heir.splitDirection, Axis.horizontal);
      expect(heir.splitRatio, 0.3);
      expect(edited.activePaneId, 'a2');
      _expectReplayable(edited);
    });

    test('removePane re-parents the other splits onto the heir', () {
      final template = _template().addSplit(
        'a1',
        newPaneId: 'a3',
        direction: Axis.horizontal,
      );
      final edited = template.removePane('a1');
      expect(_find(edited, 'a3').parentPaneId, 'a');
      expect(_find(edited, 'a2').parentPaneId, 'a3');
      _expectReplayable(edited);
    });

    test('removePane of a leaf just drops it; a root is left alone', () {
      expect(_ids(_template().removePane('a2')), ['a', 'a1', 'b']);
      expect(_ids(_template().removePane('a')), _ids(_template()));
    });

    test('moveTab moves a tab with all of its panes', () {
      final edited = _template().moveTab('b', 0);
      expect(_ids(edited), ['b', 'a', 'a1', 'a2']);
      _expectReplayable(edited);
      expect(_ids(edited.moveTab('b', 99)), ['a', 'a1', 'a2', 'b']);
    });

    test('problemWith mirrors what the runner would skip', () {
      final hosts = {
        'web': HostModel(
          id: 'web',
          workspaceId: 'ws',
          label: 'web',
          hostname: 'web',
          createdAt: DateTime(2026),
        ),
      };
      final template = _template().addSplit(
        'a',
        newPaneId: 'local-under-ssh',
        direction: Axis.vertical,
      );
      String? problem(String id, {bool local = true}) => template.problemWith(
        _find(template, id),
        hostsById: hosts,
        supportsLocalShell: local,
      );

      expect(problem('a'), isNull);
      expect(problem('a1'), contains('no longer exists'));
      expect(problem('b'), isNull);
      expect(problem('b', local: false), contains('not available'));
      expect(problem('local-under-ssh'), contains('split out of an SSH pane'));
    });
  });
}
