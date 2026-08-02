import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/terly_tokens.dart';
import '../../../../app/widgets/terly_ui.dart';
import '../../../hosts/presentation/notifiers/hosts_notifier.dart';
import '../../../settings/presentation/notifiers/settings_notifier.dart';
import '../dialogs/identity_form_dialog.dart';
import '../notifiers/identities_notifier.dart';
import '../notifiers/vault_notifier.dart';
import '../../../../shared/providers/workspace_provider.dart';
import '../../domain/models/identity_model.dart';

/// Width at which the vault's context column fits alongside the list.
const double _kVaultContextColumnBreakpoint = 900;

/// Rendered width of one trailing control.
///
/// Measured, not guessed: a compact [IconButton] still occupies 40px once
/// Material's minimum tap target is applied, whatever `constraints` says.
const double _kIdentityActionWidth = 40;

/// The `authType` values the context column filters on, plus an "all" bucket.
const List<String> _kAuthTypes = ['password', 'key', 'agent'];

class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> {
  String _searchQuery = '';
  String? _authTypeFilter;

  @override
  Widget build(BuildContext context) {
    final identitiesAsync = ref.watch(identitiesProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final showContextColumn =
            constraints.maxWidth >= _kVaultContextColumnBreakpoint;
        return Scaffold(
          body: Row(
            children: [
              if (showContextColumn)
                _buildContextColumn(context, identitiesAsync),
              Expanded(
                child: _buildWorkArea(
                  context,
                  identitiesAsync,
                  showContextColumn: showContextColumn,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContextColumn(
    BuildContext context,
    AsyncValue<List<IdentityModel>> identitiesAsync,
  ) {
    final tokens = TerlyTokens.resolve(context);
    final identities = identitiesAsync.value ?? const <IdentityModel>[];

    return TerlyContextColumn(
      head: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          border: Border.all(color: tokens.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'VAULT STATE',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      letterSpacing: 0.8,
                      color: tokens.textMuted,
                    ),
                  ),
                  Text(
                    'Unlocked',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.lockOpen, size: 15, color: tokens.brand),
          ],
        ),
      ),
      search: TerlySearchField(
        fieldKey: const Key('vault_search_input'),
        hintText: 'Search identities…',
        onChanged: (value) =>
            setState(() => _searchQuery = value.toLowerCase()),
      ),
      children: [
        const TerlySectionLabel(label: 'Types'),
        TerlyNavItem(
          itemKey: const Key('vault_filter_all'),
          icon: LucideIcons.layoutGrid,
          label: 'All',
          count: identities.length,
          selected: _authTypeFilter == null,
          onTap: () => setState(() => _authTypeFilter = null),
        ),
        for (final authType in _kAuthTypes)
          TerlyNavItem(
            itemKey: Key('vault_filter_$authType'),
            icon: _authTypeIcon(authType),
            label: _authTypeLabel(authType),
            count: identities
                .where((identity) => identity.authType == authType)
                .length,
            selected: _authTypeFilter == authType,
            onTap: () => setState(() => _authTypeFilter = authType),
          ),
      ],
    );
  }

  Widget _buildWorkArea(
    BuildContext context,
    AsyncValue<List<IdentityModel>> identitiesAsync, {
    required bool showContextColumn,
  }) {
    final settings = ref.watch(settingsProvider).value;
    final autoLockSeconds = settings?.autoLockTimerSeconds ?? 0;
    final hosts = ref.watch(hostsProvider).value ?? const [];

    final addButton = ShadButton(
      key: const Key('add_identity_button'),
      size: ShadButtonSize.sm,
      leading: const Icon(LucideIcons.plus, size: 16),
      onPressed: () => _openIdentityForm(context),
      child: const Text('Add Identity'),
    );
    final lockButton = ShadButton.outline(
      key: const Key('vault_lock_now_button'),
      size: ShadButtonSize.sm,
      onPressed: () => ref.read(vaultProvider.notifier).lock(),
      child: const Text('Lock now'),
    );

    return Column(
      children: [
        if (showContextColumn)
          TerlyWorkToolbar(
            title: _authTypeFilter == null
                ? 'All identities'
                : _authTypeLabel(_authTypeFilter!),
            meta: autoLockSeconds > 0
                ? 'auto-lock ${_formatAutoLock(autoLockSeconds)}'
                : 'auto-lock off',
            actions: [lockButton, addButton],
          )
        else
          TerlyPageHeader(
            icon: LucideIcons.shieldCheck,
            title: 'Identity Vault',
            description:
                'Encrypted credentials stay separate from host definitions.',
            actions: [lockButton, addButton],
          ),
        if (!showContextColumn)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TerlySearchField(
              fieldKey: const Key('vault_search_input'),
              hintText: 'Search identities…',
              onChanged: (value) =>
                  setState(() => _searchQuery = value.toLowerCase()),
            ),
          ),
        Expanded(
          child: identitiesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => TerlyEmptyState(
              icon: LucideIcons.triangleAlert,
              title: 'Could not load the Vault',
              description: '$err',
            ),
            data: (identities) {
              final filtered = identities.where((identity) {
                if (_authTypeFilter != null &&
                    identity.authType != _authTypeFilter) {
                  return false;
                }
                return identity.title.toLowerCase().contains(_searchQuery) ||
                    identity.username.toLowerCase().contains(_searchQuery);
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
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final item = filtered[index];
                  return _IdentityRow(
                    key: ValueKey(item.id),
                    identity: item,
                    compact: !showContextColumn,
                    usedByHostCount: hosts
                        .where((host) => host.identityId == item.id)
                        .length,
                    onEdit: () => _editIdentity(context, item),
                    onDelete: () => _deleteIdentity(context, item),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  static IconData _authTypeIcon(String authType) => switch (authType) {
    'password' => LucideIcons.rectangleEllipsis,
    'key' => LucideIcons.keyRound,
    'agent' => LucideIcons.shieldCheck,
    _ => LucideIcons.lock,
  };

  static String _authTypeLabel(String authType) => switch (authType) {
    'password' => 'Passwords',
    'key' => 'SSH keys',
    'agent' => 'Agent',
    _ => authType,
  };

  static String _formatAutoLock(int seconds) {
    if (seconds % 60 == 0) return '${seconds ~/ 60} min';
    return '$seconds s';
  }

  void _openIdentityForm(
    BuildContext context, {
    IdentityModel? initialIdentity,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => IdentityFormDialog(
        initialIdentity: initialIdentity,
        workspaceId: ref.read(activeWorkspaceIdProvider),
      ),
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

/// Single-line identity row.
///
/// The secret itself is never rendered and there is no reveal control: an
/// identity is represented by its type, name and how many hosts use it.
class _IdentityRow extends ConsumerWidget {
  final IdentityModel identity;
  final int usedByHostCount;
  final bool compact;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _IdentityRow({
    super.key,
    required this.identity,
    required this.usedByHostCount,
    required this.compact,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = TerlyTokens.resolve(context);
    final isPassword = identity.authType == 'password';
    final isKey = identity.authType == 'key';
    final canCopy = isPassword || isKey;
    final mutedStyle = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: tokens.textMuted);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(_shortKind(identity.authType), style: mutedStyle),
          ),
          Expanded(
            flex: 4,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  identity.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  identity.hasUndecryptableSecrets
                      ? 'secret unreadable'
                      : identity.passphrase != null &&
                            identity.passphrase!.isNotEmpty
                      ? 'passphrase protected'
                      : 'no passphrase',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mutedStyle,
                ),
              ],
            ),
          ),
          // The username column is the first thing to go when the row has to
          // share its width with three 40px controls.
          if (!compact)
            Expanded(
              flex: 3,
              child: Text(
                identity.username.isEmpty ? '—' : identity.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mutedStyle,
              ),
            ),
          Expanded(
            flex: 2,
            child: Text(
              usedByHostCount == 1 ? '1 host' : '$usedByHostCount hosts',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: mutedStyle,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: (canCopy ? 3 : 2) * _kIdentityActionWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (canCopy)
                  _RowIconButton(
                    buttonKey: Key('copy_identity_button_${identity.id}'),
                    icon: LucideIcons.copy,
                    tooltip: isPassword ? 'Copy Password' : 'Copy Key',
                    onPressed: () => _copySecret(context, ref, isPassword),
                  ),
                _RowIconButton(
                  icon: LucideIcons.pencil,
                  tooltip: 'Edit',
                  onPressed: onEdit,
                ),
                _RowIconButton(
                  icon: LucideIcons.trash2,
                  tooltip: 'Delete',
                  color: tokens.danger,
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _shortKind(String authType) => switch (authType) {
    'password' => 'pwd',
    'key' => 'key',
    'agent' => 'agent',
    _ => authType,
  };

  Future<void> _copySecret(
    BuildContext context,
    WidgetRef ref,
    bool isPassword,
  ) async {
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
    final secret = isPassword ? decrypted?.password : decrypted?.privateKey;

    if (secret == null || secret.isEmpty) {
      if (context.mounted) {
        ShadToaster.of(context).show(
          const ShadToast(
            description: Text('No secret saved for this identity'),
          ),
        );
      }
      return;
    }

    final settings = ref.read(settingsProvider).value;
    final clearSeconds = settings?.clipboardAutoClearSeconds ?? 30;
    await ref
        .read(clipboardAutoClearServiceProvider)
        .copyAndScheduleClear(
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
  }
}

class _RowIconButton extends StatelessWidget {
  final Key? buttonKey;
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onPressed;

  const _RowIconButton({
    this.buttonKey,
    required this.icon,
    required this.tooltip,
    this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: buttonKey,
      icon: Icon(icon, size: 16, color: color),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      onPressed: onPressed,
    );
  }
}
