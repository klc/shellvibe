import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/sync/backup_envelope.dart';
import 'package:shellvibe/core/sync/sync_aliases.dart';

/// Aliases have to be deterministic and opaque at the same time.
///
/// Deterministic because entity level last-writer-wins only works if two
/// devices name the same row identically. Opaque because the server stores
/// them and should learn how many buckets exist, not what they are.
void main() {
  late SyncAliases aliases;
  late SecretKey syncKey;

  setUp(() {
    syncKey = SecretKey(BackupEnvelope().generateSyncKey());
    aliases = SyncAliases(syncKey: syncKey);
  });

  test('the same row always gets the same alias', () async {
    final first = await aliases.forEntity(
      entityType: 'hosts',
      entityId: '01HZY7Q2K3M4N5P6R7S8T9V0WX',
    );
    final second = await SyncAliases(
      syncKey: syncKey,
    ).forEntity(entityType: 'hosts', entityId: '01HZY7Q2K3M4N5P6R7S8T9V0WX');

    expect(first, second);
  });

  test('a different vault gets different aliases for the same row', () async {
    // Two accounts that hold a host with the same id must not be linkable by
    // the server through their aliases.
    final other = SyncAliases(
      syncKey: SecretKey(BackupEnvelope().generateSyncKey()),
    );

    expect(
      await aliases.forEntity(entityType: 'hosts', entityId: 'h1'),
      isNot(await other.forEntity(entityType: 'hosts', entityId: 'h1')),
    );
  });

  test('the same id under two tables gets two aliases', () async {
    // Nothing prevents a host and a snippet sharing an id, and merging them
    // would be a data loss bug that looks like a sync bug.
    expect(
      await aliases.forEntity(entityType: 'hosts', entityId: 'x'),
      isNot(await aliases.forEntity(entityType: 'snippets', entityId: 'x')),
    );
  });

  test('a type alias is not an entity alias of the same name', () async {
    expect(
      await aliases.forType('hosts'),
      isNot(await aliases.forEntity(entityType: 'hosts', entityId: '')),
    );
  });

  test('an alias fits the column the server stores it in', () async {
    // The server validates length and nothing else; 64 characters is the
    // limit, and the alias has to stay well inside it.
    final alias = await aliases.forEntity(entityType: 'hosts', entityId: 'h1');

    expect(alias.length, SyncAliases.aliasLength);
    expect(alias.length, lessThanOrEqualTo(64));
    expect(alias, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
  });

  test('an alias does not contain the value it stands for', () async {
    final alias = await aliases.forEntity(
      entityType: 'hosts',
      entityId: 'production-db',
    );

    expect(alias, isNot(contains('production')));
    expect(alias, isNot(contains('hosts')));
  });
}
