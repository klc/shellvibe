// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bookmarks_dao.dart';

// ignore_for_file: type=lint
mixin _$BookmarksDaoMixin on DatabaseAccessor<AppDatabase> {
  $WorkspacesTable get workspaces => attachedDatabase.workspaces;
  $HostGroupsTable get hostGroups => attachedDatabase.hostGroups;
  $IdentitiesTable get identities => attachedDatabase.identities;
  $SnippetsTable get snippets => attachedDatabase.snippets;
  $HostsTable get hosts => attachedDatabase.hosts;
  $RunbooksTable get runbooks => attachedDatabase.runbooks;
  $TemplatesTable get templates => attachedDatabase.templates;
  $BookmarksTable get bookmarks => attachedDatabase.bookmarks;
  BookmarksDaoManager get managers => BookmarksDaoManager(this);
}

class BookmarksDaoManager {
  final _$BookmarksDaoMixin _db;
  BookmarksDaoManager(this._db);
  $$WorkspacesTableTableManager get workspaces =>
      $$WorkspacesTableTableManager(_db.attachedDatabase, _db.workspaces);
  $$HostGroupsTableTableManager get hostGroups =>
      $$HostGroupsTableTableManager(_db.attachedDatabase, _db.hostGroups);
  $$IdentitiesTableTableManager get identities =>
      $$IdentitiesTableTableManager(_db.attachedDatabase, _db.identities);
  $$SnippetsTableTableManager get snippets =>
      $$SnippetsTableTableManager(_db.attachedDatabase, _db.snippets);
  $$HostsTableTableManager get hosts =>
      $$HostsTableTableManager(_db.attachedDatabase, _db.hosts);
  $$RunbooksTableTableManager get runbooks =>
      $$RunbooksTableTableManager(_db.attachedDatabase, _db.runbooks);
  $$TemplatesTableTableManager get templates =>
      $$TemplatesTableTableManager(_db.attachedDatabase, _db.templates);
  $$BookmarksTableTableManager get bookmarks =>
      $$BookmarksTableTableManager(_db.attachedDatabase, _db.bookmarks);
}
