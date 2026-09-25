import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/sync/sync_journal.dart';
import 'package:shellvibe/shared/database/app_database.dart';

/// The outbox is the part of automatic sync that cannot be retried.
///
/// An operation that was never recorded is a change that silently never syncs,
/// and there is nothing later in the pipeline that can notice. So the journal
/// wraps the write instead of following it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SyncJournal journal;
  var ids = 0;

  setUp(() {
    ids = 0;
    db = AppDatabase(NativeDatabase.memory());
    journal = SyncJournal(db: db, newId: () => 'op-${++ids}');
  });

  tearDown(() => db.close());

  Future<void> writeHost(String id, {String label = 'web'}) => journal.upsert(
    entityType: 'hosts',
    entityId: id,
    write: () => db
        .into(db.hosts)
        .insertOnConflictUpdate(
          HostsCompanion.insert(
            id: id,
            workspaceId: 'default',
            label: label,
            hostname: '$id.example.com',
            createdAt: DateTime.now(),
          ),
        ),
  );

  Future<void> deleteHost(String id) => journal.delete(
    entityType: 'hosts',
    entityId: id,
    write: () => (db.delete(db.hosts)..where((h) => h.id.equals(id))).go(),
  );

  Future<void> writeEnvVar(String id, {String name = 'API_TOKEN'}) =>
      journal.upsert(
        entityType: 'vault_env_vars',
        entityId: id,
        write: () => db
            .into(db.vaultEnvVars)
            .insertOnConflictUpdate(
              VaultEnvVarsCompanion.insert(
                id: id,
                workspaceId: 'default',
                name: name,
                valueEncrypted: 'ciphertext-for-$id',
                createdAt: DateTime.now(),
              ),
            ),
      );

  Future<void> deleteEnvVar(String id) => journal.delete(
    entityType: 'vault_env_vars',
    entityId: id,
    write: () =>
        (db.delete(db.vaultEnvVars)..where((v) => v.id.equals(id))).go(),
  );

  group('recording', () {
    test('a write produces one operation carrying the whole row', () async {
      await writeHost('h1');

      final pending = await journal.pending();

      expect(pending, hasLength(1));
      expect(pending.single.operation, 'upsert');
      expect(pending.single.entityType, 'hosts');

      final payload =
          jsonDecode(pending.single.payload!) as Map<String, dynamic>;

      expect(payload['id'], 'h1');
      expect(payload['hostname'], 'h1.example.com');
      // Entity level last-writer-wins needs the whole row, so a column the
      // encoder forgot is a column the receiving device silently loses.
      expect(payload.containsKey('username'), isTrue);
      expect(payload.containsKey('environment'), isTrue);
    });

    test('the clock advances by one per change', () async {
      await writeHost('h1');
      await writeHost('h2');

      final clocks = (await journal.pending())
          .map((o) => o.logicalClock)
          .toList();

      expect(clocks, [1, 2]);
    });

    test('a write that leaves no row records nothing', () async {
      // Nothing to tell anyone about, and an operation carrying a payload
      // that does not exist is worse than no operation.
      await journal.upsert(
        entityType: 'hosts',
        entityId: 'never-written',
        write: () async {},
      );

      expect(await journal.pending(), isEmpty);
    });
  });

  group('coalescing', () {
    test('two changes to one row leave one operation', () async {
      // With entity level last-writer-wins the intermediate state means
      // nothing to any receiver, and sending it spends a 30-per-minute write
      // budget on a state nobody applies.
      await writeHost('h1', label: 'first');
      await writeHost('h1', label: 'second');

      final pending = await journal.pending();

      expect(pending, hasLength(1));
      expect((jsonDecode(pending.single.payload!) as Map)['label'], 'second');
    });

    test('the ancestor is the state before the first change', () async {
      // The second change's "before" is a state no other device ever saw, so
      // it is useless as a common ancestor.
      await writeHost('h1', label: 'original');
      await writeHost('h1', label: 'edited once');
      await writeHost('h1', label: 'edited twice');

      final before =
          jsonDecode((await journal.pending()).single.beforeImage!) as Map;

      expect(before['label'], 'original');
    });

    test('a row created and then deleted leaves only the delete', () async {
      await writeHost('h1');
      await deleteHost('h1');

      final pending = await journal.pending();

      expect(pending, hasLength(1));
      expect(pending.single.operation, 'delete');
      expect(pending.single.payload, isNull);
    });

    test(
      'a row deleted and then written again leaves only the write',
      () async {
        await writeHost('h1');
        await deleteHost('h1');
        await writeHost('h1', label: 'back');

        final pending = await journal.pending();

        expect(pending, hasLength(1));
        expect(pending.single.operation, 'upsert');
      },
    );

    test('a new row has no ancestor', () async {
      await writeHost('h1');

      expect((await journal.pending()).single.beforeImage, isNull);
    });
  });

  group('vault env vars', () {
    test('a write produces one operation carrying the whole row', () async {
      await writeEnvVar('env-1');

      final pending = await journal.pending();

      expect(pending, hasLength(1));
      expect(pending.single.operation, 'upsert');
      expect(pending.single.entityType, 'vault_env_vars');

      final payload =
          jsonDecode(pending.single.payload!) as Map<String, dynamic>;
      expect(payload['id'], 'env-1');
      expect(payload['name'], 'API_TOKEN');
      expect(payload['workspaceId'], 'default');
      // Entity level last-writer-wins needs the whole row, so a column the
      // encoder forgot is a column the receiving device silently loses.
      expect(payload.containsKey('valueEncrypted'), isTrue);
      // Never the plaintext: only the already-encrypted column travels.
      expect(payload['valueEncrypted'], 'ciphertext-for-env-1');
    });

    test('a row created and then deleted leaves only the delete', () async {
      await writeEnvVar('env-1');
      await deleteEnvVar('env-1');

      final pending = await journal.pending();

      expect(pending, hasLength(1));
      expect(pending.single.operation, 'delete');
      expect(pending.single.payload, isNull);
    });

    test('a deleted row keeps its body, restorable from the trash', () async {
      await writeEnvVar('env-1', name: 'RESTORE_ME');
      await deleteEnvVar('env-1');

      final trashed = await journal.trash();
      expect(trashed, hasLength(1));
      expect(trashed.single.entityType, 'vault_env_vars');

      final restored = await journal.restoreFromTrash(
        entityType: 'vault_env_vars',
        entityId: 'env-1',
      );
      expect(restored, isTrue);

      final row = await (db.select(
        db.vaultEnvVars,
      )..where((v) => v.id.equals('env-1'))).getSingleOrNull();
      expect(row, isNotNull);
      expect(row!.name, 'RESTORE_ME');
    });
  });

  group('tombstones', () {
    test(
      'a delete is remembered so a late write cannot resurrect it',
      () async {
        // Delete and rewrite arriving out of order is the most commonly
        // reported way a home-grown sync brings back a row the user deleted.
        await writeHost('h1');
        await deleteHost('h1');

        expect(
          await journal.isDeleted(entityType: 'hosts', entityId: 'h1'),
          isTrue,
        );
      },
    );

    test('writing the row again clears the tombstone', () async {
      await writeHost('h1');
      await deleteHost('h1');
      await writeHost('h1');

      expect(
        await journal.isDeleted(entityType: 'hosts', entityId: 'h1'),
        isFalse,
        reason:
            'This device would otherwise drop its own row on the next '
            'reconciliation.',
      );
    });

    test('deleting a row that was never there records nothing', () async {
      // A tombstone here would stand in the way of an upsert still in flight
      // from another device.
      await deleteHost('ghost');

      expect(await journal.pending(), isEmpty);
      expect(
        await journal.isDeleted(entityType: 'hosts', entityId: 'ghost'),
        isFalse,
      );
    });
  });

  group('trash', () {
    test('a deleted row keeps its body', () async {
      await writeHost('h1', label: 'production');
      await deleteHost('h1');

      final trash = await journal.trash();

      expect(trash, hasLength(1));
      expect((jsonDecode(trash.single.body!) as Map)['label'], 'production');
    });

    test('purging empties the body but keeps the id', () async {
      // The id has to outlive the body: without it a late upsert brings the
      // row back.
      await writeHost('h1');
      await deleteHost('h1');

      await journal.purgeTrash(retention: Duration.zero);

      expect(await journal.trash(), isEmpty);
      expect(
        await journal.isDeleted(entityType: 'hosts', entityId: 'h1'),
        isTrue,
      );
    });

    test('a recent delete survives a purge', () async {
      await writeHost('h1');
      await deleteHost('h1');

      await journal.purgeTrash(retention: const Duration(days: 30));

      expect(await journal.trash(), hasLength(1));
    });

    test('emptying the trash now leaves the ids behind', () async {
      await writeHost('h1');
      await deleteHost('h1');

      await journal.emptyTrash();

      expect(await journal.trash(), isEmpty);
      expect(
        await journal.isDeleted(entityType: 'hosts', entityId: 'h1'),
        isTrue,
      );
    });
  });

  group('clocks', () {
    test('a clock seen from elsewhere moves this device forward', () async {
      await journal.observeClock(42);
      await writeHost('h1');

      expect((await journal.pending()).single.logicalClock, 43);
    });

    test('an older clock does not move it backwards', () async {
      await journal.observeClock(42);
      await journal.observeClock(7);
      await writeHost('h1');

      expect((await journal.pending()).single.logicalClock, 43);
    });

    test('the pull cursor is separate from the clock', () async {
      await journal.acknowledgePull(10);

      final state = await journal.readState();

      expect(state.pulledThroughClock, 10);
      expect(state.lastSeenClock, 10);
    });
  });

  group('re-keying', () {
    test('this device\'s rows are queued again, the others are not', () async {
      // The repair for a device that sealed its operations with a key nobody
      // else held: the log never carried them, but the version rows say it
      // did, and the seed step skips exactly those.
      await writeHost('mine');
      await journal.clearSent(await journal.pending());

      // A row this device learned about from someone else, which was never
      // part of the split.
      await journal.setVersion(
        entityType: 'hosts',
        entityId: 'theirs',
        logicalClock: 9,
        deviceId: 'device-b',
      );

      final forgotten = await journal.forgetVersionsBy(journal.deviceId);

      expect(forgotten, 1);
      expect(
        await journal.versionFor(entityType: 'hosts', entityId: 'mine'),
        isNull,
      );
      expect(
        await journal.versionFor(entityType: 'hosts', entityId: 'theirs'),
        isNotNull,
        reason:
            'A row standing at another device\'s clock would lose to any '
            'operation that mentions it once its version is gone.',
      );

      // And the point of it: the row is offered to the seed step again. The
      // default workspace comes with it -- it has never been versioned either.
      expect(await journal.seedUnversioned(), 2);
      expect(
        (await journal.pending()).map((o) => '${o.entityType}/${o.entityId}'),
        containsAll(['hosts/mine', 'workspaces/default']),
      );
    });
  });

  group('sending', () {
    test('accepted operations are dropped', () async {
      await writeHost('h1');
      final sent = await journal.pending();

      await journal.clearSent(sent);

      expect(await journal.pending(), isEmpty);
    });

    test('a row changed while the request was in flight is kept', () async {
      // The change made during the request is a newer operation that was
      // never sent; dropping it by id alone would lose it.
      await writeHost('h1', label: 'sent');
      final sent = await journal.pending();

      await writeHost('h1', label: 'changed mid-flight');

      await journal.clearSent(sent);

      final pending = await journal.pending();

      expect(pending, hasLength(1));
      expect(
        (jsonDecode(pending.single.payload!) as Map)['label'],
        'changed mid-flight',
      );
    });
  });
}
