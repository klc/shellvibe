import 'package:flutter/widgets.dart';

import '../../../hosts/domain/models/host_model.dart';
import '../../../terminal/domain/models/terminal_tab_session.dart';
import '../../../vault/domain/models/identity_model.dart';
import '../models/template_model.dart';
import '../models/template_pane_model.dart';

/// Outcome of resolving the credentials a pane needs.
///
/// Mirrors the terminal's own `_resolveIdentity`: `ok: false` means the stored
/// credentials could not be read, which must abort the pane rather than connect
/// without them.
typedef TemplateIdentityResolver = Future<({bool ok, IdentityModel? identity})>
    Function(HostModel host);

/// The slice of the terminal tab notifier a template replay drives.
///
/// Exists so replay ordering can be tested without opening real SSH sessions;
/// [LiveTemplateRunnerTarget] is the production implementation.
abstract class TemplateRunnerTarget {
  /// Id of the pane created by the most recent open/split call — every one of
  /// them focuses the pane it created.
  String? get activeTabId;

  Future<void> openTabForHost(HostModel host, {IdentityModel? identity});

  void openLocalTab({String? title});

  Future<void> splitTab(
    String parentTabId, {
    required Axis direction,
    HostModel? host,
    IdentityModel? identity,
  });

  void setSplitRatio(String tabId, double ratio);

  void setActiveTab(String tabId);
}

class TemplateRunResult {
  /// Panes that were actually opened.
  final int openedPanes;

  /// Panes that were skipped, one human-readable reason each.
  final List<String> warnings;

  const TemplateRunResult({
    required this.openedPanes,
    this.warnings = const [],
  });

  bool get isComplete => warnings.isEmpty;
}

/// Recreates a saved layout on top of whatever is already open.
///
/// Replay is strictly sequential rather than concurrent: a split pane can only
/// be created once its parent is in the tab list, and the visual order of split
/// siblings is their insertion order, so firing the opens in parallel would
/// scramble the layout.
class TemplateRunner {
  const TemplateRunner();

  /// Whether running [template] would touch stored credentials, and therefore
  /// needs the vault unlocked first.
  bool requiresUnlockedVault(
    TemplateModel template,
    Map<String, HostModel> hostsById,
  ) {
    return template.panes.any((pane) {
      if (pane.sessionType != TerminalSessionType.ssh) return false;
      final host = hostsById[pane.hostId];
      return host?.identityId != null;
    });
  }

  Future<TemplateRunResult> run(
    TemplateModel template, {
    required TemplateRunnerTarget target,
    required Map<String, HostModel> hostsById,
    required TemplateIdentityResolver resolveIdentity,
    bool supportsLocalShell = true,
  }) async {
    final panes = [...template.panes]
      ..sort((a, b) => a.paneOrder.compareTo(b.paneOrder));

    // Template pane id -> live session id, for the panes that came up.
    final liveIds = <String, String>{};
    final skipped = <String>{};
    final warnings = <String>[];

    void skip(TemplatePaneModel pane, String reason) {
      skipped.add(pane.id);
      warnings.add(reason);
    }

    for (final pane in panes) {
      final label = pane.title ?? 'Pane ${pane.paneOrder + 1}';
      final parentPane = pane.parentPaneId == null
          ? null
          : panes.where((p) => p.id == pane.parentPaneId).firstOrNull;

      // A pane whose parent never came up has nothing to split, so the whole
      // subtree drops out with a single warning for the parent.
      if (pane.parentPaneId != null &&
          (skipped.contains(pane.parentPaneId) ||
              !liveIds.containsKey(pane.parentPaneId))) {
        skipped.add(pane.id);
        continue;
      }

      HostModel? host;
      IdentityModel? identity;

      if (pane.sessionType == TerminalSessionType.ssh) {
        host = hostsById[pane.hostId];
        if (host == null) {
          skip(pane, '$label: host no longer exists.');
          continue;
        }
        final resolved = await resolveIdentity(host);
        if (!resolved.ok) {
          skip(pane, '$label: stored credentials could not be read.');
          continue;
        }
        identity = resolved.identity;
      } else if (!supportsLocalShell) {
        skip(pane, '$label: local shells are not available on this platform.');
        continue;
      } else if (parentPane != null &&
          parentPane.sessionType == TerminalSessionType.ssh) {
        // Splitting an SSH pane always opens another SSH session on the same
        // host, so a local pane cannot be recreated there. The terminal cannot
        // produce this shape either, so it only guards hand-edited data.
        skip(pane, '$label: a local pane cannot be split out of an SSH pane.');
        continue;
      }

      if (pane.parentPaneId == null) {
        if (host != null) {
          await target.openTabForHost(host, identity: identity);
        } else {
          target.openLocalTab(title: pane.title);
        }
      } else {
        await target.splitTab(
          liveIds[pane.parentPaneId]!,
          direction: pane.splitDirection ?? Axis.horizontal,
          host: host,
          identity: identity,
        );
      }

      final liveId = target.activeTabId;
      if (liveId == null) {
        skip(pane, '$label: could not be opened.');
        continue;
      }
      liveIds[pane.id] = liveId;
    }

    // Ratios are applied only once every pane exists: `setSplitRatio` looks the
    // pane up in the tab list and silently does nothing for one that is not
    // there yet.
    for (final pane in panes) {
      if (pane.parentPaneId == null) continue;
      final liveId = liveIds[pane.id];
      if (liveId == null) continue;
      target.setSplitRatio(liveId, pane.splitRatio);
    }

    // Every open and split focuses itself, so without this the last pane
    // created would keep the focus instead of the one that had it at capture.
    final activeLiveId = liveIds[template.activePaneId];
    if (activeLiveId != null) {
      target.setActiveTab(activeLiveId);
    }

    return TemplateRunResult(
      openedPanes: liveIds.length,
      warnings: warnings,
    );
  }
}
