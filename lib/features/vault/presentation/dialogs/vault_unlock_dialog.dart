import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
      final vaultState = ref.read(vaultNotifierProvider).valueOrNull;
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
    final vaultAsync = ref.watch(vaultNotifierProvider);
    final vaultState = vaultAsync.valueOrNull;
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
                    color: isLockedOut
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
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
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  if (failedAttempts > 0 && !isLockedOut) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Failed attempts: $failedAttempts',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ShadInput(
                    controller: _passwordCtrl,
                    obscureText: _obscure,
                    enabled: !isLockedOut && !vaultAsync.isLoading,
                    placeholder: const Text('Master Password'),
                    trailing: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                      ),
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
                    child: ShadButton(
                      onPressed: (isLockedOut || vaultAsync.isLoading)
                          ? null
                          : _submit,
                      child: vaultAsync.isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Unlock'),
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
        .read(vaultNotifierProvider.notifier)
        .unlock(_passwordCtrl.text);
    if (success && mounted) {
      _passwordCtrl.clear();
    }
    if (!success && mounted) {
      final vaultState = ref.read(vaultNotifierProvider).valueOrNull;
      if (vaultState?.isLockedOut ?? false) {
        _startLockoutTimer();
        setState(() => _error = null);
      } else {
        setState(() => _error = 'Incorrect password');
      }
    }
  }
}
