import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../shared/providers/workspace_provider.dart';
import '../../../hosts/domain/models/host_model.dart';
import '../../../hosts/presentation/notifiers/hosts_notifier.dart';
import '../../../settings/presentation/notifiers/settings_notifier.dart';
import '../../domain/models/identity_model.dart';
import '../dialogs/assign_identity_hosts_dialog.dart';
import '../dialogs/identity_form_dialog.dart';
import '../notifiers/identities_notifier.dart';
import '../notifiers/vault_notifier.dart';

/// Rendered width of one trailing control.
///
/// Measured, not guessed: a [ShellVibeIconButton] is square at one control
/// height, which is 34px under a pointer and rises to the 44px touch target
/// under a thumb. The reservation takes the larger of the two, since a row
/// that is a few pixels wide of its controls costs nothing and one that is a
/// few pixels short clips them.
const double _kIdentityActionWidth = 44;

/// Below this width the identity row stops being a table.
///
/// The type glyph and four [_kIdentityActionWidth] controls claim 210px of any
/// row. Under this width the three text columns are left sharing less space
/// than the controls take, so every one of them collapses to an ellipsis. A
/// phone gets the stacked form instead.
const double _kIdentityStackedWidth = 560;

/// The `authType` values the context column filters on, plus an "all" bucket.
const List<String> _kAuthTypes = ['password', 'key'];

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
    final tierTokens = ShellVibeTokens.resolve(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final showContextColumn =
            constraints.maxWidth >= tierTokens.breakpointMedium;
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Row(
            children: [
              if (showContextColumn)
                _buildContextColumn(context, identitiesAsync),
              Expanded(
                child: showContextColumn
                    ? ShellVibePanel(
                        gradientExtent: 160,
                        child: _buildWorkArea(
                          context,
                          identitiesAsync,
                          showContextColumn: showContextColumn,
                        ),
                      )
                    // On a phone the list sits straight on the canvas rather
                    // than in a slab that would touch every screen edge.
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: _buildWorkArea(
                          context,
                          identitiesAsync,
                          showContextColumn: showContextColumn,
                        ),
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
    final tokens = ShellVibeTokens.resolve(context);
    final identities = identitiesAsync.value ?? const <IdentityModel>[];

    final autoLockSeconds =
        ref.watch(settingsProvider).value?.autoLockTimerSeconds ?? 0;

    return ShellVibeContextColumn(
      head: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const ShellVibeSectionLabel(label: 'Vault', padding: EdgeInsets.zero),
          const SizedBox(height: 6),
          Text('Identities', style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
      search: ShellVibeSearchField(
        fieldKey: const Key('vault_search_input'),
        hintText: 'Search identities…',
        onChanged: (value) =>
            setState(() => _searchQuery = value.toLowerCase()),
      ),
      children: [
        const ShellVibeSectionLabel(label: 'Types'),
        ShellVibeNavItem(
          itemKey: const Key('vault_filter_all'),
          icon: LucideIcons.layoutGrid,
          label: 'All',
          count: identities.length,
          selected: _authTypeFilter == null,
          onTap: () => setState(() => _authTypeFilter = null),
        ),
        for (final authType in _kAuthTypes)
          ShellVibeNavItem(
            itemKey: Key('vault_filter_$authType'),
            icon: _authTypeIcon(authType),
            label: _authTypeLabel(authType),
            count: identities
                .where((identity) => identity.authType == authType)
                .length,
            selected: _authTypeFilter == authType,
            onTap: () => setState(() => _authTypeFilter = authType),
          ),
        const SizedBox(height: 16),
        // The lock state lives at the foot of the column rather than in its
        // header: it is a standing condition of the module, not a title.
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(tokens.radiusMedium),
            border: Border.all(color: tokens.success.withValues(alpha: 0.20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    LucideIcons.shieldCheck,
                    size: 15,
                    color: tokens.success,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Vault unlocked',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tokens.success,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                autoLockSeconds > 0
                    ? 'locks in ${_formatAutoLock(autoLockSeconds)}'
                    : 'auto-lock off',
                style: shellvibeMono(
                  context,
                  size: 10.5,
                  color: tokens.textSubtle,
                ),
              ),
            ],
          ),
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
    final unreadableIds =
        ref.watch(undecryptableIdentityIdsProvider).value ?? const <String>{};

    final addButton = ShellVibeButton(
      buttonKey: const Key('add_identity_button'),
      icon: LucideIcons.plus,
      label: 'Add identity',
      onPressed: () => _openIdentityForm(context),
    );
    final lockButton = ShellVibeButton.secondary(
      buttonKey: const Key('vault_lock_now_button'),
      icon: LucideIcons.lock,
      label: 'Lock now',
      onPressed: () => ref.read(vaultProvider.notifier).lock(),
    );

    return Column(
      children: [
        if (showContextColumn)
          ShellVibeWorkToolbar(
            title: _authTypeFilter == null
                ? 'All identities'
                : _authTypeLabel(_authTypeFilter!),
            meta: identitiesAsync.maybeWhen(
              data: (identities) =>
                  '${identities.length} identities · '
                  '${identities.where((identity) => hosts.any((host) => host.identityId == identity.id)).length} bound to a host',
              orElse: () => autoLockSeconds > 0
                  ? 'auto-lock ${_formatAutoLock(autoLockSeconds)}'
                  : 'auto-lock off',
            ),
            actions: [lockButton, addButton],
          )
        else
          ShellVibePageHeader(
            icon: LucideIcons.shieldCheck,
            title: 'Identity Vault',
            description:
                'Encrypted credentials stay separate from host definitions.',
            actions: [lockButton, addButton],
          ),
        if (!showContextColumn)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: ShellVibeSearchField(
              fieldKey: const Key('vault_search_input'),
              hintText: 'Search identities…',
              onChanged: (value) =>
                  setState(() => _searchQuery = value.toLowerCase()),
            ),
          ),
        Expanded(
          child: identitiesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => ShellVibeEmptyState(
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
                return ShellVibeEmptyState(
                  icon: LucideIcons.keyRound,
                  title: 'No identities found in Vault.',
                  description:
                      'Create an encrypted password or private-key identity and reuse it across hosts.',
                  actions: [
                    ShellVibeButton(
                      icon: LucideIcons.plus,
                      label: 'Add identity',
                      onPressed: () => _openIdentityForm(context),
                    ),
                  ],
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final item = filtered[index];
                  return _IdentityRow(
                    key: ValueKey(item.id),
                    // The list itself never decrypts, so the unreadable flag
                    // has to come from the separate health check.
                    identity: item.copyWith(
                      hasUndecryptableSecrets: unreadableIds.contains(item.id),
                    ),
                    compact: !showContextColumn,
                    usedByHostCount: hosts
                        .where((host) => host.identityId == item.id)
                        .length,
                    onEdit: () => _editIdentity(context, item),
                    onAssignHosts: () => _assignHosts(context, item),
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
    _ => LucideIcons.lock,
  };

  static String _authTypeLabel(String authType) => switch (authType) {
    'password' => 'Passwords',
    'key' => 'SSH keys',
    _ => authType,
  };

  static String _formatAutoLock(int seconds) {
    if (seconds % 60 == 0) return '${seconds ~/ 60} min';
    return '$seconds s';
  }

  Future<void> _openIdentityForm(
    BuildContext context, {
    IdentityModel? initialIdentity,
    bool repairSecrets = false,
  }) async {
    await showDialog(
      context: context,
      builder: (ctx) => IdentityFormDialog(
        initialIdentity: initialIdentity,
        workspaceId: ref.read(activeWorkspaceIdProvider),
        repairSecrets: repairSecrets,
      ),
    );
    // A repaired secret changes what the health check would say, and that
    // check does not observe the write itself.
    if (repairSecrets) ref.invalidate(undecryptableIdentityIdsProvider);
  }

  Future<void> _editIdentity(BuildContext context, IdentityModel item) async {
    // A secret that cannot be decrypted is gone for good, but the identity row
    // is not: its id is what every host points at. Open the repair form, which
    // replaces the secret in place, instead of leaving deletion as the only
    // way forward.
    if (item.hasUndecryptableSecrets) {
      _openIdentityForm(context, initialIdentity: item, repairSecrets: true);
      return;
    }

    IdentityModel? decrypted;
    try {
      decrypted = await ref
          .read(identitiesProvider.notifier)
          .getDecryptedIdentity(item.id);
    } catch (_) {
      // Opening the ordinary form with silently blank secrets would overwrite
      // the stored ones on save. Repair mode says so out loud instead.
      if (context.mounted) {
        _openIdentityForm(context, initialIdentity: item, repairSecrets: true);
      }
      return;
    }
    if (context.mounted) {
      _openIdentityForm(context, initialIdentity: decrypted ?? item);
    }
  }

  Future<void> _assignHosts(BuildContext context, IdentityModel item) async {
    final changed = await showDialog<int>(
      context: context,
      builder: (ctx) => AssignIdentityHostsDialog(identity: item),
    );
    if (changed != null && changed > 0 && context.mounted) {
      ShadToaster.of(context).show(
        ShadToast(
          description: Text(
            changed == 1 ? '1 host updated' : '$changed hosts updated',
          ),
        ),
      );
    }
  }

  Future<void> _deleteIdentity(BuildContext context, IdentityModel item) async {
    final hosts = ref.read(hostsProvider).value ?? const <HostModel>[];
    final boundHostCount = hosts
        .where((host) => host.identityId == item.id)
        .length;
    final alternatives =
        (ref.read(identitiesProvider).value ?? const <IdentityModel>[])
            .where((identity) => identity.id != item.id)
            .toList();

    final outcome = await showDialog<_DeleteIdentityOutcome>(
      context: context,
      builder: (ctx) => _DeleteIdentityDialog(
        identity: item,
        boundHostCount: boundHostCount,
        alternatives: alternatives,
      ),
    );

    if (outcome == null || !mounted) return;

    try {
      // Move the hosts first: the foreign key is ON DELETE SET NULL, so once
      // the identity row is gone there is nothing left to find them by.
      if (outcome.reassignToId != null) {
        await ref
            .read(hostsProvider.notifier)
            .reassignIdentity(item.id, outcome.reassignToId);
      }
      await ref.read(identitiesProvider.notifier).deleteIdentity(item.id);
      // The delete nulls out identityId in the database, behind the notifier's
      // back — refetch rather than show stale bindings.
      ref.invalidate(hostsProvider);
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

/// Single-line identity row.
///
/// The secret itself is never rendered and there is no reveal control: an
/// identity is represented by its type, name and how many hosts use it.
class _IdentityRow extends ConsumerWidget {
  final IdentityModel identity;
  final int usedByHostCount;
  final bool compact;
  final VoidCallback onEdit;
  final VoidCallback onAssignHosts;
  final VoidCallback onDelete;

  const _IdentityRow({
    super.key,
    required this.identity,
    required this.usedByHostCount,
    required this.compact,
    required this.onEdit,
    required this.onAssignHosts,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ShellVibeTokens.resolve(context);
    final isPassword = identity.authType == 'password';
    final isKey = identity.authType == 'key';
    final canCopy = isPassword || isKey;

    // Three states worth marking: a secret that cannot be read is an error, an
    // identity no host uses is a warning, everything else is quiet.
    final unreadable = identity.hasUndecryptableSecrets;
    final unused = usedByHostCount == 0;
    final iconColor = unreadable
        ? tokens.danger
        : unused
        ? tokens.warning
        : tokens.textSubtle;
    final usageColor = unreadable
        ? tokens.danger
        : unused
        ? tokens.warning
        : tokens.textMuted;

    // Only a key has a passphrase, so only a key gets the line about one:
    // "no passphrase" under a password identity reads as "no password stored",
    // which is the opposite of what just happened.
    final secretLabel = unreadable
        ? 'secret unreadable'
        : !isKey
        ? null
        : identity.passphrase != null && identity.passphrase!.isNotEmpty
        ? 'passphrase protected'
        : 'no passphrase';

    final usageLabel = unused
        ? 'unused'
        : usedByHostCount == 1
        ? '1 host'
        : '$usedByHostCount hosts';

    final typeIcon = SizedBox(
      width: 34,
      child: Icon(
        isPassword
            ? LucideIcons.lock
            : isKey
            ? LucideIcons.keyRound
            : LucideIcons.smartphone,
        size: 16,
        color: iconColor,
      ),
    );

    final title = Text(
      identity.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleSmall,
    );

    final actions = <Widget>[
      if (canCopy)
        ShellVibeIconButton(
          buttonKey: Key('copy_identity_button_${identity.id}'),
          icon: LucideIcons.copy,
          tooltip: isPassword ? 'Copy Password' : 'Copy Key',
          onPressed: () => _copySecret(context, ref, isPassword),
        ),
      ShellVibeIconButton(
        buttonKey: Key('assign_hosts_button_${identity.id}'),
        icon: LucideIcons.link,
        tooltip: 'Assign to hosts',
        onPressed: onAssignHosts,
      ),
      ShellVibeIconButton(
        buttonKey: Key('edit_identity_button_${identity.id}'),
        icon: unreadable ? LucideIcons.wrench : LucideIcons.pencil,
        tooltip: unreadable ? 'Repair secret' : 'Edit',
        danger: unreadable,
        onPressed: onEdit,
      ),
      ShellVibeIconButton(
        buttonKey: Key('delete_identity_button_${identity.id}'),
        icon: LucideIcons.trash2,
        tooltip: 'Delete',
        danger: true,
        onPressed: onDelete,
      ),
    ];

    // Reserved at a fixed width in both layouts, so the row never clips a
    // control it is a few pixels short of.
    final actionStrip = SizedBox(
      width: actions.length * _kIdentityActionWidth,
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: LayoutBuilder(
        builder: (context, constraints) =>
            constraints.maxWidth < _kIdentityStackedWidth
            ? _buildStacked(
                context,
                tokens: tokens,
                typeIcon: typeIcon,
                title: title,
                actionStrip: actionStrip,
                secretLabel: secretLabel,
                usageLabel: usageLabel,
                usageColor: usageColor,
              )
            : _buildTable(
                context,
                tokens: tokens,
                typeIcon: typeIcon,
                title: title,
                actionStrip: actionStrip,
                secretLabel: secretLabel,
                usageLabel: usageLabel,
                usageColor: usageColor,
              ),
      ),
    );
  }

  /// The wide form: one 52px line of columns, read across like a table.
  Widget _buildTable(
    BuildContext context, {
    required ShellVibeTokens tokens,
    required Widget typeIcon,
    required Widget title,
    required Widget actionStrip,
    required String? secretLabel,
    required String usageLabel,
    required Color usageColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      height: 52,
      child: Row(
        children: [
          typeIcon,
          Expanded(
            flex: 5,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                if (secretLabel != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    secretLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: shellvibeMono(
                      context,
                      size: 10.5,
                      color: tokens.textSubtle,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              _shortKind(identity.authType),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: shellvibeMono(context, size: 12),
            ),
          ),
          // The username column is the first thing to go when the row has to
          // share its width with the four 44px controls.
          if (!compact)
            Expanded(
              flex: 4,
              child: Text(
                identity.username.isEmpty ? '—' : identity.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: shellvibeMono(
                  context,
                  size: 11.5,
                  color: tokens.textSubtle,
                ),
              ),
            ),
          Expanded(
            flex: 3,
            child: Text(
              usageLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: usageColor),
            ),
          ),
          const SizedBox(width: 8),
          actionStrip,
        ],
      ),
    );
  }

  /// The narrow form: title, metadata, controls, each on its own line.
  ///
  /// The controls get a line of their own because sharing one with the title
  /// leaves it 141px on a 411px phone — still short of a name like
  /// "Production Server Key", which is the truncation this layout exists to
  /// end.
  Widget _buildStacked(
    BuildContext context, {
    required ShellVibeTokens tokens,
    required Widget typeIcon,
    required Widget title,
    required Widget actionStrip,
    required String? secretLabel,
    required String usageLabel,
    required Color usageColor,
  }) {
    final username = identity.username.isEmpty ? '—' : identity.username;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [typeIcon, Expanded(child: title)]),
          Padding(
            // Hangs off the title, not the glyph.
            padding: const EdgeInsets.only(left: 34),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${_shortKind(identity.authType)} · $username · ',
                  ),
                  TextSpan(
                    text: usageLabel,
                    style: TextStyle(color: usageColor),
                  ),
                  if (secretLabel != null) TextSpan(text: ' · $secretLabel'),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: shellvibeMono(
                context,
                size: 11.5,
                color: tokens.textSubtle,
              ),
            ),
          ),
          Align(alignment: Alignment.centerRight, child: actionStrip),
        ],
      ),
    );
  }

  static String _shortKind(String authType) => switch (authType) {
    'password' => 'password',
    'key' => 'private key',
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

/// What the user chose in [_DeleteIdentityDialog].
///
/// [reassignToId] is the identity the bound hosts should move to before the
/// delete. Null means "leave them without an identity", which is also what the
/// database would do on its own.
class _DeleteIdentityOutcome {
  final String? reassignToId;

  const _DeleteIdentityOutcome({this.reassignToId});
}

/// Delete confirmation that says how many hosts the identity is holding up.
///
/// The `hosts.identityId` foreign key is ON DELETE SET NULL: deleting an
/// identity silently detaches every host that used it, and nothing records
/// which ones those were. Offering the move here is the only chance to keep
/// them, short of editing each host by hand afterwards.
class _DeleteIdentityDialog extends StatefulWidget {
  final IdentityModel identity;
  final int boundHostCount;
  final List<IdentityModel> alternatives;

  const _DeleteIdentityDialog({
    required this.identity,
    required this.boundHostCount,
    required this.alternatives,
  });

  @override
  State<_DeleteIdentityDialog> createState() => _DeleteIdentityDialogState();
}

class _DeleteIdentityDialogState extends State<_DeleteIdentityDialog> {
  String? _reassignToId;

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final bound = widget.boundHostCount;
    final canReassign = bound > 0 && widget.alternatives.isNotEmpty;

    return ShadDialog.alert(
      title: const Text('Delete Identity'),
      description: Text(
        'Are you sure you want to delete "${widget.identity.title}"?',
      ),
      actions: adaptiveDialogActions(context, [
        ShellVibeButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        ShellVibeButton.danger(
          key: const Key('confirm_delete_identity_button'),
          label: _reassignToId != null ? 'Move hosts and delete' : 'Delete',
          onPressed: () => Navigator.of(
            context,
          ).pop(_DeleteIdentityOutcome(reassignToId: _reassignToId)),
        ),
      ]),
      actionsAxis: adaptiveDialogActionsAxis(context),
      child: bound == 0
          ? const SizedBox.shrink()
          : SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(tokens.radiusMedium),
                      border: Border.all(color: tokens.warning),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          LucideIcons.triangleAlert,
                          size: 16,
                          color: tokens.warning,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            bound == 1
                                ? '1 host uses this identity and will be left '
                                      'without one. That binding cannot be '
                                      'recovered afterwards.'
                                : '$bound hosts use this identity and will be '
                                      'left without one. Those bindings cannot '
                                      'be recovered afterwards.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: tokens.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (canReassign) ...[
                    const SizedBox(height: 14),
                    ShadSelectFormField<String?>(
                      key: const Key('reassign_identity_select'),
                      initialValue: _reassignToId,
                      label: const Text('Move those hosts to'),
                      selectedOptionBuilder: (context, value) => Text(
                        value == null
                            ? 'Nothing — detach them'
                            : widget.alternatives
                                  .firstWhere(
                                    (identity) => identity.id == value,
                                  )
                                  .title,
                      ),
                      options: [
                        const ShadOption<String?>(
                          value: null,
                          child: Text('Nothing — detach them'),
                        ),
                        ...widget.alternatives.map(
                          (identity) => ShadOption<String?>(
                            value: identity.id,
                            child: Text(identity.title),
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _reassignToId = value),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
