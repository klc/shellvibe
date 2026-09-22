import 'package:flutter/widgets.dart';

import '../../../hosts/domain/models/host_model.dart';
import '../../../terminal/domain/models/terminal_tab_session.dart';
import '../models/template_model.dart';
import '../models/template_pane_model.dart';

/// Edits to a saved layout, as pure functions of the template.
///
/// Every edit returns a new template whose panes are renumbered `0..n-1` in
/// replay order, and keeps the one invariant [TemplateRunner] depends on: a
/// pane comes after its parent. New pane ids are passed in rather than made
/// here, so the edits stay deterministic.
extension TemplateEditing on TemplateModel {
  /// Panes in the order a replay creates them.
  List<TemplatePaneModel> get orderedPanes =>
      [...panes]..sort((a, b) => a.paneOrder.compareTo(b.paneOrder));

  /// Root panes, one per tab, in tab order.
  List<TemplatePaneModel> get orderedRoots =>
      orderedPanes.where((pane) => pane.isRoot).toList();

  /// Direct splits of [paneId], in the order they were made.
  List<TemplatePaneModel> childrenOf(String paneId) =>
      orderedPanes.where((pane) => pane.parentPaneId == paneId).toList();

  /// [rootId] and every pane split out of it, in replay order.
  List<TemplatePaneModel> subtreeOf(String rootId) {
    final ids = <String>{rootId};
    final subtree = <TemplatePaneModel>[];
    for (final pane in orderedPanes) {
      if (pane.id == rootId ||
          (pane.parentPaneId != null && ids.contains(pane.parentPaneId))) {
        ids.add(pane.id);
        subtree.add(pane);
      }
    }
    return subtree;
  }

  /// Points [paneId] at [hostId], or at a local shell when [hostId] is null.
  TemplateModel withPaneHost(String paneId, String? hostId) {
    return _withPanes([
      for (final pane in orderedPanes)
        if (pane.id != paneId)
          pane
        else if (hostId == null)
          _pane(
            pane,
            sessionType: TerminalSessionType.local,
            hostId: null,
            title: pane.sessionType == TerminalSessionType.local
                ? pane.title
                : 'Local Shell',
          )
        else
          _pane(pane, sessionType: TerminalSessionType.ssh, hostId: hostId),
    ]);
  }

  /// Turns split pane [paneId] to split its parent along [direction].
  TemplateModel withSplitDirection(String paneId, Axis direction) {
    return _withPanes([
      for (final pane in orderedPanes)
        pane.id == paneId && !pane.isRoot
            ? _pane(pane, splitDirection: direction)
            : pane,
    ]);
  }

  /// Appends a tab holding one pane on [hostId], or a local shell.
  TemplateModel addTab({required String newPaneId, String? hostId}) {
    return _withPanes([
      ...orderedPanes,
      TemplatePaneModel(
        id: newPaneId,
        templateId: id,
        paneOrder: panes.length,
        sessionType: hostId == null
            ? TerminalSessionType.local
            : TerminalSessionType.ssh,
        hostId: hostId,
        title: hostId == null ? 'Local Shell' : null,
      ),
    ]);
  }

  /// Splits [parentId] with a new pane on [hostId], or a local shell.
  ///
  /// The new pane is placed after everything that already exists, which puts
  /// it on the trailing side of its parent — the side the terminal puts a new
  /// split on.
  TemplateModel addSplit(
    String parentId, {
    required String newPaneId,
    required Axis direction,
    String? hostId,
  }) {
    if (!panes.any((pane) => pane.id == parentId)) return this;
    return _withPanes([
      ...orderedPanes,
      TemplatePaneModel(
        id: newPaneId,
        templateId: id,
        paneOrder: panes.length,
        parentPaneId: parentId,
        splitDirection: direction,
        sessionType: hostId == null
            ? TerminalSessionType.local
            : TerminalSessionType.ssh,
        hostId: hostId,
        title: hostId == null ? 'Local Shell' : null,
      ),
    ]);
  }

  /// Removes the tab rooted at [rootId], with every pane split out of it.
  TemplateModel removeTab(String rootId) {
    final removed = {for (final pane in subtreeOf(rootId)) pane.id};
    return _withPanes([
      for (final pane in orderedPanes)
        if (!removed.contains(pane.id)) pane,
    ], activePaneId: removed.contains(activePaneId) ? null : activePaneId);
  }

