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
      title: Row(
        children: [
          const Icon(LucideIcons.keyRound, size: 20),
          const SizedBox(width: 8),
          Text(isEditing ? 'Edit Identity' : 'Add New Identity'),
        ],
      ),
      description: const Text(
        'Credentials used for SSH authentication. Secrets are encrypted '
        'and stored securely in the Vault.',
      ),
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
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                // ---- Basic details ----
                const _FormSectionHeader(
                  icon: LucideIcons.user,
                  title: 'Basic Details',
                ),
                const SizedBox(height: 12),
                ShadInputFormField(
                  key: const Key('identity_title_input'),
                  controller: _titleController,
                  label: const Text('Title / Label'),
                  placeholder: const Text('e.g. Production Server Key'),
                  leading: const Icon(LucideIcons.tag, size: 16),
                  validator: (v) =>
                      v.trim().isEmpty ? 'Title is required' : null,
                ),
                const SizedBox(height: 12),
                // ShadInputDecorator start-aligns its child, so the select
                // shrinks to its default min width. Feed the available width
                // in as minWidth to match the full-width inputs.
                LayoutBuilder(
                  builder: (context, constraints) => ShadSelectFormField<String>(
                    key: const Key('identity_authtype_dropdown'),
                    minWidth: constraints.maxWidth,
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
                        setState(() {
                          _authType = val;
                          if (val != 'password') {
                            _usernameController.clear();
                          }
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(height: 20),
                // ---- Credentials ----
                const _FormSectionHeader(
                  icon: LucideIcons.lockKeyhole,
                  title: 'Credentials',
                ),
                const SizedBox(height: 12),
                if (_authType == 'password') ...[
                  ShadInputFormField(
                    key: const Key('identity_username_input'),
                    controller: _usernameController,
                    label: const Text('Username'),
                    placeholder: const Text('e.g. root, ubuntu'),
                    leading: const Icon(LucideIcons.user, size: 16),
                    validator: (v) =>
                        v.trim().isEmpty ? 'Username is required' : null,
                  ),
                  const SizedBox(height: 12),
                  ShadInputFormField(
                    key: const Key('identity_password_input'),
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    label: const Text('Password'),
                    leading: const Icon(LucideIcons.lock, size: 16),
                    validator: (v) =>
                        v.trim().isEmpty ? 'Password is required' : null,
                    trailing: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                        size: 16,
                      ),
                      tooltip: _obscurePassword
                          ? 'Show password'
                          : 'Hide password',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      visualDensity: VisualDensity.compact,
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
                    leading: const Icon(LucideIcons.file, size: 16),
                    validator: (v) =>
                        v.trim().isEmpty ? 'Private key is required' : null,
                  ),
                  const SizedBox(height: 12),
                  ShadInputFormField(
                    key: const Key('identity_passphrase_input'),
                    controller: _passphraseController,
                    obscureText: true,
                    label: const Text('Passphrase (Optional)'),
                    leading: const Icon(LucideIcons.lockOpen, size: 16),
                    placeholder: const Text('Key passphrase, if any'),
                  ),
                ],
                if (_authType == 'agent') ...[
                  _InfoNote(
                    icon: LucideIcons.shieldCheck,
                    text:
                        'No secret is stored. The local system SSH agent is '
                        'used for authentication at connect time.',
                    color: Theme.of(context).colorScheme.primary,
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

/// Small section title used to group related form fields.
class _FormSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _FormSectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 15, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Divider(
            height: 1,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

/// Informational callout used for hint/note style content.
class _InfoNote extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _InfoNote({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

