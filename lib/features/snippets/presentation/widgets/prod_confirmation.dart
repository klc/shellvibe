import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../hosts/domain/models/host_model.dart';

/// The production hosts among [hosts], in order, without repeats.
List<HostModel> prodHostsOf(Iterable<HostModel> hosts) {
  final seen = <String>{};
  return [
    for (final host in hosts)
      if (host.isProd && seen.add(host.id)) host,
  ];
}

/// Asks before [what] runs anywhere that is production.
///
/// One check for every way a command can reach a machine without the user
/// typing it: a runbook, a snippet, a re-run from history, a template's
/// on-open runbook, a snippet sent into a pane. Returns true at once when no
/// host in [hosts] is `prod`; otherwise shows a dialog naming them and returns
/// whether the user confirmed.
///
/// [what] reads as a noun phrase: `runbook "Deploy"`, `snippet "Restart"`.
Future<bool> confirmProdRun(
  BuildContext context, {
  required String what,
  required Iterable<HostModel> hosts,
}) async {
  final prod = prodHostsOf(hosts);
  if (prod.isEmpty) return true;
  if (!context.mounted) return false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => ShadDialog.alert(
      key: const Key('prod_confirm_dialog'),
      title: const Text('Run on production?'),
      description: Text(
        'You are about to run $what on '
        '${prod.length == 1 ? 'a production host' : 'production hosts'}:\n'
        '${prod.map((h) => '• ${h.label}').join('\n')}',
      ),
      actions: adaptiveDialogActions(dialogContext, [
        ShellVibeButton.secondary(
          key: const Key('prod_confirm_cancel'),
          label: 'Cancel',
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        ShellVibeButton.danger(
          key: const Key('prod_confirm_run'),
          label: 'Run on production',
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ]),
      actionsAxis: adaptiveDialogActionsAxis(dialogContext),
    ),
  );
  return confirmed == true;
}
