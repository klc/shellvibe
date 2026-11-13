import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../shared/providers/database_providers.dart';
import '../notifiers/vault_notifier.dart';

class VaultUnlockDialog extends ConsumerStatefulWidget {
  const VaultUnlockDialog({super.key});

  @override
  ConsumerState<VaultUnlockDialog> createState() => _VaultUnlockDialogState();
}

class _VaultUnlockDialogState extends ConsumerState<VaultUnlockDialog> {
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  String? _error;
  bool _retrying = false;
  Timer? _lockoutTimer;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _lockoutTimer?.cancel();
    super.dispose();
  }

  void _startLockoutTimer() {
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final vaultState = ref.read(vaultProvider).value;
      if (vaultState == null || !vaultState.isLockedOut) {
        _lockoutTimer?.cancel();
        _lockoutTimer = null;
      }
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = ShellVibeTokens.resolve(context);
    final vaultAsync = ref.watch(vaultProvider);
    final vaultState = vaultAsync.value;
    final isLockedOut = vaultState?.isLockedOut ?? false;
    final failedAttempts = vaultState?.failedAttempts ?? 0;

    // Start countdown timer if locked out
    if (isLockedOut && _lockoutTimer == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _lockoutTimer == null) {
          _startLockoutTimer();
        }
      });
    }

    final remainingSeconds = vaultState?.remainingLockout.inSeconds ?? 0;

    if (vaultState?.keyLost ?? false) {
      return _frame(
        children: [
          Icon(Icons.key_off_outlined, size: 48, color: tokens.danger),
          const SizedBox(height: 16),
          Text('Vault Key Missing', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(
            'The vault key could not be read from the system keychain, but '
            'the passwords, keys and vault variables it encrypts are still '
            'stored here. If you just denied a keychain prompt, or your '
            'keyring is locked, unlock it and try again. Reset the vault only '
            'if the key is truly gone: that deletes every stored secret.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ShellVibeButton(
              key: const Key('vault_retry_key_button'),
              label: 'Try Again',
              busy: _retrying,
              onPressed: _retrying ? null : _retryKeyRead,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ShellVibeButton.danger(
              key: const Key('vault_reset_button'),
              label: 'Reset Vault',
              onPressed: _retrying ? null : _confirmReset,
            ),
          ),
        ],
      );
    }

    return _frame(
      children: [
        Icon(
          isLockedOut ? Icons.timer_outlined : Icons.lock_outline,
          size: 48,
          color: isLockedOut ? tokens.danger : tokens.textMuted,
        ),
        const SizedBox(height: 16),
        Text(
          isLockedOut ? 'Too Many Attempts' : 'Unlock Vault',
          style: theme.textTheme.headlineSmall,
        ),
        if (isLockedOut) ...[
          const SizedBox(height: 12),
          Text(
            'Please wait $remainingSeconds seconds before trying again.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: tokens.danger),
          ),
        ],
        if (failedAttempts > 0 && !isLockedOut) ...[
          const SizedBox(height: 8),
          Text(
            'Failed attempts: $failedAttempts',
            style: theme.textTheme.bodySmall?.copyWith(color: tokens.danger),
          ),
        ],
        const SizedBox(height: 24),
        ShadInput(
          controller: _passwordCtrl,
          obscureText: _obscure,
          enabled: !isLockedOut && !vaultAsync.isLoading,
          placeholder: const Text('Master Password'),
          trailing: ShellVibeIconButton(
            icon: _obscure ? LucideIcons.eye : LucideIcons.eyeOff,
            tooltip: _obscure ? 'Show password' : 'Hide password',
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
          onSubmitted: isLockedOut ? null : (_) => _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(
            _error!,
            style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ShellVibeButton(
            label: 'Unlock',
            onPressed: isLockedOut ? null : _submit,
            busy: vaultAsync.isLoading,
          ),
        ),
        const SizedBox(height: 8),
        ShellVibeButton.quiet(
          key: const Key('vault_reset_button'),
          label: 'Forgot password? Reset vault',
          onPressed: vaultAsync.isLoading ? null : _confirmReset,
        ),
      ],
    );
  }

  Widget _frame({required List<Widget> children}) {
    return Scaffold(
      body: Center(
        // Scrolls on a screen too short for the card, a phone held sideways.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: ShadCard(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Reads the keychain again for a key that looked missing. A denied
  /// keychain prompt, or a keyring not yet unlocked at login, can read the
  /// same as no key at all; the vault stays key-lost only if the key is still
  /// not there. A read that fails outright is an error, never key-lost.
  Future<void> _retryKeyRead() async {
    setState(() {
      _retrying = true;
      _error = null;
    });
    try {
      ref.read(secureStorageServiceProvider).forgetCache();
      ref.invalidate(vaultProvider);
      await ref.read(vaultProvider.future);
      if (mounted && (ref.read(vaultProvider).value?.keyLost ?? false)) {
        setState(() => _error = 'The key is still not in the keychain.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'The keychain could not be read: $e');
      }
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  Future<void> _confirmReset() async {
    final confirmed = await showShadDialog<bool>(
      context: context,
      barrierColor: AppTheme.scrimOf(context),
      builder: (_) => const _ResetVaultDialog(),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(vaultProvider.notifier).resetVault();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not reset the vault: $e');
    }
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final success = await ref
        .read(vaultProvider.notifier)
        .unlock(_passwordCtrl.text);
    if (success && mounted) {
      _passwordCtrl.clear();
    }
    if (!success && mounted) {
      final vaultState = ref.read(vaultProvider).value;
      if (vaultState?.isLockedOut ?? false) {
        _startLockoutTimer();
        setState(() => _error = null);
      } else {
        setState(() => _error = 'Incorrect password');
      }
    }
  }
}

/// Asks for the reset to be typed out, so it cannot be one stray click.
class _ResetVaultDialog extends StatefulWidget {
  const _ResetVaultDialog();

  /// What the user types to confirm.
  static const confirmation = 'RESET';

  @override
  State<_ResetVaultDialog> createState() => _ResetVaultDialogState();
}

class _ResetVaultDialogState extends State<_ResetVaultDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final confirmed = _controller.text.trim() == _ResetVaultDialog.confirmation;
    return ShadDialog.alert(
      title: const Text('Reset the vault?'),
      description: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This permanently deletes every password, private key, passphrase '
            'and vault variable stored on this device, and removes the master '
            'password. Hosts, snippets and settings stay. Other synced devices '
            'keep their own copies. This cannot be undone.',
          ),
          const SizedBox(height: 12),
          const Text('Type ${_ResetVaultDialog.confirmation} to confirm.'),
          const SizedBox(height: 8),
          ShadInput(
            key: const Key('vault_reset_confirm_field'),
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            placeholder: const Text(_ResetVaultDialog.confirmation),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: adaptiveDialogActions(context, [
        ShellVibeButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        ShellVibeButton.danger(
          key: const Key('vault_reset_confirm_button'),
          label: 'Delete Secrets and Reset',
          onPressed: confirmed ? () => Navigator.of(context).pop(true) : null,
        ),
      ]),
      actionsAxis: adaptiveDialogActionsAxis(context),
    );
  }
}
