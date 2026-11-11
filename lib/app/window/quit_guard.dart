import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../features/sftp/domain/models/transfer_item.dart';
import '../../features/sftp/presentation/providers/sftp_providers.dart';
import '../../features/snippets/presentation/notifiers/runbook_run_notifier.dart';
import '../../features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../widgets/adaptive_modal.dart';
import '../widgets/shellvibe_ui.dart';
import 'host_navigation.dart';
import 'window_chrome.dart';

/// What quitting would cut off: "2 sessions, 1 file transfer". Null when
/// nothing is running.
@visibleForTesting
String? describeRunningWork({
  required int sessions,
  required int transfers,
  required bool runbookRunning,
}) {
  String count(int n, String noun) => n == 1 ? '1 $noun' : '$n ${noun}s';
  final parts = [
    if (sessions > 0) count(sessions, 'connected session'),
    if (transfers > 0) count(transfers, 'file transfer'),
    if (runbookRunning) 'a running runbook',
  ];
  return parts.isEmpty ? null : parts.join(', ');
}

Future<bool>? _asking;

/// Set once a quit is confirmed: on macOS the tray's Quit comes back through
/// the OS's exit request, which must not ask a second time.
bool _confirmed = false;

/// Whether to go ahead with quitting. Asks first while a session, a file
/// transfer or a runbook is running, since quitting ends them all. Requests
/// that arrive together (the tray's Quit and the OS's own exit request) share
/// one dialog.
Future<bool> confirmQuit(WidgetRef ref) {
  final work = describeRunningWork(
    sessions: ref
        .read(terminalTabsProvider)
        .tabs
        .where((tab) => tab.splitParentId == null && tab.isConnected)
        .length,
    transfers: ref
        .read(sftpTransferQueueWorkerProvider)
        .queueList
        .where(
          (item) =>
              item.status == TransferStatus.pending ||
              item.status == TransferStatus.inProgress,
        )
        .length,
    runbookRunning: ref.read(runbookRunProvider)?.running ?? false,
  );
  if (_confirmed || work == null) return Future.value(true);
  return _asking ??= _ask(
    work,
  ).then((ok) => _confirmed = ok).whenComplete(() => _asking = null);
}

@visibleForTesting
void debugResetQuitGuard() => _confirmed = false;

Future<bool> _ask(String work) async {
  await showHostWindow();
  final context = hostNavigatorContext;
  // Nowhere to ask: quit, as the app always did.
  if (context == null || !context.mounted) return true;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => ShadDialog.alert(
      title: const Text('Quit ShellVibe?'),
      description: Text('Quitting ends $work.'),
      actions: adaptiveDialogActions(dialogContext, [
        ShellVibeButton.secondary(
          key: const Key('quit_cancel_button'),
          label: 'Cancel',
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        ShellVibeButton.danger(
          key: const Key('quit_confirm_button'),
          label: 'Quit',
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ]),
      actionsAxis: adaptiveDialogActionsAxis(dialogContext),
    ),
  );
  return confirmed ?? false;
}
