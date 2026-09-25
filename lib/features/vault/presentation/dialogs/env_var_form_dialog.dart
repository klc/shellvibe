import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/app/widgets/shellvibe_ui.dart';

import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../shared/providers/workspace_provider.dart';
import '../../domain/models/vault_env_var.dart';
import '../../domain/models/vault_env_var_rules.dart';
import '../notifiers/vault_env_vars_notifier.dart';

class EnvVarFormDialog extends ConsumerStatefulWidget {
  final VaultEnvVarModel? initialVariable;
  final String? workspaceId;

  const EnvVarFormDialog({super.key, this.initialVariable, this.workspaceId});

  @override
  ConsumerState<EnvVarFormDialog> createState() => _EnvVarFormDialogState();
}

class _EnvVarFormDialogState extends ConsumerState<EnvVarFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _valueController;
  bool _obscureValue = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final init = widget.initialVariable;
    _nameController = TextEditingController(text: init?.name ?? '');
    _valueController = TextEditingController(text: init?.value ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  /// Mirrors the repository's own checks (`VaultEnvRepository.save`), so a bad
  /// name is flagged under the field instead of surfacing only after the save
  /// round-trips to the database.
  String? _validateName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Name is required';
    if (!vaultEnvVarNameRegex.hasMatch(trimmed)) {
      return 'Letters, numbers and underscores only, starting with a letter '
          'or underscore';
    }
    if (kReservedVaultEnvVarNames.contains(trimmed)) {
      return '"$trimmed" is set automatically and cannot be overridden';
    }

    final existing =
        ref.read(vaultEnvVarsProvider).value ?? const <VaultEnvVarModel>[];
    final isDuplicate = existing.any(
      (variable) =>
          variable.name == trimmed && variable.id != widget.initialVariable?.id,
    );
    if (isDuplicate) return 'A variable named "$trimmed" already exists';

    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final notifier = ref.read(vaultEnvVarsProvider.notifier);
      final isEditing = widget.initialVariable != null;
      final name = _nameController.text.trim();
      final value = _valueController.text;

      if (isEditing) {
        await notifier.updateVariable(
          id: widget.initialVariable!.id,
          workspaceId: widget.initialVariable!.workspaceId,
          name: name,
          value: value,
        );
      } else {
        await notifier.addVariable(
          workspaceId:
              widget.workspaceId ?? ref.read(activeWorkspaceIdProvider),
          name: name,
          value: value,
        );
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            title: const Text('Save Environment Variable Error'),
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
    final isEditing = widget.initialVariable != null;

    return ShadDialog(
      title: Row(
        children: [
          const Icon(LucideIcons.variable, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              isEditing
                  ? 'Edit Environment Variable'
                  : 'Add Environment Variable',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      description: const Text(
        'Encrypted in the Vault and added to every new local shell.',
      ),
      actions: adaptiveDialogActions(context, [
        ShellVibeButton.secondary(
          label: 'Cancel',
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
        ),
        ShellVibeButton(
          key: const Key('env_var_save_button'),
          label: isEditing ? 'Update' : 'Save',
          onPressed: _save,
          busy: _isLoading,
        ),
      ]),
      actionsAxis: adaptiveDialogActionsAxis(context),
      child: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                ShadInputFormField(
                  key: const Key('env_var_name_input'),
                  controller: _nameController,
                  label: const Text('Name'),
                  placeholder: const Text('e.g. GITHUB_TOKEN'),
                  leading: const Icon(LucideIcons.tag, size: 16),
                  validator: _validateName,
                ),
                const SizedBox(height: 12),
                ShadInputFormField(
                  key: const Key('env_var_value_input'),
                  controller: _valueController,
                  obscureText: _obscureValue,
                  label: const Text('Value'),
                  leading: const Icon(LucideIcons.lockKeyhole, size: 16),
                  validator: (v) => v.isEmpty ? 'Value is required' : null,
                  trailing: ShellVibeIconButton(
                    icon: _obscureValue ? LucideIcons.eye : LucideIcons.eyeOff,
                    tooltip: _obscureValue ? 'Show value' : 'Hide value',
                    onPressed: () =>
                        setState(() => _obscureValue = !_obscureValue),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
