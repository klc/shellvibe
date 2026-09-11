// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'known_hosts_dao.dart';

// ignore_for_file: type=lint
mixin _$KnownHostsDaoMixin on DatabaseAccessor<AppDatabase> {
  $KnownHostsTable get knownHosts => attachedDatabase.knownHosts;
  KnownHostsDaoManager get managers => KnownHostsDaoManager(this);
}

class KnownHostsDaoManager {
  final _$KnownHostsDaoMixin _db;
  KnownHostsDaoManager(this._db);
  $$KnownHostsTableTableManager get knownHosts =>
      $$KnownHostsTableTableManager(_db.attachedDatabase, _db.knownHosts);
}
