import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:window_manager/window_manager.dart';

import '../../features/settings/presentation/notifiers/settings_notifier.dart';
import '../../features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../features/tunnels/presentation/providers/tunnels_providers.dart';
import '../../shared/providers/workspace_provider.dart';
import '../theme/shellvibe_tokens.dart';
import '../window/window_chrome.dart';
import 'shellvibe_ui.dart';

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

  /// Whether the shell shows the icon rail instead of the phone tab bar.
  ///
  /// The policy lives in [usesRailLayout] because modals ask the same question
  /// — a bottom sheet belongs wherever the tab bar does — and two copies of it
  /// would drift.
  bool _usesRailLayout(BuildContext context) => usesRailLayout(context);

  @override
  Widget build(BuildContext context) {
    final isDesktop = _usesRailLayout(context);
    final tokens = ShellVibeTokens.resolve(context);

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
        const SingleActivator(LogicalKeyboardKey.keyW, meta: true, shift: true):
            _closeWindow,
        const SingleActivator(
          LogicalKeyboardKey.keyW,
          control: true,
          shift: true,
        ): _closeWindow,
      },
      child: Focus(
        autofocus: true,
        // The canvas wraps the whole scaffold, not just its body: on phones the
        // floating tab bar is inset from the screen edge, and the night ground
        // has to be what shows through around it.
        child: ShellVibeCanvas(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            // The wireframe skeleton is rail → context column → work with no
            // application header above it: switching modules must move only the
            // middle of the screen, never the chrome.
            //
            // Nocturne floats that skeleton: the whole shell sits on the night
            // canvas, inset by one panel gap, and the rail is a slab of its own
            // separated by whitespace rather than a divider rule.
            body: SafeArea(
              top: true,
              // The phone layout hands the bottom inset to the tab bar, which
              // pads itself clear of the gesture area. The rail layout has no
              // bar underneath it, so on a tablet running that layout the work
              // area would otherwise sit under the home indicator.
              bottom: isDesktop,
              child: isDesktop
                  ? Column(
                      children: [
                        // Where the platform title bar used to be. It carries no
                        // fill of its own, so the night canvas simply reaches the
                        // window's top edge and the macOS traffic lights float on
                        // it — the strip spans the shell rather than insetting the
                        // rail because three buttons need about 70px and the rail
                        // is 56. It is also the window's drag handle now that the
                        // bar it used to live on is gone; a double-click still
                        // zooms, which DragToMoveArea wires for us.
                        if (windowChromeTopInset > 0)
                          DragToMoveArea(
                            child: SizedBox(
                              height: windowChromeTopInset,
                              width: double.infinity,
                            ),
                          ),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.all(tokens.panelGap),
                            child: Row(
                              children: [
                                _buildRail(context),
                                SizedBox(width: tokens.panelGap),
                                Expanded(child: widget.navigationShell),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : widget.navigationShell,
            ),
            bottomNavigationBar: isDesktop
                ? null
                : _buildMobileBottomBar(context),
          ),
        ),
      ),
    );
  }

  Widget _buildRail(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final currentIndex = widget.navigationShell.currentIndex;
    final terminalState = ref.watch(terminalTabsProvider);
    final activeSshCount = terminalState.tabs
        .where((tab) => tab.isConnected)
        .length;
    final activeTunnels =
        ref.watch(activeTunnelsStreamProvider).value ?? const [];
    final settings = ref.watch(settingsProvider).value;
    final vaultAutoLockOn = (settings?.autoLockTimerSeconds ?? 0) > 0;

    return ShellVibePanel(
      width: tokens.railWidth,
      gradientExtent: 120,
      child: Column(
        children: [
          const SizedBox(height: 12),
          Semantics(
            label: 'ShellVibe application home',
            child: Image.asset(
              // The launcher icon itself, so the rail mark and the icon the
              // user clicked to get here are the same artwork. It ships its
              // own squircle and margin, so it needs no plate behind it.
              'assets/brand/icon.png',
              key: const Key('header_brand_logo'),
              width: 36,
              height: 36,
              filterQuality: FilterQuality.medium,
            ),
          ),
          const SizedBox(height: 14),
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
          const SizedBox(height: 12),
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

    final tokens = ShellVibeTokens.resolve(context);

    // On phones the bar is a slab too: it floats clear of the screen edge with
    // the same raised gradient as the desktop overlays, so the night ground
    // stays visible underneath it.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [tokens.surfaceRaised, tokens.surfaceLow],
          ),
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: tokens.shadowColorStrong,
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        // Drawn over the child: a clipped child covers a background border
        // along the corner arcs and breaks the outline there.
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: tokens.textPrimary.withValues(alpha: 0.08)),
        ),
        child: NavigationBar(
          key: const Key('mobile_bottom_navigation_bar'),
          height: 64,
          backgroundColor: Colors.transparent,
          // The floating slab already separates the bar from the content, so
          // a selection pill on top of it would be a third layer for nothing.
          indicatorColor: Colors.transparent,
          overlayColor: WidgetStatePropertyAll(
            tokens.brand.withValues(alpha: 0.08),
          ),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          // Modules outside the five tabs (tunnels, snippets, workspaces) keep
          // the last tab highlighted rather than clearing the selection.
          selectedIndex: selectedTab >= 0
              ? selectedTab
              : branchIndexes.length - 1,
          onDestinationSelected: (index) =>
              _onTabSelected(branchIndexes[index]),
          destinations: [
            for (final path in kMobileTabPaths)
              NavigationDestination(
                key: Key('mobile_nav_destination_${path.substring(1)}'),
                icon: Icon(
                  appNavigationItems[navigationIndexForPath(path)].icon,
                  size: 20,
                  color: tokens.textMuted,
                ),
                selectedIcon: Icon(
                  appNavigationItems[navigationIndexForPath(path)].icon,
                  size: 20,
                  color: tokens.brandBright,
                ),
                label: _mobileTabLabel(path),
              ),
          ],
        ),
      ),
    );
  }

  static String _mobileTabLabel(String path) => switch (path) {
    '/hosts' => 'Hosts',
    '/terminal' => 'Terminal',

    '/vault' => 'Vault',
    '/settings' => 'Settings',
    _ => path.substring(1),
  };

  /// Closes the window, since Cmd-W is spoken for by the terminal tab strip.
  void _closeWindow() {
    unawaited(closeHostWindow());
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
}

