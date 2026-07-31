import 'package:flutter/material.dart';
import '../../domain/models/snippet_model.dart';

/// Form dialog for creating or editing a Snippet.
class SnippetFormDialog extends StatefulWidget {
  final SnippetModel? snippet;
  final String workspaceId;

  const SnippetFormDialog({
    super.key,
    this.snippet,
    required this.workspaceId,
  });

  static Future<SnippetModel?> show(
    BuildContext context, {
    SnippetModel? snippet,
    required String workspaceId,
  }) {
    return showDialog<SnippetModel>(
      context: context,
      builder: (context) => SnippetFormDialog(
        snippet: snippet,
        workspaceId: workspaceId,
      ),
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
    _tagsController = TextEditingController(text: widget.snippet?.tags.join(', ') ?? '');
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

    return AlertDialog(
      title: Text(isEditing ? 'Edit Snippet' : 'New Snippet'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('snippet_title_field'),
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'e.g. Restart Docker Container',
                  border: OutlineInputBorder(),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Title is required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Code Command', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: _insertVariablePlaceholder,
                    icon: const Icon(Icons.add_link, size: 16),
                    label: const Text('+ Var'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              TextFormField(
                key: const Key('snippet_code_field'),
                controller: _codeController,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: 'docker restart \${INPUT:container_name}',
                  border: OutlineInputBorder(),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Code is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('snippet_tags_field'),
                controller: _tagsController,
                decoration: const InputDecoration(
                  labelText: 'Tags (comma separated)',
                  hintText: 'docker, devops, production',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const Key('snippet_save_button'),
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
          child: Text(isEditing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
