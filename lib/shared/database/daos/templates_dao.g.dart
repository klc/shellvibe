// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'templates_dao.dart';

// ignore_for_file: type=lint
mixin _$TemplatesDaoMixin on DatabaseAccessor<AppDatabase> {
  $WorkspacesTable get workspaces => attachedDatabase.workspaces;
  $RunbooksTable get runbooks => attachedDatabase.runbooks;
  $TemplatesTable get templates => attachedDatabase.templates;
  $SnippetsTable get snippets => attachedDatabase.snippets;
  $TemplatePanesTable get templatePanes => attachedDatabase.templatePanes;
  TemplatesDaoManager get managers => TemplatesDaoManager(this);
}

class TemplatesDaoManager {
  final _$TemplatesDaoMixin _db;
  TemplatesDaoManager(this._db);
  $$WorkspacesTableTableManager get workspaces =>
      $$WorkspacesTableTableManager(_db.attachedDatabase, _db.workspaces);
  $$RunbooksTableTableManager get runbooks =>
      $$RunbooksTableTableManager(_db.attachedDatabase, _db.runbooks);
  $$TemplatesTableTableManager get templates =>
      $$TemplatesTableTableManager(_db.attachedDatabase, _db.templates);
  $$SnippetsTableTableManager get snippets =>
      $$SnippetsTableTableManager(_db.attachedDatabase, _db.snippets);
  $$TemplatePanesTableTableManager get templatePanes =>
      $$TemplatePanesTableTableManager(_db.attachedDatabase, _db.templatePanes);
}
