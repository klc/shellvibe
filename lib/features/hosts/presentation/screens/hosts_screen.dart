import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../app/widgets/workspace_switcher.dart';
import '../../../../core/network/ssh_session_manager.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../../shared/providers/workspace_provider.dart';
import '../../../templates/domain/models/template_model.dart';
import '../../../templates/presentation/dialogs/save_template_dialog.dart';
import '../../../templates/presentation/notifiers/templates_notifier.dart';
import '../../../templates/presentation/widgets/template_picker_sheet.dart';
import '../../../terminal/presentation/dialogs/host_key_prompt_dialog.dart';
import '../../../terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../../vault/domain/models/identity_model.dart';
import '../../../vault/presentation/notifiers/identities_notifier.dart';
import '../../data/services/ssh_config_import_service.dart';
import '../../domain/models/host_group_model.dart';
import '../../domain/models/host_model.dart';
import '../dialogs/host_form_dialog.dart';
import '../dialogs/host_group_form_dialog.dart';
import '../dialogs/ssh_config_import_dialog.dart';
import '../notifiers/host_groups_notifier.dart';
import '../notifiers/hosts_notifier.dart';

/// Whether [host] can carry an SFTP session.
///
/// Local hosts have no SSH transport, so file transfer is hidden rather than
/// offered and then failing at connect time.
bool hostSupportsFileTransfer(HostModel host) => host.protocol != 'local';

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

  /// True while a config-looking file hovers the drop target (desktop).
  bool _isDraggingConfig = false;

  @override
  Widget build(BuildContext context) {
    final hostsAsync = ref.watch(hostsProvider);
    final groupsAsync = ref.watch(hostGroupsProvider);

    final tierTokens = ShellVibeTokens.resolve(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Measured on the module's own constraints, not on the screen: the rail
        // and its gaps have already been taken out by the time this runs.
        final showContextColumn =
            constraints.maxWidth >= tierTokens.breakpointMedium;
        final showDetailDrawer =
            constraints.maxWidth >= tierTokens.breakpointExpanded;

        // Nocturne lays the module out as sibling slabs on the canvas the
        // shell already painted, so the scaffold contributes no surface of its
        // own and the detail panel is a peer of the work area rather than a
        // column inside it.
        final hosts = hostsAsync.value ?? const <HostModel>[];
        final groups = groupsAsync.value ?? const <HostGroupModel>[];
        final selectedHost = _visibleHosts(
          hosts,
        ).where((host) => host.id == _selectedHostId).firstOrNull;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Row(
            children: [
              if (showContextColumn)
                _buildContextColumn(context, groupsAsync, hostsAsync),
              Expanded(
                child: Builder(
                  builder: (context) {
                    final workArea = _buildWorkArea(
                      context,
                      hostsAsync: hostsAsync,
                      groupsAsync: groupsAsync,
                      showContextColumn: showContextColumn,
                      showDetailDrawer: showDetailDrawer,
                    );
                    // A phone has no room to spend on a slab inside a slab:
                    // there the list sits straight on the canvas, and only the
                    // desktop layout floats it.
                    // The list already carries its own gutter, so the phone
                    // layout adds nothing around it.
                    if (!showContextColumn) return workArea;
                    return ShellVibePanel(gradientExtent: 160, child: workArea);
                  },
                ),
              ),
              if (showDetailDrawer && selectedHost != null)
                ShellVibeDetailDrawer(
                  child: _HostDetailPanel(
                    host: selectedHost,
                    hosts: hosts,
                    groups: groups,
                    connected: _connectedHostIds().contains(selectedHost.id),
                    onConnect: () => _onConnectHost(selectedHost),
                    onOpenSftp: () => _onOpenSftp(selectedHost),
                    onEdit: () =>
                        _openHostForm(context, initialHost: selectedHost),
                    onDelete: () => _deleteHost(context, selectedHost),
                    onClose: () => setState(() => _selectedHostId = null),
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
    final templates = ref.watch(templatesProvider).value ?? const [];

    return ShellVibeContextColumn(
      head: ShellVibeWorkspaceSwitcher(
        onManageWorkspaces: () => GoRouter.maybeOf(context)?.go('/workspaces'),
      ),
      search: ShellVibeSearchField(
        fieldKey: const Key('hosts_search_input'),
        hintText: 'Search hosts…',
        onChanged: (value) =>
            setState(() => _searchQuery = value.toLowerCase()),
      ),
      children: [
        const ShellVibeSectionLabel(label: 'Groups'),
        ShellVibeNavItem(
          itemKey: const Key('hosts_filter_all'),
          icon: LucideIcons.layoutGrid,
          label: 'All',
          count: hosts.length,
          selected: _selectedGroupId == null && _filter == _HostFilter.all,
          onTap: () => _selectFilter(_HostFilter.all),
        ),
        ShellVibeNavItem(
          itemKey: const Key('hosts_filter_connected'),
          icon: LucideIcons.radio,
          label: 'Connected',
          count: connectedIds.length,
          selected:
              _selectedGroupId == null && _filter == _HostFilter.connected,
          onTap: () => _selectFilter(_HostFilter.connected),
        ),
        ShellVibeNavItem(
          itemKey: const Key('hosts_filter_ungrouped'),
          icon: LucideIcons.inbox,
          label: 'Ungrouped',
          count: hosts.where((host) => host.groupId == null).length,
          selected:
              _selectedGroupId == null && _filter == _HostFilter.ungrouped,
          onTap: () => _selectFilter(_HostFilter.ungrouped),
        ),
        if (groups.isNotEmpty) const ShellVibeSectionLabel(label: 'Tags'),
        for (final group in groups)
          ShellVibeNavItem(
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
        // Saved terminal layouts. Unlike the entries above these are actions,
        // not filters: tapping one opens its tabs and panes in the terminal.
        if (templates.isNotEmpty) ...[
          const ShellVibeSectionLabel(label: 'Templates'),
          for (final template in templates)
            _TemplateNavItem(
              template: template,
              onRun: () => _runTemplate(template),
              onRename: () => _renameTemplate(template),
              onDelete: () => _deleteTemplate(context, template),
            ),
        ],
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
    final tokens = ShellVibeTokens.resolve(context);
    final groups = groupsAsync.value ?? const <HostGroupModel>[];
    final connectedIds = _connectedHostIds();

    // One brand action per panel: adding a host is the thing this screen is
    // for, so everything else stays a hairline control.
    final actions = <Widget>[
      ShellVibeButton.secondary(
        buttonKey: const Key('add_group_button'),
        icon: LucideIcons.folderPlus,
        label: 'Add group',
        onPressed: () => _openGroupForm(context),
      ),
      ShellVibeButton.secondary(
        buttonKey: const Key('import_ssh_config_button'),
        icon: LucideIcons.fileInput,
        label: 'Import',
        onPressed: () => _openImportConfig(context),
      ),
      ShellVibeButton(
        buttonKey: const Key('add_host_button'),
        icon: LucideIcons.plus,
        label: 'Add host',
        onPressed: () => _openHostForm(context),
      ),
    ];

    final workArea = Column(
      children: [
        // Without the context column there is no home for the workspace
        // switcher, so the compact title bar carries it instead.
        if (!showContextColumn)
          ShellVibePageHeader(
            icon: LucideIcons.server,
            title: 'Hosts & Servers',
            actions: [
              ShellVibeWorkspaceSwitcher(
                compact: true,
                onManageWorkspaces: () =>
                    GoRouter.maybeOf(context)?.go('/workspaces'),
              ),
              ...actions,
            ],
          )
        else
          ShellVibeWorkToolbar(
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
            error: (error, stackTrace) => ShellVibeEmptyState(
              icon: LucideIcons.triangleAlert,
              title: 'Could not load hosts',
              description: '$error',
            ),
            data: (hosts) => groupsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => ShellVibeEmptyState(
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
                  return const ShellVibeEmptyState(
                    icon: LucideIcons.searchX,
                    title: 'No hosts match your search.',
                    description: 'Try a label, hostname, username or protocol.',
                  );
                }

                return Column(
                  children: [
                    _HostListHeader(
                      tokens: tokens,
                      compact: !showContextColumn,
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final host = visible[index];
                          return _HostRow(
                            key: ValueKey(host.id),
                            host: host,
                            groups: groups,
                            connected: connectedIds.contains(host.id),
                            isConnecting: _connectingHostIds.contains(host.id),
                            selected: host.id == _selectedHostId,
                            compact: !showContextColumn,
                            onSelect: () {
                              setState(() => _selectedHostId = host.id);
                              // Too narrow for the inline drawer, so the detail
                              // becomes a sheet rather than a selection that
                              // leads nowhere.
                              if (!showDetailDrawer) {
                                _showHostDetailSheet(
                                  host: host,
                                  hosts: hosts,
                                  groups: groups,
                                  connected: connectedIds.contains(host.id),
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
                );
              },
            ),
          ),
        ),
      ],
    );
    return _wrapWithConfigDropTarget(context, workArea);
  }

  Widget _buildCompactFilterBar(
    BuildContext context,
    List<HostGroupModel> groups,
    List<HostModel> hosts,
  ) {
    final tokens = ShellVibeTokens.resolve(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        tokens.pagePadding,
        10,
        tokens.pagePadding,
        8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShellVibeSearchField(
            fieldKey: const Key('hosts_search_input'),
            hintText: 'Search hosts, addresses and protocols…',
            onChanged: (value) =>
                setState(() => _searchQuery = value.toLowerCase()),
          ),
          const SizedBox(height: 10),
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
    final tokens = ShellVibeTokens.resolve(context);
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
    return ShellVibeEmptyState(
      icon: LucideIcons.server,
      title: 'No hosts or groups configured.',
      description:
          'Add your first server to connect in one click. You can organize infrastructure into groups at any time.',
      // Each label is `Flexible` rather than a bare `Text`: shadcn lays a
      // button out as a shrink-wrapped Row, so on a 320px screen — or at a
      // large system text scale — an unbounded label overflows its own button.
      actions: [
        ShellVibeButton(
          label: 'Add your first host',
          icon: LucideIcons.plus,
          onPressed: () => _openHostForm(context),
        ),
        ShellVibeButton.secondary(
          label: 'Create group',
          icon: LucideIcons.folderPlus,
          onPressed: () => _openGroupForm(context),
        ),
        ShellVibeButton.secondary(
          key: const Key('empty_state_import_button'),
          label: 'Import SSH Config',
          icon: LucideIcons.fileInput,
          onPressed: () => _openImportConfig(context),
        ),
      ],
    );
  }

  // ── ssh config import ───────────────────────────────────────────────────

  /// Picks a `~/.ssh/config`-style file and opens the import preview dialog.
  Future<void> _openImportConfig(BuildContext context) async {
    // Deliberately no acceptedTypeGroups: the canonical file is literally
    // named `config` with NO extension, and extension/UTType filters grey it
    // out in the native dialogs (macOS/Linux/Windows alike). The import
    // dialog validates the content anyway.
    final file = await openFile(initialDirectory: _sshConfigDirectory());
    if (file == null || file.path.isEmpty) return;
    if (!context.mounted) return;
    await _showImportDialog(context, file.path);
  }

  /// Desktop drag-and-drop entry point; accepts files named `config`,
  /// `ssh_config` or ending in `.config`.
  Future<void> _handleConfigDrop(
    BuildContext context,
    List<XFile> files,
  ) async {
    final dropped = files.where((f) => _isConfigFileName(f.name)).firstOrNull;
    if (dropped == null || dropped.path.isEmpty) return;
    await _showImportDialog(context, dropped.path);
  }

  bool _isConfigFileName(String name) =>
      name == 'config' || name == 'ssh_config' || name.endsWith('.config');

  /// `~/.ssh` when it exists on this machine, else null (mobile: no picker
  /// initial directory; the sandbox has no user `.ssh` folder).
  String? _sshConfigDirectory() {
    if (isMobilePlatform) return null;
    // HOME is absent on Windows, where the equivalent is USERPROFILE.
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null) return null;
    final dir = Directory(p.join(home, '.ssh'));
    return dir.existsSync() ? dir.path : null;
  }

  Future<void> _showImportDialog(BuildContext context, String path) async {
    final String content;
    try {
      content = await File(path).readAsString();
    } catch (_) {
      if (context.mounted) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            title: const Text('Import Failed'),
            description: Text('Could not read $path'),
          ),
        );
      }
      return;
    }
    if (!context.mounted) return;
    final SshConfigImportResult? result;
    try {
      result = await showDialog<SshConfigImportResult>(
        context: context,
        builder: (_) => SshConfigImportDialog(filePath: path, content: content),
      );
    } catch (e) {
      if (context.mounted) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            title: const Text('Import Failed'),
            description: Text('Could not open the import dialog: $e'),
          ),
        );
      }
      return;
    }
    if (result != null && context.mounted) {
      // The import service writes through the DAOs directly, bypassing the
      // notifiers — invalidate so hosts/groups/identities reload immediately
      // instead of on the next app start.
      ref.invalidate(hostsProvider);
      ref.invalidate(hostGroupsProvider);
      ref.invalidate(identitiesProvider);
      _showImportSummary(context, result);
    }
  }

  void _showImportSummary(BuildContext context, SshConfigImportResult result) {
    final parts = <String>[
      if (result.hostsAdded > 0) '${result.hostsAdded} added',
      if (result.hostsUpdated > 0) '${result.hostsUpdated} updated',
      if (result.hostsSkipped > 0) '${result.hostsSkipped} skipped',
    ];
    final extras = <String>[
      if (result.identitiesAdded > 0) '${result.identitiesAdded} keys',
      if (result.tunnelsAdded > 0) '${result.tunnelsAdded} forwards',
      if (result.jumpHostsAdded > 0) '${result.jumpHostsAdded} jump hosts',
    ];
    final summary = parts.isEmpty ? 'Nothing imported' : parts.join(', ');
    final description = [
      summary,
      if (extras.isNotEmpty) extras.join(', '),
      if (result.warnings.isNotEmpty)
        '${result.warnings.length} '
            'note${result.warnings.length == 1 ? '' : 's'}',
    ].join(' · ');
    ShadToaster.of(context).show(
      ShadToast(
        title: const Text('Import Complete'),
        description: Text(description),
      ),
    );
  }

  /// Desktop only: wraps the work area in a drop target accepting ssh config
  /// files. Mobile gets the plain work area — `desktop_drop` has no mobile
  /// implementation.
  Widget _wrapWithConfigDropTarget(BuildContext context, Widget child) {
    if (isMobilePlatform) return child;
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDraggingConfig = true),
      onDragExited: (_) {
        if (_isDraggingConfig) setState(() => _isDraggingConfig = false);
      },
      onDragDone: (details) async {
        if (_isDraggingConfig) setState(() => _isDraggingConfig = false);
        await _handleConfigDrop(context, details.files);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: _isDraggingConfig
            ? BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(8),
              )
            : null,
        child: child,
      ),
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
    final resolved = await _resolveIdentity(host);
    if (!resolved.ok) return null;

    await ref
        .read(terminalTabsProvider.notifier)
        .openTabForHost(
          host,
          identity: resolved.identity,
          onHostKeyPrompt: _promptHostKey,
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

  // ── templates ───────────────────────────────────────────────────────────

  /// Decrypts a host's stored credentials for a template replay.
  ///
  /// `ok: false` aborts the pane instead of connecting without the credentials
  /// it was saved with.
  Future<({bool ok, IdentityModel? identity})> _resolveIdentity(
    HostModel host,
  ) async {
    if (host.identityId == null) return (ok: true, identity: null);
    try {
      final identity = await ref
          .read(identitiesProvider.notifier)
          .getDecryptedIdentity(host.identityId!);
      return (ok: true, identity: identity);
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            description: Text('Cannot read stored credentials: $e'),
          ),
        );
      }
      return (ok: false, identity: null);
    }
  }

  Future<bool> _promptHostKey(
    String hostname,
    int port,
    String keyType,
    String fingerprint,
    HostKeyVerificationStatus status,
  ) async {
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
  }

  /// Opens a template's tabs and panes and moves to the terminal.
  Future<void> _runTemplate(TemplateModel template) async {
    final result = await ref
        .read(templatesProvider.notifier)
        .runTemplate(
          template,
          resolveIdentity: _resolveIdentity,
          onHostKeyPrompt: _promptHostKey,
        );
    if (!mounted) return;

    if (result.openedPanes > 0) {
      GoRouter.maybeOf(context)?.go('/terminal');
    }
    if (!result.isComplete) {
      ShadToaster.of(context).show(
        ShadToast.destructive(
          title: Text(
            result.openedPanes == 0
                ? 'Could not run "${template.name}"'
                : 'Ran "${template.name}" with skipped panes',
          ),
          description: Text(result.warnings.join('\n')),
        ),
      );
    }
  }

  Future<void> _renameTemplate(TemplateModel template) async {
    final details = await SaveTemplateDialog.show(
      context,
      initialName: template.name,
      isRename: true,
    );
    if (details == null) return;
    await ref
        .read(templatesProvider.notifier)
        .renameTemplate(template, details.name);
  }

  Future<void> _deleteTemplate(
    BuildContext context,
    TemplateModel template,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => ShadDialog.alert(
        title: const Text('Delete Template'),
        description: Text('Delete the saved layout "${template.name}"?'),
        actions: adaptiveDialogActions(context, [
          ShellVibeButton.secondary(
            label: 'Cancel',
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          ShellVibeButton.danger(
            label: 'Delete',
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ]),
        actionsAxis: adaptiveDialogActionsAxis(context),
      ),
    );

    if (confirm == true) {
      await ref.read(templatesProvider.notifier).deleteTemplate(template.id);
    }
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
        actions: adaptiveDialogActions(context, [
          ShellVibeButton.secondary(
            label: 'Cancel',
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          ShellVibeButton.danger(
            label: 'Delete',
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ]),
        actionsAxis: adaptiveDialogActionsAxis(context),
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
const List<int> _kHostColumnFlex = [5, 5, 3, 2];

/// Rendered width of the row's trailing controls.
///
/// Measured, not guessed: the two [ShellVibeIconButton]s occupy one control
/// height each (34px under a pointer) and the [PopupMenuButton] 48px once
/// Material's minimum tap target is applied, plus the 12px the popup adds
/// around its icon.
const double _kHostActionsWidth = 124;

/// The same measurement for a phone row, which carries one icon action and the
/// overflow menu — never the spelled-out Open pill, which does not fit beside
/// an address on a 400px screen.
const double _kHostActionsWidthCompact = 92;

class _HostListHeader extends StatelessWidget {
  final ShellVibeTokens tokens;
  final bool compact;

  const _HostListHeader({required this.tokens, required this.compact});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.4,
      color: tokens.textSubtle,
    );
    // No rule under the header: the rows below are pills with their own
    // spacing, so a line here would only cut the panel in half.
    // The list below pads 10px, each row another 10 (14 when compact), so the
    // header has to carry the sum or the labels sit off their columns.
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 24 : 20, 0, compact ? 24 : 20, 6),
      child: Row(
        children: [
          SizedBox(width: compact ? 15 : 24),
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
              child: Text('TAG', style: style, maxLines: 1),
            ),
            Expanded(
              flex: _kHostColumnFlex[3],
              child: Text('LAST', style: style, maxLines: 1),
            ),
          ],
          SizedBox(
            width: compact ? _kHostActionsWidthCompact : _kHostActionsWidth,
          ),
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
    final tokens = ShellVibeTokens.resolve(context);
    final address =
        '${host.username != null && host.username!.isNotEmpty ? '${host.username}@' : ''}'
        '${host.hostname}:${host.port}';
    final groupName = groups
        .where((group) => group.id == host.groupId)
        .firstOrNull
        ?.name;
    final monoStyle = shellvibeMono(
      context,
      color: selected ? tokens.textSecondary : tokens.textMuted,
    );

    return Semantics(
      button: true,
      selected: selected,
      label:
          '${host.label}, ${host.protocol} host at ${host.hostname}, '
          '${connected ? 'connected' : 'not connected'}',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: InkWell(
          onTap: onSelect,
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 10),
            // Phone rows trade density for a 44px hit target on the row action.
            height: compact ? 62 : tokens.rowHeight,
            decoration: BoxDecoration(
              color: selected
                  ? tokens.brand.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(tokens.radiusMedium),
              border: Border.all(
                color: selected
                    ? tokens.brand.withValues(alpha: 0.22)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                // A lit bar rather than a dot: read down a column of nine hosts
                // it separates live from idle at a glance, and it doubles as
                // the row's left margin.
                SizedBox(
                  width: compact ? 15 : 24,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ShellVibeRowIndicator(
                      live: connected,
                      height: compact ? 26 : 20,
                    ),
                  ),
                ),
                Expanded(
                  flex: _kHostColumnFlex[0],
                  child: Text(
                    host.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: selected
                          ? tokens.textPrimary
                          : tokens.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  flex: _kHostColumnFlex[1],
                  child: Text(
                    // Compact drops the last-seen column, so the state text
                    // that pairs with the bar moves onto the address line.
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
                            child: _HostTagChip(label: groupName),
                          ),
                  ),
                  Expanded(
                    flex: _kHostColumnFlex[3],
                    child: Text(
                      // Status is never carried by colour alone: the bar is
                      // paired with this text so the row reads without hue.
                      connected ? 'connected' : host.protocol,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: shellvibeMono(
                        context,
                        size: 11,
                        color: connected ? tokens.brand : tokens.textSubtle,
                      ),
                    ),
                  ),
                ],
                SizedBox(
                  width: compact
                      ? _kHostActionsWidthCompact
                      : _kHostActionsWidth,
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
                      // The selected row is the only one that spells its
                      // primary action out; the rest keep quiet icons so a full
                      // list stays dense without turning into a wall of buttons.
                      // A phone row never spells it out — the pill plus the
                      // menu overflowed the row, and selecting a host there
                      // opens the detail sheet, which carries Connect anyway.
                      else if (selected && !compact)
                        ShellVibeButton.secondary(
                          buttonKey: Key('connect_host_${host.id}'),
                          label: 'Open',
                          icon: LucideIcons.terminal,
                          onPressed: onConnect,
                        )
                      else
                        ShellVibeIconButton(
                          buttonKey: Key('connect_host_${host.id}'),
                          icon: LucideIcons.play,
                          tooltip: 'Connect Terminal',
                          onPressed: onConnect,
                        ),
                      // Transfer only makes sense over SSH; a local host has
                      // no SFTP subsystem to talk to. On phones it drops out
                      // entirely — the row has one action there, and transfer
                      // lives in the detail sheet.
                      if (hostSupportsFileTransfer(host) &&
                          !selected &&
                          !compact)
                        ShellVibeIconButton(
                          buttonKey: Key('sftp_host_${host.id}'),
                          icon: LucideIcons.folderSync,
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
      ),
    );
  }
}

/// Neutral tag pill on a host row.
///
/// Deliberately not a [ShellVibeStatusChip]: a group name is a label, not a state,
/// so it never borrows a status hue.
class _HostTagChip extends StatelessWidget {
  final String label;

  const _HostTagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.textPrimary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: tokens.textMuted,
        ),
      ),
    );
  }
}

/// Context-column entry for a saved layout.
///
/// Shaped like [ShellVibeNavItem] so it reads as part of the column, but it runs an
/// action rather than selecting a filter, and carries its own rename/delete
/// menu.
class _TemplateNavItem extends StatelessWidget {
  final TemplateModel template;
  final VoidCallback onRun;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _TemplateNavItem({
    required this.template,
    required this.onRun,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Semantics(
      button: true,
      label: 'Run template ${template.name}, ${templateSummary(template)}',
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              key: Key('run_template_${template.id}'),
              onTap: onRun,
              borderRadius: BorderRadius.circular(tokens.radiusSmall),
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.layoutTemplate,
                      size: 15,
                      color: tokens.textMuted,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        template.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: tokens.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            key: Key('template_menu_${template.id}'),
            tooltip: 'Template actions',
            padding: EdgeInsets.zero,
            iconSize: 14,
            icon: const Icon(LucideIcons.ellipsis, size: 14),
            onSelected: (value) {
              if (value == 'rename') onRename();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(LucideIcons.pencil, size: 16),
                    SizedBox(width: 8),
                    Text('Rename template'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(LucideIcons.trash2, size: 16, color: tokens.danger),
                    const SizedBox(width: 8),
                    Text(
                      'Delete template',
                      style: TextStyle(color: tokens.danger),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
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
    final tokens = ShellVibeTokens.resolve(context);
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: InkWell(
        key: chipKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? tokens.brand.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? tokens.brand.withValues(alpha: 0.26)
                  : tokens.textPrimary.withValues(alpha: 0.07),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? tokens.brandSoft : tokens.textMuted,
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
    final tokens = ShellVibeTokens.resolve(context);
    final jumpHost = hosts
        .where((candidate) => candidate.id == host.jumpHostId)
        .firstOrNull;
    final group = groups
        .where((candidate) => candidate.id == host.groupId)
        .firstOrNull;

    final address =
        '${host.username != null && host.username!.isNotEmpty ? '${host.username}@' : ''}'
        '${host.hostname}:${host.port}';

    return ListView(
      key: const Key('host_detail_drawer'),
      padding: const EdgeInsets.all(18),
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
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    address,
                    style: shellvibeMono(
                      context,
                      size: 11,
                      color: tokens.textSubtle,
                    ),
                  ),
                ],
              ),
            ),
            ShellVibeIconButton(
              icon: LucideIcons.x,
              tooltip: 'Close details',
              onPressed: onClose,
            ),
          ],
        ),
        const SizedBox(height: 14),
        // The state pill carries the uptime as well as the state: on a detail
        // panel the two are read together, and splitting them wastes a row.
        _HostStatePill(connected: connected),
        const SizedBox(height: 14),
        ShellVibeButton(
          buttonKey: const Key('detail_open_terminal'),
          icon: LucideIcons.terminal,
          label: 'Open terminal',
          expand: true,
          onPressed: onConnect,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (hostSupportsFileTransfer(host)) ...[
              Expanded(
                child: ShellVibeButton.secondary(
                  buttonKey: const Key('detail_open_sftp'),
                  label: 'Files',
                  expand: true,
                  onPressed: onOpenSftp,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: ShellVibeButton.secondary(
                label: 'Tunnel',
                expand: true,
                onPressed: () => GoRouter.maybeOf(context)?.go('/tunnels'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ShellVibeButton.secondary(
                label: 'Edit',
                expand: true,
                onPressed: onEdit,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const ShellVibeSectionLabel(
          label: 'Connection',
          padding: EdgeInsets.only(bottom: 8),
        ),
        ShellVibeDetailRow(label: 'protocol', value: host.protocol),
        ShellVibeDetailRow(label: 'port', value: '${host.port}'),
        ShellVibeDetailRow(label: 'user', value: host.username ?? '—'),
        ShellVibeDetailRow(label: 'group', value: group?.name ?? '—'),
        ShellVibeDetailRow(label: 'jump host', value: jumpHost?.label ?? '—'),
        ShellVibeDetailRow(
          label: 'identity',
          value: host.identityId == null ? 'none' : 'from vault',
        ),
        const SizedBox(height: 20),
        ShellVibeButton.danger(
          label: 'Delete host',
          expand: true,
          onPressed: onDelete,
        ),
      ],
    );
  }
}

/// The connection state banner at the top of the host detail panel.
class _HostStatePill extends StatelessWidget {
  final bool connected;

  const _HostStatePill({required this.connected});

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final color = connected ? tokens.brand : tokens.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          ShellVibeStatusDot(
            state: connected
                ? ShellVibeDotState.online
                : ShellVibeDotState.idle,
          ),
          const SizedBox(width: 8),
          Text(
            connected ? 'connected' : 'not connected',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: connected ? tokens.brandSoft : tokens.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
