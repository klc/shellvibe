/// Shared enumerations for the MCP agent-access layer.
///
/// These are the contract every MCP component agrees on: the classifier
/// produces a [RiskCategory], the policy engine turns it into a
/// [PolicyAction], and the transport reports failures as an `McpErrorCode`
/// (`core/mcp/mcp_errors.dart`, re-exported here).
library;

export '../../../../core/mcp/mcp_errors.dart' show McpErrorCode;

/// How much an agent client is allowed to do on one host.
///
/// The decision is anchored to the machine, not to the command: a `readonly`
/// host stays read-only no matter how harmless a command looks.
enum McpAccessMode {
  /// Only commands classified [RiskCategory.readonlySafe] run. Anything else,
  /// including commands the classifier cannot place, is denied outright.
  readonly,

  /// Risky commands are surfaced to the user for approval before they run.
  guarded,

  /// Risky commands run without asking, except on production hosts.
  ///
  /// Not offered in v0; the value exists so stored rows and the policy matrix
  /// do not need a migration when it ships.
  autonomous;

  static McpAccessMode fromName(String value) => switch (value) {
    'readonly' => McpAccessMode.readonly,
    'guarded' => McpAccessMode.guarded,
    'autonomous' => McpAccessMode.autonomous,
    // An unknown persisted value must never widen access.
    _ => McpAccessMode.readonly,
  };
}

/// Deployment criticality of a host, used as an override on top of the policy
/// matrix: nothing destructive runs unattended on `prod`.
enum HostEnvironment {
  dev,
  staging,
  prod;

  static HostEnvironment fromName(String value) => switch (value) {
    'staging' => HostEnvironment.staging,
    'prod' => HostEnvironment.prod,
    _ => HostEnvironment.dev,
  };
}

/// What a command is judged to do, as produced by `CommandClassifier`.
///
/// This is a UX signal, not a security boundary: a determined command can
/// evade it (`base64 -d | sh`). The real boundaries are human approval,
/// server-side restrictions, and the audit log.
enum RiskCategory {
  /// Reads state without changing it: `ls`, `cat`, `df`, `systemctl status`.
  readonlySafe,

  /// Destroys files: `rm -rf`, `shred`, `mkfs`, `dd of=`, `find -delete`.
  destructiveFs,

  /// Escalates privileges: `sudo`, `su`, `doas`, `chmod u+s`.
  privilege,

  /// Starts, stops or masks services; reboots or halts the machine.
  serviceControl,

  /// Installs or removes packages.
  package,

  /// Changes users, ownership or permissions.
  identityPerm,

  /// Changes firewall or network filtering rules.
  networkFw,

  /// Mutates a database: `DROP`, `TRUNCATE`, unqualified `DELETE`.
  database,

  /// Rewrites version control history or discards work.
  vcs,

  /// Removes or prunes containers and cluster objects.
  container,

  /// Executes content the classifier cannot read: `curl … | sh`, `eval`,
  /// `base64 -d | sh`.
  opaqueExec,

  /// Needs a terminal and would block the session: `vim`, `top`, `less`.
  interactive,

  /// Reads credential material: `cat …/.env`, `/etc/shadow`, `printenv`.
  secretRead,

  /// The classifier could not place the command. Treated as risky.
  unclassified;

  String get wireName => switch (this) {
    RiskCategory.readonlySafe => 'readonly_safe',
    RiskCategory.destructiveFs => 'destructive_fs',
    RiskCategory.privilege => 'privilege',
    RiskCategory.serviceControl => 'service_control',
    RiskCategory.package => 'package',
    RiskCategory.identityPerm => 'identity_perm',
    RiskCategory.networkFw => 'network_fw',
    RiskCategory.database => 'database',
    RiskCategory.vcs => 'vcs',
    RiskCategory.container => 'container',
    RiskCategory.opaqueExec => 'opaque_exec',
    RiskCategory.interactive => 'interactive',
    RiskCategory.secretRead => 'secret_read',
    RiskCategory.unclassified => 'unclassified',
  };

  /// Categories that may never be silently repeated on a production host.
  bool get isDestructive => switch (this) {
    RiskCategory.destructiveFs ||
    RiskCategory.serviceControl ||
    RiskCategory.identityPerm ||
    RiskCategory.database => true,
    _ => false,
  };
}

/// What the policy engine decided to do with one command.
enum PolicyAction {
  /// Run it without asking.
  allow,

  /// Ask the user first; run only if they approve.
  confirm,

  /// Refuse. The agent is told the category and why.
  deny,

  /// Refuse, but hand back a batch-mode alternative the agent can retry with.
  rejectInteractive,
}

/// How long an approval is remembered.
///
/// Every remembered approval is bound to the exact `(client, host, cwd,
/// normalized command)` tuple. It is never generalized into a pattern — the
/// user writes patterns themselves as policy rules.
enum ApprovalScope {
  once,
  fifteenMinutes,
  session,
  always;

  static ApprovalScope fromName(String value) => switch (value) {
    'fifteen_minutes' => ApprovalScope.fifteenMinutes,
    'session' => ApprovalScope.session,
    'always' => ApprovalScope.always,
    _ => ApprovalScope.once,
  };

  String get wireName => switch (this) {
    ApprovalScope.once => 'once',
    ApprovalScope.fifteenMinutes => 'fifteen_minutes',
    ApprovalScope.session => 'session',
    ApprovalScope.always => 'always',
  };
}

/// The outcome recorded in the audit log for one tool call.
enum AuditDecision {
  allowed,
  confirmed,
  denied,
  autoDenied,
  error;

  String get wireName => switch (this) {
    AuditDecision.allowed => 'allowed',
    AuditDecision.confirmed => 'confirmed',
    AuditDecision.denied => 'denied',
    AuditDecision.autoDenied => 'auto_denied',
    AuditDecision.error => 'error',
  };

  /// Reverses [wireName] for a stored audit row. An unrecognized value must
  /// never read as a quiet success.
  static AuditDecision fromName(String value) => switch (value) {
    'allowed' => AuditDecision.allowed,
    'confirmed' => AuditDecision.confirmed,
    'denied' => AuditDecision.denied,
    'auto_denied' => AuditDecision.autoDenied,
    _ => AuditDecision.error,
  };
}
