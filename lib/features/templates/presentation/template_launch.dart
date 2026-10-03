import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../hosts/domain/services/host_launcher.dart';
import '../domain/models/template_model.dart';
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
