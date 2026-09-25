import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('⌘T new tab'),
                    SizedBox(width: 22),
                    Text('⌘K command palette'),
                    SizedBox(width: 22),
                    Text('⌘1…7 modules'),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Bookmarked hosts as one-tap chips on the empty screen.
  ///
  /// This costs nothing while the app is in use — the empty state is only on
  /// screen when no session is open, which is exactly when a shortcut is what
  /// is wanted. Returns null when nothing is starred, so the screen keeps the
  /// shape it had.
  Widget? _bookmarkShortcuts(BuildContext context, WidgetRef ref) {
    final bookmarks = ref.watch(bookmarksProvider).value ?? const [];
    final hosts = ref.watch(hostsProvider).value ?? const <HostModel>[];
    final starred = [
      for (final bookmark in bookmarks)
        if (bookmark.hostId != null)
          ...hosts.where((host) => host.id == bookmark.hostId),
    ];
    if (starred.isEmpty) return null;

    final tokens = ShellVibeTokens.resolve(context);
    return Column(
      children: [
        Text(
          'FAVORITES',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: tokens.textSubtle,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final host in starred)
              ShellVibeButton.secondary(
                buttonKey: Key('empty_bookmark_${host.id}'),
                icon: LucideIcons.star,
                label: host.label,
                onPressed: () => unawaited(onConnectToHost(host)),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyStateBody(BuildContext context, WidgetRef ref) {
    return ShellVibeEmptyState(
      footer: _bookmarkShortcuts(context, ref),
      icon: LucideIcons.squareTerminal,
      title: 'No open sessions',
      description: isMobilePlatform
          ? 'Connect to a saved server, or take over a session from your '
                'desktop.'
          : 'Open a local shell, connect to a saved server, or take over a '
                'session from your phone.',
      actions: [
        if (supportsLocalShell)
          ShellVibeButton(
            buttonKey: const Key('empty_open_local_button'),
            icon: LucideIcons.monitor,
            label: 'Local shell',
            onPressed: () =>
                ref.read(terminalTabsProvider.notifier).openLocalTab(),
          ),
        ShellVibeButton.secondary(
          buttonKey: const Key('empty_select_host_button'),
          icon: LucideIcons.server,
          label: 'Connect to host',
          onPressed: onShowSelectHostModal,
        ),
        ShellVibeButton.secondary(
          buttonKey: const Key('empty_device_link_button'),
          icon: isMobilePlatform ? LucideIcons.scanQrCode : LucideIcons.qrCode,
          label: 'Device Link',
          onPressed: onDeviceLinkAction,
        ),
      ],
    );
  }
}
