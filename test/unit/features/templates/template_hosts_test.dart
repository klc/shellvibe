import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/templates/domain/models/template_model.dart';
import 'package:shellvibe/features/templates/domain/models/template_pane_model.dart';
import 'package:shellvibe/features/templates/domain/services/template_hosts.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_tab_session.dart';

HostModel host(String id, {String protocol = 'ssh'}) => HostModel(
  id: id,
  workspaceId: 'w',
  label: id,
  hostname: '$id.example.com',
  protocol: protocol,
  createdAt: DateTime(2026),
);

TemplatePaneModel pane(
  int order, {
  TerminalSessionType type = TerminalSessionType.ssh,
  String? hostId,
}) => TemplatePaneModel(
  id: 'p$order',
  templateId: 't',
  paneOrder: order,
  sessionType: type,
  hostId: hostId,
);

TemplateModel template(List<TemplatePaneModel> panes) => TemplateModel(
  id: 't',
  workspaceId: 'w',
  name: 'T',
  createdAt: DateTime(2026),
  panes: panes,
);

void main() {
  final hosts = {
    'a': host('a'),
    'b': host('b'),
    'm': host('m', protocol: 'mosh'),
    'l': host('l', protocol: 'local'),
  };

  test('distinct hosts in pane order', () {
    final result = resolveTemplateHosts(
      template([
        pane(2, hostId: 'b'),
        pane(0, hostId: 'a'),
        pane(1, hostId: 'a'),
        pane(3, hostId: 'b'),
      ]),
      hosts,
    );
    expect(result.hosts.map((h) => h.id), ['a', 'b']);
    expect(result.skippedPanes, 0);
  });

  test('skips local panes, panes without a host and deleted hosts', () {
    final result = resolveTemplateHosts(
      template([
        pane(0, hostId: 'a'),
        pane(1, type: TerminalSessionType.local),
        pane(2),
        pane(3, hostId: 'gone'),
        pane(4, type: TerminalSessionType.local, hostId: 'a'),
      ]),
      hosts,
    );
    expect(result.hosts.map((h) => h.id), ['a']);
    expect(result.skippedPanes, 4);
  });

  test('a host that is itself a local shell cannot take a background run', () {
    final result = resolveTemplateHosts(
      template([pane(0, hostId: 'l'), pane(1, hostId: 'm')]),
      hosts,
    );
    expect(result.hosts.map((h) => h.id), ['m']);
    expect(result.skippedPanes, 1);
  });

  test('an empty template resolves to nothing', () {
    final result = resolveTemplateHosts(template(const []), hosts);
    expect(result.hosts, isEmpty);
    expect(result.skippedPanes, 0);
  });
}
