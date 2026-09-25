import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/network/ssh_session_manager.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../hosts/domain/models/host_model.dart';
import '../../../snippets/domain/models/snippet_model.dart';
import '../../../snippets/domain/services/snippet_variable_parser.dart';
import '../../../snippets/presentation/widgets/snippet_picker_sheet.dart';
import '../../../snippets/presentation/widgets/variable_input_dialog.dart';
import '../../../templates/domain/models/template_model.dart';
import '../../../templates/presentation/dialogs/save_template_dialog.dart';
import '../../../templates/presentation/notifiers/templates_notifier.dart';
import '../../../templates/presentation/widgets/template_picker_sheet.dart';
import '../../../vault/domain/models/identity_model.dart';
import '../../../vault/presentation/notifiers/identities_notifier.dart';
import '../../domain/models/terminal_tab_session.dart';
import '../dialogs/host_key_prompt_dialog.dart';
import '../notifiers/terminal_tabs_notifier.dart';
import '../widgets/select_host_panel.dart';
import '../widgets/terminal_empty_state.dart';
import '../widgets/terminal_pane_helpers.dart';
import '../widgets/terminal_session_tree.dart';
import '../widgets/terminal_tab_strip.dart';

/// Whether this platform writes shortcuts with ⌘ rather than Ctrl+Shift.
bool get _isApplePlatform =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// How far the strip reaches down over the pane below it.
///
/// One pixel: the width of the pane's own top border, which the active tab has
/// to cover for the tab and the terminal to read as a single outline.
const double _kTabPaneOverlap = 1;

class TerminalTabView extends ConsumerStatefulWidget {
  const TerminalTabView({super.key});

  @override
  ConsumerState<TerminalTabView> createState() => _TerminalTabViewState();
}

