import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/widgets/shellvibe_ui.dart';
import '../../domain/models/transfer_item.dart';
import '../providers/sftp_providers.dart';

/// Pause / resume / retry / cancel for one queue row, shared by the docked
/// panel and the sheet so both offer the same controls for the same status.
class TransferRowActions extends ConsumerWidget {
  final TransferItem item;

  const TransferRowActions({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final worker = ref.watch(sftpTransferQueueWorkerProvider);
    // Resume and retry re-open the remote file, so they need a live client,
    // and it has to be the one the transfer started on: another host's would
    // write the file there, or download its namesake over the local file.
    final (client, sessionId) = ref.watch(
      sftpProvider.select((s) => (s.remoteClient, s.remoteSessionId)),
    );
    final sameConnection = sessionId == item.sessionId;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // A paused transfer keeps no partial file: "resume" starts it over,
        // and the labels say so.
        if (item.status == TransferStatus.inProgress)
          ShellVibeIconButton(
            icon: LucideIcons.pause,
            tooltip: 'Stop transfer (restart later)',
            onPressed: () => worker.pauseTransfer(item.id),
          )
        else if (item.status == TransferStatus.paused &&
            client != null &&
            sameConnection)
          ShellVibeIconButton(
            icon: LucideIcons.play,
            tooltip: 'Restart transfer from the beginning',
            onPressed: () => worker.resumeTransfer(client, item.id),
          )
        else if ((item.status == TransferStatus.failed ||
                item.status == TransferStatus.cancelled) &&
            client != null &&
            sameConnection)
          ShellVibeIconButton(
            icon: LucideIcons.refreshCw,
            tooltip: 'Retry transfer',
            onPressed: () => worker.retryTransfer(client, item.id),
          ),
        if (item.status == TransferStatus.inProgress ||
            item.status == TransferStatus.pending ||
            item.status == TransferStatus.paused)
          ShellVibeIconButton(
            icon: LucideIcons.x,
            tooltip: 'Cancel transfer',
            onPressed: () => worker.cancelTransfer(item.id),
          ),
      ],
    );
  }
}
