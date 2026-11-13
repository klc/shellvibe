import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/keyboard/app_keymap.dart';
import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../bookmarks/presentation/notifiers/bookmarks_notifier.dart';
import '../../../hosts/domain/models/host_model.dart';
import '../../../hosts/presentation/notifiers/hosts_notifier.dart';
import '../notifiers/terminal_tabs_notifier.dart';

/// The screen shown when no tab is open: a place to start one, and — on a
/// keyboard — where a keyboard-first app teaches its keys.
class TerminalEmptyState extends ConsumerWidget {
  /// Connects to a bookmarked host tapped from [_bookmarkShortcuts].
  final Future<void> Function(HostModel host) onConnectToHost;

  /// Opens the "Connect to Host" panel.
  final VoidCallback onShowSelectHostModal;

  /// Scans or shows the Device Link QR, depending on the platform.
  final VoidCallback onDeviceLinkAction;

  const TerminalEmptyState({
    super.key,
    required this.onConnectToHost,
    required this.onShowSelectHostModal,
    required this.onDeviceLinkAction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The empty screen is where a keyboard-first app teaches its keys. Only on
    // a keyboard, though: a phone has no ⌘ to press, and the row is 96px wider
    // than a 375px screen anyway.
    final tokens = ShellVibeTokens.resolve(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final body = _buildEmptyStateBody(context, ref);
        if (constraints.maxWidth < tokens.breakpointCompact) return body;
        return Column(
          children: [
            Expanded(child: body),
            Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: DefaultTextStyle.merge(
                style: shellvibeMono(
                  context,
                  size: 11,
                  color: ShellVibeTokens.resolve(context).textSubtle,
                ),
                // Wraps rather than overflows: the Ctrl+Shift labels are half
                // as long again as the ⌘ ones.
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 22,
                  runSpacing: 6,
                  children: [
                    // The new-tab key is on the Local shell row itself.
                    Text(
                      '${shortcutLabel(AppCommand.commandPalette)} '
                      'command palette',
                    ),
                    Text('${moduleRangeShortcutLabel()} modules'),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Bookmarked hosts as one-tap rows under the start actions.
  ///
  /// This costs nothing while the app is in use — the empty state is only on
  /// screen when no session is open, which is exactly when a shortcut is what
  /// is wanted. Empty when nothing is starred.
  List<Widget> _bookmarkRows(BuildContext context, WidgetRef ref) {
    final bookmarks = ref.watch(bookmarksProvider).value ?? const [];
    final hosts = ref.watch(hostsProvider).value ?? const <HostModel>[];
    final starred = [
      for (final bookmark in bookmarks)
        if (bookmark.hostId != null)
          ...hosts.where((host) => host.id == bookmark.hostId),
    ];
    if (starred.isEmpty) return const [];

    return [
      const SizedBox(height: 20),
      const ShellVibeSectionLabel(
        label: 'Favorites',
        padding: EdgeInsets.fromLTRB(10, 0, 10, 4),
      ),
      for (final host in starred)
        _StartRow(
          rowKey: Key('empty_bookmark_${host.id}'),
          icon: LucideIcons.star,
          label: host.label,
          trailing: host.address,
          onTap: () => unawaited(onConnectToHost(host)),
        ),
    ];
  }

  /// A short list of ways in, not a hero: the shortcut sits on the row it
  /// triggers.
  Widget _buildEmptyStateBody(BuildContext context, WidgetRef ref) {
    final tokens = ShellVibeTokens.resolve(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                child: Text(
                  'No open sessions',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
              if (supportsLocalShell)
                _StartRow(
                  rowKey: const Key('empty_open_local_button'),
                  icon: LucideIcons.monitor,
                  label: 'Local shell',
                  trailing: shortcutLabel(AppCommand.newLocalTab),
                  onTap: () =>
                      ref.read(terminalTabsProvider.notifier).openLocalTab(),
                ),
              _StartRow(
                rowKey: const Key('empty_select_host_button'),
                icon: LucideIcons.server,
                label: 'Connect to a host…',
                onTap: onShowSelectHostModal,
              ),
              _StartRow(
                rowKey: const Key('empty_device_link_button'),
                icon: isMobilePlatform
                    ? LucideIcons.scanQrCode
                    : LucideIcons.smartphone,
                label: isMobilePlatform
                    ? 'Continue a session from your desktop'
                    : 'Continue a session from your phone',
                onTap: onDeviceLinkAction,
              ),
              ..._bookmarkRows(context, ref),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartRow extends StatelessWidget {
  final Key rowKey;
  final IconData icon;
  final String label;
  final String? trailing;
  final VoidCallback onTap;

  const _StartRow({
    required this.rowKey,
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Semantics(
      button: true,
      child: InkWell(
        key: rowKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        child: Container(
          height: isMobilePlatform ? tokens.touchTarget : 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Icon(icon, size: 15, color: tokens.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: tokens.textPrimary),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                Text(trailing!, style: shellvibeMono(context, size: 11)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
