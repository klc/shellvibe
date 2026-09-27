import 'dart:math';

import 'package:shellvibe/core/api/api_exception.dart';
import 'package:shellvibe/features/cloud_backup/data/sync_operations_api.dart';

/// The sync operation log, in memory, shared by every device in a test.
///
/// Pages by position the way the current server does, and can be switched to
/// answer the way an older one did, to refuse a pruned cursor, to cap a page
/// below what the client asked for, or to drop pushes on the floor.
final class InMemoryOperationLog implements SyncOperationTransport {
  /// Everything pushed, in the order the log stored it. An operation's
  /// position is its index plus one. Nothing is ever pruned.
  final List<SyncOperationDto> operations = [];

  /// When true, every pull answers the way a pruned log does.
  bool expireCursors = false;

  /// When true, every push fails as if the server could not be reached.
  bool failPushes = false;

  /// A page size the server imposes whatever the client asked for, which is
  /// what makes a page boundary land somewhere the client did not choose.
  int? pageCap;

  /// Answers the way a server that predates positions does: ordered and
  /// paged by clock, with no `max_seq`.
  bool answersByClock = false;

  int get _cap => pageCap ?? 1 << 30;

  @override
  Future<int> push(List<SyncOperationDto> batch) async {
    if (failPushes) throw const ApiTransportException('log unreachable');
    operations.addAll(batch);

    return batch.length;
  }

  @override
  Future<SyncOperationPage> pull({
    required int sinceClock,
    int? sinceSeq,
    int limit = 100,
  }) async {
    if (expireCursors) {
      throw const ApiException(
        statusCode: 409,
        code: ApiErrorCode.syncCursorExpired,
        message: 'Operations after this cursor have been pruned.',
      );
    }

    if (answersByClock) return _pullByClock(sinceClock, limit);

    // A device that has no position yet starts from the beginning.
    final start = sinceSeq ?? 0;
    final after = [
      for (var i = start; i < operations.length; i++) (i + 1, operations[i]),
    ];
    final page = after.take(min(limit, _cap)).toList();

    return SyncOperationPage(
      operations: [for (final entry in page) entry.$2],
      maxClock: page.isEmpty
          ? sinceClock
          : page.map((entry) => entry.$2.logicalClock).reduce(max),
      maxSeq: page.isEmpty ? start : page.last.$1,
      hasMore: after.length > page.length,
    );
  }

  SyncOperationPage _pullByClock(int sinceClock, int limit) {
    // Ordered the way the server orders it, which is what the client's cursor
    // arithmetic depends on.
    final ordered = [...operations]
      ..sort((a, b) {
        final byClock = a.logicalClock.compareTo(b.logicalClock);

        return byClock != 0 ? byClock : a.id.compareTo(b.id);
      });

    final after = ordered
        .where((o) => o.logicalClock > sinceClock)
        .toList(growable: false);
    final page = after.take(min(limit, _cap)).toList(growable: false);

    return SyncOperationPage(
      operations: page,
      maxClock: page.isEmpty ? sinceClock : page.last.logicalClock,
      hasMore: after.length > page.length,
    );
  }
}
