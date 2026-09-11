import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';

/// Name and description entered for a template.
typedef TemplateDetails = ({String name, String? description});

/// Collects the name for a saved layout.
///
/// Only collects — the caller does the saving, so the same dialog serves both
/// "save this layout" and renaming an existing template.
class SaveTemplateDialog extends StatefulWidget {
  final String? initialName;
  final String? initialDescription;

  /// Summary of what is being saved, shown above the fields (e.g. "3 tabs,
  /// 5 panes"). Null when renaming.
  final String? summary;

  final bool isRename;

  const SaveTemplateDialog({
    super.key,
    this.initialName,
    this.initialDescription,
    this.summary,
    this.isRename = false,
  });

  static Future<TemplateDetails?> show(
    BuildContext context, {
    String? initialName,
    String? initialDescription,
    String? summary,
    bool isRename = false,
  }) {
    return showDialog<TemplateDetails>(
      context: context,
      builder: (ctx) => SaveTemplateDialog(
        initialName: initialName,
        initialDescription: initialDescription,
        summary: summary,
        isRename: isRename,
      ),
    );
  }

  @override
  State<SaveTemplateDialog> createState() => _SaveTemplateDialogState();
}

class _SaveTemplateDialogState extends State<SaveTemplateDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _descriptionController = TextEditingController(
      text: widget.initialDescription ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final description = _descriptionController.text.trim();
    Navigator.of(context).pop((
      name: _nameController.text.trim(),
      description: description.isEmpty ? null : description,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      title: Text(widget.isRename ? 'Rename Template' : 'Save as Template'),
      description: widget.isRename
          ? null
          : const Text(
              'Saves the open tabs and split panes so you can reopen the same '
              'layout later.',
            ),
      actions: adaptiveDialogActions(context, [
        ShellVibeButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        ShellVibeButton(
          key: const Key('template_save_button'),
          label: widget.isRename ? 'Rename' : 'Save',
          onPressed: _submit,
        ),
      ]),
      actionsAxis: adaptiveDialogActionsAxis(context),
      child: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              if (widget.summary case final summary?) ...[
                Text(summary, style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 10),
              ],
              ShadInputFormField(
                key: const Key('template_name_input'),
                controller: _nameController,
                autofocus: true,
                label: const Text('Template Name'),
                placeholder: const Text('e.g. Prod triage, Deploy check'),
                validator: (v) =>
                    v.trim().isEmpty ? 'Template name is required' : null,
                onSubmitted: (_) => _submit(),
              ),
              if (!widget.isRename) ...[
                const SizedBox(height: 12),
                ShadInputFormField(
                  key: const Key('template_description_input'),
                  controller: _descriptionController,
                  label: const Text('Description (Optional)'),
                  placeholder: const Text('What this layout is for'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
