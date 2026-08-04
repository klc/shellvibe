import 'package:drift/drift.dart';

/// 1. Workspaces Table
class Workspaces extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get colorCode => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 2. Identities Table (Credentials & SSH Keys)
class Identities extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text().references(Workspaces, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()();
  TextColumn get username => text()();
  TextColumn get authType => text()(); // 'password', 'key', 'agent'
  TextColumn get passwordEncrypted => text().nullable()();
  TextColumn get privateKeyEncrypted => text().nullable()();
  TextColumn get passphraseEncrypted => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 3. Host Groups Table (Hierarchical Folders)
class HostGroups extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text().references(Workspaces, #id, onDelete: KeyAction.cascade)();
  TextColumn get parentId => text().nullable().references(HostGroups, #id, onDelete: KeyAction.setNull)();
  TextColumn get name => text()();
  TextColumn get colorTag => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 4. Hosts Table (Server List)
class Hosts extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text().references(Workspaces, #id, onDelete: KeyAction.cascade)();
  TextColumn get groupId => text().nullable().references(HostGroups, #id, onDelete: KeyAction.setNull)();
  TextColumn get identityId => text().nullable().references(Identities, #id, onDelete: KeyAction.setNull)();
  TextColumn get label => text()();
  TextColumn get hostname => text()();
  TextColumn get username => text().nullable()();
  IntColumn get port => integer().withDefault(const Constant(22))();
  TextColumn get protocol => text().withDefault(const Constant('ssh'))(); // 'ssh', 'mosh', 'local', 'serial'
  TextColumn get colorTag => text().nullable()();
  TextColumn get jumpHostId => text().nullable().references(Hosts, #id, onDelete: KeyAction.setNull)();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 5. Known Hosts Table (SSH Host Key Verification & Fingerprints)
class KnownHosts extends Table {
  TextColumn get id => text()();
  TextColumn get hostname => text()();
  IntColumn get port => integer()();
  TextColumn get keyType => text()(); // 'ssh-ed25519', 'rsa-sha2-512'
  TextColumn get fingerprintSha256 => text()();
  DateTimeColumn get firstSeenAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {hostname, port}
      ];
}

/// 6. Port Forward Rules Table
class PortForwardRules extends Table {
  TextColumn get id => text()();
  TextColumn get hostId => text().references(Hosts, #id, onDelete: KeyAction.cascade)();
  TextColumn get type => text()(); // 'local', 'remote', 'dynamic'
  IntColumn get localPort => integer()();
  TextColumn get remoteHost => text().nullable()();
  IntColumn get remotePort => integer().nullable()();
  BoolColumn get autoStart => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 7. Snippets Table
class Snippets extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text().references(Workspaces, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()();
  TextColumn get code => text()();
  TextColumn get tags => text().nullable()(); // JSON Array of strings

  @override
  Set<Column> get primaryKey => {id};
}

/// 8. Runbooks Table
class Runbooks extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text().references(Workspaces, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 9. Runbook Steps Table
class RunbookSteps extends Table {
  TextColumn get id => text()();
  TextColumn get runbookId => text().references(Runbooks, #id, onDelete: KeyAction.cascade)();
  IntColumn get stepOrder => integer()();
  TextColumn get command => text()();
  IntColumn get expectedExitCode => integer().withDefault(const Constant(0))();
  TextColumn get expectedOutputPattern => text().nullable()();
  IntColumn get timeoutSeconds => integer().withDefault(const Constant(30))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 10. Templates Table (saved terminal tab/pane layouts)
class Templates extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text().references(Workspaces, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();

  /// Template-local id of the pane that was focused at capture time, restored
  /// as the active pane once the whole layout is back up. Null when the capture
  /// had no focused pane.
  TextColumn get activePaneId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 11. Template Panes Table (one row per tab or split pane in a template)
///
/// A pane with a null [parentPaneId] is a root tab; otherwise it is a split
/// pane of the referenced pane. [paneOrder] preserves the order the panes were
/// captured in, which is what reproduces the original layout on replay — split
/// siblings are rendered in the order they were inserted into the tab list.
class TemplatePanes extends Table {
  TextColumn get id => text()();
  TextColumn get templateId => text().references(Templates, #id, onDelete: KeyAction.cascade)();
  IntColumn get paneOrder => integer()();

  /// Template-local reference to another pane of the same template.
  ///
  /// Deliberately not a foreign key: panes are always written and deleted as
  /// one batch per template, and a self-referencing FK would impose insert
  /// ordering constraints on that batch for no benefit.
  TextColumn get parentPaneId => text().nullable()();
  TextColumn get splitDirection => text().nullable()(); // 'horizontal', 'vertical'
  RealColumn get splitRatio => real().withDefault(const Constant(0.5))();
  TextColumn get sessionType => text()(); // 'ssh', 'local'

  /// Host this pane connected to, or null for a local shell.
  ///
  /// Deliberately **not** a foreign key to [Hosts]: deleting a host must not
  /// silently rewrite or delete saved templates. A pane whose host no longer
  /// exists is skipped with a warning when the template runs.
  TextColumn get hostId => text().nullable()();
  TextColumn get title => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

