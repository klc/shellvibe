import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifiers/host_groups_notifier.dart';
import '../../domain/models/host_group_model.dart';

class HostGroupFormDialog extends ConsumerStatefulWidget {
  final HostGroupModel? initialGroup;
  final String workspaceId;

  const HostGroupFormDialog({
    super.key,
    this.initialGroup,
    this.workspaceId = 'default',
  });

  @override
  ConsumerState<HostGroupFormDialog> createState() => _HostGroupFormDialogState();
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
      final notifier = ref.read(hostGroupsNotifierProvider.notifier);
      final isEditing = widget.initialGroup != null;

      if (isEditing) {
        await notifier.updateGroup(
          id: widget.initialGroup!.id,
          workspaceId: widget.initialGroup!.workspaceId,
          parentId: _selectedParentId,
          name: _nameController.text.trim(),
          colorTag: _colorTagController.text.trim().isEmpty ? null : _colorTagController.text.trim(),
        );
      } else {
        await notifier.addGroup(
          workspaceId: widget.workspaceId,
          parentId: _selectedParentId,
          name: _nameController.text.trim(),
          colorTag: _colorTagController.text.trim().isEmpty ? null : _colorTagController.text.trim(),
        );
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save group: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(hostGroupsNotifierProvider);
    final isEditing = widget.initialGroup != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Folder / Group' : 'Add Folder / Group'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('group_name_input'),
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Group Name',
                  hintText: 'e.g. Production Servers, Staging',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Group name is required' : null,
              ),
              const SizedBox(height: 12),
              groupsAsync.when(
                data: (groups) {
                  final availableParents = groups
                      .where((g) => isEditing ? g.id != widget.initialGroup!.id : true)
                      .toList();

                  return DropdownButtonFormField<String?>(
                    key: const Key('group_parent_dropdown'),
                    initialValue: _selectedParentId,
                    decoration: const InputDecoration(
                      labelText: 'Parent Group (Optional)',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('(Root Level - No Parent)'),
                      ),
                      ...availableParents.map(
                        (g) => DropdownMenuItem<String?>(
                          value: g.id,
                          child: Text(g.name),
                        ),
                      ),
                    ],
                    onChanged: (val) => setState(() => _selectedParentId = val),
                  );
                },
                loading: () => const CircularProgressIndicator(),
                error: (e, s) => Text('Error loading parent groups: $e'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('group_colortag_input'),
                controller: _colorTagController,
                decoration: const InputDecoration(
                  labelText: 'Color Tag (HEX / Name)',
                  hintText: 'e.g. #FF5722 or blue',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const Key('group_save_button'),
          onPressed: _isLoading ? null : _save,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEditing ? 'Update' : 'Save'),
        ),
      ],
    );
  }
}