class _TerminalTabViewState extends ConsumerState<TerminalTabView> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  TerminalTabSession? _resolveRootTab(TerminalTabsState tabsState) {
    final activeTab = tabsState.activeTab;
    if (activeTab == null) return null;
    var current = activeTab;
    while (current.splitParentId != null) {
      final parent = tabsState.tabs.firstWhere(
        (t) => t.id == current.splitParentId,
        orElse: () => current,
      );
      if (parent.id == current.id) break;
      current = parent;
    }
    return current;
  }

  @override
  Widget build(BuildContext context) {
    final tabsState = ref.watch(terminalTabsProvider);
    final activeRootTab = _resolveRootTab(tabsState);

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      child: CallbackShortcuts(
        bindings: {
          if (supportsLocalShell) ...{
            const SingleActivator(LogicalKeyboardKey.keyT, meta: true): () {
              ref.read(terminalTabsProvider.notifier).openLocalTab();
            },
            const SingleActivator(LogicalKeyboardKey.keyT, control: true): () {
              ref.read(terminalTabsProvider.notifier).openLocalTab();
            },
          },
          const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () {
            if (activeRootTab != null) {
              ref
                  .read(terminalTabsProvider.notifier)
                  .closeTab(activeRootTab.id);
            }
          },
          const SingleActivator(LogicalKeyboardKey.keyW, control: true): () {
            if (activeRootTab != null) {
              ref
                  .read(terminalTabsProvider.notifier)
                  .closeTab(activeRootTab.id);
            }
          },
          // Snippets used to sit in a strip pinned under the panes, which cost
          // every session three rows of terminal for something reached once in
          // a while. They are now summoned instead — here, and from the pane's
          // context menu.
          const SingleActivator(
            LogicalKeyboardKey.keyS,
            meta: true,
            shift: true,
          ): _openSnippetPicker,
          const SingleActivator(
            LogicalKeyboardKey.keyS,
            control: true,
            shift: true,
          ): _openSnippetPicker,
        },
        child: Scaffold(
          // The shell already painted the canvas; the terminal contributes the
          // tab strip and the pane slabs, nothing behind them.
          backgroundColor: Colors.transparent,
          body: Column(
            children: [
              // The tab and its terminal are one shape, not two stacked slabs.
              // A Column can't reorder painting, so the strip is stacked over
              // the pane and the pane starts one pixel under it: the active
              // tab is filled in the terminal's own colour and has no bottom
              // border, so that pixel is where it swallows the pane's top
              // hairline and the two outlines become a single folder tab.
              Expanded(
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                        top: kTerminalTabStripHeight - _kTabPaneOverlap,
                      ),
                      child: activeRootTab == null
                          ? ShellVibePanel(
                              gradientExtent: 220,
                              child: TerminalEmptyState(
                                onConnectToHost: _connectToHost,
                                onShowSelectHostModal: () =>
                                    _showSelectHostModal(context, ref),
                                onDeviceLinkAction: _handleDeviceLinkAction,
                              ),
                            )
                          : _buildTabBody(
                              context,
                              ref,
                              tabsState,
                              activeRootTab,
                            ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: TerminalTabStrip(
                        tabsState: tabsState,
                        activeRootTab: activeRootTab,
                        onPromptHostKey: _promptHostKey,
                        onStartSplitWithHost: _startSplitWithHost,
                        onSaveTemplate: _saveCurrentLayoutAsTemplate,
                        onRunTemplate: _runTemplate,
                        onDeviceLinkAction: _handleDeviceLinkAction,
                        onShowTabMenu: _showTabMenu,
                        onShowNewTabMenu: (buttonContext) =>
                            _showNewTabMenu(buttonContext, ref),
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

  Widget _buildTabBody(
    BuildContext context,
    WidgetRef ref,
    TerminalTabsState tabsState,
    TerminalTabSession activeRootTab,
  ) {
    final tokens = ShellVibeTokens.resolve(context);
    // Only the first tab starts at the panel's left edge, so only then is the
    // top-left corner the one the merged tab grows out of. On any later tab
    // that corner sits under an inactive tab — text on the canvas, nothing to
    // merge with — and it keeps its curve.
    final rootTabs = tabsState.tabs.where((t) => t.splitParentId == null);
    final activeIsFirstTab =
        rootTabs.isNotEmpty && rootTabs.first.id == activeRootTab.id;
    return buildTerminalSessionTree(
      context,
      ref,
      activeRootTab,
      tabsState.tabs,
      tokens,
      paneOrder: _paneOrder(tabsState, activeRootTab),
      activePaneId: tabsState.activeTabId,
      selectedPaneIds: tabsState.selectedPaneIds,
      buildPaneMenuEntries: _paneMenuEntries,
      squareTopLeft: activeIsFirstTab,
    );
  }

  /// The tab-level half of a pane's right-click menu: the same actions the tab
  /// bar carries in its top-right cluster, aimed at the pane that was clicked
  /// rather than at whichever one happens to be focused.
  ///
  /// Built when the menu opens, not when the pane is laid out, so it reads the
  /// live tab state — a split made since the pane was built still counts.
  List<AdaptiveMenuEntry<VoidCallback>> _paneMenuEntries(
    TerminalTabSession pane,
  ) {
    final tabsState = ref.read(terminalTabsProvider);
    final notifier = ref.read(terminalTabsProvider.notifier);
    final root = rootOfPane(tabsState.tabs, pane);
    final paneCount = tabsState.tabs
        .where((t) => rootOfPane(tabsState.tabs, t).id == root.id)
        .length;

    return [
      const AdaptiveMenuDivider(),
      // A local shell has no remote side to transfer files to.
      if (pane.sessionType == TerminalSessionType.ssh)
        AdaptiveMenuAction(
          itemKey: const Key('terminal_menu_sftp'),
          icon: LucideIcons.folderSync,
          label: 'File Transfer (SFTP)',
          value: () => openSftpForPane(context, pane),
        ),
      AdaptiveMenuAction(
        itemKey: const Key('terminal_menu_split_vertical'),
        icon: LucideIcons.columns2,
        label: 'Split Side by Side',
        value: () => unawaited(
          notifier.splitTab(
            pane.id,
            direction: Axis.horizontal,
            onHostKeyPrompt: _promptHostKey,
          ),
        ),
      ),
      AdaptiveMenuAction(
        itemKey: const Key('terminal_menu_split_horizontal'),
        icon: LucideIcons.rows2,
        label: 'Split Top / Bottom',
        value: () => unawaited(
          notifier.splitTab(
            pane.id,
            direction: Axis.vertical,
            onHostKeyPrompt: _promptHostKey,
          ),
        ),
      ),
      AdaptiveMenuAction(
        itemKey: const Key('terminal_menu_split_host'),
        icon: LucideIcons.serverCog,
        label: 'Split with Another Host…',
        value: () => _startSplitWithHost(pane.id),
      ),
      const AdaptiveMenuDivider(),
      AdaptiveMenuAction(
        itemKey: const Key('terminal_menu_snippets'),
        icon: LucideIcons.codeXml,
        label: 'Send Snippet…',
        shortcut: _isApplePlatform ? '⌘⇧S' : 'Ctrl+Shift+S',
        value: _openSnippetPicker,
      ),
      const AdaptiveMenuDivider(),
      AdaptiveMenuAction(
        itemKey: const Key('terminal_menu_save_template'),
        icon: LucideIcons.bookmarkPlus,
        label: 'Save Tabs & Panes as Template',
        value: _saveCurrentLayoutAsTemplate,
      ),
      AdaptiveMenuAction(
        itemKey: const Key('terminal_menu_run_template'),
        icon: LucideIcons.layoutTemplate,
        label: 'Run Template',
        value: () => TemplatePickerSheet.show(context, onSelect: _runTemplate),
      ),
      AdaptiveMenuAction(
        itemKey: const Key('terminal_menu_device_link'),
        icon: isMobilePlatform ? LucideIcons.scanQrCode : LucideIcons.qrCode,
        label: isMobilePlatform ? 'Scan Device Link QR' : 'Show Device Link QR',
        value: _handleDeviceLinkAction,
      ),
      const AdaptiveMenuDivider(),
      // Closing the only pane of a tab is closing the tab, so the two rows
      // would do the same thing; the pane row appears once there is a split.
      if (paneCount > 1)
        AdaptiveMenuAction(
          itemKey: const Key('terminal_menu_close_pane'),
          icon: LucideIcons.x,
          label: 'Close Pane',
          value: () => unawaited(notifier.closePane(pane.id)),
        ),
      AdaptiveMenuAction(
        itemKey: const Key('terminal_menu_close_tab'),
        icon: LucideIcons.trash2,
        label: 'Close Tab',
        value: () => unawaited(notifier.closeTab(root.id)),
      ),
    ];
  }

  /// Depth-first pane ids of the active tab, so pane headers can be numbered
  /// the same way they are laid out.
  List<String> _paneOrder(
    TerminalTabsState tabsState,
    TerminalTabSession root,
  ) {
    final order = <String>[];
    void walk(TerminalTabSession session) {
      order.add(session.id);
      for (final child in tabsState.tabs.where(
        (tab) => tab.splitParentId == session.id,
      )) {
        walk(child);
      }
    }

    walk(root);
    return order;
  }

  /// Sends snippet text to the focused pane, or to every selected pane while
  /// broadcast input is active (two or more panes selected).
  void _sendToPanes(TerminalTabsState tabsState, String code) {
    if (tabsState.isBroadcasting) {
      ref.read(terminalTabsProvider.notifier).sendTextToSelectedPanes(code);
      return;
    }
    final target =
        tabsState.activeTab ??
        (tabsState.tabs.isEmpty ? null : tabsState.tabs.first);
    if (target == null) return;
    target.terminal.paste(code);
  }

  /// Opens the snippet picker for whatever the next send would target, and
  /// sends the chosen snippet.
  void _openSnippetPicker() {
    final tabsState = ref.read(terminalTabsProvider);
    if (tabsState.tabs.isEmpty) return;
    final selectedCount = tabsState.selectedPaneIds.length;
    SnippetPickerSheet.show(
      context,
      targetLabel: tabsState.isBroadcasting
          ? 'Send to $selectedCount panes'
          : 'Send to the active pane',
      onSelect: (snippet) => _runSnippet(snippet),
    );
  }

  /// Fills a snippet's `\${INPUT:…}` placeholders, then sends it.
  ///
  /// The tabs state is re-read at send time rather than captured when the
  /// picker opened: filling variables is a second dialog, and the user can
  /// change the active pane or the broadcast selection while it is up.
  Future<void> _runSnippet(SnippetModel snippet) async {
    final variables = SnippetVariableParser.extractVariables(snippet.code);
    var values = <String, String>{};
    if (variables.isNotEmpty) {
      if (!mounted) return;
      final entered = await VariableInputDialog.show(
        context,
        variables: variables,
        title: 'Fill variables for "${snippet.title}"',
      );
      if (entered == null) return;
      values = entered;
    }
    if (!mounted) return;
    _sendToPanes(
      ref.read(terminalTabsProvider),
      SnippetVariableParser.substituteVariables(snippet.code, values),
    );
  }

  /// A tab's right-click menu: close it, or the tabs around it.
  ///
  /// The actions that would close nothing stay listed but disabled, so the
  /// menu keeps one shape and the eye learns where each row is.
  Future<void> _showTabMenu(
    TerminalTabSession tab, {
    required int index,
    required int tabCount,
    required Offset position,
  }) async {
    final notifier = ref.read(terminalTabsProvider.notifier);
    final chosen = await showAdaptiveActionMenu<VoidCallback>(
      context: context,
      globalPosition: position,
      actions: [
        AdaptiveMenuAction(
          itemKey: const Key('tab_menu_close'),
          icon: LucideIcons.x,
          label: 'Close Tab',
          shortcut: _isApplePlatform ? '⌘W' : 'Ctrl+W',
          value: () => unawaited(notifier.closeTab(tab.id)),
        ),
        AdaptiveMenuAction(
          itemKey: const Key('tab_menu_close_others'),
          icon: LucideIcons.squareX,
          label: 'Close Other Tabs',
          enabled: tabCount > 1,
          value: () => unawaited(notifier.closeOtherTabs(tab.id)),
        ),
        const AdaptiveMenuDivider(),
        AdaptiveMenuAction(
          itemKey: const Key('tab_menu_close_left'),
          icon: LucideIcons.arrowLeftToLine,
          label: 'Close Tabs to the Left',
          enabled: index > 0,
          value: () => unawaited(notifier.closeTabsToLeft(tab.id)),
        ),
        AdaptiveMenuAction(
          itemKey: const Key('tab_menu_close_right'),
          icon: LucideIcons.arrowRightToLine,
          label: 'Close Tabs to the Right',
          enabled: index < tabCount - 1,
          value: () => unawaited(notifier.closeTabsToRight(tab.id)),
        ),
      ],
    );
    chosen?.call();
  }

  /// Scans the Device Link QR on a phone, or shows it on a desktop.
  ///
  /// The one place this branch is written: the tab bar, the pane menu, the
  /// empty state and the "+" menu all offer the same action and share this
  /// method rather than repeating the platform check four times.
  void _handleDeviceLinkAction() {
    if (isMobilePlatform) {
      unawaited(context.push('/device-link/scan'));
    } else {
      unawaited(_openDeviceLinkQr(context, ref));
    }
  }

  Future<void> _openDeviceLinkQr(BuildContext context, WidgetRef ref) async {
    try {
      final payload = await ref
          .read(terminalTabsProvider.notifier)
          .createDeviceLinkPairingPayload();
      if (!context.mounted) return;
      await context.push('/device-link/pair', extra: payload);
    } catch (error) {
      if (!context.mounted) return;
      ShadToaster.of(context).show(
        ShadToast.destructive(
          description: Text('Device Link server could not start: $error'),
        ),
      );
    }
  }

  /// The "+" menu. Desktop anchors it to the button it came from; a phone
  /// gets the same rows as a sheet.
  Future<void> _showNewTabMenu(BuildContext context, WidgetRef ref) async {
    final action = await showAdaptiveActionMenu<_NewTabAction>(
      context: context,
      actions: [
        if (supportsLocalShell)
          const AdaptiveMenuAction(
            value: _NewTabAction.localShell,
            itemKey: Key('new_tab_menu_local'),
            icon: LucideIcons.monitor,
            label: 'Local Shell',
          ),
        const AdaptiveMenuAction(
          value: _NewTabAction.connectToHost,
          itemKey: Key('new_tab_menu_host'),
          icon: LucideIcons.server,
          label: 'Connect to Host...',
        ),
        AdaptiveMenuAction(
          value: _NewTabAction.deviceLink,
          itemKey: const Key('new_tab_menu_device_link'),
          icon: isMobilePlatform ? LucideIcons.scanQrCode : LucideIcons.qrCode,
          label: isMobilePlatform
              ? 'Scan Device Link QR'
              : 'Show Device Link QR',
        ),
      ],
    );
    if (action == null || !mounted) return;

    switch (action) {
      case _NewTabAction.localShell:
        ref.read(terminalTabsProvider.notifier).openLocalTab();
      case _NewTabAction.connectToHost:
        _showSelectHostModal(this.context, ref);
      case _NewTabAction.deviceLink:
        _handleDeviceLinkAction();
    }
  }

  /// Decrypts the identity attached to [host], if any.
  ///
  /// Returns `(ok: false, ...)` when the stored credentials cannot be read, so
  /// callers abort instead of connecting with silently missing credentials;
  /// the failure is surfaced as a toast here.
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

  /// Resolves the host's identity and opens an SSH tab.
  ///
  /// Host key verification is routed through [HostKeyPromptDialog] so the user
  /// actually gets asked.
  Future<void> _connectToHost(HostModel host) async {
    final resolved = await _resolveIdentity(host);
    if (!resolved.ok) return;

    await ref
        .read(terminalTabsProvider.notifier)
        .openTabForHost(
          host,
          identity: resolved.identity,
          onHostKeyPrompt: _promptHostKey,
        );
  }

  /// Splits [paneId] into a pane running on a different host: asks for the
  /// split direction first, then for the host.
  Future<void> _startSplitWithHost(String paneId) async {
    final direction = await _askSplitDirection();
    if (direction == null || !mounted) return;
    _showSelectHostModal(
      context,
      ref,
      onSelect: (host) => _splitWithHost(paneId, direction, host),
    );
  }

  Future<Axis?> _askSplitDirection() {
    return showAdaptivePanel<Axis>(
      context: context,
      title: 'Split Direction',
      desktopWidth: 340,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('split_host_direction_vertical'),
            leading: const Icon(LucideIcons.columns2, size: 18),
            title: const Text('Side by Side'),
            onTap: () => Navigator.of(ctx).pop(Axis.horizontal),
          ),
          ListTile(
            key: const Key('split_host_direction_horizontal'),
            leading: const Icon(LucideIcons.rows2, size: 18),
            title: const Text('Top / Bottom'),
            onTap: () => Navigator.of(ctx).pop(Axis.vertical),
          ),
        ],
      ),
    );
  }

  Future<void> _splitWithHost(
    String paneId,
    Axis direction,
    HostModel host,
  ) async {
    final resolved = await _resolveIdentity(host);
    if (!resolved.ok) return;

    await ref
        .read(terminalTabsProvider.notifier)
        .splitTab(
          paneId,
          direction: direction,
          host: host,
          identity: resolved.identity,
          onHostKeyPrompt: _promptHostKey,
        );
  }

  /// Saves every open tab and split pane as a named template.
  Future<void> _saveCurrentLayoutAsTemplate() async {
    final tabsState = ref.read(terminalTabsProvider);
    if (tabsState.tabs.isEmpty) return;

    final tabs = tabsState.tabs.where((t) => t.splitParentId == null).length;
    final splits = tabsState.tabs.length - tabs;
    final summary = splits == 0
        ? 'Saving $tabs ${tabs == 1 ? 'tab' : 'tabs'}.'
        : 'Saving $tabs ${tabs == 1 ? 'tab' : 'tabs'} and $splits '
              '${splits == 1 ? 'split pane' : 'split panes'}.';

    final details = await SaveTemplateDialog.show(context, summary: summary);
    if (details == null || !mounted) return;

    final template = await ref
        .read(templatesProvider.notifier)
        .saveCurrentLayout(
          name: details.name,
          description: details.description,
        );
    if (!mounted) return;

    ShadToaster.of(context).show(
      template == null
          ? const ShadToast.destructive(
              description: Text('Nothing open to save as a template.'),
            )
          : ShadToast(description: Text('Saved "${template.name}".')),
    );
  }

  /// Reopens a saved layout alongside whatever is already open.
  ///
  /// Panes that cannot be recreated — a deleted host, unreadable credentials —
  /// are reported rather than failing the whole run.
  Future<void> _runTemplate(TemplateModel template) async {
    final result = await ref
        .read(templatesProvider.notifier)
        .runTemplate(
          template,
          resolveIdentity: _resolveIdentity,
          onHostKeyPrompt: _promptHostKey,
        );
    if (!mounted) return;

    if (result.isComplete) {
      ShadToaster.of(context).show(
        ShadToast(
          description: Text(
            'Opened "${template.name}" — ${result.openedPanes} '
            '${result.openedPanes == 1 ? 'pane' : 'panes'}.',
          ),
        ),
      );
      return;
    }

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

  /// Host picker sheet. [onSelect] runs after the sheet is dismissed, so the
  /// same list drives both "new tab" and "split with another host".
  ///
  /// A new tab can also be a whole saved layout, so unless [onSelect] narrows
  /// the choice to one host (a split can only take one), templates are listed
  /// beside the hosts.
  void _showSelectHostModal(
    BuildContext context,
    WidgetRef ref, {
    Future<void> Function(HostModel host)? onSelect,
  }) {
    showAdaptivePanel<void>(
      context: context,
      title: 'Connect to Host',
      desktopHeight: 420,
      builder: (ctx) => SelectHostPanel(
        onSelected: (host) async {
          Navigator.of(ctx).pop();
          await (onSelect ?? _connectToHost)(host);
        },
        onTemplateSelected: onSelect != null
            ? null
            : (template) {
                Navigator.of(ctx).pop();
                unawaited(_runTemplate(template));
              },
      ),
    );
  }
}

/// The rows of the "+" menu, so the choice survives the modal being a dropdown
/// on one host and a sheet on another.
enum _NewTabAction { localShell, connectToHost, deviceLink }
