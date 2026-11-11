import 'package:flutter/widgets.dart';

import '../../../core/network/ssh_session_manager.dart';
import '../../hosts/domain/models/host_model.dart';
import '../../terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../vault/domain/models/identity_model.dart';
import '../domain/services/template_runner.dart';

/// Drives the real terminal notifier for a template replay.
///
/// [readTabIds] reads the notifier's current state through the provider
/// rather than the notifier object; the runner compares it across an open or
/// split to learn the id of the pane that call created.
class LiveTemplateRunnerTarget implements TemplateRunnerTarget {
  final TerminalTabsNotifier notifier;
  final List<String> Function() readTabIds;
  final HostKeyPromptCallback? onHostKeyPrompt;

  const LiveTemplateRunnerTarget({
    required this.notifier,
    required this.readTabIds,
    this.onHostKeyPrompt,
  });

  @override
  List<String> get tabIds => readTabIds();

  @override
  Future<void> openTabForHost(
    HostModel host, {
    IdentityModel? identity,
    String? startupSnippetId,
    String? startupRunbookId,
  }) {
    return notifier.openTabForHost(
      host,
      identity: identity,
      onHostKeyPrompt: onHostKeyPrompt,
      startupSnippetId: startupSnippetId,
      startupRunbookId: startupRunbookId,
    );
  }

  @override
  void openLocalTab({String? title}) => notifier.openLocalTab(title: title);

  @override
  Future<void> splitTab(
    String parentTabId, {
    required Axis direction,
    HostModel? host,
    IdentityModel? identity,
    String? startupSnippetId,
    String? startupRunbookId,
  }) {
    // `splitTab` returns null for a local pane, which needs no awaiting: the
    // PTY is already wired by the time it returns.
    return notifier.splitTab(
          parentTabId,
          direction: direction,
          host: host,
          identity: identity,
          onHostKeyPrompt: onHostKeyPrompt,
          startupSnippetId: startupSnippetId,
          startupRunbookId: startupRunbookId,
        ) ??
        Future.value();
  }

  @override
  void setSplitRatio(String tabId, double ratio) =>
      notifier.setSplitRatio(tabId, ratio);

  @override
  void setActiveTab(String tabId) => notifier.setActiveTab(tabId);
}
