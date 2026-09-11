// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'snippets_dao.dart';

// ignore_for_file: type=lint
mixin _$SnippetsDaoMixin on DatabaseAccessor<AppDatabase> {
  $WorkspacesTable get workspaces => attachedDatabase.workspaces;
  $SnippetsTable get snippets => attachedDatabase.snippets;
  SnippetsDaoManager get managers => SnippetsDaoManager(this);
}

class SnippetsDaoManager {
  final _$SnippetsDaoMixin _db;
  SnippetsDaoManager(this._db);
  $$WorkspacesTableTableManager get workspaces =>
      $$WorkspacesTableTableManager(_db.attachedDatabase, _db.workspaces);
  $$SnippetsTableTableManager get snippets =>
      $$SnippetsTableTableManager(_db.attachedDatabase, _db.snippets);
}
