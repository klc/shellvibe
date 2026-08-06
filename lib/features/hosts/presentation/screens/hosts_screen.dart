import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/terly_tokens.dart';
import '../../../../app/widgets/terly_ui.dart';
import '../../../../app/widgets/workspace_switcher.dart';
import '../../../../core/network/ssh_session_manager.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../templates/domain/models/template_model.dart';
import '../../../templates/presentation/dialogs/save_template_dialog.dart';
import '../../../templates/presentation/notifiers/templates_notifier.dart';
import '../../../templates/presentation/widgets/template_picker_sheet.dart';
import '../../../terminal/presentation/dialogs/host_key_prompt_dialog.dart';
import '../../../terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../../vault/domain/models/identity_model.dart';
import '../../../vault/presentation/notifiers/identities_notifier.dart';
import '../../../../shared/providers/workspace_provider.dart';
import '../../data/services/ssh_config_import_service.dart';
import '../dialogs/host_form_dialog.dart';
import '../dialogs/host_group_form_dialog.dart';
import '../dialogs/ssh_config_import_dialog.dart';
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

  /// True while a config-looking file hovers the drop target (desktop).
  bool _isDraggingConfig = false;

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
    final templates = ref.watch(templatesProvider).value ?? const [];

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
        // Saved terminal layouts. Unlike the entries above these are actions,
        // not filters: tapping one opens its tabs and panes in the terminal.
        if (templates.isNotEmpty) ...[
          const TerlySectionLabel(label: 'Templates'),
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
      ShadButton.outline(
        key: const Key('import_ssh_config_button'),
        size: ShadButtonSize.sm,
        leading: const Icon(LucideIcons.fileInput, size: 16),
        onPressed: () => _openImportConfig(context),
        child: const Text('Import'),
      ),
      ShadButton(
        key: const Key('add_host_button'),
        size: ShadButtonSize.sm,
        leading: const Icon(LucideIcons.plus, size: 16),
        onPressed: () => _openHostForm(context),
        child: const Text('Add Host'),
      ),
    ];

    final workArea = Column(
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
    return _wrapWithConfigDropTarget(context, workArea);
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
        ShadButton.outline(
          key: const Key('empty_state_import_button'),
          onPressed: () => _openImportConfig(context),
          leading: const Icon(LucideIcons.fileInput, size: 16),
          child: const Text('Import SSH Config'),
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
  Future<void> _handleConfigDrop(BuildContext context, List<XFile> files) async {
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
        builder: (_) =>
            SshConfigImportDialog(filePath: path, content: content),
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
                borderRadius: BorderRadius.circular(10),
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

/// Context-column entry for a saved layout.
///
/// Shaped like [TerlyNavItem] so it reads as part of the column, but it runs an
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
    final tokens = TerlyTokens.resolve(context);
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
