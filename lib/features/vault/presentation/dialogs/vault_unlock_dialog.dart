import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
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

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: ShadCard(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isLockedOut ? Icons.timer_outlined : Icons.lock_outline,
                    size: 48,
                    color: isLockedOut ? tokens.danger : tokens.brand,
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
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: tokens.danger,
                      ),
                    ),
                  ],
                  if (failedAttempts > 0 && !isLockedOut) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Failed attempts: $failedAttempts',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.danger,
                      ),
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
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontSize: 12,
                      ),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
