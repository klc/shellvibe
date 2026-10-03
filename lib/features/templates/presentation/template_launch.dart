import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../app/widgets/adaptive_modal.dart';
import '../../../app/widgets/shellvibe_ui.dart';
import '../../hosts/domain/models/host_model.dart';
import '../../hosts/domain/services/host_launcher.dart';
import '../../hosts/presentation/notifiers/hosts_notifier.dart';
import '../../snippets/domain/models/runbook_model.dart';
import '../../snippets/presentation/notifiers/runbook_run_notifier.dart';
import '../../snippets/presentation/notifiers/runbooks_notifier.dart';
import '../../snippets/presentation/widgets/run_progress_view.dart';
import '../../snippets/presentation/widgets/variable_input_dialog.dart';
import '../domain/models/template_model.dart';
import '../domain/services/template_on_open.dart';
import 'notifiers/templates_notifier.dart';

/// Replays [template]'s layout in the terminal tabs without leaving the screen
/// it was asked from.
///
/// Used by "Also open the layout" in the run-target sheet: the background run
/// stays on its own connections, and this only adds the tabs. Panes that could
/// not open are reported, as everywhere a template runs.
Future<void> openTemplateLayout(
  BuildContext context,
  WidgetRef ref,
  TemplateModel template,
) async {
  final launcher = HostLauncher(context: context, ref: ref);
  final result = await ref
      .read(templatesProvider.notifier)
      .runTemplate(
        template,
        resolveIdentity: launcher.resolveIdentity,
        onHostKeyPrompt: launcher.promptHostKey,
      );
  if (!context.mounted) return;
  final toaster = ShadToaster.maybeOf(context);
  if (result.isComplete) {
    toaster?.show(
      ShadToast(
        description: Text(
          'Opened "${template.name}" — ${result.openedPanes} '
          '${result.openedPanes == 1 ? 'pane' : 'panes'}.',
        ),
      ),
    );
    return;
  }
  toaster?.show(
    ShadToast.destructive(
      title: Text(
        result.openedPanes == 0
            ? 'Could not run "${template.name}"'
            : 'Ran "${template.name}" with skipped panes',
      ),
      description: Text(result.warnings.join('\n')),
    ),
  );
}

/// Starts [template]'s on-open runbook, if it has one, after its layout has
/// been replayed. Call it from every place a template is run.
///
/// The rules (confirm, prompt for input, skip when busy) live in
/// [TemplateOnOpen]; this wires them to dialogs, the run notifier and a toast
/// with a way into the run view. [context] must outlive the call, so the
/// caller passes one that is still mounted when it asks.
Future<OnOpenOutcome> runTemplateOnOpen(
  BuildContext context,
  WidgetRef ref,
  TemplateModel template,
) async {
  if (template.onOpenRunbookId == null) return OnOpenOutcome.notConfigured;

  final runbooks = await ref.read(runbooksProvider.future);
  final hosts = await ref.read(hostsProvider.future);
  if (!context.mounted) return OnOpenOutcome.notConfigured;

  final notifier = ref.read(runbookRunProvider.notifier);
  final onOpen = TemplateOnOpen(
    isRunning: () => notifier.isRunning,
    confirm: (runbook, hosts) =>
        _confirmOnOpen(context, template, runbook, hosts),
    promptVariables: (runbook, variables) {
      if (!context.mounted) return Future.value();
      return VariableInputDialog.show(
        context,
        variables: variables,
        title: 'Input for "${runbook.title}"',
      );
    },
    start: (runbook, hosts, values) =>
        unawaited(notifier.start(runbook, hosts, variableValues: values)),
    notify: (message, {offerRunView = false}) {
      if (!context.mounted) return;
      ShadToaster.maybeOf(context)?.show(
        ShadToast(
          description: Text(message),
          action: offerRunView
              ? ShellVibeButton.secondary(
                  key: const Key('on_open_view_run'),
                  label: 'View run',
                  onPressed: () => RunResultDialog.show(context),
                )
              : null,
        ),
      );
    },
  );
  return onOpen.run(
    template,
    runbooks: runbooks,
    hostsById: {for (final host in hosts) host.id: host},
  );
}

Future<bool> _confirmOnOpen(
  BuildContext context,
  TemplateModel template,
  RunbookModel runbook,
  List<HostModel> hosts,
) async {
  if (!context.mounted) return false;
  final run = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => ShadDialog.alert(
      key: const Key('on_open_confirm_dialog'),
      title: Text('Run "${runbook.title}"?'),
      description: Text(
        '"${template.name}" is set to run this runbook on its hosts:\n'
        '${hosts.map((h) => '• ${h.label}${h.isProd ? ' (production)' : ''}').join('\n')}',
      ),
      actions: adaptiveDialogActions(dialogContext, [
        ShellVibeButton.secondary(
          key: const Key('on_open_confirm_skip'),
          label: 'Skip',
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        // Destructive-styled when production is among them.
        if (hosts.any((h) => h.isProd))
          ShellVibeButton.danger(
            key: const Key('on_open_confirm_run'),
            label: 'Run on production',
            onPressed: () => Navigator.of(dialogContext).pop(true),
          )
        else
          ShellVibeButton(
            key: const Key('on_open_confirm_run'),
            label: 'Run',
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
      ]),
      actionsAxis: adaptiveDialogActionsAxis(dialogContext),
    ),
  );
  return run == true;
}
