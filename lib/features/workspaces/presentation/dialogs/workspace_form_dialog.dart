import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../domain/models/workspace_model.dart';
import '../notifiers/workspaces_notifier.dart';

class WorkspaceFormDialog extends ConsumerStatefulWidget {
  final WorkspaceModel? workspace;

  const WorkspaceFormDialog({super.key, this.workspace});

  @override
  ConsumerState<WorkspaceFormDialog> createState() =>
      _WorkspaceFormDialogState();
}

class _WorkspaceFormDialogState extends ConsumerState<WorkspaceFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  bool _isSaving = false;

  bool get _isEditing => widget.workspace != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.workspace?.name ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final notifier = ref.read(workspaceManagerProvider.notifier);
      if (_isEditing) {
        await notifier.rename(widget.workspace!.id, _nameController.text);
      } else {
        await notifier.create(_nameController.text);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            title: const Text('Workspace Save Error'),
            description: Text('$error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      title: Text(_isEditing ? 'Rename Workspace' : 'Add Workspace'),
      actions: adaptiveDialogActions(context, [
        ShellVibeButton.secondary(
          label: 'Cancel',
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
        ),
        ShellVibeButton(
          key: const Key('workspace_save_button'),
          label: _isEditing ? 'Rename' : 'Create',
          onPressed: _save,
          busy: _isSaving,
        ),
      ]),
      actionsAxis: adaptiveDialogActionsAxis(context),
      child: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              ShadInputFormField(
                key: const Key('workspace_name_input'),
                controller: _nameController,
                label: const Text('Workspace Name'),
                placeholder: const Text('e.g. Client Infrastructure'),
                validator: (value) =>
                    value.trim().isEmpty ? 'Workspace name is required' : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
