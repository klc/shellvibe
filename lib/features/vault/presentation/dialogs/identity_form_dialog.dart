import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/app/widgets/shellvibe_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../shared/providers/workspace_provider.dart';
import '../../domain/models/identity_model.dart';
import '../notifiers/identities_notifier.dart';

class IdentityFormDialog extends ConsumerStatefulWidget {
  final IdentityModel? initialIdentity;
  final String? workspaceId;

  /// Opens the form on an identity whose stored secrets cannot be decrypted.
  ///
  /// The secret fields start empty because the old ciphertext is unreadable,
  /// not because there is no secret — so saving writes a *replacement* under
  /// the current vault key. The identity keeps its id, which is what every
  /// host's `identityId` points at: repairing here leaves those bindings
  /// intact, where deleting and re-adding would null them all out.
  final bool repairSecrets;

  const IdentityFormDialog({
    super.key,
    this.initialIdentity,
    this.workspaceId,
    this.repairSecrets = false,
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
    // Databases synced from a build that still offered the removed SSH agent
    // option can hand us an auth type the select has no option for, which
    // would leave the field blank and unsaveable. Fall back to password.
    final storedAuthType = init?.authType ?? 'password';
    _authType = const {'password', 'key'}.contains(storedAuthType)
        ? storedAuthType
        : 'password';
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
    final isRepairing = widget.repairSecrets;

    return ShadDialog(
      title: Row(
        children: [
          Icon(
            isRepairing ? LucideIcons.wrench : LucideIcons.keyRound,
            size: 20,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              isRepairing
                  ? 'Repair Identity'
                  : isEditing
                  ? 'Edit Identity'
                  : 'Add New Identity',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      description: Text(
        isRepairing
            ? 'Re-enter the secret for this identity. Every host already '
                  'bound to it keeps working.'
            : 'Credentials used for SSH authentication. Secrets are encrypted '
                  'and stored securely in the Vault.',
      ),
      actions: adaptiveDialogActions(context, [
        ShellVibeButton.secondary(
          label: 'Cancel',
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
        ),
        ShellVibeButton(
          key: const Key('identity_save_button'),
          label: isRepairing
              ? 'Replace secret'
              : isEditing
              ? 'Update'
              : 'Save',
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
                if (isRepairing) ...[
                  _RepairNotice(
                    authType: widget.initialIdentity?.authType ?? _authType,
                  ),
                  const SizedBox(height: 16),
                ],
                // ---- Basic details ----
                const ShellVibeFormSectionHeader(
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
                ShadSelectFormField<String>(
                  key: const Key('identity_authtype_dropdown'),
                  initialValue: _authType,
                  label: const Text('Authentication Type'),
                  selectedOptionBuilder: (context, value) {
                    switch (value) {
                      case 'key':
                        return const Text('SSH Private Key');
                      case 'password':
                      default:
                        return const Text('Password');
                    }
                  },
                  options: const [
                    ShadOption(value: 'password', child: Text('Password')),
                    ShadOption(value: 'key', child: Text('SSH Private Key')),
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
                const SizedBox(height: 20),
                // ---- Credentials ----
                const ShellVibeFormSectionHeader(
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
                    trailing: ShellVibeIconButton(
                      icon: _obscurePassword
                          ? LucideIcons.eye
                          : LucideIcons.eyeOff,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Explains why the secret fields of a repaired identity are blank.
///
/// Without it the form looks like an ordinary edit whose secret went missing,
/// and the obvious reaction — delete the identity and make a new one — is the
/// one that breaks every host bound to it.
class _RepairNotice extends StatelessWidget {
  final String authType;

  const _RepairNotice({required this.authType});

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final secretName = authType == 'key' ? 'private key' : 'password';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.danger),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.triangleAlert, size: 16, color: tokens.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'The stored $secretName was encrypted with a vault key this '
              'install no longer has, so it cannot be read or recovered. '
              'Paste the $secretName again to re-encrypt it under the current '
              'key. Hosts bound to this identity are not touched.',
              style: TextStyle(fontSize: 12.5, color: tokens.danger),
            ),
          ),
        ],
      ),
    );
  }
}