class _RailSeparator extends StatelessWidget {
  final Color color;

  const _RailSeparator({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 8),
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
    final tokens = ShellVibeTokens.resolve(context);
    Widget glyph = Icon(
      icon,
      key: iconKey,
      size: 17,
      color: selected ? tokens.brandBright : tokens.textMuted,
    );
    if (badgeKey != null) {
      // Nocturne reports rail activity as a glowing dot rather than a counted
      // pill: the number is legible in the module itself, and at 38px the
      // count only adds noise.
      // Badge only draws the small dot when its label is null — any non-null
      // label, an empty box included, switches it to the stadium pill sized by
      // largeSize, which is what an empty label renders as.
      glyph = Badge(
        key: badgeKey,
        isLabelVisible: badgeCount > 0,
        smallSize: 8,
        backgroundColor: tokens.brand,
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
                    ? tokens.brand.withValues(alpha: 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(tokens.radiusMedium),
                border: Border.all(
                  color: selected
                      ? tokens.brand.withValues(alpha: 0.30)
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
    final tokens = ShellVibeTokens.resolve(context);
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
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tokens.surfaceRaised,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: tokens.textPrimary.withValues(alpha: 0.08),
            ),
          ),
          child: Text(
            initials.isEmpty ? 'W' : initials,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: tokens.textSecondary,
            ),
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
    final tokens = ShellVibeTokens.resolve(context);
    final filtered = appNavigationItems.indexed.where((entry) {
      final item = entry.$2;
      final value = query.toLowerCase();
      return item.label.toLowerCase().contains(value) ||
          item.tooltip.toLowerCase().contains(value);
    }).toList();

    // Pinned near the top rather than centred: the palette is a jump target,
    // and the eye should land on the query line, not the middle of the screen.
    return Dialog(
      alignment: const Alignment(0, -0.7),
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 660, maxHeight: 620),
        child: ShellVibeOverlaySurface(
          gradientExtent: 200,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: tokens.textPrimary.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.search, size: 18, color: tokens.brand),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        key: const Key('command_palette_search'),
                        autofocus: true,
                        cursorColor: tokens.brand,
                        cursorWidth: 2,
                        style: TextStyle(
                          fontSize: 16,
                          color: tokens.textPrimary,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          hintText: 'Search hosts, sessions, files and tools…',
                          hintStyle: TextStyle(
                            fontSize: 16,
                            color: tokens.textSubtle,
                          ),
                        ),
                        onChanged: (value) => setState(() => query = value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const _PaletteKeyCap(label: 'esc'),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                  children: [
                    const ShellVibeSectionLabel(
                      label: 'Modules',
                      padding: EdgeInsets.fromLTRB(10, 8, 10, 6),
                    ),
                    for (var index = 0; index < filtered.length; index++)
                      _PaletteRow(
                        item: filtered[index].$2,
                        // The first hit is what Enter runs, so it is the only
                        // row that carries the brand ring and says so.
                        highlighted: index == 0,
                        onTap: () => widget.onSelected(filtered[index].$1),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: tokens.textPrimary.withValues(alpha: 0.025),
                  border: Border(
                    top: BorderSide(
                      color: tokens.textPrimary.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                child: DefaultTextStyle.merge(
                  style: shellvibeMono(
                    context,
                    size: 10.5,
                    color: tokens.textSubtle,
                  ),
                  child: const Row(
                    children: [
                      Text('↑↓ move'),
                      SizedBox(width: 18),
                      Text('↵ run'),
                      SizedBox(width: 18),
                      Text('⇥ actions'),
                      Spacer(),
                      Text('⌘K'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One 44px result row in the command palette.
class _PaletteRow extends StatelessWidget {
  final NavigationItemData item;
  final bool highlighted;
  final VoidCallback onTap;

  const _PaletteRow({
    required this.item,
    required this.highlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: highlighted
                ? tokens.brand.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: highlighted
                  ? tokens.brand.withValues(alpha: 0.22)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                item.icon,
                size: 16,
                color: highlighted ? tokens.brandBright : tokens.textMuted,
              ),
              const SizedBox(width: 12),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: highlighted
                      ? tokens.textPrimary
                      : tokens.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  item.tooltip.split(' (').first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: shellvibeMono(context, size: 11),
                ),
              ),
              const Spacer(),
              if (highlighted) ...[
                Text(
                  'open',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: tokens.brand,
                  ),
                ),
                const SizedBox(width: 10),
                const _PaletteKeyCap(label: '↵', brand: true),
              ] else
                Text(item.shortcut, style: shellvibeMono(context, size: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The small mono key hint used in the palette's query row and result rows.
class _PaletteKeyCap extends StatelessWidget {
  final String label;
  final bool brand;

  const _PaletteKeyCap({required this.label, this.brand = false});

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: brand
            ? tokens.brand.withValues(alpha: 0.18)
            : tokens.textPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: shellvibeMono(
          context,
          size: 10,
          color: brand ? tokens.brandSoft : tokens.textMuted,
        ),
      ),
    );
  }
}
