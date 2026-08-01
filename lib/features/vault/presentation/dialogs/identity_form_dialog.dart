import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../notifiers/identities_notifier.dart';
import '../../domain/models/identity_model.dart';
import '../../../../shared/providers/workspace_provider.dart';

class IdentityFormDialog extends ConsumerStatefulWidget {
  final IdentityModel? initialIdentity;
  final String? workspaceId;

  const IdentityFormDialog({super.key, this.initialIdentity, this.workspaceId});

  @override
  ConsumerState<IdentityFormDialog> createState() => _IdentityFormDialogState();
}

class _IdentityFormDialogState extends ConsumerState<IdentityFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _titleController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late TextEditingController _privateKeyController;
  late TextEditingController _passphraseController;

  late String _authType;
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final init = widget.initialIdentity;
    _titleController = TextEditingController(text: init?.title ?? '');
    _usernameController = TextEditingController(text: init?.username ?? '');
    _passwordController = TextEditingController(text: init?.password ?? '');
    _privateKeyController = TextEditingController(text: init?.privateKey ?? '');
    _passphraseController = TextEditingController(text: init?.passphrase ?? '');
    _authType = init?.authType ?? 'password';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _privateKeyController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final notifier = ref.read(identitiesProvider.notifier);
      final isEditing = widget.initialIdentity != null;

      if (isEditing) {
        await notifier.updateIdentity(
          id: widget.initialIdentity!.id,
          workspaceId: widget.initialIdentity!.workspaceId,
          title: _titleController.text.trim(),
          username: _usernameController.text.trim(),
          authType: _authType,
          password: _authType == 'password' ? _passwordController.text : null,
          privateKey: _authType == 'key' ? _privateKeyController.text : null,
          passphrase: _authType == 'key' ? _passphraseController.text : null,
        );
      } else {
        await notifier.addIdentity(
          workspaceId:
              widget.workspaceId ?? ref.read(activeWorkspaceIdProvider),
          title: _titleController.text.trim(),
          username: _usernameController.text.trim(),
          authType: _authType,
          password: _authType == 'password' ? _passwordController.text : null,
          privateKey: _authType == 'key' ? _privateKeyController.text : null,
          passphrase: _authType == 'key' ? _passphraseController.text : null,
        );
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            title: const Text('Save Identity Error'),
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
    final isEditing = widget.initialIdentity != null;

    return ShadDialog(
      title: Text(isEditing ? 'Edit Identity' : 'Add New Identity'),
      actions: [
        ShadButton.outline(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ShadButton(
          key: const Key('identity_save_button'),
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
      child: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                ShadInputFormField(
                  key: const Key('identity_title_input'),
                  controller: _titleController,
                  label: const Text('Title / Label'),
                  placeholder: const Text('e.g. Production Server Key'),
                  validator: (v) =>
                      v.trim().isEmpty ? 'Title is required' : null,
                ),
                const SizedBox(height: 12),
                ShadInputFormField(
                  key: const Key('identity_username_input'),
                  controller: _usernameController,
                  label: const Text('Username (Optional)'),
                  placeholder: const Text('e.g. root, ubuntu (optional)'),
                ),
                const SizedBox(height: 12),
                ShadSelectFormField<String>(
                  key: const Key('identity_authtype_dropdown'),
                  initialValue: _authType,
                  label: const Text('Authentication Type'),
                  selectedOptionBuilder: (context, value) {
                    switch (value) {
                      case 'key':
                        return const Text('SSH Private Key');
                      case 'agent':
                        return const Text('SSH Agent');
                      case 'password':
                      default:
                        return const Text('Password');
                    }
                  },
                  options: const [
                    ShadOption(value: 'password', child: Text('Password')),
                    ShadOption(value: 'key', child: Text('SSH Private Key')),
                    ShadOption(value: 'agent', child: Text('SSH Agent')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _authType = val);
                    }
                  },
                ),
                const SizedBox(height: 12),
                if (_authType == 'password') ...[
                  ShadInputFormField(
                    key: const Key('identity_password_input'),
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    label: const Text('Password'),
                    validator: (v) =>
                        v.trim().isEmpty ? 'Password is required' : null,
                    trailing: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      tooltip: _obscurePassword
                          ? 'Show password'
                          : 'Hide password',
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ],
                if (_authType == 'key') ...[
                  ShadInputFormField(
                    key: const Key('identity_privatekey_input'),
                    controller: _privateKeyController,
                    maxLines: 4,
                    label: const Text('Private Key (PEM)'),
                    placeholder: const Text(
                      '-----BEGIN OPENSSH PRIVATE KEY-----...',
                    ),
                    validator: (v) =>
                        v.trim().isEmpty ? 'Private key is required' : null,
                  ),
                  const SizedBox(height: 12),
                  ShadInputFormField(
                    key: const Key('identity_passphrase_input'),
                    controller: _passphraseController,
                    obscureText: true,
                    label: const Text('Passphrase (Optional)'),
                  ),
                ],
                if (_authType == 'agent') ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      'Uses the local system SSH agent for authentication.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
