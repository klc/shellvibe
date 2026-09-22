import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/api/api_exception.dart';
import 'package:shellvibe/core/sync/backup_envelope.dart';
import 'package:shellvibe/core/sync/backup_scope.dart';
import 'package:shellvibe/core/sync/sync_engine.dart';
import 'package:shellvibe/core/sync/sync_journal.dart';
import 'package:shellvibe/features/cloud_backup/data/sync_operations_api.dart';
import 'package:shellvibe/shared/database/app_database.dart';

/// Two devices, one log, and the question the whole design turns on: do they
/// end up holding the same thing?
///
/// The log is in memory because the interesting behaviour is convergence, not
/// request plumbing. Everything else -- the sync key, the aliases, the
/// ciphertext, the clocks -- is the real implementation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Log log;
  late SecretKey syncKey;

  setUp(() {
    log = _Log();
    syncKey = SecretKey(BackupEnvelope().generateSyncKey());
  });

  /// One device: its own database, journal and engine over the shared log.
  Future<_Device> device(String id, {BackupScope? scope}) async {
    final db = AppDatabase(NativeDatabase.memory());
    final journal = SyncJournal(db: db, deviceId: id);
    db.syncJournal = journal;

    addTearDown(db.close);

    return _Device(
      db: db,
      journal: journal,
      engine: SyncEngine(
        db: db,
        journal: journal,
        api: log,
        syncKey: syncKey,
        scope: scope ?? BackupScope.full,
      ),
    );
  }

  group('convergence', () {
    test('a host written on one device arrives on the other', () async {
      final a = await device('device-a');
      final b = await device('device-b');

      await a.writeHost('h1', label: 'web');

      await a.engine.syncOnce();
      await b.engine.syncOnce();

      final host = await b.host('h1');

      expect(host, isNotNull);
      expect(host!.label, 'web');
      expect(host.hostname, 'h1.example.com');
    });

    test('a delete travels too', () async {
      final a = await device('device-a');
      final b = await device('device-b');

      await a.writeHost('h1');
      await a.engine.syncOnce();
      await b.engine.syncOnce();

      await a.deleteHost('h1');
      await a.engine.syncOnce();
      await b.engine.syncOnce();

      expect(await b.host('h1'), isNull);
    });

    test('both devices reach the same row after concurrent edits', () async {
      // Offline on both sides, then both come back. The rule only has to be
      // deterministic -- whichever side loses, both must agree on it.
      final a = await device('device-a');
      final b = await device('device-b');

      await a.writeHost('h1', label: 'from a');
      await b.writeHost('h1', label: 'from b');

      await a.engine.push();
      await b.engine.push();

      await a.engine.pull();
      await b.engine.pull();

      final fromA = await a.host('h1');
      final fromB = await b.host('h1');

      expect(
        fromA!.label,
        fromB!.label,
        reason: 'The two devices swapped values instead of converging.',
      );
      // Same clock, so the device id decides. Which one wins does not matter;
      // that both pick the same one does.
      expect(fromA.label, 'from b');
    });

    test('the higher clock wins', () async {
      final a = await device('device-a');
      final b = await device('device-b');

      await a.writeHost('h1', label: 'first');
      await a.engine.syncOnce();
      await b.engine.syncOnce();

      // b now knows a's clock, so its edit is ordered after it.
      await b.writeHost('h1', label: 'second');
      await b.engine.syncOnce();
      await a.engine.syncOnce();

      expect((await a.host('h1'))!.label, 'second');
    });

    test('a device does not apply its own operations back', () async {
      final a = await device('device-a');

      await a.writeHost('h1', label: 'mine');
      await a.engine.push();

      // Change it again locally, then pull: the echo of the first operation
      // must not put the old label back.
      await a.writeHost('h1', label: 'newer');
      await a.engine.pull();

      expect((await a.host('h1'))!.label, 'newer');
    });
  });

  group('deletes and resurrection', () {
    test('a late upsert does not bring back a deleted row', () async {
      // The failure that turns up in every write-up of a home-grown sync:
      // delete and rewrite processed out of order.
      final a = await device('device-a');
      final b = await device('device-b');

      await a.writeHost('h1');
      await a.engine.syncOnce();
      await b.engine.syncOnce();

      // b edits while a deletes, and a's delete is the later clock.
      await b.writeHost('h1', label: 'still here');
      await b.engine.push();

      await a.engine.pull();
      await a.deleteHost('h1');
      await a.engine.push();

      await a.engine.pull();

      expect(
        await a.host('h1'),
        isNull,
        reason: 'The row this device deleted came back.',
      );
    });
  });

  group('category switches', () {
    test(
      'a device with identities off neither sends nor applies them',
      () async {
        final a = await device('device-a');
        final b = await device(
          'device-b',
          scope: BackupScope.of(const [BackupCategory.hosts]),
        );

        await a.writeIdentity('i1');
        await a.writeHost('h1');
        await a.engine.syncOnce();

        await b.engine.syncOnce();

        expect(await b.db.select(b.db.identities).get(), isEmpty);
        expect(await b.host('h1'), isNotNull);
      },
    );

    test('a host arrives without the identity that was filtered out', () async {
      // The nullable reference is cleared rather than failing the write. The
      // host works; it simply has no credentials on this device.
      final a = await device('device-a');
      final b = await device(
        'device-b',
        scope: BackupScope.of(const [BackupCategory.hosts]),
      );

      await a.writeIdentity('i1');
      await a.writeHost('h1', identityId: 'i1');
      await a.engine.syncOnce();
      await b.engine.syncOnce();

      expect((await b.host('h1'))!.identityId, isNull);
    });
  });

  group('the log', () {
    test('a pruned cursor asks for the snapshot instead', () async {
      final a = await device('device-a');

      log.expireCursors = true;

      await expectLater(a.engine.pull(), throwsA(isA<SyncCursorExpired>()));
    });

    test('the cursor only moves after the rows are written', () async {
      final a = await device('device-a');
      final b = await device('device-b');

      await a.writeHost('h1');
      await a.engine.syncOnce();

      final before = (await b.journal.readState()).pulledThroughClock;
      await b.engine.pull();
      final after = (await b.journal.readState()).pulledThroughClock;

      expect(before, 0);
      expect(after, greaterThan(0));
      expect(await b.host('h1'), isNotNull);
    });

    test(
      'an operation sealed under another key is skipped, not fatal',
      () async {
        // A vault whose sync key was rotated, or a server handing back something
        // that does not belong to this account.
        final a = await device('device-a');
        await a.writeHost('h1');
        await a.engine.push();

        final other = AppDatabase(NativeDatabase.memory());
        addTearDown(other.close);
        final otherJournal = SyncJournal(db: other, deviceId: 'device-c');
        other.syncJournal = otherJournal;

        final stranger = SyncEngine(
          db: other,
          journal: otherJournal,
          api: log,
          syncKey: SecretKey(BackupEnvelope().generateSyncKey()),
        );

        final result = await stranger.pull();

        expect(result.pulled, 0);
        expect(await other.select(other.hosts).get(), isEmpty);
      },
    );

    test(
      'a page that ends inside a clock does not lose the rest of it',
      () async {
        // Two devices, each on its own counter, so both produce a clock 1 and
        // both produce a clock 2. The page cap then lands in the middle of the
        // clock 2 pair -- and an exclusive cursor moved to 2 would ask for
        // everything *after* it next time, leaving the other half of the pair
        // in a part of the log nobody asks for again.
        final b = await device('device-b');
        final c = await device('device-c');

        await b.writeHost('b1');
        await b.writeHost('b2');
        await c.writeHost('c1');
        await c.writeHost('c2');

        await b.engine.push();
        await c.engine.push();

        log.pageCap = 3;

        final d = await device('device-d');
        final result = await d.engine.pull();

        // Four rows, and at least four applications: the operations that
        // shared the boundary clock are read again on the next page and
        // written a second time. Idempotent, and the price of not losing one.
        expect(result.pulled, greaterThanOrEqualTo(4));
        for (final id in ['b1', 'b2', 'c1', 'c2']) {
          expect(await d.host(id), isNotNull, reason: '$id never arrived');
        }
      },
    );

    test('operations this device cannot open are counted, not hidden', () async {
      final a = await device('device-a');

      await a.writeHost('h1');
      await a.writeHost('h2');
      await a.engine.push();

      final other = AppDatabase(NativeDatabase.memory());
      addTearDown(other.close);
      final otherJournal = SyncJournal(db: other, deviceId: 'device-c');
      other.syncJournal = otherJournal;

      final stranger = SyncEngine(
        db: other,
        journal: otherJournal,
        api: log,
        syncKey: SecretKey(BackupEnvelope().generateSyncKey()),
      );

      final result = await stranger.pull();

      // The number is the whole point: silence here is a device that syncs
      // forever and never sees anything.
      expect(result.unreadable, 2);
      expect(result.pulled, 0);
    });

    test('the server never sees a table name or a row id', () async {
      final a = await device('device-a');

      await a.writeHost('production-db', label: 'production');
      await a.engine.push();

      final stored = log.operations.single;

      expect(stored.entityType, isNot(contains('hosts')));
      expect(stored.entityId, isNot(contains('production')));
      expect(stored.encryptedPayload, isNot(contains('production')));
      expect(stored.entityType.length, 32);
    });
  });
}

