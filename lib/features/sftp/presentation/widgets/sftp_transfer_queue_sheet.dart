import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../data/sftp_transfer_queue_worker.dart';
import '../../domain/models/transfer_item.dart';
import '../providers/sftp_providers.dart';

class SftpTransferQueueSheet extends ConsumerWidget {
  const SftpTransferQueueSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(transferQueueStreamProvider);
    final colorScheme = ShadTheme.of(context).colorScheme;

    return Container(
      height: 320,
      decoration: BoxDecoration(
        color: colorScheme.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 10, spreadRadius: 2),
        ],
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.sync_alt, color: Colors.cyanAccent),
                const SizedBox(width: 8),
                const Text(
                  'SFTP Transfer Queue',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                ShadButton.ghost(
                  leading: const Icon(Icons.clear_all, size: 18),
                  onPressed: () {
                    ref.read(sftpTransferQueueWorkerProvider).clearFinished();
                  },
                  child: const Text('Clear Finished'),
                ),
                Tooltip(
                  message: 'Close Queue',
                  child: ShadIconButton.ghost(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colorScheme.border),
          // Queue list
          Expanded(
            child: queueAsync.when(
              data: (queue) {
                if (queue.isEmpty) {
                  return Center(
                    child: Text(
                      'No active or queued file transfers.',
                      style: TextStyle(color: colorScheme.mutedForeground),
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: queue.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: colorScheme.border),
                  itemBuilder: (context, index) {
                    final item = queue[index];
                    return _TransferTile(item: item);
                  },
                );
              },
              loading: () => const Center(child: ShadProgress()),
              error: (err, stack) => Center(child: Text('Error loading queue: $err')),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferTile extends ConsumerWidget {
  final TransferItem item;

  const _TransferTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUpload = item.type == TransferType.upload;
    final worker = ref.watch(sftpTransferQueueWorkerProvider);
    final sftpClient = ref.watch(sftpProvider.select((s) => s.remoteClient));
    final colorScheme = ShadTheme.of(context).colorScheme;

    IconData statusIcon;
    Color statusColor;

    switch (item.status) {
      case TransferStatus.pending:
        statusIcon = Icons.hourglass_empty;
        statusColor = Colors.amber;
        break;
      case TransferStatus.inProgress:
        statusIcon = isUpload ? Icons.upload : Icons.download;
        statusColor = Colors.cyan;
        break;
      case TransferStatus.paused:
        statusIcon = Icons.pause_circle_outline;
        statusColor = Colors.orange;
        break;
      case TransferStatus.completed:
        statusIcon = Icons.check_circle_outline;
        statusColor = Colors.greenAccent;
        break;
      case TransferStatus.failed:
        statusIcon = Icons.error_outline;
        statusColor = Colors.redAccent;
        break;
      case TransferStatus.cancelled:
        statusIcon = Icons.cancel_outlined;
        statusColor = Colors.grey;
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.fileName,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (item.status == TransferStatus.inProgress)
                Text(
                  item.formattedSpeed,
                  style: const TextStyle(fontSize: 12, color: Colors.cyanAccent),
                ),
              const SizedBox(width: 8),
              _buildActionButtons(worker, sftpClient),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: ShadProgress(
                  value: item.progress,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${(item.progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 12, color: colorScheme.mutedForeground),
              ),
            ],
          ),
          if (item.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                item.error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(SftpTransferQueueWorker worker, SftpClient? client) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (item.status == TransferStatus.inProgress)
          Tooltip(
            message: 'Pause Transfer',
            child: ShadIconButton.ghost(
              icon: const Icon(Icons.pause, size: 18),
              onPressed: () => worker.pauseTransfer(item.id),
            ),
          )
        else if (item.status == TransferStatus.paused && client != null)
          Tooltip(
            message: 'Resume Transfer',
            child: ShadIconButton.ghost(
              icon: const Icon(Icons.play_arrow, size: 18),
              onPressed: () => worker.resumeTransfer(client, item.id),
            ),
          )
        else if ((item.status == TransferStatus.failed || item.status == TransferStatus.cancelled) &&
            client != null)
          Tooltip(
            message: 'Retry Transfer',
            child: ShadIconButton.ghost(
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: () => worker.retryTransfer(client, item.id),
            ),
          ),
        if (item.status == TransferStatus.inProgress || item.status == TransferStatus.pending || item.status == TransferStatus.paused)
          Tooltip(
            message: 'Cancel Transfer',
            child: ShadIconButton.ghost(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => worker.cancelTransfer(item.id),
            ),
          ),
      ],
    );
  }
}
