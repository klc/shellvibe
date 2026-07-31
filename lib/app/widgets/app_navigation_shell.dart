import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    icon: Icons.dns_outlined,
    selectedIcon: Icons.dns,
    path: '/hosts',
    shortcut: '⌘1',
    tooltip: 'SSH & Remote Hosts (Cmd+1)',
  ),
  NavigationItemData(
    label: 'Terminal',
    icon: Icons.terminal_outlined,
    selectedIcon: Icons.terminal,
    path: '/terminal',
    shortcut: '⌘2',
    tooltip: 'Terminal Workstation (Cmd+2)',
  ),
  NavigationItemData(
    label: 'Vault',
    icon: Icons.shield_outlined,
    selectedIcon: Icons.shield,
    path: '/vault',
    shortcut: '⌘3',
    tooltip: 'Credentials & Key Vault (Cmd+3)',
  ),
  NavigationItemData(
    label: 'SFTP',
    icon: Icons.folder_zip_outlined,
    selectedIcon: Icons.folder_zip,
    path: '/sftp',
    shortcut: '⌘4',
    tooltip: 'Dual-Pane SFTP Manager (Cmd+4)',
  ),
  NavigationItemData(
    label: 'Tunnels',
    icon: Icons.alt_route_outlined,
    selectedIcon: Icons.alt_route,
    path: '/tunnels',
    shortcut: '⌘5',
    tooltip: 'Port Forwarding Tunnels (Cmd+5)',
  ),
  NavigationItemData(
    label: 'Snippets',
    icon: Icons.bolt_outlined,
    selectedIcon: Icons.bolt,
    path: '/snippets',
    shortcut: '⌘6',
    tooltip: 'Snippets & Runbooks (Cmd+6)',
  ),
  NavigationItemData(
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
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
        body: Column(
          children: [
            // Top Application Header Bar
            _buildTopHeader(context),
            // Main Body Area with Sidebar / BottomNav
            Expanded(
              child: isDesktop
                  ? Row(
                      children: [
                        _buildDesktopSidebar(context),
                        const VerticalDivider(width: 1, thickness: 1, color: Color(0xFF2E3144)),
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
        bottomNavigationBar: isDesktop ? null : _buildMobileBottomBar(context),
      ),
    );
  }

  Widget _buildTopHeader(BuildContext context) {
    final activeWorkspaceId = ref.watch(activeWorkspaceIdProvider);
    final workspaces = ref.watch(workspacesProvider);

    // Active SSH connections count
    final terminalState = ref.watch(terminalTabsNotifierProvider);
    final activeSshCount = terminalState.tabs.where((t) => t.isConnected).length;

    // Active Tunnels count
    final activeTunnelsAsync = ref.watch(activeTunnelsStreamProvider);
    final activeTunnelsCount = activeTunnelsAsync.value?.length ?? 0;

    // Biometric lock status
    final settingsAsync = ref.watch(settingsNotifierProvider);
    final isBiometricsEnabled = (settingsAsync.value?.autoLockTimerSeconds ?? 0) > 0;

    final isCompactHeader = MediaQuery.of(context).size.width < 600;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF181825),
        border: Border(
          bottom: BorderSide(color: Color(0xFF2E3144), width: 1),
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
                  color: const Color(0xFF8AADF4),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Center(
                  child: Text(
                    '>_',
                    style: TextStyle(
                      color: Color(0xFF1E1E2E),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              if (!isCompactHeader) ...[
                const SizedBox(width: 8),
                const Text(
                  'Terly2',
                  style: TextStyle(
                    color: Colors.white,
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
                color: const Color(0xFF24273A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF363A4F)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: activeWorkspaceId,
                  dropdownColor: const Color(0xFF24273A),
                  icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF8AADF4), size: 14),
                  isDense: true,
                  isExpanded: true,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                  onChanged: (newVal) {
                    if (newVal != null) {
                      ref.read(activeWorkspaceIdProvider.notifier).state = newVal;
                    }
                  },
                  items: workspaces.map((ws) {
                    return DropdownMenuItem<String>(
                      value: ws.id,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.workspaces_outline, size: 12, color: Color(0xFF8AADF4)),
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
                        : Colors.white10,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: activeSshCount > 0 ? Colors.green : Colors.grey.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.terminal,
                        size: 13,
                        color: activeSshCount > 0 ? Colors.green : Colors.grey,
                      ),
                      if (!isCompactHeader) ...[
                        const SizedBox(width: 4),
                        Text(
                          'SSH: $activeSshCount',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: activeSshCount > 0 ? Colors.green : Colors.grey,
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
                        : Colors.white10,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: activeTunnelsCount > 0
                          ? Colors.amber
                          : Colors.grey.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.alt_route,
                        size: 13,
                        color: activeTunnelsCount > 0 ? Colors.amber : Colors.grey,
                      ),
                      if (!isCompactHeader) ...[
                        const SizedBox(width: 4),
                        Text(
                          'Tunnels: $activeTunnelsCount',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: activeTunnelsCount > 0 ? Colors.amber : Colors.grey,
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
                        ? const Color(0xFF8AADF4).withValues(alpha: 0.15)
                        : Colors.white10,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isBiometricsEnabled
                          ? const Color(0xFF8AADF4)
                          : Colors.grey.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isBiometricsEnabled ? Icons.fingerprint : Icons.lock_open,
                        size: 13,
                        color: isBiometricsEnabled ? const Color(0xFF8AADF4) : Colors.grey,
                      ),
                      if (!isCompactHeader) ...[
                        const SizedBox(width: 4),
                        Text(
                          isBiometricsEnabled ? 'Secured' : 'Unlocked',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isBiometricsEnabled ? const Color(0xFF8AADF4) : Colors.grey,
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

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: sidebarWidth,
      color: const Color(0xFF181825),
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
                  color: Colors.grey,
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
          const Divider(color: Color(0xFF2E3144), height: 1),
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
                              ? const Color(0xFF8AADF4).withValues(alpha: 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: isSelected
                              ? Border.all(color: const Color(0xFF8AADF4).withValues(alpha: 0.4))
                              : null,
                        ),
                        child: _isSidebarCollapsed
                            ? Center(
                                child: Icon(
                                  isSelected ? item.selectedIcon : item.icon,
                                  size: 20,
                                  color: isSelected ? const Color(0xFF8AADF4) : Colors.white60,
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
                                        color:
                                            isSelected ? const Color(0xFF8AADF4) : Colors.white60,
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
                                            color: isSelected ? Colors.white : Colors.white70,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.06),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          item.shortcut,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey,
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

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF2E3144), width: 1)),
      ),
      child: NavigationBar(
        key: const Key('mobile_bottom_navigation_bar'),
        selectedIndex: currentIndex,
        onDestinationSelected: _onTabSelected,
        backgroundColor: const Color(0xFF181825),
        indicatorColor: const Color(0xFF8AADF4).withValues(alpha: 0.25),
        destinations: appNavigationItems.map((item) {
          return NavigationDestination(
            key: Key('mobile_nav_destination_${item.label.toLowerCase()}'),
            icon: Icon(item.icon, color: Colors.white60),
            selectedIcon: Icon(item.selectedIcon, color: const Color(0xFF8AADF4)),
            label: item.label,
            tooltip: item.tooltip,
          );
        }).toList(),
      ),
    );
  }
}
