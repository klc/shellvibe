import 'package:uuid/uuid.dart';

import '../../../terminal/domain/models/terminal_tab_session.dart';
import '../models/template_model.dart';
import '../models/template_pane_model.dart';

/// Turns the live terminal layout into a saveable [TemplateModel].
///
/// Deliberately a pure function over the session list: nothing here touches a
/// terminal buffer, an SSH manager or a PTY bridge, so a capture is fully
/// unit-testable and can never carry runtime handles or credentials into
/// storage.
class TemplateCapture {
  const TemplateCapture();

  /// Captures [tabs] — every open tab *and* split pane, in their current order
  /// — as a template.
  ///
  /// Live session ids are replaced with template-local ids: the saved layout
  /// must not reference ids that will never exist again, and replay generates
  /// fresh ones anyway.
  TemplateModel capture({
    required String workspaceId,
    required String name,
    String? description,
    required List<TerminalTabSession> tabs,
    String? activeTabId,
    DateTime? createdAt,
    String Function()? idFactory,
  }) {
    final newId = idFactory ?? () => const Uuid().v4();
    final templateId = newId();

    // Live session id -> template-local pane id, filled in list order so a
    // parent is always mapped before the panes that point at it.
    final paneIds = <String, String>{
      for (final tab in tabs) tab.id: newId(),
    };

    final panes = <TemplatePaneModel>[];
    for (var i = 0; i < tabs.length; i++) {
      final tab = tabs[i];
      // A parent that is not part of the capture cannot be referenced, so the
      // pane is saved as a root tab rather than as a dangling child.
      final parentPaneId = tab.splitParentId == null
          ? null
          : paneIds[tab.splitParentId];

      panes.add(
        TemplatePaneModel(
          id: paneIds[tab.id]!,
          templateId: templateId,
          paneOrder: i,
          parentPaneId: parentPaneId,
          splitDirection: parentPaneId == null ? null : tab.splitDirection,
          splitRatio: tab.splitRatio,
          sessionType: tab.sessionType,
          hostId: tab.host?.id,
          title: tab.title,
        ),
      );
    }

    return TemplateModel(
      id: templateId,
      workspaceId: workspaceId,
      name: name,
      description: description,
      panes: panes,
      activePaneId: activeTabId == null ? null : paneIds[activeTabId],
      createdAt: createdAt ?? DateTime.now(),
    );
  }
}