  /// Removes split pane [paneId] the way the terminal closes one.
  ///
  /// Its last split takes over its slot — its parent, direction, ratio and
  /// place in the replay order — and its other splits hang off that heir, so
  /// the rest of the tab keeps its shape. A root is removed with [removeTab].
  TemplateModel removePane(String paneId) {
    final pane = panes.where((p) => p.id == paneId).firstOrNull;
    if (pane == null || pane.isRoot) return this;
    final children = childrenOf(paneId);
    if (children.isEmpty) {
      return _withPanes([
        for (final other in orderedPanes)
          if (other.id != paneId) other,
      ], activePaneId: activePaneId == paneId ? null : activePaneId);
    }

    final heir = children.last;
    final promoted = _pane(
      heir,
      parentPaneId: pane.parentPaneId,
      splitDirection: pane.splitDirection,
      splitRatio: pane.splitRatio,
    );
    return _withPanes([
      for (final other in orderedPanes)
        if (other.id == paneId)
          promoted
        else if (other.id == heir.id)
          ...[]
        else if (other.parentPaneId == paneId)
          _pane(other, parentPaneId: heir.id)
        else
          other,
    ], activePaneId: activePaneId == paneId ? heir.id : activePaneId);
  }

  /// Moves the tab rooted at [rootId] to [toIndex] among the tabs.
  TemplateModel moveTab(String rootId, int toIndex) {
    final roots = orderedRoots;
    final from = roots.indexWhere((root) => root.id == rootId);
    if (from == -1) return this;
    final to = toIndex.clamp(0, roots.length - 1);
    if (from == to) return this;
    roots.insert(to, roots.removeAt(from));
    // A tab's panes travel as one block, so every parent still precedes its
    // splits.
    return _withPanes([for (final root in roots) ...subtreeOf(root.id)]);
  }

  /// Why [pane] would be skipped if this template ran now, or null when it
  /// would open. The same checks [TemplateRunner] makes, so the editor can say
  /// so before the run does.
  String? problemWith(
    TemplatePaneModel pane, {
    required Map<String, HostModel> hostsById,
    required bool supportsLocalShell,
  }) {
    if (pane.sessionType == TerminalSessionType.ssh) {
      return hostsById.containsKey(pane.hostId)
          ? null
          : 'This host no longer exists.';
    }
    if (!supportsLocalShell) {
      return 'Local shells are not available on this device.';
    }
    final parent = panes.where((p) => p.id == pane.parentPaneId).firstOrNull;
    if (parent != null && parent.sessionType == TerminalSessionType.ssh) {
      return 'A local shell cannot be split out of an SSH pane.';
    }
    return null;
  }

  TemplateModel _withPanes(
    List<TemplatePaneModel> ordered, {
    Object? activePaneId = _keep,
  }) {
    final active = identical(activePaneId, _keep)
        ? this.activePaneId
        : activePaneId as String?;
    return TemplateModel(
      id: id,
      workspaceId: workspaceId,
      name: name,
      description: description,
      panes: [
        for (var i = 0; i < ordered.length; i++)
          _pane(ordered[i], paneOrder: i),
      ],
      activePaneId: active,
      createdAt: createdAt,
    );
  }
}

/// Stand-in default for [TemplateEditing._withPanes]'s `activePaneId`, so a
/// caller can pass null to clear the focus.
const String _keep = '\u0000keep';

/// [TemplatePaneModel.copyWith] cannot clear a field, and a pane turned into a
/// local shell has to lose its host.
TemplatePaneModel _pane(
  TemplatePaneModel pane, {
  int? paneOrder,
  Object? parentPaneId = _keep,
  Axis? splitDirection,
  double? splitRatio,
  TerminalSessionType? sessionType,
  Object? hostId = _keep,
  Object? title = _keep,
}) {
  return TemplatePaneModel(
    id: pane.id,
    templateId: pane.templateId,
    paneOrder: paneOrder ?? pane.paneOrder,
    parentPaneId: identical(parentPaneId, _keep)
        ? pane.parentPaneId
        : parentPaneId as String?,
    splitDirection: splitDirection ?? pane.splitDirection,
    splitRatio: splitRatio ?? pane.splitRatio,
    sessionType: sessionType ?? pane.sessionType,
    hostId: identical(hostId, _keep) ? pane.hostId : hostId as String?,
    title: identical(title, _keep) ? pane.title : title as String?,
  );
}
