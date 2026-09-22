import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/sync/sync_journal.dart';
import 'package:shellvibe/shared/database/app_database.dart';

/// Undoing a delete.
///
/// Automatic sync carries a mistaken delete to every other device in seconds,
/// which closes the window where someone could say "wait, that was wrong"
/// before they have finished reading the confirmation. The trash is what
/// reopens it, and it has to reopen it for the other devices too -- putting
/// the row back only here would leave them agreeing it is gone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SyncJournal journal;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    journal = SyncJournal(db: db, deviceId: 'device-a');
    db.syncJournal = journal;
  });

  tearDown(() => db.close());

  Future<void> addHost(String id, {String label = 'a host'}) =>
      db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: id,
          workspaceId: 'default',
          label: label,
          hostname: '$id.example.com',
          createdAt: DateTime.now(),
        ),
      );

  Future<Host?> host(String id) =>
      (db.select(db.hosts)..where((h) => h.id.equals(id))).getSingleOrNull();

  test('a deleted row comes back with what it held', () async {
    await addHost('h1', label: 'production');
    await db.hostsDao.deleteHost('h1');

    expect(await host('h1'), isNull);

    final restored = await journal.restoreFromTrash(
      entityType: 'hosts',
      entityId: 'h1',
    );

    expect(restored, isTrue);
    expect((await host('h1'))?.label, 'production');
  });

  test('it goes out as an upsert above the delete that removed it', () async {
    // The other devices have to see a row being written, not a delete being
    // argued with. A lower clock would lose to their copy of the delete and
    // the row would come back here and nowhere else.
    await addHost('h1');
    await db.hostsDao.deleteHost('h1');

    final deleteClock = (await journal.pending())
        .firstWhere((o) => o.entityId == 'h1')
        .logicalClock;

    await journal.restoreFromTrash(entityType: 'hosts', entityId: 'h1');

    final queued = (await journal.pending()).firstWhere(
      (o) => o.entityId == 'h1',
    );

    expect(queued.operation, 'upsert');
    expect(queued.logicalClock, greaterThan(deleteClock));
  });

  test('restoring clears the tombstone that was defending it', () async {
    // Left in place, this device would drop its own row the next time it
    // reconciled -- the tombstone is what stops a late upsert resurrecting
    // something, and after a restore there is nothing to stop.
    await addHost('h1');
    await db.hostsDao.deleteHost('h1');
    await journal.restoreFromTrash(entityType: 'hosts', entityId: 'h1');

    expect(
      await journal.isDeleted(entityType: 'hosts', entityId: 'h1'),
      isFalse,
    );
  });

  test('an expired entry cannot be restored, and says so', () async {
    await addHost('h1');
    await db.hostsDao.deleteHost('h1');

    // The thirty days are up: the body goes, the id stays.
    await journal.purgeTrash(retention: Duration.zero);

    expect(
      await journal.restoreFromTrash(entityType: 'hosts', entityId: 'h1'),
      isFalse,
    );
    expect(await host('h1'), isNull);
  });

  test('the id outlives the body it was holding', () async {
    // Without it a late upsert from a device that never heard about the
    // delete would bring the row back on its own.
    await addHost('h1');
    await db.hostsDao.deleteHost('h1');
    await journal.purgeTrash(retention: Duration.zero);

    expect(
      await journal.isDeleted(entityType: 'hosts', entityId: 'h1'),
      isTrue,
    );
  });

  test('emptying by hand leaves nothing restorable', () async {
    await addHost('h1');
    await db.hostsDao.deleteHost('h1');

    await journal.emptyTrash();

    expect(
      await journal.restoreFromTrash(entityType: 'hosts', entityId: 'h1'),
      isFalse,
    );
  });

  test('a row whose parent is gone too stays offerable', () async {
    // The port forward is fine; the host it hangs off is not. Nothing is
    // restored and the entry stays, so restoring the host and trying again
    // works rather than leaving a dead button.
    await addHost('h1');
    await db
        .into(db.portForwardRules)
        .insert(
          PortForwardRulesCompanion.insert(
            id: 'p1',
            hostId: 'h1',
            type: 'local',
            localPort: 8080,
          ),
        );

    // Deleting the host cascades to the port forward, and both are recorded.
    await db.hostsDao.deleteHost('h1');

    expect(
      await journal.restoreFromTrash(
        entityType: 'port_forward_rules',
        entityId: 'p1',
      ),
      isFalse,
    );

    // Still there to try again once the host is back.
    expect(
      await journal.tombstoneFor(
        entityType: 'port_forward_rules',
        entityId: 'p1',
      ),
      isNotNull,
    );

    await journal.restoreFromTrash(entityType: 'hosts', entityId: 'h1');

    expect(
      await journal.restoreFromTrash(
        entityType: 'port_forward_rules',
        entityId: 'p1',
      ),
      isTrue,
    );
  });
}
