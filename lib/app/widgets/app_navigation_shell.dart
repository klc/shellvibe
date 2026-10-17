import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../features/hosts/domain/services/host_launcher.dart';
import '../../features/settings/presentation/notifiers/settings_notifier.dart';
import '../../features/templates/domain/models/template_model.dart';
import '../../features/templates/presentation/notifiers/templates_notifier.dart';
import '../../features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../features/tunnels/presentation/providers/tunnels_providers.dart';
import '../../features/tunnels/presentation/tunnel_availability.dart';
import '../../features/workspaces/presentation/providers/workspace_provider.dart';
import '../keyboard/app_keymap.dart';
import '../theme/shellvibe_tokens.dart';
import '../window/window_chrome.dart';
import '../../features/templates/presentation/template_launch.dart';
import 'command_palette.dart';
import 'shellvibe_ui.dart';
import 'window_caption_strip.dart';

class NavigationItemData {
  final String label;
  final IconData icon;
  final String path;

  /// What the module is, in a few words: the palette's detail line.
  final String description;

  const NavigationItemData({
    required this.label,
    required this.icon,
    required this.path,
    required this.description,
  });

  /// `⌘2` or `Ctrl+Shift+2`, whichever this platform's keyboard says. The
  /// digit is the item's place in [appNavigationItems], which is also what
  /// [moduleShortcut] binds.
  String get shortcut => moduleShortcutLabel(appNavigationItems.indexOf(this));

  String get tooltip => '$description ($shortcut)';
}

