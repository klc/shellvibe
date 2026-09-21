import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/sync/backup_scope_store.dart';
import '../../../settings/presentation/notifiers/backup_scope_notifier.dart';
import '../../../settings/presentation/widgets/backup_scope_picker.dart';
import '../../domain/sync_join_service.dart';
import '../notifiers/sync_notifier.dart';
import '../notifiers/sync_trash_notifier.dart';

/// Automatic sync: whether it runs, and what it carries.
///
/// Deliberately its own switch rather than an implication of the manual
/// backup's scope. A manual backup is something the user asks for at a moment
/// they chose; automatic sync writes to the account on its own schedule, in
/// both directions. Turning the last category off would be a strange way to
/// say "stop doing that", and leaving it on by default would be a stranger way
/// to start.
final class SyncSection extends ConsumerWidget {
  const SyncSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ShellVibeTokens.resolve(context);
    final enabled = ref.watch(autoSyncEnabledProvider).value ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile.adaptive(
            key: const Key('auto_sync_enabled_switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Automatic sync'),
            subtitle: Text(
              'Sends changes as you make them and applies what other devices '
              'send. Separate from the manual backup above, which stays a '
              'snapshot you take yourself.',
              style: TextStyle(fontSize: 11, color: tokens.textSubtle),
            ),
            value: enabled,
            onChanged: (value) =>
                ref.read(autoSyncEnabledProvider.notifier).set(value),
          ),
        ),
        if (enabled) ...[
          const SizedBox(height: 4),
          _SyncStatus(state: ref.watch(syncProvider)),
          _JoinSummary(result: ref.watch(syncProvider).value?.lastJoin),
        ],
        const SizedBox(height: 8),
        BackupScopePicker(
          target: BackupTarget.autoSync,
          title: 'What syncs automatically',
          subtitle:
              'Per device, and in both directions: a category that is off is '
              'neither sent from here nor applied here. Manual backups are '
              'not affected.',
          enabled: enabled,
        ),
        const SizedBox(height: 16),
        const _Trash(),
      ],
    );
  }
}

/// What automatic sync is doing right now, in one line.
///
/// A switch that is on but does nothing is worse than one that is off, so
/// every state that stops sync says which one it is and what would clear it.
final class _SyncStatus extends ConsumerWidget {
  const _SyncStatus({required this.state});

  final AsyncValue<SyncState> state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ShellVibeTokens.resolve(context);

    final (icon, colour, text) = switch (state) {
      AsyncLoading() => (LucideIcons.refreshCw, tokens.textSubtle, 'Starting…'),
      AsyncError(:final error) => (
        LucideIcons.circleAlert,
        Theme.of(context).colorScheme.error,
        'Sync could not start: $error',
      ),
      AsyncData(:final value) => _describe(context, tokens, value),
    };

    if (text.isEmpty) return const SizedBox.shrink();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: colour),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 11, color: colour)),
        ),
        if (value(state)?.isActive ?? false)
          ShellVibeIconButton(
            icon: LucideIcons.refreshCw,
            tooltip: 'Sync now',
            onPressed: () => ref.read(syncProvider.notifier).syncNow(),
          ),
      ],
    );
  }

  static SyncState? value(AsyncValue<SyncState> state) => state.value;

  (IconData, Color, String) _describe(
    BuildContext context,
    ShellVibeTokens tokens,
    SyncState value,
  ) {
    if (value.error != null) {
      return (
        LucideIcons.circleAlert,
        value.needsSnapshotRestore
            ? tokens.warning
            : Theme.of(context).colorScheme.error,
        value.error!,
      );
    }

    return switch (value.blocker) {
      SyncBlocker.disabled => (LucideIcons.info, tokens.textSubtle, ''),
      SyncBlocker.signedOut => (
        LucideIcons.circleAlert,
        tokens.warning,
        'Sign in under Account to sync.',
      ),
      SyncBlocker.notConfigured => (
        LucideIcons.circleAlert,
        tokens.warning,
        'Set a sync passphrase first.',
      ),
      // Every snapshot this account holds carries less than sync does.
      // Starting from one would leave a category missing that nothing later
      // fills in, so the user is asked rather than quietly given part of it.
      SyncBlocker.noCompleteGround => (
        LucideIcons.cloudUpload,
        tokens.warning,
        'No complete snapshot to start from. Take a full backup on a device '
            'that already has your data, then try again.',
      ),
      SyncBlocker.wrongPassphrase => (
        LucideIcons.circleAlert,
        tokens.warning,
        'The passphrase on this device does not open this account\'s sync '
            'snapshot. Use the one from a device that is already syncing.',
      ),
      null when value.running => (
        LucideIcons.refreshCw,
        tokens.textSubtle,
        'Syncing…',
      ),
      null => (
        LucideIcons.circleCheck,
        tokens.success,
        value.lastSyncAt == null
            ? 'Watching for changes.'
            : 'Up to date · sent ${value.lastPushed}, received '
                  '${value.lastPulled}.',
      ),
    };
  }
}

