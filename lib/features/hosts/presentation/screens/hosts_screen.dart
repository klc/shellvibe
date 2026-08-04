import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/terly_tokens.dart';
import '../../../../app/widgets/terly_ui.dart';
import '../../../../app/widgets/workspace_switcher.dart';
import '../../../terminal/presentation/dialogs/host_key_prompt_dialog.dart';
import '../../../terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../../vault/domain/models/identity_model.dart';
import '../../../vault/presentation/notifiers/identities_notifier.dart';
import '../../../../shared/providers/workspace_provider.dart';
import '../dialogs/host_form_dialog.dart';
import '../dialogs/host_group_form_dialog.dart';
import '../notifiers/host_groups_notifier.dart';
import '../notifiers/hosts_notifier.dart';
import '../../domain/models/host_group_model.dart';
import '../../domain/models/host_model.dart';

/// Width at which the module's context column fits alongside the list.
const double _kContextColumnBreakpoint = 900;

/// Width at which the inline detail drawer fits as well.
const double _kDetailDrawerBreakpoint = 1180;

/// Whether [host] can carry an SFTP session.
///
/// Local and serial hosts have no SSH transport, so file transfer is hidden
/// rather than offered and then failing at connect time.
bool hostSupportsFileTransfer(HostModel host) =>
    host.protocol != 'local' && host.protocol != 'serial';

/// Pseudo-group selections that sit above the real groups in the column.
enum _HostFilter { all, connected, ungrouped }

class HostsScreen extends ConsumerStatefulWidget {
  final void Function(HostModel host)? onConnectHost;

  const HostsScreen({super.key, this.onConnectHost});

  @override
  ConsumerState<HostsScreen> createState() => _HostsScreenState();
}

class _HostsScreenState extends ConsumerState<HostsScreen> {
  String _searchQuery = '';
  final Set<String> _connectingHostIds = {};

  _HostFilter _filter = _HostFilter.all;

  /// Non-null when a real group (rather than a pseudo-filter) is selected.
  String? _selectedGroupId;
  String? _selectedHostId;

