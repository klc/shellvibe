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

  const AppNavigationShell({
    super.key,
    required this.navigationShell,
  });

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
    if (kIsWeb) return MediaQuery.of(context).size.width >= 800;
    try {
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        return MediaQuery.of(context).size.width >= 600;
      }
    } catch (_) {}
    return MediaQuery.of(context).size.width >= 800;
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = _isDesktopPlatform(context);
    final colorScheme = ShadTheme.of(context).colorScheme;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.digit1, meta: true): () => _onTabSelected(0),
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () => _onTabSelected(0),
        const SingleActivator(LogicalKeyboardKey.digit2, meta: true): () => _onTabSelected(1),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () => _onTabSelected(1),
        const SingleActivator(LogicalKeyboardKey.digit3, meta: true): () => _onTabSelected(2),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true): () => _onTabSelected(2),
        const SingleActivator(LogicalKeyboardKey.digit4, meta: true): () => _onTabSelected(3),
        const SingleActivator(LogicalKeyboardKey.digit4, control: true): () => _onTabSelected(3),
        const SingleActivator(LogicalKeyboardKey.digit5, meta: true): () => _onTabSelected(4),
        const SingleActivator(LogicalKeyboardKey.digit5, control: true): () => _onTabSelected(4),
        const SingleActivator(LogicalKeyboardKey.digit6, meta: true): () => _onTabSelected(5),
        const SingleActivator(LogicalKeyboardKey.digit6, control: true): () => _onTabSelected(5),
        const SingleActivator(LogicalKeyboardKey.digit7, meta: true): () => _onTabSelected(6),
        const SingleActivator(LogicalKeyboardKey.digit7, control: true): () => _onTabSelected(6),
      },
      child: Scaffold(
        body: SafeArea(
          top: true,
          bottom: false,
          child: Column(
            children: [
              // Top Application Header Bar
              _buildTopHeader(context),
              // Main Body Area with Sidebar / BottomNav
              Expanded(
                child: isDesktop
                    ? Row(
                        children: [
                          _buildDesktopSidebar(context),
                          VerticalDivider(width: 1, thickness: 1, color: colorScheme.border),
                          Expanded(child: widget.navigationShell),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(child: widget.navigationShell),
                        ],
                      ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: isDesktop ? null : _buildMobileBottomBar(context),
      ),
    );
  }

  Widget _buildTopHeader(BuildContext context) {
    final colorScheme = ShadTheme.of(context).colorScheme;

    final activeWorkspaceId = ref.watch(activeWorkspaceIdProvider);
    final workspaces = ref.watch(workspacesProvider);

    // Active SSH connections count
    final terminalState = ref.watch(terminalTabsProvider);
    final activeSshCount = terminalState.tabs.where((t) => t.isConnected).length;

    // Active Tunnels count
    final activeTunnelsAsync = ref.watch(activeTunnelsStreamProvider);
    final activeTunnelsCount = activeTunnelsAsync.value?.length ?? 0;

    // Biometric lock status
    final settingsAsync = ref.watch(settingsProvider);
    final isBiometricsEnabled = (settingsAsync.value?.autoLockTimerSeconds ?? 0) > 0;

    final isCompactHeader = MediaQuery.of(context).size.width < 600;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colorScheme.card,
        border: Border(
          bottom: BorderSide(color: colorScheme.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          // App Logo & Brand
          Row(
            key: const Key('header_brand_logo'),
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(
                    '>_',
                    style: TextStyle(
                      color: colorScheme.primaryForeground,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              if (!isCompactHeader) ...[
                const SizedBox(width: 8),
                Text(
                  'Terly2',
                  style: TextStyle(
                    color: colorScheme.foreground,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(width: 8),

          // Active Workspace Selector Dropdown
          Flexible(
            child: Container(
              key: const Key('workspace_selector_dropdown'),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.muted.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: activeWorkspaceId,
                  dropdownColor: colorScheme.card,
                  icon: Icon(Icons.keyboard_arrow_down, color: colorScheme.primary, size: 14),
                  isDense: true,
                  isExpanded: true,
                  style: TextStyle(color: colorScheme.foreground, fontSize: 11),
                  onChanged: (newVal) {
                    if (newVal != null) {
                      ref.read(activeWorkspaceIdProvider.notifier).select(newVal);
                    }
                  },
                  items: workspaces.map((ws) {
                    return DropdownMenuItem<String>(
                      value: ws.id,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.workspaces_outline, size: 12, color: colorScheme.primary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              ws.name,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),

          const SizedBox(width: 6),

          // Status Badges & Biometric Indicator
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // SSH Connections Badge
              Tooltip(
                message: 'Active SSH Connections: $activeSshCount',
                child: Container(
                  key: const Key('ssh_status_badge'),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: activeSshCount > 0
                        ? Colors.green.withValues(alpha: 0.15)
                        : colorScheme.muted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: activeSshCount > 0 ? Colors.green : colorScheme.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.terminal,
                        size: 13,
                        color: activeSshCount > 0 ? Colors.green : colorScheme.mutedForeground,
                      ),
                      if (!isCompactHeader) ...[
                        const SizedBox(width: 4),
                        Text(
                          'SSH: $activeSshCount',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: activeSshCount > 0 ? Colors.green : colorScheme.mutedForeground,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),

              // Active Tunnels Badge
              Tooltip(
                message: 'Active Port Tunnels: $activeTunnelsCount',
                child: Container(
                  key: const Key('tunnels_status_badge'),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: activeTunnelsCount > 0
                        ? Colors.amber.withValues(alpha: 0.15)
                        : colorScheme.muted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: activeTunnelsCount > 0
                          ? Colors.amber
                          : colorScheme.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.alt_route,
                        size: 13,
                        color: activeTunnelsCount > 0 ? Colors.amber : colorScheme.mutedForeground,
                      ),
                      if (!isCompactHeader) ...[
                        const SizedBox(width: 4),
                        Text(
                          'Tunnels: $activeTunnelsCount',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: activeTunnelsCount > 0 ? Colors.amber : colorScheme.mutedForeground,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),

              // Biometric Lock Indicator
              Tooltip(
                message: isBiometricsEnabled ? 'Vault Biometric Security Active' : 'Biometrics Disabled',
                child: Container(
                  key: const Key('biometric_status_indicator'),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: isBiometricsEnabled
                        ? colorScheme.primary.withValues(alpha: 0.15)
                        : colorScheme.muted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isBiometricsEnabled
                          ? colorScheme.primary
                          : colorScheme.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isBiometricsEnabled ? Icons.fingerprint : Icons.lock_open,
                        size: 13,
                        color: isBiometricsEnabled ? colorScheme.primary : colorScheme.mutedForeground,
                      ),
                      if (!isCompactHeader) ...[
                        const SizedBox(width: 4),
                        Text(
                          isBiometricsEnabled ? 'Secured' : 'Unlocked',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isBiometricsEnabled ? colorScheme.primary : colorScheme.mutedForeground,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSidebar(BuildContext context) {
    final currentIndex = widget.navigationShell.currentIndex;
    final sidebarWidth = _isSidebarCollapsed ? 68.0 : 240.0;
    final colorScheme = ShadTheme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: sidebarWidth,
      color: colorScheme.card,
      child: Column(
        children: [
          const SizedBox(height: 8),

          // Collapse / Expand Toggle Button
          Align(
            alignment: _isSidebarCollapsed ? Alignment.center : Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: IconButton(
                key: const Key('sidebar_toggle_button'),
                icon: Icon(
                  _isSidebarCollapsed ? Icons.chevron_right : Icons.chevron_left,
                  color: colorScheme.mutedForeground,
                ),
                tooltip: _isSidebarCollapsed ? 'Expand Sidebar' : 'Collapse Sidebar',
                onPressed: () {
                  setState(() {
                    _isSidebarCollapsed = !_isSidebarCollapsed;
                  });
                },
              ),
            ),
          ),
          Divider(color: colorScheme.border, height: 1),
          const SizedBox(height: 8),

          // Navigation List Items
          Expanded(
            child: ListView.builder(
              itemCount: appNavigationItems.length,
              itemBuilder: (context, index) {
                final item = appNavigationItems[index];
                final isSelected = index == currentIndex;

                return Tooltip(
                  message: _isSidebarCollapsed ? '${item.label} (${item.shortcut})' : item.tooltip,
                  waitDuration: const Duration(milliseconds: 400),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    child: InkWell(
                      key: Key('nav_item_$index'),
                      onTap: () => _onTabSelected(index),
                      borderRadius: BorderRadius.circular(8),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: EdgeInsets.symmetric(
                          horizontal: _isSidebarCollapsed ? 8 : 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colorScheme.primary.withValues(alpha: 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: isSelected
                              ? Border.all(color: colorScheme.primary.withValues(alpha: 0.4))
                              : null,
                        ),
                        child: _isSidebarCollapsed
                            ? Center(
                                child: Icon(
                                  isSelected ? item.selectedIcon : item.icon,
                                  size: 20,
                                  color: isSelected ? colorScheme.primary : colorScheme.mutedForeground,
                                ),
                              )
                            : SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                physics: const NeverScrollableScrollPhysics(),
                                child: SizedBox(
                                  width: 204,
                                  child: Row(
                                    children: [
                                      Icon(
                                        isSelected ? item.selectedIcon : item.icon,
                                        size: 20,
                                        color: isSelected ? colorScheme.primary : colorScheme.mutedForeground,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          item.label,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight:
                                                isSelected ? FontWeight.bold : FontWeight.w500,
                                            color: isSelected ? colorScheme.foreground : colorScheme.mutedForeground,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: colorScheme.muted.withValues(alpha: 0.5),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          item.shortcut,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: colorScheme.mutedForeground,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileBottomBar(BuildContext context) {
    final currentIndex = widget.navigationShell.currentIndex;
    final colorScheme = ShadTheme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.card,
        border: Border(top: BorderSide(color: colorScheme.border, width: 1)),
      ),
      child: NavigationBar(
        key: const Key('mobile_bottom_navigation_bar'),
        selectedIndex: currentIndex,
        onDestinationSelected: _onTabSelected,
        backgroundColor: colorScheme.card,
        indicatorColor: colorScheme.primary.withValues(alpha: 0.25),
        destinations: appNavigationItems.map((item) {
          return NavigationDestination(
            key: Key('mobile_nav_destination_${item.label.toLowerCase()}'),
            icon: Icon(item.icon, color: colorScheme.mutedForeground),
            selectedIcon: Icon(item.selectedIcon, color: colorScheme.primary),
            label: item.label,
            tooltip: item.tooltip,
          );
        }).toList(),
      ),
    );
  }
}
