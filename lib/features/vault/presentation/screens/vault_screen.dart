import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/terly_tokens.dart';
import '../../../../app/widgets/terly_ui.dart';
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
    final identitiesAsync = ref.watch(identitiesProvider);
    final tokens = TerlyTokens.resolve(context);

    return Scaffold(
      body: Column(
        children: [
          TerlyPageHeader(
            icon: LucideIcons.shieldCheck,
            title: 'Identity Vault',
            description:
                'Encrypted credentials stay separate from host definitions.',
            actions: [
              ShadButton(
                key: const Key('add_identity_button'),
                size: ShadButtonSize.sm,
                leading: const Icon(LucideIcons.plus, size: 16),
                onPressed: () => _openIdentityForm(context),
                child: const Text('Add Identity'),
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              tokens.pagePadding,
              14,
              tokens.pagePadding,
              10,
            ),
            child: TerlySearchField(
              fieldKey: const Key('vault_search_input'),
              hintText: 'Search identities…',
              onChanged: (value) =>
                  setState(() => _searchQuery = value.toLowerCase()),
            ),
          ),
          Expanded(
            child: identitiesAsync.when(
              data: (identities) {
                final filtered = identities.where((id) {
                  final title = id.title.toLowerCase();
                  final username = id.username.toLowerCase();
                  return title.contains(_searchQuery) ||
                      username.contains(_searchQuery);
                }).toList();

                if (filtered.isEmpty) {
                  return TerlyEmptyState(
                    icon: LucideIcons.keyRound,
                    title: 'No identities found in Vault.',
                    description:
                        'Create an encrypted password or private-key identity and reuse it across hosts.',
                    actions: [
                      ShadButton(
                        onPressed: () => _openIdentityForm(context),
                        leading: const Icon(LucideIcons.plus, size: 16),
                        child: const Text('Add identity'),
                      ),
                    ],
                  );
                }

                return ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    tokens.pagePadding,
                    2,
                    tokens.pagePadding,
                    20,
                  ),
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
              error: (err, stack) => TerlyEmptyState(
                icon: LucideIcons.triangleAlert,
                title: 'Could not load the Vault',
                description: '$err',
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openIdentityForm(
    BuildContext context, {
    IdentityModel? initialIdentity,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => IdentityFormDialog(initialIdentity: initialIdentity),
    );
  }

  Future<void> _editIdentity(BuildContext context, IdentityModel item) async {
    IdentityModel? decrypted;
    try {
      decrypted = await ref
          .read(identitiesProvider.notifier)
          .getDecryptedIdentity(item.id);
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
        await ref.read(identitiesProvider.notifier).deleteIdentity(item.id);
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
        return LucideIcons.rectangleEllipsis;
      case 'key':
        return LucideIcons.keyRound;
      case 'agent':
        return LucideIcons.shieldCheck;
      default:
        return LucideIcons.lock;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPassword = identity.authType == 'password';
    final isKey = identity.authType == 'key';
    final canCopy = isPassword || isKey;
    final tokens = TerlyTokens.resolve(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TerlySurface(
        child: ListTile(
          minTileHeight: 62,
          leading: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tokens.brand.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(tokens.radiusMedium),
              border: Border.all(color: tokens.brand.withValues(alpha: 0.20)),
            ),
            child: Icon(_getAuthTypeIcon(), size: 17, color: tokens.brand),
          ),
          title: Text(
            identity.title,
            style: const TextStyle(fontWeight: FontWeight.w600),
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
                  icon: const Icon(LucideIcons.copy, size: 17),
                  tooltip: isPassword ? 'Copy Password' : 'Copy Key',
                  onPressed: () async {
                    IdentityModel? decrypted;
                    try {
                      decrypted = await ref
                          .read(identitiesProvider.notifier)
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
                    final secret = isPassword
                        ? decrypted?.password
                        : decrypted?.privateKey;

                    if (secret != null && secret.isNotEmpty) {
                      final settings = ref.read(settingsProvider).value;
                      final clearSeconds =
                          settings?.clipboardAutoClearSeconds ?? 30;
                      final autoClearService = ref.read(
                        clipboardAutoClearServiceProvider,
                      );
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
                            description: Text(
                              'No secret saved for this identity',
                            ),
                          ),
                        );
                      }
                    }
                  },
                ),
              IconButton(
                icon: const Icon(LucideIcons.pencil, size: 17),
                tooltip: 'Edit',
                onPressed: onEdit,
              ),
              IconButton(
                icon: Icon(LucideIcons.trash2, size: 17, color: tokens.danger),
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
