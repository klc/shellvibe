import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../shared/providers/workspace_provider.dart';
import '../../domain/models/host_group_model.dart';
import '../notifiers/host_groups_notifier.dart';

class HostGroupFormDialog extends ConsumerStatefulWidget {
  final HostGroupModel? initialGroup;
  final String? workspaceId;

  const HostGroupFormDialog({super.key, this.initialGroup, this.workspaceId});

  @override
  ConsumerState<HostGroupFormDialog> createState() =>
      _HostGroupFormDialogState();
}

class _HostGroupFormDialogState extends ConsumerState<HostGroupFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _colorTagController;
  String? _selectedParentId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final init = widget.initialGroup;
    _nameController = TextEditingController(text: init?.name ?? '');
    _colorTagController = TextEditingController(text: init?.colorTag ?? '');
    _selectedParentId = init?.parentId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _colorTagController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final notifier = ref.read(hostGroupsProvider.notifier);
      final isEditing = widget.initialGroup != null;

      if (isEditing) {
        await notifier.updateGroup(
          id: widget.initialGroup!.id,
          workspaceId: widget.initialGroup!.workspaceId,
          parentId: _selectedParentId,
          name: _nameController.text.trim(),
          colorTag: _colorTagController.text.trim().isEmpty
              ? null
              : _colorTagController.text.trim(),
        );
      } else {
        await notifier.addGroup(
          workspaceId:
              widget.workspaceId ?? ref.read(activeWorkspaceIdProvider),
          parentId: _selectedParentId,
          name: _nameController.text.trim(),
          colorTag: _colorTagController.text.trim().isEmpty
              ? null
              : _colorTagController.text.trim(),
        );
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            title: const Text('Save Group Error'),
            description: Text('$e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(hostGroupsProvider);
    final isEditing = widget.initialGroup != null;

    return ShadDialog(
      title: Text(isEditing ? 'Edit Folder / Group' : 'Add Folder / Group'),
      actions: adaptiveDialogActions(context, [
        ShellVibeButton.secondary(
          label: 'Cancel',
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
        ),
        ShellVibeButton(
          key: const Key('group_save_button'),
          label: isEditing ? 'Update' : 'Save',
          onPressed: _save,
          busy: _isLoading,
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                ShadInputFormField(
                  key: const Key('group_name_input'),
                  controller: _nameController,
                  label: const Text('Group Name'),
                  placeholder: const Text('e.g. Production Servers, Staging'),
                  validator: (v) =>
                      v.trim().isEmpty ? 'Group name is required' : null,
                ),
                const SizedBox(height: 12),
                groupsAsync.when(
                  data: (groups) {
                    final availableParents = groups
                        .where(
                          (g) => isEditing
                              ? g.id != widget.initialGroup!.id
                              : true,
                        )
                        .toList();

                    return ShadSelectFormField<String?>(
                      key: const Key('group_parent_dropdown'),
                      initialValue: _selectedParentId,
                      label: const Text('Parent Group (Optional)'),
                      selectedOptionBuilder: (context, value) {
                        if (value == null) {
                          return const Text('(Root Level - No Parent)');
                        }
                        final parent = availableParents
                            .where((g) => g.id == value)
                            .firstOrNull;
                        return Text(parent?.name ?? value);
                      },
                      options: [
                        const ShadOption<String?>(
                          value: null,
                          child: Text('(Root Level - No Parent)'),
                        ),
                        ...availableParents.map(
                          (g) => ShadOption<String?>(
                            value: g.id,
                            child: Text(g.name),
                          ),
                        ),
                      ],
                      onChanged: (val) =>
                          setState(() => _selectedParentId = val),
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (e, s) => Text('Error loading parent groups: $e'),
                ),
                const SizedBox(height: 12),
                ShadInputFormField(
                  key: const Key('group_colortag_input'),
                  controller: _colorTagController,
                  label: const Text('Color Tag (HEX / Name)'),
                  placeholder: const Text('e.g. #FF5722 or blue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
