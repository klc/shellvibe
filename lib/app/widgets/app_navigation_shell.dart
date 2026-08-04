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

/// Declared in router branch order — the index of an entry here *is* its
/// `StatefulShellBranch` index. Presentation order is expressed separately by
/// [kRailLayout] and [kMobileTabPaths] so the rail can be re-ordered without
/// silently re-routing anything.
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
    label: 'Tunnels',
    icon: LucideIcons.network,
    selectedIcon: LucideIcons.network,
    path: '/tunnels',
    shortcut: '⌘4',
    tooltip: 'Port Forwarding Tunnels (Cmd+4)',
  ),
  NavigationItemData(
    label: 'Snippets',
    icon: LucideIcons.zap,
    selectedIcon: LucideIcons.zap,
    path: '/snippets',
    shortcut: '⌘5',
    tooltip: 'Snippets & Runbooks (Cmd+5)',
  ),
  NavigationItemData(
    label: 'Workspaces',
    icon: LucideIcons.panelTop,
    selectedIcon: LucideIcons.panelTop,
    path: '/workspaces',
    shortcut: '⌘6',
    tooltip: 'Workspace Manager (Cmd+6)',
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

/// Rail order from the wireframe. `null` renders the separator that divides
/// connection modules from credential and configuration modules.
const List<String?> kRailLayout = [
  '/hosts',
  '/terminal',
  '/tunnels',
  '/snippets',
  null,
  '/vault',
  '/workspaces',
  '/settings',
];

/// The first-class Android tabs. Vault and Settings are promoted out of the
/// old "Tools" sheet so the tab order mirrors the desktop rail.
///
/// File transfer is deliberately absent: it is always scoped to one SSH
/// connection now, so it is entered from a host row or the terminal toolbar
/// rather than from a standalone tab with no visible target.
const List<String> kMobileTabPaths = [
  '/hosts',
  '/terminal',
  '/vault',
  '/settings',
];

/// Resolves a route path to its shell branch index.
///
/// Every navigation site goes through this rather than a literal index, so
/// reordering the rail or the tab bar can never mis-route a branch.
int navigationIndexForPath(String path) {
  final index = appNavigationItems.indexWhere((item) => item.path == path);
  assert(index >= 0, 'Unknown navigation path: $path');
  return index < 0 ? 0 : index;
}

class AppNavigationShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const AppNavigationShell({super.key, required this.navigationShell});

  @override
  ConsumerState<AppNavigationShell> createState() => _AppNavigationShellState();
}

