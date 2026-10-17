import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../vault/presentation/notifiers/vault_notifier.dart';

/// Sets, removes and locks the vault master password.
class VaultMasterPasswordSection extends ConsumerStatefulWidget {
  const VaultMasterPasswordSection({super.key});

  @override
  ConsumerState<VaultMasterPasswordSection> createState() =>
      _VaultMasterPasswordSectionState();
}

class _VaultMasterPasswordSectionState
    extends ConsumerState<VaultMasterPasswordSection> {
  final _vaultPasswordController = TextEditingController();

  @override
  void dispose() {
    _vaultPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vaultStatus = ref.watch(vaultProvider).value?.status;
    final isConfigured =
        vaultStatus != null && vaultStatus != VaultStatus.unconfigured;

    return ShadCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isConfigured
                ? 'Your vault key is protected by a master password. It is required '
                      'after every app restart before identity secrets can be used. '
                      'Removing it returns the key to the operating system keychain, '
                      'so the app stops asking — and stops being protected by the '
                      'password.'
                : 'Without a master password your vault key is protected only by the '
                      'operating system keychain. Setting one wraps the key with '
                      'Argon2id + AES-256-GCM. Existing identities stay readable.',
            style: TextStyle(
              fontSize: 13,
              color: ShellVibeTokens.resolve(context).textMuted,
            ),
          ),
          const SizedBox(height: 12),
          if (isConfigured) ...[
            ShellVibeButton.secondary(
              key: const Key('lock_vault_button'),
              label: vaultStatus == VaultStatus.locked
                  ? 'Vault Locked'
                  : 'Lock Vault Now',
              icon: LucideIcons.lock,
              onPressed: vaultStatus == VaultStatus.locked
                  ? null
                  : () => ref.read(vaultProvider.notifier).lock(),
            ),
            const SizedBox(height: 12),
            ShadInput(
              key: const Key('remove_master_password_field'),
              controller: _vaultPasswordController,
              obscureText: true,
              placeholder: const Text('Current master password'),
            ),
            const SizedBox(height: 12),
            ShellVibeButton.danger(
              key: const Key('remove_master_password_button'),
              label: 'Remove Master Password',
              icon: LucideIcons.lockOpen,
              onPressed: _handleRemoveMasterPassword,
            ),
          ] else ...[
            ShadInput(
              key: const Key('vault_master_password_field'),
              controller: _vaultPasswordController,
              obscureText: true,
              placeholder: const Text('New master password (min 8 characters)'),
            ),
            const SizedBox(height: 12),
            ShellVibeButton(
              key: const Key('set_master_password_button'),
              label: 'Set Master Password',
              icon: LucideIcons.lockKeyhole,
              onPressed: _handleSetMasterPassword,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleRemoveMasterPassword() async {
    final password = _vaultPasswordController.text;
    if (password.isEmpty) {
      ShadToaster.of(context).show(
        const ShadToast.destructive(
          description: Text('Enter your current master password to remove it.'),
        ),
      );
      return;
    }

    final confirmed = await showShadDialog<bool>(
      context: context,
      builder: (dialogContext) => ShadDialog.alert(
        title: const Text('Remove master password?'),
        description: const Text(
          'Your vault key goes back to the operating system keychain. The app '
          'will no longer ask for a password at startup, and anyone with '
          'access to your unlocked account can use your identity secrets.',
        ),
        actions: adaptiveDialogActions(context, [
          ShellVibeButton.secondary(
            label: 'Cancel',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          ShellVibeButton.danger(
            key: const Key('confirm_remove_master_password_button'),
            label: 'Remove',
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ]),
        actionsAxis: adaptiveDialogActionsAxis(context),
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final removed = await ref
          .read(vaultProvider.notifier)
          .removeMasterPassword(password);
      // The controller may already be disposed if the screen left the tree
      // while the (isolate-backed) verification was running.
      if (!mounted) return;
      if (!removed) {
        ShadToaster.of(context).show(
          const ShadToast.destructive(
            description: Text(
              'Wrong master password, or too many failed attempts.',
            ),
          ),
        );
        return;
      }
      _vaultPasswordController.clear();
      ShadToaster.of(context).show(
        const ShadToast(
          description: Text(
            'Master password removed. The vault no longer locks on restart.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            description: Text('Failed to remove master password: $e'),
          ),
        );
      }
    }
  }

  Future<void> _handleSetMasterPassword() async {
    final password = _vaultPasswordController.text;
    if (password.length < 8) {
      ShadToaster.of(context).show(
        const ShadToast.destructive(
          description: Text('Master password must be at least 8 characters.'),
        ),
      );
      return;
    }

    try {
      await ref.read(vaultProvider.notifier).setup(password);
      // The controller may already be disposed if the screen left the tree
      // while the (isolate-backed) setup was running.
      if (!mounted) return;
      _vaultPasswordController.clear();
      ShadToaster.of(context).show(
        const ShadToast(
          description: Text(
            'Master password set. The vault now locks on app restart.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            description: Text('Failed to set master password: $e'),
          ),
        );
      }
    }
  }
}