/// Declared in router branch order — the index of an entry here *is* its
/// `StatefulShellBranch` index. Presentation order is expressed separately by
/// [kRailLayout] and [kMobileTabPaths] so the rail can be re-ordered without
/// silently re-routing anything.
const List<NavigationItemData> appNavigationItems = [
  NavigationItemData(
    label: 'Hosts',
    icon: LucideIcons.server,
    path: '/hosts',
    description: 'SSH & Remote Hosts',
  ),
  NavigationItemData(
    label: 'Terminal',
    icon: LucideIcons.terminal,
    path: '/terminal',
    description: 'Terminal Workstation',
  ),
  NavigationItemData(
    label: 'Vault',
    icon: LucideIcons.shieldCheck,
    path: '/vault',
    description: 'Credentials & Key Vault',
  ),
  NavigationItemData(
    label: 'Tunnels',
    icon: LucideIcons.network,
    path: '/tunnels',
    description: 'Port Forwarding Tunnels',
  ),
  NavigationItemData(
    label: 'Snippets',
    icon: LucideIcons.zap,
    path: '/snippets',
    description: 'Snippets & Runbooks',
  ),
  NavigationItemData(
    label: 'Workspaces',
    icon: LucideIcons.panelTop,
    path: '/workspaces',
    description: 'Workspace Manager',
  ),
  NavigationItemData(
    label: 'Settings',
    icon: LucideIcons.settings,
    path: '/settings',
    description: 'Application Settings',
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

  @override
  Widget build(BuildContext context) {
    final isDesktop = usesRailLayout(context);
    final tokens = ShellVibeTokens.resolve(context);
    final tunnelsSupported = tunnelsSupportedFor(context);

    return Actions(
      actions: {
        OpenCommandPaletteIntent: CallbackAction<OpenCommandPaletteIntent>(
          onInvoke: (_) => _showCommandPalette(),
        ),
        GoToModuleIntent: CallbackAction<GoToModuleIntent>(
          onInvoke: (intent) {
            // An iPhone has no Tunnels (see tunnelsSupportedOnThisDevice), and
            // a hardware keyboard must not reach what the UI does not offer.
            final path = appNavigationItems[intent.index].path;
            if (path == '/tunnels' && !tunnelsSupported) return null;
            _onTabSelected(intent.index);
            return null;
          },
        ),
        CloseWindowIntent: CallbackAction<CloseWindowIntent>(
          onInvoke: (_) => _closeWindow(),
        ),
        OpenSettingsIntent: CallbackAction<OpenSettingsIntent>(
          onInvoke: (_) => _goToPath('/settings'),
        ),
      },
      child: AppKeymapShortcuts(
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
                          // Where the platform title bar used to be; it holds
                          // the window controls and is the drag handle. See
                          // WindowCaptionStrip.
                          const WindowCaptionStrip(),
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
    final tunnelsSupported = tunnelsSupportedFor(context);

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
            tooltip: 'Jump to… (${shortcutLabel(AppCommand.commandPalette)})',
            selected: false,
            onPressed: _showCommandPalette,
          ),
          _RailSeparator(color: tokens.border),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final path in kRailLayout)
                    if (path == '/tunnels' && !tunnelsSupported)
                      const SizedBox.shrink()
                    else if (path == null)
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
          : item.icon,
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

    // The screen insets are spent outside the slab, not inside it. A
    // NavigationBar wraps its row in a SafeArea, which within a floating bar
    // padded the gradient with the home indicator below *and* the dynamic
    // island's 59px above — most of the bar's height was empty. Both are
    // removed below; the bottom inset is paid once, as the gap under the slab.
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    // On phones the bar is a slab too: it floats clear of the screen edge with
    // the same raised gradient as the desktop overlays, so the night ground
    // stays visible underneath it.
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 6, 16, bottomInset > 0 ? 18 : 14),
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
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          child: NavigationBar(
            key: const Key('mobile_bottom_navigation_bar'),
            height: 58,
            backgroundColor: Colors.transparent,
            // The floating slab already separates the bar from the content, so
            // a selection pill on top of it would be a third layer for nothing.
            indicatorColor: Colors.transparent,
            overlayColor: WidgetStatePropertyAll(
              tokens.brand.withValues(alpha: 0.08),
            ),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            // Modules outside the four tabs (tunnels, snippets, workspaces) keep
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
                  label: appNavigationItems[navigationIndexForPath(path)].label,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Closes the window. ⌘W and Ctrl+Shift+W close the terminal tab, so the
  /// window has a chord of its own; see [AppCommand.closeWindow].
  void _closeWindow() {
    unawaited(closeHostWindow());
  }

  void _showCommandPalette() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => CommandPalette(
        onSelected: (index) {
          Navigator.of(dialogContext).pop();
          _onTabSelected(index);
        },
        onHostSelected: (host) {
          Navigator.of(dialogContext).pop();
          // The launcher, not a connect written out here: a host with no stored
          // identity has to be asked for one and an unknown host key has to be
          // shown, and a second copy of that would be a second chance to get it
          // wrong.
          unawaited(HostLauncher(context: context, ref: ref).connect(host));
        },
        onTemplateSelected: (template) {
          Navigator.of(dialogContext).pop();
          unawaited(_runTemplateFromPalette(template));
        },
        onShowShortcuts: () {
          Navigator.of(dialogContext).pop();
          GoRouter.maybeOf(context)?.go('/settings/keyboard');
        },
      ),
    );
  }

  /// Replays a saved layout and moves to the terminal it opened in.
  Future<void> _runTemplateFromPalette(TemplateModel template) async {
    final launcher = HostLauncher(context: context, ref: ref);
    final result = await ref
        .read(templatesProvider.notifier)
        .runTemplate(
          template,
          resolveIdentity: launcher.resolveIdentity,
          onHostKeyPrompt: launcher.promptHostKey,
        );
    if (!mounted) return;
    GoRouter.maybeOf(context)?.go('/terminal');
    if (result.openedPanes > 0) {
      unawaited(runTemplateOnOpen(context, ref, template));
    }
    if (!result.isComplete) {
      ShadToaster.of(context).show(
        ShadToast.destructive(
          description: Text('Some panes of "${template.name}" could not open.'),
        ),
      );
    }
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
