import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/network/mosh_session_manager.dart';
import '../../domain/models/terminal_tab_session.dart';
import '../notifiers/terminal_tabs_notifier.dart';

/// Pure helpers shared by the tab strip and the pane tree: neither owns a pane
/// or a tab exclusively, so lookups like "which panes belong to this tab" are
/// kept here instead of being copied into each build method.

/// Root pane of the tab [pane] belongs to. The loop is bounded by the list
/// length so a corrupted parent link cannot spin forever.
TerminalTabSession rootOfPane(
  List<TerminalTabSession> allTabs,
  TerminalTabSession pane,
) {
  var current = pane;
  for (var hops = 0; hops < allTabs.length; hops++) {
    final parentId = current.splitParentId;
    if (parentId == null) return current;
    final parent = allTabs.firstWhere(
      (t) => t.id == parentId,
      orElse: () => current,
    );
    if (parent.id == current.id) return current;
    current = parent;
  }
  return current;
}

/// Every pane of the tab rooted at [root], the root included.
List<TerminalTabSession> panesOfTab(
  List<TerminalTabSession> allTabs,
  TerminalTabSession root,
) => [
  for (final tab in allTabs)
    if (rootOfPane(allTabs, tab).id == root.id) tab,
];

/// Where [session] is connected, as `user@host:port`. Null for a local shell,
/// which has nowhere to name.
String? terminalEndpointLabel(TerminalTabSession session) {
  final host = session.host;
  if (host == null) return null;
  final user = host.username;
  final prefix = user == null || user.isEmpty ? '' : '$user@';
  return '$prefix${host.hostname}:${host.port}';
}

/// Shown only once a Mosh link has gone quiet. Silence is not a disconnect
/// here — the session is alive and will catch up — but the difference
/// between "slow" and "dropped" is invisible without it, and on this protocol
/// the user cannot tell them apart any other way.
Widget? moshQuietBadge(
  BuildContext context,
  ShellVibeTokens tokens,
  TerminalTabSession session, {
  required bool showText,
}) {
  final link = session.moshLinkState;
  if (link == null || link.status != MoshLinkStatus.stale) return null;
  final seconds = link.silence.inSeconds;
  return Tooltip(
    key: Key('mosh_quiet_${session.id}'),
    message: 'Mosh link quiet for ${seconds}s',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.wifiOff, size: 12, color: tokens.warning),
        if (showText) ...[
          const SizedBox(width: 4),
          Text(
            'mosh quiet ${seconds}s',
            style: shellvibeMono(context, size: 10, color: tokens.warning),
          ),
        ],
      ],
    ),
  );
}

/// A pane another device is attached to over Device Link. The badge is the
/// only place the attachment shows, so it is also where it is ended.
Widget deviceLinkBadge(
  WidgetRef ref,
  ShellVibeTokens tokens,
  TerminalTabSession attached,
) {
  return Tooltip(
    key: Key('device_link_attachment_${attached.id}'),
    message: 'Device Link · ${attached.title} — click to disconnect',
    child: Semantics(
      label: 'Disconnect Device Link ${attached.title}',
      button: true,
      child: InkWell(
        key: Key('device_link_disconnect_${attached.id}'),
        onTap: () => unawaited(
          ref
              .read(terminalTabsProvider.notifier)
              .disconnectDeviceLink(attached.id),
        ),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(LucideIcons.link, size: 13, color: tokens.brand),
        ),
      ),
    ),
  );
}

/// Opens the file transfer screen for [pane].
void openSftpForPane(BuildContext context, TerminalTabSession pane) {
  final label = pane.host?.label ?? pane.title;
  GoRouter.of(context).push(
    '/sftp?tab=${Uri.encodeComponent(pane.id)}'
    '&label=${Uri.encodeComponent(label)}',
  );
}