  @override
  Widget build(BuildContext context) {
    final hostsAsync = ref.watch(hostsProvider);
    final groupsAsync = ref.watch(hostGroupsProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final showContextColumn =
            constraints.maxWidth >= _kContextColumnBreakpoint;
        final showDetailDrawer =
            constraints.maxWidth >= _kDetailDrawerBreakpoint;

        return Scaffold(
          body: Row(
            children: [
              if (showContextColumn)
                _buildContextColumn(context, groupsAsync, hostsAsync),
              Expanded(
                child: _buildWorkArea(
                  context,
                  hostsAsync: hostsAsync,
                  groupsAsync: groupsAsync,
                  showContextColumn: showContextColumn,
                  showDetailDrawer: showDetailDrawer,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── context column ──────────────────────────────────────────────────────

  Widget _buildContextColumn(
    BuildContext context,
    AsyncValue<List<HostGroupModel>> groupsAsync,
    AsyncValue<List<HostModel>> hostsAsync,
  ) {
    final hosts = hostsAsync.value ?? const <HostModel>[];
    final groups = groupsAsync.value ?? const <HostGroupModel>[];
    final connectedIds = _connectedHostIds();

    return TerlyContextColumn(
      head: TerlyWorkspaceSwitcher(
        onManageWorkspaces: () => GoRouter.maybeOf(context)?.go('/workspaces'),
      ),
      search: TerlySearchField(
        fieldKey: const Key('hosts_search_input'),
        hintText: 'Search hosts…',
        onChanged: (value) =>
            setState(() => _searchQuery = value.toLowerCase()),
      ),
      children: [
        const TerlySectionLabel(label: 'Groups'),
        TerlyNavItem(
          itemKey: const Key('hosts_filter_all'),
          icon: LucideIcons.layoutGrid,
          label: 'All',
          count: hosts.length,
          selected: _selectedGroupId == null && _filter == _HostFilter.all,
          onTap: () => _selectFilter(_HostFilter.all),
        ),
        TerlyNavItem(
          itemKey: const Key('hosts_filter_connected'),
          icon: LucideIcons.radio,
          label: 'Connected',
          count: connectedIds.length,
          selected:
              _selectedGroupId == null && _filter == _HostFilter.connected,
          onTap: () => _selectFilter(_HostFilter.connected),
        ),
        TerlyNavItem(
          itemKey: const Key('hosts_filter_ungrouped'),
          icon: LucideIcons.inbox,
          label: 'Ungrouped',
          count: hosts.where((host) => host.groupId == null).length,
          selected:
              _selectedGroupId == null && _filter == _HostFilter.ungrouped,
          onTap: () => _selectFilter(_HostFilter.ungrouped),
        ),
        if (groups.isNotEmpty) const TerlySectionLabel(label: 'Tags'),
        for (final group in groups)
          TerlyNavItem(
            itemKey: Key('group_${group.id}'),
            icon: LucideIcons.hash,
            label: group.name,
            count: hosts.where((host) => host.groupId == group.id).length,
            selected: _selectedGroupId == group.id,
            onTap: () => setState(() {
              _selectedGroupId = group.id;
              _filter = _HostFilter.all;
            }),
          ),
      ],
    );
  }

  void _selectFilter(_HostFilter filter) {
    setState(() {
      _filter = filter;
      _selectedGroupId = null;
    });
  }

  // ── work area ───────────────────────────────────────────────────────────

  Widget _buildWorkArea(
    BuildContext context, {
    required AsyncValue<List<HostModel>> hostsAsync,
    required AsyncValue<List<HostGroupModel>> groupsAsync,
    required bool showContextColumn,
    required bool showDetailDrawer,
  }) {
    final tokens = TerlyTokens.resolve(context);
    final groups = groupsAsync.value ?? const <HostGroupModel>[];
    final connectedIds = _connectedHostIds();

    final actions = <Widget>[
      IconButton(
        key: const Key('add_group_button'),
        icon: const Icon(LucideIcons.folderPlus, size: 17),
        tooltip: 'Add Group',
        onPressed: () => _openGroupForm(context),
      ),
      ShadButton(
        key: const Key('add_host_button'),
        size: ShadButtonSize.sm,
        leading: const Icon(LucideIcons.plus, size: 16),
        onPressed: () => _openHostForm(context),
        child: const Text('Add Host'),
      ),
    ];

    return Column(
      children: [
        // Without the context column there is no home for the workspace
        // switcher, so the compact title bar carries it instead.
        if (!showContextColumn)
          TerlyPageHeader(
            icon: LucideIcons.server,
            title: 'Hosts & Servers',
            actions: [
              TerlyWorkspaceSwitcher(
                compact: true,
                onManageWorkspaces: () =>
                    GoRouter.maybeOf(context)?.go('/workspaces'),
              ),
              ...actions,
            ],
          )
        else
          TerlyWorkToolbar(
            title: _activeScopeLabel(groups),
            meta: hostsAsync.maybeWhen(
              data: (hosts) =>
                  '${_scopedHosts(hosts).length} hosts · ${connectedIds.length} connected',
              orElse: () => null,
            ),
            actions: actions,
          ),
        if (!showContextColumn)
          _buildCompactFilterBar(context, groups, hostsAsync.value ?? const []),
        Expanded(
          child: hostsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => TerlyEmptyState(
              icon: LucideIcons.triangleAlert,
              title: 'Could not load hosts',
              description: '$error',
            ),
            data: (hosts) => groupsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => TerlyEmptyState(
                icon: LucideIcons.triangleAlert,
                title: 'Could not load host groups',
                description: '$error',
              ),
              data: (groups) {
                if (hosts.isEmpty && groups.isEmpty) {
                  return _buildFirstRunEmptyState(context);
                }

                final visible = _visibleHosts(hosts);
                if (visible.isEmpty) {
                  return const TerlyEmptyState(
                    icon: LucideIcons.searchX,
                    title: 'No hosts match your search.',
                    description: 'Try a label, hostname, username or protocol.',
                  );
                }

                final selected = visible
                    .where((host) => host.id == _selectedHostId)
                    .firstOrNull;

                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          _HostListHeader(
                            tokens: tokens,
                            compact: !showContextColumn,
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: visible.length,
                              itemBuilder: (context, index) {
                                final host = visible[index];
                                return _HostRow(
                                  key: ValueKey(host.id),
                                  host: host,
                                  groups: groups,
                                  connected: connectedIds.contains(host.id),
                                  isConnecting: _connectingHostIds.contains(
                                    host.id,
                                  ),
                                  selected: host.id == _selectedHostId,
                                  compact: !showContextColumn,
                                  onSelect: () {
                                    setState(() => _selectedHostId = host.id);
                                    // Too narrow for the inline drawer, so the
                                    // detail becomes a sheet rather than a
                                    // selection that leads nowhere.
                                    if (!showDetailDrawer) {
                                      _showHostDetailSheet(
                                        host: host,
                                        hosts: hosts,
                                        groups: groups,
                                        connected: connectedIds.contains(
                                          host.id,
                                        ),
                                      );
                                    }
                                  },
                                  onConnect: () => _onConnectHost(host),
                                  onOpenSftp: () => _onOpenSftp(host),
                                  onEdit: () =>
                                      _openHostForm(context, initialHost: host),
                                  onDelete: () => _deleteHost(context, host),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (showDetailDrawer && selected != null)
                      TerlyDetailDrawer(
                        child: _HostDetailPanel(
                          host: selected,
                          hosts: hosts,
                          groups: groups,
                          connected: connectedIds.contains(selected.id),
                          onConnect: () => _onConnectHost(selected),
                          onOpenSftp: () => _onOpenSftp(selected),
                          onEdit: () =>
                              _openHostForm(context, initialHost: selected),
                          onDelete: () => _deleteHost(context, selected),
                          onClose: () => setState(() => _selectedHostId = null),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactFilterBar(
    BuildContext context,
    List<HostGroupModel> groups,
    List<HostModel> hosts,
  ) {
    final tokens = TerlyTokens.resolve(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        tokens.pagePadding,
        10,
        tokens.pagePadding,
        8,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TerlySearchField(
            fieldKey: const Key('hosts_search_input'),
            hintText: 'Search hosts, addresses and protocols…',
            onChanged: (value) =>
                setState(() => _searchQuery = value.toLowerCase()),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  selected:
                      _selectedGroupId == null && _filter == _HostFilter.all,
                  onTap: () => _selectFilter(_HostFilter.all),
                ),
                _FilterChip(
                  label: 'Connected',
                  selected:
                      _selectedGroupId == null &&
                      _filter == _HostFilter.connected,
                  onTap: () => _selectFilter(_HostFilter.connected),
                ),
                for (final group in groups)
                  _FilterChip(
                    chipKey: Key('group_${group.id}'),
                    label: group.name,
                    selected: _selectedGroupId == group.id,
                    onTap: () => setState(() {
                      _selectedGroupId = group.id;
                      _filter = _HostFilter.all;
                    }),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The narrow-width form of the detail drawer.
  void _showHostDetailSheet({
    required HostModel host,
    required List<HostModel> hosts,
    required List<HostGroupModel> groups,
    required bool connected,
  }) {
    final tokens = TerlyTokens.resolve(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: tokens.surface,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.72,
          child: _HostDetailPanel(
            host: host,
            hosts: hosts,
            groups: groups,
            connected: connected,
            onConnect: () {
              Navigator.of(sheetContext).pop();
              _onConnectHost(host);
            },
            onOpenSftp: () {
              Navigator.of(sheetContext).pop();
              _onOpenSftp(host);
            },
            onEdit: () {
              Navigator.of(sheetContext).pop();
              _openHostForm(context, initialHost: host);
            },
            onDelete: () {
              Navigator.of(sheetContext).pop();
              _deleteHost(context, host);
            },
            onClose: () => Navigator.of(sheetContext).pop(),
          ),
        ),
      ),
    );
  }

  Widget _buildFirstRunEmptyState(BuildContext context) {
    return TerlyEmptyState(
      icon: LucideIcons.server,
      title: 'No hosts or groups configured.',
      description:
          'Add your first server to connect in one click. You can organize infrastructure into groups at any time.',
      actions: [
        ShadButton(
          onPressed: () => _openHostForm(context),
          leading: const Icon(LucideIcons.plus, size: 16),
          child: const Text('Add your first host'),
        ),
        ShadButton.outline(
          onPressed: () => _openGroupForm(context),
          leading: const Icon(LucideIcons.folderPlus, size: 16),
          child: const Text('Create group'),
        ),
      ],
    );
  }

  // ── filtering ───────────────────────────────────────────────────────────

  Set<String> _connectedHostIds() {
    final tabs = ref.watch(terminalTabsProvider).tabs;
    return {
      for (final tab in tabs)
        if (tab.isConnected && tab.host != null) tab.host!.id,
    };
  }

  String _activeScopeLabel(List<HostGroupModel> groups) {
    if (_selectedGroupId != null) {
      return groups
              .where((group) => group.id == _selectedGroupId)
              .firstOrNull
              ?.name ??
          'Group';
    }
    return switch (_filter) {
      _HostFilter.all => 'All',
      _HostFilter.connected => 'Connected',
      _HostFilter.ungrouped => 'Ungrouped',
    };
  }

  /// Hosts in the selected group/filter, before the search query is applied.
  List<HostModel> _scopedHosts(List<HostModel> hosts) {
    if (_selectedGroupId != null) {
      return hosts.where((host) => host.groupId == _selectedGroupId).toList();
    }
    return switch (_filter) {
      _HostFilter.all => hosts,
      _HostFilter.connected =>
        hosts.where((host) => _connectedHostIds().contains(host.id)).toList(),
      _HostFilter.ungrouped =>
        hosts.where((host) => host.groupId == null).toList(),
    };
  }

  List<HostModel> _visibleHosts(List<HostModel> hosts) {
    return _scopedHosts(hosts).where((host) {
      if (_searchQuery.isEmpty) return true;
      return host.label.toLowerCase().contains(_searchQuery) ||
          host.hostname.toLowerCase().contains(_searchQuery) ||
          (host.username ?? '').toLowerCase().contains(_searchQuery) ||
          host.protocol.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  // ── actions ─────────────────────────────────────────────────────────────

  /// Opens (and connects) a terminal tab for [host] and returns its id, or
  /// null when credentials could not be read.
  Future<String?> _openSessionForHost(HostModel host) async {
    IdentityModel? identity;
    if (host.identityId != null) {
      try {
        identity = await ref
            .read(identitiesProvider.notifier)
            .getDecryptedIdentity(host.identityId!);
      } catch (e) {
        if (mounted) {
          ShadToaster.of(context).show(
            ShadToast.destructive(
              description: Text('Cannot read stored credentials: $e'),
            ),
          );
        }
        return null;
      }
    }

    await ref
        .read(terminalTabsProvider.notifier)
        .openTabForHost(
          host,
          identity: identity,
          onHostKeyPrompt:
              (hostname, port, keyType, fingerprint, status) async {
                if (!mounted) return false;
                final approved = await HostKeyPromptDialog.show(
                  context,
                  hostname: hostname,
                  port: port,
                  keyType: keyType,
                  fingerprint: fingerprint,
                  status: status,
                );
                return approved ?? false;
              },
        );

    return ref.read(terminalTabsProvider).activeTabId;
  }

  Future<void> _defaultConnectHost(HostModel host) async {
    await _openSessionForHost(host);
    if (mounted) {
      GoRouter.maybeOf(context)?.go('/terminal');
    }
  }

  Future<void> _onConnectHost(HostModel host) async {
    if (_connectingHostIds.contains(host.id)) return;
    setState(() => _connectingHostIds.add(host.id));
    try {
      if (widget.onConnectHost != null) {
        widget.onConnectHost!(host);
      } else {
        await _defaultConnectHost(host);
      }
    } finally {
      if (mounted) {
        setState(() => _connectingHostIds.remove(host.id));
      }
    }
  }

  /// Opens file transfer against [host], reusing its live session when there is
  /// one and connecting a new one otherwise. The session id travels with the
  /// route so the SFTP screen can name the server it is writing to.
  Future<void> _onOpenSftp(HostModel host) async {
    if (_connectingHostIds.contains(host.id)) return;

    var tab = ref
        .read(terminalTabsProvider)
        .tabs
        .where((session) => session.host?.id == host.id && session.isConnected)
        .firstOrNull;

    if (tab == null) {
      setState(() => _connectingHostIds.add(host.id));
      String? tabId;
      try {
        tabId = await _openSessionForHost(host);
      } finally {
        if (mounted) {
          setState(() => _connectingHostIds.remove(host.id));
        }
      }
      if (!mounted || tabId == null) return;
      tab = ref
          .read(terminalTabsProvider)
          .tabs
          .where((session) => session.id == tabId)
          .firstOrNull;
      if (tab == null || !tab.isConnected) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            description: Text(
              'Could not connect to ${host.label} for file transfer.',
            ),
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    GoRouter.maybeOf(context)?.push(
      '/sftp?tab=${Uri.encodeComponent(tab.id)}'
      '&label=${Uri.encodeComponent(host.label)}',
    );
  }

  void _openHostForm(BuildContext context, {HostModel? initialHost}) {
    showDialog(
      context: context,
      builder: (ctx) => HostFormDialog(
        initialHost: initialHost,
        workspaceId: ref.read(activeWorkspaceIdProvider),
      ),
    );
  }

  void _openGroupForm(BuildContext context, {HostGroupModel? initialGroup}) {
    showDialog(
      context: context,
      builder: (ctx) => HostGroupFormDialog(
        initialGroup: initialGroup,
        workspaceId: ref.read(activeWorkspaceIdProvider),
      ),
    );
  }

  Future<void> _deleteHost(BuildContext context, HostModel host) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => ShadDialog.alert(
        title: const Text('Delete Host'),
        description: Text('Are you sure you want to delete "${host.label}"?'),
        actions: [
          ShadButton.outline(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          ShadButton.destructive(
            child: const Text('Delete'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (_selectedHostId == host.id) {
        setState(() => _selectedHostId = null);
      }
      await ref.read(hostsProvider.notifier).deleteHost(host.id);
    }
  }
}

// ── list primitives ───────────────────────────────────────────────────────

/// Column widths shared by the header and every row so they stay aligned.
const List<int> _kHostColumnFlex = [4, 4, 3, 2];

/// Rendered width of the row's trailing controls.
///
/// Measured, not guessed: the two compact [IconButton]s occupy 34px each and
/// the [PopupMenuButton] 48px once Material's minimum tap target is applied,
/// plus the 12px the popup adds around its icon.
const double _kHostActionsWidth = 128;

class _HostListHeader extends StatelessWidget {
  final TerlyTokens tokens;
  final bool compact;

  const _HostListHeader({required this.tokens, required this.compact});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      fontSize: 10,
      letterSpacing: 0.8,
      color: tokens.textMuted,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 18),
          Expanded(
            flex: _kHostColumnFlex[0],
            child: Text('NAME', style: style, maxLines: 1),
          ),
          Expanded(
            flex: _kHostColumnFlex[1],
            child: Text('ADDRESS', style: style, maxLines: 1),
          ),
          if (!compact) ...[
            Expanded(
              flex: _kHostColumnFlex[2],
              child: Text('TAGS', style: style, maxLines: 1),
            ),
            Expanded(
              flex: _kHostColumnFlex[3],
              child: Text('PROTOCOL', style: style, maxLines: 1),
            ),
          ],
          const SizedBox(width: _kHostActionsWidth),
        ],
      ),
    );
  }
}

/// Single-line dense host row.
///
/// The wireframe replaces the card grid with this so ~9 hosts fit where 6 did,
/// and status reads as dot + text rather than colour alone.
class _HostRow extends StatelessWidget {
  final HostModel host;
  final List<HostGroupModel> groups;
  final bool connected;
  final bool isConnecting;
  final bool selected;
  final bool compact;
  final VoidCallback onSelect;
  final VoidCallback onConnect;
  final VoidCallback onOpenSftp;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _HostRow({
    super.key,
    required this.host,
    required this.groups,
    required this.connected,
    required this.isConnecting,
    required this.selected,
    required this.compact,
    required this.onSelect,
    required this.onConnect,
    required this.onOpenSftp,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
    final address =
        '${host.username != null && host.username!.isNotEmpty ? '${host.username}@' : ''}'
        '${host.hostname}:${host.port}';
    final groupName = groups
        .where((group) => group.id == host.groupId)
        .firstOrNull
        ?.name;
    final monoStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: tokens.textMuted, fontSize: 12);

    return Semantics(
      button: true,
      selected: selected,
      label:
          '${host.label}, ${host.protocol} host at ${host.hostname}, '
          '${connected ? 'connected' : 'not connected'}',
      child: InkWell(
        onTap: onSelect,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          constraints: const BoxConstraints(minHeight: 42),
          decoration: BoxDecoration(
            color: selected
                ? tokens.textPrimary.withValues(alpha: 0.06)
                : Colors.transparent,
            border: Border(
              bottom: BorderSide(color: tokens.border),
              left: BorderSide(
                color: selected ? tokens.brand : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              TerlyStatusDot(
                state: connected ? TerlyDotState.online : TerlyDotState.offline,
              ),
              const SizedBox(width: 11),
              Expanded(
                flex: _kHostColumnFlex[0],
                child: Text(
                  host.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              Expanded(
                flex: _kHostColumnFlex[1],
                child: Text(
                  // Compact drops the protocol column, so the state text that
                  // pairs with the dot moves onto the address line.
                  compact && connected ? '$address · connected' : address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle,
                ),
              ),
              if (!compact) ...[
                Expanded(
                  flex: _kHostColumnFlex[2],
                  child: groupName == null
                      ? const SizedBox.shrink()
                      : Align(
                          alignment: Alignment.centerLeft,
                          child: TerlyStatusChip(label: groupName),
                        ),
                ),
                Expanded(
                  flex: _kHostColumnFlex[3],
                  child: Text(
                    // Status is never carried by colour alone: the dot is
                    // paired with this text so the row still reads without hue.
                    connected ? 'connected' : host.protocol,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle,
                  ),
                ),
              ],
              SizedBox(
                width: _kHostActionsWidth,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (isConnecting)
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      IconButton(
                        key: Key('connect_host_${host.id}'),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 34,
                          height: 34,
                        ),
                        icon: Icon(
                          LucideIcons.play,
                          size: 16,
                          color: tokens.success,
                        ),
                        tooltip: 'Connect Terminal',
                        onPressed: onConnect,
                      ),
                    // Transfer only makes sense over SSH; a local or serial
                    // host has no SFTP subsystem to talk to.
                    if (hostSupportsFileTransfer(host))
                      IconButton(
                        key: Key('sftp_host_${host.id}'),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 34,
                          height: 34,
                        ),
                        icon: Icon(
                          LucideIcons.folderSync,
                          size: 16,
                          color: tokens.info,
                        ),
                        tooltip: 'File Transfer (SFTP)',
                        onPressed: onOpenSftp,
                      ),
                    PopupMenuButton<String>(
                      tooltip: 'Host actions',
                      // No `constraints` here: that property sizes the popup
                      // menu, not the button, and pinning it clipped the menu
                      // items.
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      icon: const Icon(LucideIcons.ellipsis, size: 16),
                      onSelected: (value) {
                        if (value == 'edit') onEdit();
                        if (value == 'delete') onDelete();
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(LucideIcons.pencil, size: 16),
                              SizedBox(width: 8),
                              Text('Edit host'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                LucideIcons.trash2,
                                size: 16,
                                color: tokens.danger,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Delete host',
                                style: TextStyle(color: tokens.danger),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final Key? chipKey;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    this.chipKey,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        key: chipKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? tokens.brand.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(tokens.radiusPill),
            border: Border.all(
              color: selected
                  ? tokens.brand.withValues(alpha: 0.34)
                  : tokens.border,
            ),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: selected ? tokens.brand : tokens.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline right-hand detail panel — the wireframe's replacement for a modal.
class _HostDetailPanel extends StatelessWidget {
  final HostModel host;
  final List<HostModel> hosts;
  final List<HostGroupModel> groups;
  final bool connected;
  final VoidCallback onConnect;
  final VoidCallback onOpenSftp;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  const _HostDetailPanel({
    required this.host,
    required this.hosts,
    required this.groups,
    required this.connected,
    required this.onConnect,
    required this.onOpenSftp,
    required this.onEdit,
    required this.onDelete,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
    final jumpHost = hosts
        .where((candidate) => candidate.id == host.jumpHostId)
        .firstOrNull;
    final group = groups
        .where((candidate) => candidate.id == host.groupId)
        .firstOrNull;

    return ListView(
      key: const Key('host_detail_drawer'),
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    host.label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    host.hostname,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: tokens.textMuted),
                  ),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(LucideIcons.x, size: 15),
              tooltip: 'Close details',
              onPressed: onClose,
            ),
          ],
        ),
        const SizedBox(height: 6),
        TerlyStatusChip(
          label: connected ? 'connected' : 'not connected',
          tone: connected ? TerlyStatusTone.brand : TerlyStatusTone.neutral,
        ),
        const SizedBox(height: 12),
        ShadButton(
          key: const Key('detail_open_terminal'),
          width: double.infinity,
          onPressed: onConnect,
          child: const Text('Open terminal'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (hostSupportsFileTransfer(host)) ...[
              Expanded(
                child: ShadButton.outline(
                  key: const Key('detail_open_sftp'),
                  size: ShadButtonSize.sm,
                  onPressed: onOpenSftp,
                  child: const Text('Files'),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: ShadButton.outline(
                size: ShadButtonSize.sm,
                onPressed: () => GoRouter.maybeOf(context)?.go('/tunnels'),
                child: const Text('Tunnel'),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: ShadButton.outline(
                size: ShadButtonSize.sm,
                onPressed: onEdit,
                child: const Text('Edit'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _DetailRow(label: 'protocol', value: host.protocol),
        _DetailRow(label: 'port', value: '${host.port}'),
        _DetailRow(label: 'user', value: host.username ?? '—'),
        _DetailRow(label: 'group', value: group?.name ?? '—'),
        _DetailRow(label: 'jump host', value: jumpHost?.label ?? '—'),
        _DetailRow(
          label: 'identity',
          value: host.identityId == null ? 'none' : 'from vault',
        ),
        const SizedBox(height: 14),
        ShadButton.destructive(
          size: ShadButtonSize.sm,
          width: double.infinity,
          onPressed: onDelete,
          child: const Text('Delete host'),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 9,
                letterSpacing: 0.8,
                color: tokens.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
