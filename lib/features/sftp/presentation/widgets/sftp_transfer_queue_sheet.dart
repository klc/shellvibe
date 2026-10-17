import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../domain/models/transfer_item.dart';
import '../providers/sftp_providers.dart';
import 'transfer_row_actions.dart';

class SftpTransferQueueSheet extends ConsumerWidget {
  const SftpTransferQueueSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(transferQueueStreamProvider);
    final colorScheme = ShadTheme.of(context).colorScheme;
    final tokens = ShellVibeTokens.resolve(context);

    return Container(
      height: 320,
      decoration: BoxDecoration(
        color: colorScheme.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        boxShadow: [
          BoxShadow(
            color: tokens.shadowColorStrong,
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            // Both header actions are toolbar glyphs, so the header fits the
            // sheet at every width and no longer has to measure itself to
            // decide whether the label survives.
            child: Row(
              children: [
                Icon(LucideIcons.arrowRightLeft, color: tokens.brand),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'SFTP Transfer Queue',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                const SizedBox(width: 8),
                ShellVibeIconButton(
                  icon: LucideIcons.listX,
                  tooltip: 'Clear Finished',
                  onPressed: () =>
                      ref.read(sftpTransferQueueWorkerProvider).clearFinished(),
                ),
                ShellVibeIconButton(
                  icon: LucideIcons.x,
                  tooltip: 'Close Queue',
                  onPressed: () => Navigator.of(context).pop(),
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
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: colorScheme.border),
                  itemBuilder: (context, index) {
                    final item = queue[index];
                    return _TransferTile(item: item);
                  },
                );
              },
              loading: () => const Center(child: ShadProgress()),
              error: (err, stack) =>
                  Center(child: Text('Error loading queue: $err')),
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
    final colorScheme = ShadTheme.of(context).colorScheme;
    final tokens = ShellVibeTokens.resolve(context);

    IconData statusIcon;
    Color statusColor;

    switch (item.status) {
      case TransferStatus.pending:
        statusIcon = Icons.hourglass_empty;
        statusColor = tokens.warning;
        break;
      case TransferStatus.inProgress:
        statusIcon = isUpload ? Icons.upload : Icons.download;
        statusColor = tokens.info;
        break;
      case TransferStatus.paused:
        statusIcon = Icons.pause_circle_outline;
        statusColor = tokens.warning;
        break;
      case TransferStatus.completed:
        statusIcon = Icons.check_circle_outline;
        statusColor = tokens.success;
        break;
      case TransferStatus.failed:
        statusIcon = Icons.error_outline;
        statusColor = tokens.danger;
        break;
      case TransferStatus.cancelled:
        statusIcon = Icons.cancel_outlined;
        statusColor = tokens.textMuted;
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
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (item.status == TransferStatus.inProgress)
                Text(
                  item.formattedSpeed,
                  style: TextStyle(fontSize: 12, color: tokens.brandBright),
                ),
              const SizedBox(width: 8),
              TransferRowActions(item: item),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: ShadProgress(value: item.progress)),
              const SizedBox(width: 12),
              Text(
                '${(item.progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.mutedForeground,
                ),
              ),
            ],
          ),
          if (item.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                item.error!,
                style: TextStyle(color: tokens.danger, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}
