import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/api/api_exception.dart';
import 'package:shellvibe/core/crypto/encryption_engine.dart';
import 'package:shellvibe/core/sync/backup_envelope.dart';
import 'package:shellvibe/core/sync/backup_scope.dart';
import 'package:shellvibe/core/sync/sync_aliases.dart';
import 'package:shellvibe/core/sync/sync_engine.dart';
import 'package:shellvibe/core/sync/sync_journal.dart';
import 'package:shellvibe/features/cloud_backup/data/sync_operations_api.dart';
import 'package:shellvibe/features/vault/data/vault_key_service.dart';
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
  ///
  /// Every device gets a vault key of its own, as a real one does.
  /// [vaultKey] replaces the lookup, to stand in for a locked vault.
  Future<_Device> device(
    String id, {
    BackupScope? scope,
    Future<SecretKey> Function()? vaultKey,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    final journal = SyncJournal(db: db, deviceId: id);
    db.syncJournal = journal;

    addTearDown(db.close);

    final dek = SecretKey(EncryptionEngine().generateKey());

    return _Device(
      db: db,
      journal: journal,
      dek: dek,
      engine: SyncEngine(
        db: db,
        journal: journal,
        api: log,
        syncKey: syncKey,
        scope: scope ?? BackupScope.full,
        vaultKey: vaultKey ?? () async => dek,
      ),
    );
  }

  /// [original] as the server could rewrite it: every field outside the
  /// ciphertext is the server's to change.
  SyncOperationDto rewritten(
    SyncOperationDto original, {
    String? operation,
    String? deviceId,
    int? logicalClock,
    String? encryptedPayload,
  }) => SyncOperationDto(
    id: original.id,
    deviceId: deviceId ?? original.deviceId,
    logicalClock: logicalClock ?? original.logicalClock,
    entityType: original.entityType,
    entityId: original.entityId,
    operation: operation ?? original.operation,
    encryptedPayload: encryptedPayload ?? original.encryptedPayload,
  );

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

  group('identity secrets', () {
    test('arrive under the receiving device\'s own vault key', () async {
      final a = await device('device-a');
      final b = await device('device-b');

      await a.writeIdentity('i1', password: 'hunter2');
      await a.engine.syncOnce();
      await b.engine.syncOnce();

      final stored = (await b.identity('i1'))!.passwordEncrypted!;
      expect(await b.open(stored), 'hunter2');
      expect(
        () => a.open(stored),
        throwsA(anything),
        reason: 'still under the sending device\'s key',
      );
    });

    test('a vault variable does too', () async {
      final a = await device('device-a');
      final b = await device('device-b');

      await a.writeEnvVar('e1', value: 's3cret');
      await a.engine.syncOnce();
      await b.engine.syncOnce();

      final stored = await (b.db.select(
        b.db.vaultEnvVars,
      )..where((v) => v.id.equals('e1'))).getSingle();
      expect(await b.open(stored.valueEncrypted), 's3cret');
    });

    test('never reach the server in the clear', () async {
      final a = await device('device-a');

      await a.writeIdentity('i1', password: 'hunter2');
      await a.engine.push();

      expect(log.operations.single.encryptedPayload, isNot(contains('hunter2')));
    });

    test('behind a locked vault nothing is applied or acknowledged', () async {
      final a = await device('device-a');
      var locked = true;
      final bKey = SecretKey(EncryptionEngine().generateKey());
      final b = await device(
        'device-b',
        vaultKey: () async {
          if (locked) throw StateError('vault locked');
          return bKey;
        },
      );

      await a.writeIdentity('i1', password: 'hunter2');
      await a.writeHost('h1', identityId: 'i1');
      await a.engine.syncOnce();

      await expectLater(b.engine.pull(), throwsStateError);
      expect(await b.host('h1'), isNull);
      expect((await b.journal.readState()).pulledThroughClock, 0);

      locked = false;
      await b.engine.pull();

      expect((await b.host('h1'))!.identityId, 'i1');
      final stored = (await b.identity('i1'))!.passwordEncrypted!;
      expect(
        await EncryptionEngine().decrypt(
          encryptedBase64: stored,
          secretKey: bKey,
        ),
        'hunter2',
      );
    });

    test('a locked vault holds back sending, not receiving', () async {
      // An identity waiting in the outbox used to stop the whole pass, so a
      // device left locked never saw another host arrive either.
      final a = await device('device-a');
      var locked = true;
      late final _Device b;
      b = await device(
        'device-b',
        vaultKey: () async {
          if (locked) throw const VaultLockedException();
          return b.dek;
        },
      );

      await b.writeIdentity('i1', password: 'hunter2');
      await a.writeHost('h1');
      await a.engine.push();

      await expectLater(
        b.engine.syncOnce(),
        throwsA(isA<VaultLockedException>()),
      );
      expect(await b.host('h1'), isNotNull);
      expect(await b.journal.pending(), hasLength(1));
      expect(log.operations.where((o) => o.deviceId == 'device-b'), isEmpty);

      locked = false;
      await b.engine.syncOnce();
      await a.engine.pull();

      final stored = (await a.identity('i1'))!.passwordEncrypted!;
      expect(await a.open(stored), 'hunter2');
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

    test('the server cannot turn an upsert into a delete', () async {
      final a = await device('device-a');
      final b = await device('device-b');

      await a.writeHost('h1', label: 'first');
      await a.engine.syncOnce();
      await b.engine.syncOnce();

      await a.writeHost('h1', label: 'second');
      await a.engine.push();
      log.operations.last = rewritten(log.operations.last, operation: 'delete');

      final result = await b.engine.pull();

      expect(result.unreadable, 1);
      expect((await b.host('h1'))!.label, 'first');
    });

    test('the server cannot raise a clock or swap the device', () async {
      final a = await device('device-a');
      final b = await device('device-b');

      await a.writeHost('h1', label: 'first');
      await a.engine.syncOnce();
      await b.engine.syncOnce();

      // b's own edit, later than anything a has sent.
      await b.writeHost('h1', label: 'from b');

      await a.writeHost('h1', label: 'from a');
      await a.engine.push();
      final sent = log.operations.last;
      log.operations
        ..removeLast()
        ..add(rewritten(sent, logicalClock: sent.logicalClock + 1000))
        ..add(rewritten(sent, deviceId: 'device-z'));

      final result = await b.engine.pull();

      expect(result.unreadable, 2);
      expect((await b.host('h1'))!.label, 'from b');
    });

    test('an upsert that carries no row is skipped, not fatal', () async {
      // An operation from a build that did not seal its kind, flipped from
      // delete to upsert. It used to throw inside the apply transaction and
      // fail the same page on every pull after it.
      final a = await device('device-a');
      final b = await device('device-b');

      await a.writeHost('h1');
      await a.engine.syncOnce();
      await b.engine.syncOnce();

      final aliases = SyncAliases(syncKey: syncKey);
      log.operations.add(
        SyncOperationDto(
          id: 'legacy-1',
          deviceId: 'device-old',
          logicalClock: 50,
          entityType: await aliases.forType('hosts'),
          entityId: await aliases.forEntity(entityType: 'hosts', entityId: 'h1'),
          operation: 'upsert',
          encryptedPayload: await EncryptionEngine().encrypt(
            plaintext: jsonEncode({'t': 'hosts', 'i': 'h1'}),
            secretKey: syncKey,
          ),
        ),
      );
      await a.writeHost('h2');
      await a.engine.push();

      final result = await b.engine.pull();

      expect(result.unreadable, 1);
      expect(await b.host('h2'), isNotNull, reason: 'the log moved on');
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

  /// This device's vault key.
  final SecretKey dek;

  const _Device({
    required this.db,
    required this.journal,
    required this.engine,
    required this.dek,
  });

  Future<Identity?> identity(String id) => (db.select(
    db.identities,
  )..where((i) => i.id.equals(id))).getSingleOrNull();

  /// Decrypts [ciphertext] with this device's vault key.
  Future<String> open(String ciphertext) =>
      EncryptionEngine().decrypt(encryptedBase64: ciphertext, secretKey: dek);

  Future<void> writeEnvVar(String id, {required String value}) async {
    final sealed = await EncryptionEngine().encrypt(
      plaintext: value,
      secretKey: dek,
    );
    await db.syncJournal!.upsert(
      entityType: 'vault_env_vars',
      entityId: id,
      write: () => db
          .into(db.vaultEnvVars)
          .insert(
            VaultEnvVarsCompanion.insert(
              id: id,
              workspaceId: 'default',
              name: 'TOKEN_$id',
              valueEncrypted: sealed,
              createdAt: DateTime.now(),
            ),
          ),
    );
  }

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

  Future<void> writeIdentity(String id, {String? password}) async =>
      db.identitiesDao.insertIdentity(
        IdentitiesCompanion.insert(
          id: id,
          workspaceId: 'default',
          title: 'key',
          username: 'deploy',
          authType: 'key',
          passwordEncrypted: Value(
            password == null
                ? null
                : await EncryptionEngine().encrypt(
                    plaintext: password,
                    secretKey: dek,
                  ),
          ),
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