class _AppNavigationShellState extends ConsumerState<AppNavigationShell> {
  void _onTabSelected(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  void _goToPath(String path) => _onTabSelected(navigationIndexForPath(path));

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
          // The wireframe skeleton is rail → context column → work with no
          // application header above it: switching modules must move only the
          // middle of the screen, never the chrome.
          body: SafeArea(
            top: true,
            bottom: false,
            child: isDesktop
                ? Row(
                    children: [
                      _buildRail(context),
                      VerticalDivider(width: 1, color: tokens.border),
                      Expanded(child: widget.navigationShell),
                    ],
                  )
                : widget.navigationShell,
          ),
          bottomNavigationBar: isDesktop
              ? null
              : _buildMobileBottomBar(context),
        ),
      ),
    );
  }

  Widget _buildRail(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
    final currentIndex = widget.navigationShell.currentIndex;
    final terminalState = ref.watch(terminalTabsProvider);
    final activeSshCount = terminalState.tabs
        .where((tab) => tab.isConnected)
        .length;
    final activeTunnels =
        ref.watch(activeTunnelsStreamProvider).value ?? const [];
    final settings = ref.watch(settingsProvider).value;
    final vaultAutoLockOn = (settings?.autoLockTimerSeconds ?? 0) > 0;

    return Container(
      width: tokens.railWidth,
      color: tokens.surface,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Semantics(
            label: 'Terly application home',
            child: Container(
              key: const Key('header_brand_logo'),
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: tokens.brand.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(tokens.radiusMedium),
                border: Border.all(color: tokens.brand.withValues(alpha: 0.30)),
              ),
              child: Icon(
                LucideIcons.squareTerminal,
                size: 16,
                color: tokens.brand,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // The wireframe promises one command palette entry on every screen;
          // with the header gone, the rail is that entry.
          _RailButton(
            buttonKey: const Key('command_palette_button'),
            icon: LucideIcons.search,
            tooltip: 'Jump to… (Cmd+K)',
            selected: false,
            onPressed: _showCommandPalette,
          ),
          _RailSeparator(color: tokens.border),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final path in kRailLayout)
                    if (path == null)
                      _RailSeparator(color: tokens.border)
                    else
                      _buildRailModuleButton(
                        path: path,
                        currentIndex: currentIndex,
                        activeSshCount: activeSshCount,
                        activeTunnelCount: activeTunnels.length,
                        vaultAutoLockOn: vaultAutoLockOn,
                      ),
                ],
              ),
            ),
          ),
          _WorkspaceAvatar(onPressed: () => _goToPath('/workspaces')),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildRailModuleButton({
    required String path,
    required int currentIndex,
    required int activeSshCount,
    required int activeTunnelCount,
    required bool vaultAutoLockOn,
  }) {
    final index = navigationIndexForPath(path);
    final item = appNavigationItems[index];
    final selected = currentIndex == index;

    // With the status badges gone from the header, the rail itself reports
    // live counts so ops state stays visible from every module.
    final (badgeKey, badgeCount) = switch (path) {
      '/terminal' => (const Key('ssh_status_badge'), activeSshCount),
      '/tunnels' => (const Key('tunnels_status_badge'), activeTunnelCount),
      _ => (null, 0),
    };

    return _RailButton(
      buttonKey: Key('nav_item_$index'),
      icon: path == '/vault'
          ? (vaultAutoLockOn ? LucideIcons.shieldCheck : LucideIcons.shield)
          : (selected ? item.selectedIcon : item.icon),
      iconKey: path == '/vault'
          ? const Key('biometric_status_indicator')
          : null,
      tooltip: item.tooltip,
      selected: selected,
      badgeKey: badgeKey,
      badgeCount: badgeCount,
      onPressed: () => _onTabSelected(index),
    );
  }

  Widget _buildMobileBottomBar(BuildContext context) {
    final currentIndex = widget.navigationShell.currentIndex;
    final branchIndexes = kMobileTabPaths.map(navigationIndexForPath).toList();
    final selectedTab = branchIndexes.indexOf(currentIndex);

    return NavigationBar(
      key: const Key('mobile_bottom_navigation_bar'),
      // Modules outside the five tabs (tunnels, snippets, workspaces) keep the
      // last tab highlighted rather than clearing the selection.
      selectedIndex: selectedTab >= 0 ? selectedTab : branchIndexes.length - 1,
      onDestinationSelected: (index) => _onTabSelected(branchIndexes[index]),
      destinations: [
        for (final path in kMobileTabPaths)
          NavigationDestination(
            key: Key('mobile_nav_destination_${path.substring(1)}'),
            icon: Icon(appNavigationItems[navigationIndexForPath(path)].icon),
            label: _mobileTabLabel(path),
          ),
      ],
    );
  }

  static String _mobileTabLabel(String path) => switch (path) {
    '/hosts' => 'Hosts',
    '/terminal' => 'Terminal',

    '/vault' => 'Vault',
    '/settings' => 'Settings',
    _ => path.substring(1),
  };

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
}

class _RailSeparator extends StatelessWidget {
  final Color color;

  const _RailSeparator({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: color,
    );
  }
}

class _RailButton extends StatelessWidget {
  final Key buttonKey;
  final Key? iconKey;
  final Key? badgeKey;
  final IconData icon;
  final String tooltip;
  final bool selected;
  final int badgeCount;
  final VoidCallback onPressed;

  const _RailButton({
    required this.buttonKey,
    this.iconKey,
    this.badgeKey,
    required this.icon,
    required this.tooltip,
    required this.selected,
    this.badgeCount = 0,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
    Widget glyph = Icon(
      icon,
      key: iconKey,
      size: 17,
      color: selected ? tokens.brand : tokens.textMuted,
    );
    if (badgeKey != null) {
      glyph = Badge(
        key: badgeKey,
        isLabelVisible: badgeCount > 0,
        label: Text('$badgeCount'),
        backgroundColor: tokens.brand,
        textColor: const Color(0xFF06211E),
        child: glyph,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          selected: selected,
          label: tooltip,
          child: InkWell(
            key: buttonKey,
            onTap: onPressed,
            borderRadius: BorderRadius.circular(tokens.radiusMedium),
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? tokens.brand.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(tokens.radiusMedium),
                border: Border.all(
                  color: selected
                      ? tokens.brand.withValues(alpha: 0.28)
                      : Colors.transparent,
                ),
              ),
              child: glyph,
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceAvatar extends ConsumerWidget {
  final VoidCallback onPressed;

  const _WorkspaceAvatar({required this.onPressed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = TerlyTokens.resolve(context);
    final activeId = ref.watch(activeWorkspaceIdProvider);
    final workspaces = ref.watch(workspacesProvider).value ?? const [];
    final active =
        workspaces.where((workspace) => workspace.id == activeId).firstOrNull ??
        workspaces.firstOrNull;
    final name = active?.name ?? 'Workspace';
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    return Tooltip(
      message: '$name — manage workspaces',
      child: InkWell(
        key: const Key('workspace_avatar_button'),
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tokens.surfaceRaised,
            shape: BoxShape.circle,
            border: Border.all(color: tokens.border),
          ),
          child: Text(
            initials.isEmpty ? 'W' : initials,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: tokens.textMuted),
          ),
        ),
      ),
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
