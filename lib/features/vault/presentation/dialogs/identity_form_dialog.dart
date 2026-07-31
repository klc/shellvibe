import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../notifiers/identities_notifier.dart';
import '../../domain/models/identity_model.dart';

class IdentityFormDialog extends ConsumerStatefulWidget {
  final IdentityModel? initialIdentity;
  final String workspaceId;

  const IdentityFormDialog({
    super.key,
    this.initialIdentity,
    this.workspaceId = 'default',
  });

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
      final notifier = ref.read(identitiesNotifierProvider.notifier);
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
          workspaceId: widget.workspaceId,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save identity: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialIdentity != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Identity' : 'Add New Identity'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('identity_title_input'),
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title / Label',
                  hintText: 'e.g. Production Server Key',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Title is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('identity_username_input'),
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  hintText: 'e.g. root, ubuntu',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Username is required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('identity_authtype_dropdown'),
                initialValue: _authType,
                decoration: const InputDecoration(
                  labelText: 'Authentication Type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'password', child: Text('Password')),
                  DropdownMenuItem(value: 'key', child: Text('SSH Private Key')),
                  DropdownMenuItem(value: 'agent', child: Text('SSH Agent')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _authType = val);
                  }
                },
              ),
              const SizedBox(height: 12),
              if (_authType == 'password') ...[
                TextFormField(
                  key: const Key('identity_password_input'),
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),
              ],
              if (_authType == 'key') ...[
                TextFormField(
                  key: const Key('identity_privatekey_input'),
                  controller: _privateKeyController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Private Key (PEM)',
                    hintText: '-----BEGIN OPENSSH PRIVATE KEY-----...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('identity_passphrase_input'),
                  controller: _passphraseController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Passphrase (Optional)',
                    border: OutlineInputBorder(),
                  ),
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
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
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
    );
  }
}
