import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/terly_tokens.dart';
import '../../data/sftp_transfer_queue_worker.dart';
import '../../domain/models/transfer_item.dart';
import '../providers/sftp_providers.dart';

/// Height the wireframe reserves for the docked queue — roughly four rows.
const double kSftpQueuePanelHeight = 168;

/// Always-visible transfer queue docked under the file panes.
///
/// The wireframe is explicit that this must not be hideable: a long transfer
/// has to keep reporting progress while the user carries on browsing.
class SftpTransferQueuePanel extends ConsumerWidget {
  const SftpTransferQueuePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = TerlyTokens.resolve(context);
    final queueAsync = ref.watch(transferQueueStreamProvider);
    final queue = queueAsync.value ?? const <TransferItem>[];
    final active = queue
        .where((item) => item.status == TransferStatus.inProgress)
        .length;
    final pending = queue
        .where((item) => item.status == TransferStatus.pending)
        .length;
    final failed = queue
        .where((item) => item.status == TransferStatus.failed)
        .length;

    return Container(
      key: const Key('sftp_transfer_queue_panel'),
      height: kSftpQueuePanelHeight,
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: tokens.border)),
            ),
            child: Row(
              children: [
                Text(
                  'Transfer queue',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$active active · $pending queued'
                    '${failed > 0 ? ' · $failed failed' : ''}',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: tokens.textMuted),
                  ),
                ),
                ShadButton.ghost(
                  key: const Key('queue_clear_finished'),
                  size: ShadButtonSize.sm,
                  onPressed: () =>
                      ref.read(sftpTransferQueueWorkerProvider).clearFinished(),
                  child: const Text('Clear finished'),
                ),
              ],
            ),
          ),
          Expanded(
            child: queue.isEmpty
                ? Center(
                    child: Text(
                      'No active or queued file transfers.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
                    ),
                  )
                : ListView.builder(
                    itemCount: queue.length,
                    itemBuilder: (context, index) =>
                        _QueueRow(item: queue[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _QueueRow extends ConsumerWidget {
  final TransferItem item;

  const _QueueRow({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = TerlyTokens.resolve(context);
    final worker = ref.watch(sftpTransferQueueWorkerProvider);
    final client = ref.watch(
      sftpProvider.select((state) => state.remoteClient),
    );
    final isUpload = item.type == TransferType.upload;
    final labelStyle = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: tokens.textMuted);

    return Container(
      key: Key('queue_row_${item.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: item.status == TransferStatus.failed
            ? tokens.danger.withValues(alpha: 0.08)
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(color: tokens.border.withValues(alpha: 0.55)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              '${isUpload ? '↑' : '↓'} ${item.fileName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(tokens.radiusPill),
              child: LinearProgressIndicator(
                value: item.progress,
                minHeight: 5,
                backgroundColor: tokens.textPrimary.withValues(alpha: 0.06),
                valueColor: AlwaysStoppedAnimation<Color>(
                  item.status == TransferStatus.inProgress
                      ? tokens.brand
                      : tokens.textMuted,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 78,
            child: Text(
              _statusLabel(item),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: labelStyle,
            ),
          ),
          SizedBox(
            width: 68,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: _actions(worker, client),
            ),
          ),
        ],
      ),
    );
  }

  static String _statusLabel(TransferItem item) => switch (item.status) {
    TransferStatus.inProgress => item.formattedSpeed,
    TransferStatus.pending => 'queued',
    TransferStatus.paused => 'paused',
    TransferStatus.completed => 'done',
    TransferStatus.failed => 'failed',
    TransferStatus.cancelled => 'cancelled',
  };

  List<Widget> _actions(SftpTransferQueueWorker worker, SftpClient? client) {
    switch (item.status) {
      case TransferStatus.inProgress:
        return [
          _IconAction(
            icon: LucideIcons.pause,
            tooltip: 'Pause transfer',
            onPressed: () => worker.pauseTransfer(item.id),
          ),
          _IconAction(
            icon: LucideIcons.x,
            tooltip: 'Cancel transfer',
            onPressed: () => worker.cancelTransfer(item.id),
          ),
        ];
      case TransferStatus.paused:
        return [
          if (client != null)
            _IconAction(
              icon: LucideIcons.play,
              tooltip: 'Resume transfer',
              onPressed: () => worker.resumeTransfer(client, item.id),
            ),
          _IconAction(
            icon: LucideIcons.x,
            tooltip: 'Cancel transfer',
            onPressed: () => worker.cancelTransfer(item.id),
          ),
        ];
      case TransferStatus.pending:
        return [
          _IconAction(
            icon: LucideIcons.x,
            tooltip: 'Cancel transfer',
            onPressed: () => worker.cancelTransfer(item.id),
          ),
        ];
      case TransferStatus.completed:
      case TransferStatus.failed:
      case TransferStatus.cancelled:
        return const [];
    }
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 14),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      onPressed: onPressed,
    );
  }
}
