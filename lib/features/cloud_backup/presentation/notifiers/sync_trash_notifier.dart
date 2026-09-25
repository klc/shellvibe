import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/restored_data.dart';
import '../../../../core/sync/sync_journal.dart';
import '../../../../shared/providers/database_providers.dart';

part 'sync_trash_notifier.g.dart';

/// One deleted row, as the trash holds it.
@immutable
final class TrashedRow {
  final String entityType;
  final String entityId;
  final DateTime deletedAt;

  /// Something the user can recognise: a host's label, a snippet's title.
  ///
  /// Read from the stored body rather than the table, because the row is not
  /// in the table any more -- that is the point of the entry.
  final String label;

  /// How long is left before the body is emptied and this stops being
  /// restorable.
  final Duration remaining;

  const TrashedRow({
    required this.entityType,
    required this.entityId,
    required this.deletedAt,
    required this.label,
    required this.remaining,
  });

  /// A table name a person can read.
  String get kind => switch (entityType) {
    'hosts' => 'Host',
    'identities' => 'Identity',
    'vault_env_vars' => 'Environment variable',
    'host_groups' => 'Group',
    'workspaces' => 'Workspace',
    'port_forward_rules' => 'Port forward',
    'snippets' => 'Snippet',
    'runbooks' => 'Runbook',
    'runbook_steps' => 'Runbook step',
    'templates' => 'Template',
    'template_panes' => 'Template pane',
    'bookmarks' => 'Bookmark',
    _ => entityType,
  };
}

/// The deleted rows this device can still put back.
///
/// Exists because automatic sync carries a mistaken delete to every other
/// device in seconds. Without a trash, the window where someone could undo it
/// closes before they have finished reading the confirmation dialog.
///
/// Local, always. It is never uploaded and produces no operation of its own; a
/// row put back here goes out as an ordinary upsert, which is what the other
/// devices need to see.
@riverpod
class SyncTrashNotifier extends _$SyncTrashNotifier {
  @override
  Future<List<TrashedRow>> build() async {
    final db = ref.watch(appDatabaseProvider);
    final journal = db.syncJournal;
    if (journal == null) return const [];

    // Runs the retention clock down before listing, so an entry whose thirty
    // days are up is not offered as restorable one last time.
    await journal.purgeTrash();

    final now = DateTime.now();

    return [
      for (final tombstone in await journal.trash())
        if (tombstone.body != null && tombstone.body!.isNotEmpty)
          TrashedRow(
            entityType: tombstone.entityType,
            entityId: tombstone.entityId,
            deletedAt: tombstone.deletedAt,
            label: _labelFrom(tombstone.body!, tombstone.entityId),
            remaining:
                kSyncTrashRetention - now.difference(tombstone.deletedAt),
          ),
    ];
  }

  /// Puts a row back and sends it to the other devices.
  ///
  /// Returns false when the row could not be written because something it
  /// belongs to is gone as well -- its workspace, or the host a port forward
  /// hung off. The entry stays in that case, so restoring the parent first and
  /// trying again works.
  Future<bool> restore(TrashedRow row) async {
    final journal = ref.read(appDatabaseProvider).syncJournal;
    if (journal == null) return false;

    final restored = await journal.restoreFromTrash(
      entityType: row.entityType,
      entityId: row.entityId,
    );

    if (restored) {
      // The row went in underneath every list that is already holding what it
      // read at startup.
      invalidateRestoredData(ref);
    }

    ref.invalidateSelf();

    return restored;
  }

  /// Empties the trash now.
  ///
  /// The bodies go; the ids stay. Without the ids a late `upsert` from a
  /// device that never heard about the delete would bring the rows back on
  /// its own, which is the opposite of what someone emptying a trash means.
  Future<void> empty() async {
    final journal = ref.read(appDatabaseProvider).syncJournal;
    if (journal == null) return;

    await journal.emptyTrash();
    ref.invalidateSelf();
  }

  /// A name from the stored row, falling back to the id.
  ///
  /// Every syncable table names its rows differently and two of them name
  /// nothing at all, so this tries the columns that exist and gives up
  /// honestly rather than printing an empty string.
  static String _labelFrom(String body, String fallback) {
    try {
      final row = jsonDecode(body) as Map<String, dynamic>;

      for (final key in const ['label', 'title', 'name']) {
        final value = row[key];
        if (value is String && value.isNotEmpty) return value;
      }

      final hostname = row['hostname'];
      if (hostname is String && hostname.isNotEmpty) return hostname;
    } on FormatException {
      // A body this build cannot read. The id is still something to point at.
    }

    return fallback;
  }
}