/// What joining this account did, once.
///
/// Shown because the numbers are the only way to tell "sync is on and did
/// something" from "sync is on and quietly did nothing". The duplicate warning
/// is part of it: two devices that each had the same server typed by hand
/// carry two ids for it, so it shows up twice, and a user who is not told
/// reads that as a bug rather than as the cost of not losing one of them.
final class _JoinSummary extends StatelessWidget {
  const _JoinSummary({required this.result});

  final SyncJoinResult? result;

  @override
  Widget build(BuildContext context) {
    final summary = result;
    if (summary == null || !summary.succeeded) return const SizedBox.shrink();

    final tokens = ShellVibeTokens.resolve(context);
    final lines = <String>[];

    if (summary.wroteFirstGround) {
      lines.add(
        'This device started syncing for the account. Other devices will pick '
        'up its data when they join.',
      );
    }

    if (summary.seeded > 0) {
      lines.add('${summary.seeded} of this device\'s rows were sent up.');
    }

    if (summary.applied > 0) {
      lines.add('${summary.applied} rows arrived from the account.');
    }

    if (summary.seeded > 0 && summary.applied > 0) {
      lines.add(
        'Nothing was replaced. If the same server was added by hand on both '
        'devices it is here twice -- delete whichever you do not want.',
      );
    }

    if (summary.repaired > 0) {
      lines.add(
        '${summary.repaired} rows needed a reference cleared or were skipped.',
      );
    }

    if (lines.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                line,
                style: TextStyle(fontSize: 11, color: tokens.textSubtle),
              ),
            ),
        ],
      ),
    );
  }
}

/// Deleted rows this device can still put back.
///
/// Automatic sync carries a mistaken delete to every other device in seconds,
/// which closes the window where someone could say "wait, that was wrong"
/// before they have finished reading the confirmation. This reopens it.
///
/// Shown whether or not sync is on: a delete made with sync off still lands
/// here, and the deletes that most need undoing are the ones nobody was
/// watching.
final class _Trash extends ConsumerWidget {
  const _Trash();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ShellVibeTokens.resolve(context);
    final trash = ref.watch(syncTrashProvider);
    final rows = trash.value ?? const <TrashedRow>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Recently deleted',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: tokens.textPrimary,
                ),
              ),
            ),
            if (rows.isNotEmpty)
              ShellVibeButton.quiet(
                buttonKey: const Key('sync_trash_empty_button'),
                label: 'Empty Now',
                icon: LucideIcons.trash2,
                onPressed: () => ref.read(syncTrashProvider.notifier).empty(),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          rows.isEmpty
              ? 'Nothing deleted in the last 30 days.'
              : 'Kept for 30 days on this device, then the contents are '
                    'discarded. Secrets in a deleted identity stay on disk '
                    'for that long.',
          style: TextStyle(fontSize: 11, color: tokens.textSubtle),
        ),
        for (final row in rows)
          Padding(
            key: Key('sync_trash_row_${row.entityId}'),
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${row.kind} · ${row.label}',
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.textPrimary,
                        ),
                      ),
                      Text(
                        _remaining(row.remaining),
                        style: TextStyle(
                          fontSize: 11,
                          color: tokens.textSubtle,
                        ),
                      ),
                    ],
                  ),
                ),
                ShellVibeButton.quiet(
                  label: 'Restore',
                  icon: LucideIcons.undo2,
                  onPressed: () => _restore(context, ref, row),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    TrashedRow row,
  ) async {
    final restored = await ref.read(syncTrashProvider.notifier).restore(row);
    if (restored || !context.mounted) return;

    // The row itself is fine; what it belonged to is gone too. Saying which
    // way round that is turns a dead button into a two-step job.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${row.label} could not be put back: something it belongs to was '
          'deleted as well. Restore that first.',
        ),
      ),
    );
  }

  static String _remaining(Duration left) {
    if (left.isNegative) return 'Expiring now';
    if (left.inDays >= 1) return '${left.inDays} days left';
    if (left.inHours >= 1) return '${left.inHours} hours left';

    return 'Less than an hour left';
  }
}
