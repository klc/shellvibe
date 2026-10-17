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
    // Resume and retry re-open the remote file, so they need a live client.
    final client = ref.watch(sftpProvider.select((s) => s.remoteClient));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (item.status == TransferStatus.inProgress)
          ShellVibeIconButton(
            icon: LucideIcons.pause,
            tooltip: 'Pause transfer',
            onPressed: () => worker.pauseTransfer(item.id),
          )
        else if (item.status == TransferStatus.paused && client != null)
          ShellVibeIconButton(
            icon: LucideIcons.play,
            tooltip: 'Resume transfer',
            onPressed: () => worker.resumeTransfer(client, item.id),
          )
        else if ((item.status == TransferStatus.failed ||
                item.status == TransferStatus.cancelled) &&
            client != null)
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
