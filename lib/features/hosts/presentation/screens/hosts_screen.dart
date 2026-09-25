import 'dart:async';
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
import '../../../templates/presentation/widgets/template_editor_panel.dart';
import '../../../templates/presentation/notifiers/templates_notifier.dart';
import '../../../terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../../vault/domain/models/identity_model.dart';
import '../../../vault/presentation/notifiers/identities_notifier.dart';
import '../../data/services/ssh_config_import_service.dart';
import '../../domain/models/host_group_model.dart';
import '../../../bookmarks/presentation/notifiers/bookmarks_notifier.dart';
import '../../domain/models/host_model.dart';
import '../../domain/services/host_launcher.dart';
import '../dialogs/host_form_dialog.dart';
import '../dialogs/host_group_form_dialog.dart';
import '../dialogs/ssh_config_import_dialog.dart';
import '../notifiers/host_groups_notifier.dart';
import '../notifiers/hosts_notifier.dart';
import '../widgets/host_detail_panel.dart';
import '../widgets/host_list_filter.dart';
import '../widgets/host_list_header.dart';
import '../widgets/host_row.dart';
import '../widgets/template_nav_item.dart';

class HostsScreen extends ConsumerStatefulWidget {
  final void Function(HostModel host)? onConnectHost;

  const HostsScreen({super.key, this.onConnectHost});

  @override
  ConsumerState<HostsScreen> createState() => _HostsScreenState();
}

class _HostsScreenState extends ConsumerState<HostsScreen> {
  String _searchQuery = '';
  final Set<String> _connectingHostIds = {};

