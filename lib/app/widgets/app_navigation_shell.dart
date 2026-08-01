import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../features/settings/presentation/notifiers/settings_notifier.dart';
import '../../features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../features/tunnels/presentation/providers/tunnels_providers.dart';
import '../../shared/providers/workspace_provider.dart';
import '../theme/terly_tokens.dart';
import 'terly_ui.dart';

class NavigationItemData {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String path;
  final String shortcut;
  final String tooltip;

  const NavigationItemData({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.path,
    required this.shortcut,
    required this.tooltip,
  });
}

const List<NavigationItemData> appNavigationItems = [
  NavigationItemData(
    label: 'Hosts',
    icon: LucideIcons.server,
    selectedIcon: LucideIcons.server,
    path: '/hosts',
    shortcut: '⌘1',
    tooltip: 'SSH & Remote Hosts (Cmd+1)',
  ),
  NavigationItemData(
    label: 'Terminal',
    icon: LucideIcons.terminal,
    selectedIcon: LucideIcons.terminal,
    path: '/terminal',
    shortcut: '⌘2',
    tooltip: 'Terminal Workstation (Cmd+2)',
  ),
  NavigationItemData(
    label: 'Vault',
    icon: LucideIcons.shieldCheck,
    selectedIcon: LucideIcons.shieldCheck,
    path: '/vault',
    shortcut: '⌘3',
    tooltip: 'Credentials & Key Vault (Cmd+3)',
  ),
  NavigationItemData(
    label: 'SFTP',
    icon: LucideIcons.folderSync,
    selectedIcon: LucideIcons.folderSync,
    path: '/sftp',
    shortcut: '⌘4',
    tooltip: 'Dual-Pane SFTP Manager (Cmd+4)',
  ),
  NavigationItemData(
    label: 'Tunnels',
    icon: LucideIcons.network,
    selectedIcon: LucideIcons.network,
    path: '/tunnels',
    shortcut: '⌘5',
    tooltip: 'Port Forwarding Tunnels (Cmd+5)',
  ),
  NavigationItemData(
    label: 'Snippets',
    icon: LucideIcons.zap,
    selectedIcon: LucideIcons.zap,
    path: '/snippets',
    shortcut: '⌘6',
    tooltip: 'Snippets & Runbooks (Cmd+6)',
  ),
  NavigationItemData(
    label: 'Settings',
    icon: LucideIcons.settings,
    selectedIcon: LucideIcons.settings,
    path: '/settings',
    shortcut: '⌘7',
    tooltip: 'Application Settings (Cmd+7)',
  ),
];

class AppNavigationShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const AppNavigationShell({super.key, required this.navigationShell});

  @override
  ConsumerState<AppNavigationShell> createState() => _AppNavigationShellState();
}

class _AppNavigationShellState extends ConsumerState<AppNavigationShell> {
  bool _isSidebarCollapsed = false;

