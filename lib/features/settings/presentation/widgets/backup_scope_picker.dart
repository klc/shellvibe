import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../core/sync/backup_scope.dart';
import '../notifiers/backup_scope_notifier.dart';

/// Picks what the next backup carries.
///
/// Shown beside the backup buttons rather than tucked behind a screen of its
/// own: a restriction that is only remembered is a restriction that gets
/// forgotten, and the moment that matters is the one where the user asks for
/// a backup.
final class BackupScopePicker extends ConsumerWidget {
  const BackupScopePicker({super.key, this.lastFullBackupAt});

  /// When this device last wrote a complete backup, when that is known.
  ///
  /// Null on a device with no cloud backup configured, where there is nothing
  /// to measure a warning against.
  final DateTime? lastFullBackupAt;

  static String label(BackupCategory category) => switch (category) {
    BackupCategory.hosts => 'Hosts',
    BackupCategory.identities => 'Identities',
    BackupCategory.snippetsAndRunbooks => 'Snippets & runbooks',
    BackupCategory.portForwards => 'Port forwards',
    BackupCategory.knownHosts => 'Known hosts',
    BackupCategory.templates => 'Templates',
    BackupCategory.bookmarks => 'Bookmarks',
    BackupCategory.settings => 'App settings',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ShellVibeTokens.resolve(context);
    final scope = ref.watch(backupScopeProvider).value ?? BackupScope.full;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What gets backed up',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          'Workspaces and groups always go in: everything else is filed under '
          'them. Restoring is always complete — it never deletes what a backup '
          'left out.',
          style: TextStyle(fontSize: 11, color: tokens.textSubtle),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final category in BackupCategory.values)
              FilterChip(
                key: Key('backup_scope_${category.wireName}'),
                label: Text(label(category)),
                selected: scope.contains(category),
                // A port forward row cannot exist without its host, so the
                // choice is locked rather than silently repaired later.
                onSelected: _isLocked(category, scope)
                    ? null
                    : (selected) => ref
                          .read(backupScopeProvider.notifier)
                          .toggle(category, selected),
              ),
          ],
        ),
        if (_shouldWarn(scope)) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.triangleAlert, size: 14, color: tokens.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _warning(),
                  style: TextStyle(fontSize: 11, color: tokens.warning),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  bool _isLocked(BackupCategory category, BackupScope scope) {
    final requirement = kBackupCategoryRequires[category];

    return requirement != null && !scope.contains(requirement);
  }

  /// A vault whose whole history is partial only reveals that at restore time,
  /// which is the worst moment to find out.
  bool _shouldWarn(BackupScope scope) {
    if (scope.isFull) return false;

    final at = lastFullBackupAt;

    return at == null ||
        DateTime.now().difference(at) > const Duration(days: 30);
  }

  String _warning() {
    final at = lastFullBackupAt;

    if (at == null) {
      return 'This device has never written a complete backup. If a restore '
          'is ever needed, whatever is switched off above will not be there.';
    }

    return 'Last complete backup was ${DateTime.now().difference(at).inDays} '
        'days ago. Everything switched off above has not been backed up since.';
  }
}