/// One device's database, journal and engine.
final class _Device {
  final AppDatabase db;
  final SyncJournal journal;
  final SyncEngine engine;

  const _Device({
    required this.db,
    required this.journal,
    required this.engine,
  });

  Future<Host?> host(String id) =>
      (db.select(db.hosts)..where((h) => h.id.equals(id))).getSingleOrNull();

  Future<void> writeHost(
    String id, {
    String label = 'host',
    String? identityId,
  }) async {
    final existing = await host(id);

    if (existing == null) {
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: id,
          workspaceId: 'default',
          label: label,
          hostname: '$id.example.com',
          identityId: Value(identityId),
          createdAt: DateTime.now(),
        ),
      );
    } else {
      await db.hostsDao.updateHostById(
        id,
        HostsCompanion(
          label: Value(label),
          identityId: Value(identityId ?? existing.identityId),
        ),
      );
    }
  }

  Future<void> deleteHost(String id) => db.hostsDao.deleteHost(id);

  Future<void> writeIdentity(String id) => db.identitiesDao.insertIdentity(
    IdentitiesCompanion.insert(
      id: id,
      workspaceId: 'default',
      title: 'key',
      username: 'deploy',
      authType: 'key',
      createdAt: DateTime.now(),
    ),
  );
}

/// The operation log, in memory, shared by every device in a test.
final class _Log implements SyncOperationTransport {
  final List<SyncOperationDto> operations = [];

  /// When true, every pull answers the way a pruned log does.
  bool expireCursors = false;

  /// A page size the server imposes whatever the client asked for, which is
  /// what makes a page boundary land somewhere the client did not choose.
  int? pageCap;

  @override
  Future<int> push(List<SyncOperationDto> batch) async {
    operations.addAll(batch);

    return batch.length;
  }

  @override
  Future<SyncOperationPage> pull({
    required int sinceClock,
    int limit = 100,
  }) async {
    if (expireCursors) {
      throw const ApiException(
        statusCode: 409,
        code: ApiErrorCode.syncCursorExpired,
        message: 'Operations after this cursor have been pruned.',
      );
    }

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
    final page = after
        .take(pageCap == null || pageCap! > limit ? limit : pageCap!)
        .toList(growable: false);

    return SyncOperationPage(
      operations: page,
      maxClock: page.isEmpty ? sinceClock : page.last.logicalClock,
      hasMore: after.length > page.length,
    );
  }
}