  HostFilter _filter = HostFilter.all;

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
                  child: HostDetailPanel(
                    host: selectedHost,
                    hosts: hosts,
                    groups: groups,
                    connected: _connectedHostIds().contains(selectedHost.id),
                    isFavorite: _favoriteHostIds().contains(selectedHost.id),
                    onToggleFavorite: () => unawaited(
                      ref
                          .read(bookmarksProvider.notifier)
                          .toggleHost(selectedHost.id),
                    ),
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
          selected: _selectedGroupId == null && _filter == HostFilter.all,
          onTap: () => _selectFilter(HostFilter.all),
        ),
        ShellVibeNavItem(
          itemKey: const Key('hosts_filter_connected'),
          icon: LucideIcons.radio,
          label: 'Connected',
          count: connectedIds.length,
          selected: _selectedGroupId == null && _filter == HostFilter.connected,
          onTap: () => _selectFilter(HostFilter.connected),
        ),
        ShellVibeNavItem(
          itemKey: const Key('hosts_filter_favorites'),
          icon: LucideIcons.star,
          label: 'Favorites',
          count: _favoriteHostIds().length,
          selected: _selectedGroupId == null && _filter == HostFilter.favorites,
          onTap: () => _selectFilter(HostFilter.favorites),
        ),
        ShellVibeNavItem(
          itemKey: const Key('hosts_filter_ungrouped'),
          icon: LucideIcons.inbox,
          label: 'Ungrouped',
          count: hosts.where((host) => host.groupId == null).length,
          selected: _selectedGroupId == null && _filter == HostFilter.ungrouped,
          onTap: () => _selectFilter(HostFilter.ungrouped),
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
              _filter = HostFilter.all;
            }),
          ),
        // Saved terminal layouts. Unlike the entries above these are actions,
        // not filters: tapping one opens its tabs and panes in the terminal.
        if (templates.isNotEmpty) ...[
          const ShellVibeSectionLabel(label: 'Templates'),
          for (final template in templates)
            TemplateNavItem(
              template: template,
              onRun: () => _runTemplate(template),
              onEdit: () => TemplateEditorPanel.show(context, template),
              onDelete: () => _deleteTemplate(context, template),
            ),
        ],
      ],
    );
  }

  void _selectFilter(HostFilter filter) {
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
          HostCompactFilterBar(
            groups: groups,
            hosts: hostsAsync.value ?? const [],
            selectedGroupId: _selectedGroupId,
            filter: _filter,
            onSearchChanged: (value) =>
                setState(() => _searchQuery = value.toLowerCase()),
            onSelectFilter: _selectFilter,
            onSelectGroup: (groupId) => setState(() {
              _selectedGroupId = groupId;
              _filter = HostFilter.all;
            }),
          ),
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
                final favoriteIds = _favoriteHostIds();
                if (visible.isEmpty) {
                  return const ShellVibeEmptyState(
                    icon: LucideIcons.searchX,
                    title: 'No hosts match your search.',
                    description: 'Try a label, hostname, username or protocol.',
                  );
                }

                return Column(
                  children: [
                    HostListHeader(tokens: tokens, compact: !showContextColumn),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final host = visible[index];
                          return HostRow(
                            key: ValueKey(host.id),
                            host: host,
                            groups: groups,
                            connected: connectedIds.contains(host.id),
                            isConnecting: _connectingHostIds.contains(host.id),
                            selected: host.id == _selectedHostId,
                            compact: !showContextColumn,
                            isFavorite: favoriteIds.contains(host.id),
                            onToggleFavorite: () => unawaited(
                              ref
                                  .read(bookmarksProvider.notifier)
                                  .toggleHost(host.id),
                            ),
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
      // A Consumer, not the screen's own ref: the sheet is on a route of its
      // own and does not rebuild when the screen does, so the star would stay
      // on whatever it was when the sheet opened.
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.72,
          child: Consumer(
            builder: (context, sheetRef, _) => HostDetailPanel(
              host: host,
              hosts: hosts,
              groups: groups,
              connected: connected,
              isFavorite: (sheetRef.watch(bookmarksProvider).value ?? const [])
                  .any((bookmark) => bookmark.hostId == host.id),
              onToggleFavorite: () => unawaited(
                sheetRef.read(bookmarksProvider.notifier).toggleHost(host.id),
              ),
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
      HostFilter.all => 'All',
      HostFilter.connected => 'Connected',
      HostFilter.favorites => 'Favorites',
      HostFilter.ungrouped => 'Ungrouped',
    };
  }

  /// Ids of the hosts starred in this workspace.
  ///
  /// Favourites never reorder the list: they get a filter of their own and the
  /// rows stay exactly where people learned to find them.
  Set<String> _favoriteHostIds() {
    final bookmarks = ref.watch(bookmarksProvider).value ?? const [];
    return bookmarks
        .where((bookmark) => bookmark.hostId != null)
        .map((bookmark) => bookmark.hostId!)
        .toSet();
  }

  /// Hosts in the selected group/filter, before the search query is applied.
  List<HostModel> _scopedHosts(List<HostModel> hosts) {
    if (_selectedGroupId != null) {
      return hosts.where((host) => host.groupId == _selectedGroupId).toList();
    }
    return switch (_filter) {
      HostFilter.all => hosts,
      HostFilter.connected =>
        hosts.where((host) => _connectedHostIds().contains(host.id)).toList(),
      HostFilter.favorites =>
        hosts.where((host) => _favoriteHostIds().contains(host.id)).toList(),
      HostFilter.ungrouped =>
        hosts.where((host) => host.groupId == null).toList(),
    };
  }

  List<HostModel> _visibleHosts(List<HostModel> hosts) {
    return _scopedHosts(hosts).where((host) {
      return hostMatchesQuery(host, _searchQuery);
    }).toList();
  }

  // ── actions ─────────────────────────────────────────────────────────────

  /// Opens (and connects) a terminal tab for [host] and returns its id, or
  /// null when credentials could not be read.
  Future<String?> _openSessionForHost(HostModel host) async {
    return _launcher.openSession(host);
  }

  Future<void> _defaultConnectHost(HostModel host) => _launcher.connect(host);

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

  /// The connect flow, built per call because it holds this context.
  HostLauncher get _launcher => HostLauncher(context: context, ref: ref);

  /// Decrypts a host's stored credentials for a template replay.
  ///
  /// `ok: false` aborts the pane instead of connecting without the credentials
  /// it was saved with.
  Future<({bool ok, IdentityModel? identity})> _resolveIdentity(
    HostModel host,
  ) => _launcher.resolveIdentity(host);

  Future<bool> _promptHostKey(
    String hostname,
    int port,
    String keyType,
    String fingerprint,
    HostKeyVerificationStatus status,
  ) => _launcher.promptHostKey(hostname, port, keyType, fingerprint, status);

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

  /// Opens the host form and, for a new host, connects to it — which is what
  /// that form's button says it will do. The dialog pops the saved host; an
  /// update or a cancel pops null and nothing is connected.
  Future<void> _openHostForm(
    BuildContext context, {
    HostModel? initialHost,
  }) async {
    final saved = await showDialog<HostModel>(
      context: context,
      builder: (ctx) => HostFormDialog(
        initialHost: initialHost,
        workspaceId: ref.read(activeWorkspaceIdProvider),
      ),
    );
    if (saved == null || !mounted) return;
    await _onConnectHost(saved);
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
