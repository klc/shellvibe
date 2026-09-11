import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../data/sftp_transfer_queue_worker.dart';
import '../../domain/models/transfer_item.dart';
import '../providers/sftp_providers.dart';

/// Height the wireframe reserves for the docked queue — roughly four rows.
const double kSftpQueuePanelHeight = 150;

/// Always-visible transfer queue docked under the file panes.
///
/// The wireframe is explicit that this must not be hideable: a long transfer
/// has to keep reporting progress while the user carries on browsing.
class SftpTransferQueuePanel extends ConsumerWidget {
  const SftpTransferQueuePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ShellVibeTokens.resolve(context);
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

    return SizedBox(
      key: const Key('sftp_transfer_queue_panel'),
      height: kSftpQueuePanelHeight,
      child: ShellVibePanel(
        gradientExtent: 150,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                children: [
                  const ShellVibeSectionLabel(
                    label: 'Transfer queue',
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '$active active · $pending queued'
                      '${failed > 0 ? ' · $failed failed' : ''}',
                      style: shellvibeMono(
                        context,
                        size: 11,
                        color: active > 0 ? tokens.brand : tokens.textSubtle,
                      ),
                    ),
                  ),
                  ShellVibeButton.quiet(
                    key: const Key('queue_clear_finished'),
                    label: 'Clear finished',
                    onPressed: () => ref
                        .read(sftpTransferQueueWorkerProvider)
                        .clearFinished(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: queue.isEmpty
                  ? Center(
                      child: Text(
                        'No active or queued file transfers.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: tokens.textSubtle,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      itemCount: queue.length,
                      itemBuilder: (context, index) =>
                          _QueueRow(item: queue[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueRow extends ConsumerWidget {
  final TransferItem item;

  const _QueueRow({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ShellVibeTokens.resolve(context);
    final worker = ref.watch(sftpTransferQueueWorkerProvider);
    final client = ref.watch(
      sftpProvider.select((state) => state.remoteClient),
    );
    final isUpload = item.type == TransferType.upload;
    // Done is not the same colour as running: a finished row goes green so a
    // glance down the queue separates "still moving" from "landed".
    final accent = switch (item.status) {
      TransferStatus.failed => tokens.danger,
      TransferStatus.completed => tokens.success,
      TransferStatus.inProgress => tokens.brand,
      _ => tokens.textMuted,
    };

    return Padding(
      key: Key('queue_row_${item.id}'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            item.status == TransferStatus.completed
                ? LucideIcons.check
                : isUpload
                ? LucideIcons.arrowUp
                : LucideIcons.arrowDown,
            size: 14,
            color: accent,
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 230,
            child: Text(
              item.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: shellvibeMono(
                context,
                size: 11.5,
                color: tokens.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: item.progress,
                minHeight: 4,
                backgroundColor: tokens.textPrimary.withValues(alpha: 0.06),
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 52,
            child: Text(
              '${(item.progress * 100).round()}%',
              textAlign: TextAlign.right,
              style: shellvibeMono(context, size: 11, color: accent),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 86,
            child: Text(
              _statusLabel(item),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: shellvibeMono(context, size: 11, color: tokens.textSubtle),
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
    return ShellVibeIconButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }
}
