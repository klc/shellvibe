import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/sftp_transfer_queue_worker.dart';
import '../../domain/models/transfer_item.dart';
import '../providers/sftp_providers.dart';

class SftpTransferQueueSheet extends ConsumerWidget {
  const SftpTransferQueueSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(transferQueueStreamProvider);

    return Container(
      height: 320,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
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
                TextButton.icon(
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('Clear Finished'),
                  onPressed: () {
                    ref.read(sftpTransferQueueWorkerProvider).clearFinished();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close Queue',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Queue list
          Expanded(
            child: queueAsync.when(
              data: (queue) {
                if (queue.isEmpty) {
                  return const Center(
                    child: Text(
                      'No active or queued file transfers.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: queue.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, color: Colors.white10),
                  itemBuilder: (context, index) {
                    final item = queue[index];
                    return _TransferTile(item: item);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
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
    final sftpClient = ref.watch(sftpNotifierProvider).remoteClient;

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
                child: LinearProgressIndicator(
                  value: item.progress,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${(item.progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
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
          IconButton(
            icon: const Icon(Icons.pause, size: 18),
            tooltip: 'Pause Transfer',
            onPressed: () => worker.pauseTransfer(item.id),
          )
        else if (item.status == TransferStatus.paused && client != null)
          IconButton(
            icon: const Icon(Icons.play_arrow, size: 18),
            tooltip: 'Resume Transfer',
            onPressed: () => worker.resumeTransfer(client, item.id),
          )
        else if ((item.status == TransferStatus.failed || item.status == TransferStatus.cancelled) &&
            client != null)
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'Retry Transfer',
            onPressed: () => worker.retryTransfer(client, item.id),
          ),
        if (item.status == TransferStatus.inProgress || item.status == TransferStatus.pending || item.status == TransferStatus.paused)
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Cancel Transfer',
            onPressed: () => worker.cancelTransfer(item.id),
          ),
      ],
    );
  }
}
