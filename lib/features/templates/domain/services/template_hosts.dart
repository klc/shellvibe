import '../../../hosts/domain/models/host_model.dart';
import '../../../terminal/domain/models/terminal_tab_session.dart';
import '../models/template_model.dart';

/// The hosts a template's panes connect to, for running something on them in
/// the background.
class TemplateHosts {
  /// Distinct hosts, in the order their panes first appear.
  final List<HostModel> hosts;

  /// Panes that contributed no host: a local shell, a pane with no host, a
  /// host that no longer exists, or a host that is itself a local shell (a
  /// background run needs an SSH connection).
  final int skippedPanes;

  const TemplateHosts(this.hosts, this.skippedPanes);
}

/// Resolves [template]'s panes against [hostsById].
///
/// Two panes on one host give that host once: the run goes to the machine, not
/// to each window onto it.
TemplateHosts resolveTemplateHosts(
  TemplateModel template,
  Map<String, HostModel> hostsById,
) {
  final panes = [...template.panes]
    ..sort((a, b) => a.paneOrder.compareTo(b.paneOrder));
  final hosts = <HostModel>[];
  final seen = <String>{};
  var skipped = 0;
  for (final pane in panes) {
    final host = pane.sessionType == TerminalSessionType.ssh
        ? hostsById[pane.hostId]
        : null;
    if (host == null || host.protocol == 'local') {
      skipped++;
      continue;
    }
    if (seen.add(host.id)) hosts.add(host);
  }
  return TemplateHosts(hosts, skipped);
}
