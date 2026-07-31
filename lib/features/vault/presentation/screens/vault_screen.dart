import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
            child: TextField(
              key: const Key('vault_search_input'),
              decoration: const InputDecoration(
                hintText: 'Search identities...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
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
                      onEdit: () => _openIdentityForm(context, initialIdentity: item),
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

  Future<void> _deleteIdentity(BuildContext context, IdentityModel item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Identity'),
        content: Text('Are you sure you want to delete "${item.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await ref.read(identitiesNotifierProvider.notifier).deleteIdentity(item.id);
    }
  }
}

class _IdentityTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getBadgeColor(context).withValues(alpha: 0.2),
          child: Icon(_getAuthTypeIcon(), color: _getBadgeColor(context)),
        ),
        title: Text(
          identity.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('User: ${identity.username}  •  Auth: ${identity.authType.toUpperCase()}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (identity.authType == 'password' && identity.password != null)
              IconButton(
                icon: const Icon(Icons.copy, size: 20),
                tooltip: 'Copy Password',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: identity.password!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password copied to clipboard')),
                  );
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
    );
  }
}
