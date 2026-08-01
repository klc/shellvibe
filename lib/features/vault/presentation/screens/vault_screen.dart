import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../settings/presentation/notifiers/settings_notifier.dart';
import '../dialogs/identity_form_dialog.dart';
import '../notifiers/identities_notifier.dart';
import '../../domain/models/identity_model.dart';

class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final identitiesAsync = ref.watch(identitiesNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Identity Vault'),
        actions: [
          IconButton(
            key: const Key('add_identity_button'),
            icon: const Icon(Icons.add),
            tooltip: 'Add Identity',
            onPressed: () => _openIdentityForm(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: ShadInput(
              key: const Key('vault_search_input'),
              placeholder: const Text('Search identities...'),
              leading: const Icon(Icons.search, size: 16),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val.toLowerCase();
                });
              },
            ),
          ),
          Expanded(
            child: identitiesAsync.when(
              data: (identities) {
                final filtered = identities.where((id) {
                  final title = id.title.toLowerCase();
                  final username = id.username.toLowerCase();
                  return title.contains(_searchQuery) || username.contains(_searchQuery);
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(
                    child: Text('No identities found in Vault.'),
                  );
                }

                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return _IdentityTile(
                      key: ValueKey(item.id),
                      identity: item,
                      onEdit: () => _editIdentity(context, item),
                      onDelete: () => _deleteIdentity(context, item),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(
                child: Text('Error loading Vault: $err'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openIdentityForm(BuildContext context, {IdentityModel? initialIdentity}) {
    showDialog(
      context: context,
      builder: (ctx) => IdentityFormDialog(initialIdentity: initialIdentity),
    );
  }

  Future<void> _editIdentity(BuildContext context, IdentityModel item) async {
    IdentityModel? decrypted;
    try {
      decrypted =
          await ref.read(identitiesNotifierProvider.notifier).getDecryptedIdentity(item.id);
    } catch (e) {
      // Opening the form with silently blank secrets would overwrite the stored
      // ones on save, so refuse instead.
      if (context.mounted) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            description: Text('Cannot open this identity: $e'),
          ),
        );
      }
      return;
    }
    if (context.mounted) {
      _openIdentityForm(context, initialIdentity: decrypted ?? item);
    }
  }

  Future<void> _deleteIdentity(BuildContext context, IdentityModel item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => ShadDialog.alert(
        title: const Text('Delete Identity'),
        description: Text('Are you sure you want to delete "${item.title}"?'),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ShadButton.destructive(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await ref.read(identitiesNotifierProvider.notifier).deleteIdentity(item.id);
      } catch (e) {
        if (context.mounted) {
          ShadToaster.of(context).show(
            ShadToast.destructive(
              description: Text('Failed to delete identity: $e'),
            ),
          );
        }
      }
    }
  }
}

class _IdentityTile extends ConsumerWidget {
  final IdentityModel identity;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _IdentityTile({
    super.key,
    required this.identity,
    required this.onEdit,
    required this.onDelete,
  });

  IconData _getAuthTypeIcon() {
    switch (identity.authType) {
      case 'password':
        return Icons.password;
      case 'key':
        return Icons.vpn_key;
      case 'agent':
        return Icons.security;
      default:
        return Icons.lock;
    }
  }

  Color _getBadgeColor(BuildContext context) {
    switch (identity.authType) {
      case 'password':
        return Colors.blue;
      case 'key':
        return Colors.green;
      case 'agent':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPassword = identity.authType == 'password';
    final isKey = identity.authType == 'key';
    final canCopy = isPassword || isKey;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ShadCard(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: _getBadgeColor(context).withValues(alpha: 0.2),
            child: Icon(_getAuthTypeIcon(), color: _getBadgeColor(context)),
          ),
          title: Text(
            identity.title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            'User: ${identity.username.isEmpty ? '(Not specified)' : identity.username}  •  Auth: ${identity.authType.toUpperCase()}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canCopy)
                IconButton(
                  key: Key('copy_identity_button_${identity.id}'),
                  icon: const Icon(Icons.copy, size: 20),
                  tooltip: isPassword ? 'Copy Password' : 'Copy Key',
                  onPressed: () async {
                    IdentityModel? decrypted;
                    try {
                      decrypted = await ref
                          .read(identitiesNotifierProvider.notifier)
                          .getDecryptedIdentity(identity.id);
                    } catch (e) {
                      if (context.mounted) {
                        ShadToaster.of(context).show(
                          ShadToast.destructive(
                            description: Text('Cannot read this secret: $e'),
                          ),
                        );
                      }
                      return;
                    }
                    final secret = isPassword ? decrypted?.password : decrypted?.privateKey;

                    if (secret != null && secret.isNotEmpty) {
                      final settings = ref.read(settingsNotifierProvider).value;
                      final clearSeconds = settings?.clipboardAutoClearSeconds ?? 30;
                      final autoClearService = ref.read(clipboardAutoClearServiceProvider);
                      await autoClearService.copyAndScheduleClear(
                        secret,
                        duration: Duration(seconds: clearSeconds),
                      );
                      if (context.mounted) {
                        ShadToaster.of(context).show(
                          ShadToast(
                            description: Text(
                              isPassword
                                  ? 'Password copied to clipboard'
                                  : 'Key copied to clipboard',
                            ),
                          ),
                        );
                      }
                    } else {
                      if (context.mounted) {
                        ShadToaster.of(context).show(
                          const ShadToast(
                            description: Text('No secret saved for this identity'),
                          ),
                        );
                      }
                    }
                  },
                ),
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                tooltip: 'Edit',
                onPressed: onEdit,
              ),
              IconButton(
                icon: const Icon(Icons.delete, size: 20, color: Colors.redAccent),
                tooltip: 'Delete',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