  void _onTabSelected(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  bool _isDesktopPlatform(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (kIsWeb) return width >= 800;
    try {
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        return width >= 720;
      }
    } catch (_) {
      // Web and unsupported platforms fall back to the width contract.
    }
    return width >= 800;
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = _isDesktopPlatform(context);
    final tokens = TerlyTokens.resolve(context);

    return CallbackShortcuts(
      bindings: {
        for (var index = 0; index < appNavigationItems.length; index++) ...{
          SingleActivator(
            LogicalKeyboardKey.findKeyByKeyId(0x00000031 + index)!,
            meta: true,
          ): () =>
              _onTabSelected(index),
          SingleActivator(
            LogicalKeyboardKey.findKeyByKeyId(0x00000031 + index)!,
            control: true,
          ): () =>
              _onTabSelected(index),
        },
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _showCommandPalette,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _showCommandPalette,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            top: true,
            bottom: false,
            child: Column(
              children: [
                _buildTopHeader(context, isDesktop: isDesktop),
                Expanded(
                  child: isDesktop
                      ? Row(
                          children: [
                            _buildDesktopDock(context),
                            VerticalDivider(width: 1, color: tokens.border),
                            Expanded(child: widget.navigationShell),
                          ],
                        )
                      : widget.navigationShell,
                ),
              ],
            ),
          ),
          bottomNavigationBar: isDesktop
              ? null
              : _buildMobileBottomBar(context),
        ),
      ),
    );
  }

  Widget _buildTopHeader(BuildContext context, {required bool isDesktop}) {
    final tokens = TerlyTokens.resolve(context);
    final activeWorkspaceId = ref.watch(activeWorkspaceIdProvider);
    final workspaces = ref.watch(workspacesProvider);
    final terminalState = ref.watch(terminalTabsProvider);
    final activeSshCount = terminalState.tabs
        .where((tab) => tab.isConnected)
        .length;
    final activeTunnels =
        ref.watch(activeTunnelsStreamProvider).value ?? const [];
    final settings = ref.watch(settingsProvider).value;
    final isSecured = (settings?.autoLockTimerSeconds ?? 0) > 0;
    final transferOrNetworkActivity = activeSshCount + activeTunnels.length;

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          Semantics(
            label: 'Terly application home',
            child: Row(
              key: const Key('header_brand_logo'),
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: tokens.brand.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(tokens.radiusMedium),
                    border: Border.all(
                      color: tokens.brand.withValues(alpha: 0.30),
                    ),
                  ),
                  child: Icon(
                    LucideIcons.squareTerminal,
                    size: 16,
                    color: tokens.brand,
                  ),
                ),
                if (isDesktop) ...[
                  const SizedBox(width: 9),
                  Text(
                    'Terly',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isDesktop ? 210 : 140),
            child: Container(
              key: const Key('workspace_selector_dropdown'),
              height: 34,
              padding: const EdgeInsets.only(left: 9, right: 5),
              decoration: BoxDecoration(
                color: tokens.surfaceRaised,
                borderRadius: BorderRadius.circular(tokens.radiusMedium),
                border: Border.all(color: tokens.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: activeWorkspaceId,
                  isDense: true,
                  isExpanded: true,
                  dropdownColor: tokens.surfaceRaised,
                  icon: Icon(
                    LucideIcons.chevronsUpDown,
                    size: 13,
                    color: tokens.textMuted,
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: tokens.textPrimary),
                  onChanged: (value) {
                    if (value != null) {
                      ref
                          .read(activeWorkspaceIdProvider.notifier)
                          .select(value);
                    }
                  },
                  items: workspaces
                      .map(
                        (workspace) => DropdownMenuItem<String>(
                          value: workspace.id,
                          child: Text(
                            workspace.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
          const Spacer(),
          if (isDesktop)
            OutlinedButton.icon(
              key: const Key('command_palette_button'),
              onPressed: _showCommandPalette,
              icon: const Icon(LucideIcons.search, size: 15),
              label: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [Text('Jump to…'), SizedBox(width: 18), Text('⌘K')],
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.textMuted,
                side: BorderSide(color: tokens.border),
                minimumSize: const Size(190, 34),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusMedium),
                ),
              ),
            ),
          const SizedBox(width: 8),
          _HeaderAction(
            actionKey: const Key('ssh_status_badge'),
            tooltip: '$activeSshCount active SSH sessions',
            icon: LucideIcons.terminal,
            count: activeSshCount,
            active: activeSshCount > 0,
            onPressed: () => _onTabSelected(1),
          ),
          _HeaderAction(
            actionKey: const Key('tunnels_status_badge'),
            tooltip: '${activeTunnels.length} active tunnels',
            icon: LucideIcons.activity,
            count: transferOrNetworkActivity,
            active: transferOrNetworkActivity > 0,
            onPressed: () => _showActivityCenter(
              activeSshCount: activeSshCount,
              activeTunnelsCount: activeTunnels.length,
            ),
          ),
          _HeaderAction(
            actionKey: const Key('biometric_status_indicator'),
            tooltip: isSecured
                ? 'Vault auto-lock active'
                : 'Vault auto-lock disabled',
            icon: isSecured ? LucideIcons.shieldCheck : LucideIcons.shield,
            active: isSecured,
            onPressed: () => _onTabSelected(2),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopDock(BuildContext context) {
    final currentIndex = widget.navigationShell.currentIndex;
    final tokens = TerlyTokens.resolve(context);
    final width = _isSidebarCollapsed ? 64.0 : 208.0;

    return Container(
      width: width,
      color: tokens.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
            child: Align(
              alignment: _isSidebarCollapsed
                  ? Alignment.center
                  : Alignment.centerRight,
              child: IconButton(
                key: const Key('sidebar_toggle_button'),
                tooltip: _isSidebarCollapsed
                    ? 'Expand navigation'
                    : 'Collapse navigation',
                icon: Icon(
                  _isSidebarCollapsed
                      ? LucideIcons.panelLeftOpen
                      : LucideIcons.panelLeftClose,
                  size: 17,
                ),
                onPressed: () =>
                    setState(() => _isSidebarCollapsed = !_isSidebarCollapsed),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              itemCount: appNavigationItems.length,
              itemBuilder: (context, index) {
                final item = appNavigationItems[index];
                final selected = currentIndex == index;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Tooltip(
                    message: _isSidebarCollapsed ? item.tooltip : '',
                    child: Semantics(
                      selected: selected,
                      button: true,
                      label: item.tooltip,
                      child: InkWell(
                        key: Key('nav_item_$index'),
                        onTap: () => _onTabSelected(index),
                        borderRadius: BorderRadius.circular(
                          tokens.radiusMedium,
                        ),
                        child: Container(
                          height: 42,
                          padding: EdgeInsets.symmetric(
                            horizontal: _isSidebarCollapsed ? 0 : 10,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? tokens.brand.withValues(alpha: 0.10)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(
                              tokens.radiusMedium,
                            ),
                            border: Border.all(
                              color: selected
                                  ? tokens.brand.withValues(alpha: 0.24)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: _isSidebarCollapsed
                                ? MainAxisAlignment.center
                                : MainAxisAlignment.start,
                            children: [
                              Icon(
                                selected ? item.selectedIcon : item.icon,
                                size: 18,
                                color: selected
                                    ? tokens.brand
                                    : tokens.textMuted,
                              ),
                              if (!_isSidebarCollapsed) ...[
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Text(
                                    item.label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: selected
                                              ? tokens.textPrimary
                                              : tokens.textMuted,
                                        ),
                                  ),
                                ),
                                Text(
                                  item.shortcut,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: tokens.textMuted.withValues(
                                          alpha: 0.72,
                                        ),
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (!_isSidebarCollapsed)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: tokens.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Quiet Ops ready',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMobileBottomBar(BuildContext context) {
    const branchIndexes = [0, 1, 3];
    final currentIndex = widget.navigationShell.currentIndex;
    final selectedIndex = switch (currentIndex) {
      0 => 0,
      1 => 1,
      3 => 2,
      _ => 3,
    };

    return NavigationBar(
      key: const Key('mobile_bottom_navigation_bar'),
      selectedIndex: selectedIndex,
      onDestinationSelected: (index) {
        if (index < branchIndexes.length) {
          _onTabSelected(branchIndexes[index]);
        } else {
          _showMobileTools();
        }
      },
      destinations: const [
        NavigationDestination(
          key: Key('mobile_nav_destination_hosts'),
          icon: Icon(LucideIcons.server),
          label: 'Connect',
        ),
        NavigationDestination(
          key: Key('mobile_nav_destination_terminal'),
          icon: Icon(LucideIcons.terminal),
          label: 'Sessions',
        ),
        NavigationDestination(
          key: Key('mobile_nav_destination_sftp'),
          icon: Icon(LucideIcons.folderSync),
          label: 'Files',
        ),
        NavigationDestination(
          key: Key('mobile_nav_destination_tools'),
          icon: Icon(LucideIcons.blocks),
          label: 'Tools',
        ),
      ],
    );
  }

  void _showCommandPalette() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _CommandPalette(
        onSelected: (index) {
          Navigator.of(dialogContext).pop();
          _onTabSelected(index);
        },
      ),
    );
  }

  void _showMobileTools() {
    final tokens = TerlyTokens.resolve(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: tokens.surface,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                child: Text(
                  'Tools',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final index in [2, 4, 5, 6])
                ListTile(
                  key: Key(
                    'mobile_tool_${appNavigationItems[index].label.toLowerCase()}',
                  ),
                  leading: Icon(appNavigationItems[index].icon, size: 18),
                  title: Text(appNavigationItems[index].label),
                  subtitle: Text(
                    appNavigationItems[index].tooltip.split(' (').first,
                  ),
                  trailing: const Icon(LucideIcons.chevronRight, size: 16),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _onTabSelected(index);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showActivityCenter({
    required int activeSshCount,
    required int activeTunnelsCount,
  }) {
    final tokens = TerlyTokens.resolve(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: tokens.surface,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Activity Center',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              TerlySurface(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: _ActivityMetric(
                        icon: LucideIcons.terminal,
                        value: activeSshCount,
                        label: 'SSH sessions',
                      ),
                    ),
                    SizedBox(
                      height: 42,
                      child: VerticalDivider(color: tokens.border),
                    ),
                    Expanded(
                      child: _ActivityMetric(
                        icon: LucideIcons.network,
                        value: activeTunnelsCount,
                        label: 'Tunnels',
                      ),
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

class _HeaderAction extends StatelessWidget {
  final Key actionKey;
  final String tooltip;
  final IconData icon;
  final int? count;
  final bool active;
  final VoidCallback onPressed;

  const _HeaderAction({
    required this.actionKey,
    required this.tooltip,
    required this.icon,
    this.count,
    required this.active,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
    return Tooltip(
      message: tooltip,
      child: IconButton(
        key: actionKey,
        onPressed: onPressed,
        icon: Badge(
          isLabelVisible: count != null && count! > 0,
          label: Text('${count ?? 0}'),
          backgroundColor: tokens.brand,
          textColor: const Color(0xFF06211E),
          child: Icon(
            icon,
            size: 17,
            color: active ? tokens.brand : tokens.textMuted,
          ),
        ),
      ),
    );
  }
}

class _ActivityMetric extends StatelessWidget {
  final IconData icon;
  final int value;
  final String label;

  const _ActivityMetric({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: tokens.brand),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value', style: Theme.of(context).textTheme.titleMedium),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ],
    );
  }
}

class _CommandPalette extends StatefulWidget {
  final ValueChanged<int> onSelected;

  const _CommandPalette({required this.onSelected});

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
    final filtered = appNavigationItems.indexed.where((entry) {
      final item = entry.$2;
      final value = query.toLowerCase();
      return item.label.toLowerCase().contains(value) ||
          item.tooltip.toLowerCase().contains(value);
    }).toList();

    return Dialog(
      alignment: const Alignment(0, -0.55),
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TerlySearchField(
                fieldKey: const Key('command_palette_search'),
                hintText: 'Search hosts, sessions, files and tools…',
                onChanged: (value) => setState(() => query = value),
              ),
            ),
            Divider(color: tokens.border),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.all(8),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final entry = filtered[index];
                  final item = entry.$2;
                  return ListTile(
                    leading: Icon(item.icon, size: 18),
                    title: Text(item.label),
                    subtitle: Text(item.tooltip.split(' (').first),
                    trailing: Text(
                      item.shortcut,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    onTap: () => widget.onSelected(entry.$1),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
