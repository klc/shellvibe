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
  TextColumn get workspaceId =>
      text().references(Workspaces, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()();
  TextColumn get username => text()();
  TextColumn get authType => text()(); // 'password', 'key'
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
  TextColumn get workspaceId =>
      text().references(Workspaces, #id, onDelete: KeyAction.cascade)();
  TextColumn get parentId => text().nullable().references(
    HostGroups,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get name => text()();
  TextColumn get colorTag => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 4. Hosts Table (Server List)
class Hosts extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId =>
      text().references(Workspaces, #id, onDelete: KeyAction.cascade)();
  TextColumn get groupId => text().nullable().references(
    HostGroups,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get identityId => text().nullable().references(
    Identities,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get label => text()();
  TextColumn get hostname => text()();
  TextColumn get username => text().nullable()();
  IntColumn get port => integer().withDefault(const Constant(22))();
  TextColumn get protocol =>
      text().withDefault(const Constant('ssh'))(); // 'ssh', 'mosh', 'local'
  /// Remote `mosh-server` executable, when it is not on the login PATH.
  TextColumn get moshServerPath => text().nullable()();

  /// UDP range `mosh-server` is asked to bind, as `start:end`. Null means the
  /// mosh default (60000:61000).
  TextColumn get moshPortRange => text().nullable()();
  TextColumn get colorTag => text().nullable()();
  TextColumn get jumpHostId =>
      text().nullable().references(Hosts, #id, onDelete: KeyAction.setNull)();
  DateTimeColumn get createdAt => dateTime()();

  /// 'dev' | 'staging' | 'prod' — the policy engine's criticality signal.
  TextColumn get environment => text().withDefault(const Constant('dev'))();

  /// False hides this host entirely from MCP `list_hosts` output.
  BoolColumn get mcpVisible => boolean().withDefault(const Constant(true))();

  /// Mode preselected in the MCP access-approval window.
  TextColumn get mcpDefaultMode =>
      text().withDefault(const Constant('readonly'))();

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
    {hostname, port},
  ];
}

/// 6. Port Forward Rules Table
class PortForwardRules extends Table {
  TextColumn get id => text()();
  TextColumn get hostId =>
      text().references(Hosts, #id, onDelete: KeyAction.cascade)();
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
  TextColumn get workspaceId =>
      text().references(Workspaces, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()();
  TextColumn get code => text()();
  TextColumn get tags => text().nullable()(); // JSON Array of strings

  @override
  Set<Column> get primaryKey => {id};
}

/// 8. Runbooks Table
class Runbooks extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId =>
      text().references(Workspaces, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 9. Runbook Steps Table
class RunbookSteps extends Table {
  TextColumn get id => text()();
  TextColumn get runbookId =>
      text().references(Runbooks, #id, onDelete: KeyAction.cascade)();
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
  TextColumn get workspaceId =>
      text().references(Workspaces, #id, onDelete: KeyAction.cascade)();
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
  TextColumn get templateId =>
      text().references(Templates, #id, onDelete: KeyAction.cascade)();
  IntColumn get paneOrder => integer()();

  /// Template-local reference to another pane of the same template.
  ///
  /// Deliberately not a foreign key: panes are always written and deleted as
  /// one batch per template, and a self-referencing FK would impose insert
  /// ordering constraints on that batch for no benefit.
  TextColumn get parentPaneId => text().nullable()();
  TextColumn get splitDirection =>
      text().nullable()(); // 'horizontal', 'vertical'
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

/// 12. Paired Devices Table (Device Link authorization records)
///
/// The raw Device Link secret never enters SQLite. [secretHash] is an
/// Argon2id record produced by the pairing repository; the phone keeps the
/// corresponding secret in platform secure storage.
class PairedDevices extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get platform => text()();
  TextColumn get secretHash => text()();
  TextColumn get publicKey => text()();
  DateTimeColumn get pairedAt => dateTime()();
  DateTimeColumn get lastSeenAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 13. MCP Clients — authorized AI agent clients.
///
/// The raw token never enters SQLite; [tokenHash] is the token's SHA-256
/// record. The raw token itself only ever lives in
/// `~/.shellvibe/mcp-endpoint.json` (0600) and on screen at generation time.
class McpClients extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId =>
      text().references(Workspaces, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()(); // "Claude Desktop"

  /// SHA-256 hash of the token — not Argon2id. The token is 32 bytes of
  /// CSPRNG output, so there is no dictionary-attack surface a slow KDF would
  /// defend against, and this hash is checked on every JSON-RPC request; a
  /// slow KDF would burn latency on every call for no security gain.
  TextColumn get tokenHash => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastSeenAt => dateTime().nullable()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  DateTimeColumn get revokedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 14. MCP Host Grants — (client x host) access grants.
class McpHostGrants extends Table {
  TextColumn get id => text()();
  TextColumn get clientId =>
      text().references(McpClients, #id, onDelete: KeyAction.cascade)();
  TextColumn get hostId =>
      text().references(Hosts, #id, onDelete: KeyAction.cascade)();
  TextColumn get mode => text()(); // 'readonly' | 'guarded' | 'autonomous'
  DateTimeColumn get grantedAt => dateTime()();

  /// Null means a permanent grant. Otherwise the grant is invalid from this
  /// instant on.
  DateTimeColumn get expiresAt => dateTime().nullable()();

  /// "This session" scope: the row is deleted once the MCP connection it was
  /// granted under drops.
  TextColumn get connectionScopeId => text().nullable()();

  /// Cooldown after a denied request. New requests are silently denied until
  /// this instant, so the agent can't loop and bury the user in approval
  /// windows.
  DateTimeColumn get cooldownUntil => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 15. MCP Policy Rules — user-defined command rules.
class McpPolicyRules extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId =>
      text().references(Workspaces, #id, onDelete: KeyAction.cascade)();
  TextColumn get scopeType => text()(); // 'global' | 'group' | 'host'
  TextColumn get scopeId => text().nullable()();
  TextColumn get matchType => text()(); // 'exact' | 'prefix' | 'regex'
  TextColumn get pattern => text()();
  TextColumn get action => text()(); // 'allow' | 'confirm' | 'deny'
  IntColumn get priority => integer()(); // lower is evaluated first
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 16. MCP Approvals — remembered approvals.
///
/// A row is keyed to the exact triple of **full command text + host + cwd**;
/// it is never generalized to a pattern. A user who wants a pattern writes
/// one in [McpPolicyRules] themselves — the decision to generalize belongs to
/// a human, not the system.
class McpApprovals extends Table {
  TextColumn get id => text()();
  TextColumn get clientId =>
      text().references(McpClients, #id, onDelete: KeyAction.cascade)();
  TextColumn get hostId =>
      text().references(Hosts, #id, onDelete: KeyAction.cascade)();
  TextColumn get cwd => text()();
  TextColumn get commandNormalized => text()(); // whitespace-normalized only
  TextColumn get commandSha256 => text()(); // lookup index
  DateTimeColumn get approvedAt => dateTime()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  TextColumn get connectionScopeId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 17. MCP Audit Log — immutable audit trail.
///
/// [clientId] and [hostId] are deliberately **not** foreign keys: the audit
/// record must survive the client being revoked or the host being deleted
/// unchanged. The human-readable labels are copied in as of that moment.
class McpAuditLog extends Table {
  TextColumn get id => text()();
  DateTimeColumn get at => dateTime()();
  TextColumn get clientId => text()();
  TextColumn get clientName => text()();
  TextColumn get hostId => text().nullable()();
  TextColumn get hostLabel => text().nullable()();
  TextColumn get tool => text()();
  TextColumn get argsJson => text()(); // redacted
  TextColumn get decision =>
      text()(); // 'allowed'|'confirmed'|'denied'|'auto_denied'|'error'
  TextColumn get category => text().nullable()();
  IntColumn get exitCode => integer().nullable()();
  IntColumn get durationMs => integer().nullable()();
  IntColumn get outputBytes => integer().nullable()();
  TextColumn get outputSha256 => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 18. Bookmarks Table (starred hosts and layouts, in the user's own order)
///
/// One row marks one target. [hostId] and [templateId] are the two kinds a
/// bookmark can point at and exactly one of them is set; both are real foreign
/// keys with `onDelete: cascade`, so deleting a host or a template takes its
/// bookmark with it and no row is ever left pointing at nothing. A single
/// polymorphic `targetId` column could not be a foreign key at all, and would
/// need the dangling rows swept up by hand in every delete path.
///
/// [position] is the order they were put in, which is the order they are shown
/// in — a bookmark list people arrange is not a list they want re-sorted.
class Bookmarks extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId =>
      text().references(Workspaces, #id, onDelete: KeyAction.cascade)();
  TextColumn get hostId =>
      text().nullable().references(Hosts, #id, onDelete: KeyAction.cascade)();
  TextColumn get templateId => text().nullable().references(
    Templates,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get position => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 18. Pending Operations (the local outbox for automatic sync)
///
/// A change is recorded here in the **same transaction** as the change itself.
/// That is the whole point: hooking the repositories instead would let a
/// crash land the write and lose the operation, and an operation that never
/// existed is a change that silently never syncs.
///
/// [payload] is the whole row, not a field diff. Conflicts are resolved at
/// entity level, so the winning operation has to be able to reconstruct the
/// row on its own -- a diff would leave the losing side's untouched fields
/// wiped rather than merged.
///
/// [beforeImage] is the row as it was before the change. Nothing reads it yet.
/// It is stored because a three-way merge needs a common ancestor, that
/// ancestor is kept nowhere else, and it cannot be reconstructed after the
/// fact: recording it now is what keeps that option open later.
class PendingOperations extends Table {
  TextColumn get id => text()();

  /// The table the row belongs to, in its plain name (`hosts`). The opaque
  /// alias is derived at send time -- storing the alias instead would make the
  /// outbox unreadable without the sync key.
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();

  /// `upsert` or `delete`.
  TextColumn get operation => text()();

  /// The row as JSON, or null for a delete.
  TextColumn get payload => text().nullable()();

  /// The row as it was before, or null when it did not exist.
  TextColumn get beforeImage => text().nullable()();

  /// Lamport clock this device assigned to the change.
  IntColumn get logicalClock => integer()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    // One pending operation per row. A second change to the same row replaces
    // the first: with entity level last-writer-wins the intermediate states
    // mean nothing to any receiver, and sending them all would spend the
    // write rate limit on states nobody applies.
    {entityType, entityId},
  ];
}

/// 19. Sync Tombstones (what this device deleted, and what it deleted)
///
/// Two jobs in one table. The ids stop a late `upsert` from resurrecting a
/// deleted row, which is the most commonly reported failure in write-ups of
/// home-grown sync. The bodies are the local trash: a delete stays undoable
/// for a while, because automatic sync carries a mistaken delete to every
/// other device within seconds.
///
/// Never uploaded. A delete undone here goes out as an ordinary `upsert` at a
/// higher clock.
class SyncTombstones extends Table {
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();

  /// The last known row as JSON, or null once the trash window has passed.
  ///
  /// The row is emptied rather than deleted: the id has to outlive the body,
  /// or a late `upsert` would bring the row back.
  TextColumn get body => text().nullable()();

  IntColumn get logicalClock => integer()();
  DateTimeColumn get deletedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {entityType, entityId};
}

/// 20. Sync State (one row, the clocks this device is working from)
///
/// In the database rather than in secure storage so it can be advanced inside
/// the same transaction that writes the data it accounts for. Advancing a
/// cursor before the rows it covers are durable is how a sync that is
/// interrupted loses operations permanently.
class SyncState extends Table {
  /// Always `1`. A table rather than a key-value blob so the clock can take
  /// part in a transaction.
  IntColumn get id => integer()();

  /// Highest clock this device has seen, from its own changes or from a pull.
  IntColumn get lastSeenClock => integer().withDefault(const Constant(0))();

  /// Clock the last pull was acknowledged at. Only ever advanced after the
  /// operations it covers have been written.
  IntColumn get pulledThroughClock =>
      integer().withDefault(const Constant(0))();

  /// How far this device has got through joining automatic sync.
  ///
  /// `none`, then `applied` once the ground has been merged in and this
  /// device's own rows are queued, then `done` once they have been sent and
  /// the ground rewritten.
  ///
  /// Stored rather than inferred, because the two halves of joining cannot be
  /// told apart afterwards. A device that applied the ground and was closed
  /// before its own rows went out looks exactly like one that has finished:
  /// the clocks are set, the outbox is empty in the sense that nothing failed.
  /// Without this it would call itself joined and the rows it never sent --
  /// the sixty hosts that were the reason for syncing at all -- would stay on
  /// that device forever, with nothing reporting a problem.
  TextColumn get joinState => text().withDefault(const Constant('none'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 21. Sync Entity Versions (what clock each row currently stands at)
///
/// Entity level last-writer-wins needs to compare an incoming operation with
/// the state this device already holds. The outbox cannot answer that: once an
/// operation has been sent it is cleared, and the device forgets the clock its
/// own row carries. Without this table a device that has pushed accepts every
/// incoming operation, and two devices that edited the same row while offline
/// end up holding *each other's* value -- they swap rather than converge.
///
/// One row per entity, overwritten on every local change and on every applied
/// operation. The device id is stored because it breaks ties: two devices can
/// produce the same clock offline, and the rule only has to be deterministic.
class SyncEntityVersions extends Table {
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  IntColumn get logicalClock => integer()();
  TextColumn get deviceId => text()();

  @override
  Set<Column> get primaryKey => {entityType, entityId};
}

/// 22. Vault Environment Variables (per-workspace, encrypted with the vault DEK)
///
/// Every value is encrypted the same way an identity secret is — there is no
/// "secret vs. non-secret" distinction here, because the whole point is that
/// these are the kind of value (API tokens, auth keys) someone would not want
/// sitting in the database in the clear.
///
/// [name] is kept unique within a workspace by the repository, not by a
/// UNIQUE constraint: two devices can each add the same name offline, and a
/// constraint would make the second row fail to apply on sync, stalling every
/// operation queued behind it. A duplicate that arrives that way is resolved
/// when a shell starts instead.
class VaultEnvVars extends Table {
  @override
  String get tableName => 'vault_env_vars';

  TextColumn get id => text()();
  TextColumn get workspaceId =>
      text().references(Workspaces, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  TextColumn get valueEncrypted => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
