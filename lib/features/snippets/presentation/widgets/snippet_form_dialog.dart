import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/app/widgets/shellvibe_ui.dart';

import '../../../../app/widgets/adaptive_modal.dart';
import '../../domain/models/snippet_model.dart';

/// Form dialog for creating or editing a Snippet.
class SnippetFormDialog extends StatefulWidget {
  final SnippetModel? snippet;
  final String workspaceId;

  const SnippetFormDialog({super.key, this.snippet, required this.workspaceId});

  static Future<SnippetModel?> show(
    BuildContext context, {
    SnippetModel? snippet,
    required String workspaceId,
  }) {
    return showDialog<SnippetModel>(
      context: context,
      builder: (context) =>
          SnippetFormDialog(snippet: snippet, workspaceId: workspaceId),
    );
  }

  @override
  State<SnippetFormDialog> createState() => _SnippetFormDialogState();
}

class _SnippetFormDialogState extends State<SnippetFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _codeController;
  late TextEditingController _tagsController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.snippet?.title ?? '');
    _codeController = TextEditingController(text: widget.snippet?.code ?? '');
    _tagsController = TextEditingController(
      text: widget.snippet?.tags.join(', ') ?? '',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _codeController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  void _insertVariablePlaceholder() {
    final text = _codeController.text;
    final selection = _codeController.selection;
    const placeholder = '\${INPUT:VarName}';
    final newText = text.replaceRange(
      selection.start >= 0 ? selection.start : text.length,
      selection.end >= 0 ? selection.end : text.length,
      placeholder,
    );
    _codeController.text = newText;
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.snippet != null;

    return ShadDialog(
      title: Text(isEditing ? 'Edit Snippet' : 'New Snippet'),
      actions: adaptiveDialogActions(context, [
        ShellVibeButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(null),
        ),
        ShellVibeButton(
          key: const Key('snippet_save_button'),
          label: isEditing ? 'Save' : 'Create',
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final tags = _tagsController.text
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();

              final result = SnippetModel(
                id: widget.snippet?.id ?? '',
                workspaceId: widget.workspaceId,
                title: _titleController.text.trim(),
                code: _codeController.text,
                tags: tags,
              );
              Navigator.of(context).pop(result);
            }
          },
        ),
      ]),
      actionsAxis: adaptiveDialogActionsAxis(context),
      child: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                ShadInputFormField(
                  key: const Key('snippet_title_field'),
                  controller: _titleController,
                  label: const Text('Title'),
                  placeholder: const Text('e.g. Restart Docker Container'),
                  validator: (val) =>
                      val.trim().isEmpty ? 'Title is required' : null,
                ),
                const SizedBox(height: 12),
                ShellVibeFormSectionHeader(
                  icon: LucideIcons.terminal,
                  title: 'Code Command',
                  trailing: ShellVibeButton.quiet(
                    label: '+ Var',
                    icon: Icons.add_link,
                    onPressed: _insertVariablePlaceholder,
                  ),
                ),
                const SizedBox(height: 4),
                ShadInputFormField(
                  key: const Key('snippet_code_field'),
                  controller: _codeController,
                  maxLines: 5,
                  placeholder: const Text(
                    'docker restart \${INPUT:container_name}',
                  ),
                  validator: (val) =>
                      val.trim().isEmpty ? 'Code is required' : null,
                ),
                const SizedBox(height: 12),
                ShadInputFormField(
                  key: const Key('snippet_tags_field'),
                  controller: _tagsController,
                  label: const Text('Tags (comma separated)'),
                  placeholder: const Text('docker, devops, production'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
