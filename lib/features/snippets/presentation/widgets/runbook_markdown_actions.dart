import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../data/services/runbook_file_service.dart';
import '../../domain/models/runbook_model.dart';
import '../../domain/services/runbook_markdown.dart';
import '../notifiers/runbooks_notifier.dart';
import '../notifiers/snippets_notifier.dart';

/// Exports [runbook] as Markdown: saved through a file dialog where the
/// platform has one, otherwise (a phone, or a dialog that fails) copied to the
/// clipboard, and the user is told which.
Future<void> exportRunbookMarkdown(
  BuildContext context,
  WidgetRef ref,
  RunbookModel runbook,
) async {
  final snippets = {
    for (final s in await ref.read(snippetsProvider.future)) s.id: s,
  };
  final markdown = RunbookMarkdown.export(runbook, snippets: snippets);
  if (!context.mounted) return;
  final toaster = ShadToaster.maybeOf(context);
  final files = ref.read(runbookFileServiceProvider);

  Future<void> copy(String why) async {
    await Clipboard.setData(ClipboardData(text: markdown));
    toaster?.show(
      ShadToast(
        description: Text('$why Copied "${runbook.title}" as Markdown.'),
      ),
    );
  }

  if (!files.canSave) {
    await copy('This device cannot save a file here.');
    return;
  }
  try {
    final name = '${_fileStem(runbook.title)}.md';
    final path = await files.saveMarkdown(name, markdown);
    if (path != null) {
      toaster?.show(ShadToast(description: Text('Saved $path')));
    }
  } catch (_) {
    await copy('Saving a file did not work.');
  }
}

/// Asks for Markdown (a file, or pasted) and adds it as a new runbook. Never
/// overwrites one: an import is always a new runbook with new ids.
Future<void> importRunbookMarkdown(
  BuildContext context,
  WidgetRef ref, {
  required String workspaceId,
}) async {
  final imported = await showDialog<RunbookModel>(
    context: context,
    builder: (_) => RunbookImportDialog(workspaceId: workspaceId),
  );
  if (imported == null || !context.mounted) return;
  await ref
      .read(runbooksProvider.notifier)
      .addRunbook(
        workspaceId: imported.workspaceId,
        title: imported.title,
        description: imported.description,
        steps: imported.steps,
        variables: imported.variables,
        tags: imported.tags,
      );
  if (!context.mounted) return;
  ShadToaster.maybeOf(context)?.show(
    ShadToast(
      description: Text(
        'Imported "${imported.title}" with ${imported.steps.length} '
        '${imported.steps.length == 1 ? 'step' : 'steps'}.',
      ),
    ),
  );
}

String _fileStem(String title) {
  final cleaned = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return cleaned.isEmpty ? 'runbook' : cleaned;
}

/// Markdown in a text box, from a file or pasted. Shows what is wrong with it
/// right there rather than closing.
class RunbookImportDialog extends ConsumerStatefulWidget {
  final String workspaceId;

  const RunbookImportDialog({super.key, required this.workspaceId});

  @override
  ConsumerState<RunbookImportDialog> createState() =>
      _RunbookImportDialogState();
}

class _RunbookImportDialogState extends ConsumerState<RunbookImportDialog> {
  final _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _chooseFile() async {
    try {
      final contents = await ref
          .read(runbookFileServiceProvider)
          .pickMarkdown();
      if (contents == null || !mounted) return;
      setState(() {
        _text.text = contents;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not read that file: $e');
    }
  }

  void _import() {
    try {
      final runbook = RunbookMarkdown.import(
        _text.text,
        workspaceId: widget.workspaceId,
      );
      Navigator.of(context).pop(runbook);
    } on RunbookMarkdownException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return ShadDialog(
      title: const Text('Import runbook from Markdown'),
      constraints: const BoxConstraints(maxWidth: 560),
      actions: adaptiveDialogActions(context, [
        ShellVibeButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(null),
        ),
        ShellVibeButton(
          key: const Key('runbook_import_confirm'),
          label: 'Import',
          onPressed: _import,
        ),
      ]),
      actionsAxis: adaptiveDialogActionsAxis(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: ShellVibeButton.secondary(
              key: const Key('runbook_import_choose_file'),
              label: 'Choose file…',
              icon: LucideIcons.fileText,
              onPressed: _chooseFile,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'or paste Markdown. Each sh or bash block becomes a step; a new '
            'runbook is created, nothing is overwritten.',
            style: TextStyle(color: tokens.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 8),
          ShadTextarea(
            key: const Key('runbook_import_text'),
            controller: _text,
            minHeight: 160,
            maxHeight: 280,
            placeholder: const Text('```sh\nuptime\n```'),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                key: const Key('runbook_import_error'),
                style: TextStyle(color: tokens.danger, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
