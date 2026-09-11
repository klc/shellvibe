/// Shared enumerations for the MCP agent-access layer.
///
/// These are the contract every MCP component agrees on: the classifier
/// produces a [RiskCategory], the policy engine turns it into a
/// [PolicyAction], and the transport reports failures as an [McpErrorCode].
library;

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

/// Machine-readable failure codes returned to the agent.
///
/// The agent reads these to correct itself, so each one has a distinct,
/// actionable meaning; `internal` is the only catch-all.
enum McpErrorCode {
  /// The vault is locked, so no credential can be resolved.
  vaultLocked,

  /// No grant exists for this host yet; call `request_host_access` first.
  hostAccessRequired,

  /// The policy engine refused this command.
  policyDenied,

  /// The command needs a terminal; a batch alternative is in the message.
  interactiveCommand,

  /// No open session with that id.
  sessionNotFound,

  /// This client already holds the maximum number of concurrent sessions.
  sessionLimitReached,

  /// The host has no POSIX shell to normalize into.
  shellUnsupported,

  /// The host's SSH host key is not in `known_hosts` yet, and the MCP path
  /// never accepts a fingerprint on the user's behalf. Only a human verifying
  /// it from a terminal tab can clear this — retrying cannot.
  hostKeyUntrusted,

  /// The host exists but is hidden from MCP.
  hostNotVisible,

  /// Access to this host was denied recently; requests are refused until the
  /// cooldown expires.
  cooldown,

  /// Missing, revoked, or expired bearer token.
  unauthorized,

  /// Too many requests from this client.
  rateLimited,

  /// Anything not covered above.
  internal;

  String get wireName => switch (this) {
    McpErrorCode.vaultLocked => 'VAULT_LOCKED',
    McpErrorCode.hostAccessRequired => 'HOST_ACCESS_REQUIRED',
    McpErrorCode.policyDenied => 'POLICY_DENIED',
    McpErrorCode.interactiveCommand => 'INTERACTIVE_COMMAND',
    McpErrorCode.sessionNotFound => 'SESSION_NOT_FOUND',
    McpErrorCode.sessionLimitReached => 'SESSION_LIMIT_REACHED',
    McpErrorCode.shellUnsupported => 'SHELL_UNSUPPORTED',
    McpErrorCode.hostKeyUntrusted => 'HOST_KEY_UNTRUSTED',
    McpErrorCode.hostNotVisible => 'HOST_NOT_VISIBLE',
    McpErrorCode.cooldown => 'COOLDOWN',
    McpErrorCode.unauthorized => 'UNAUTHORIZED',
    McpErrorCode.rateLimited => 'RATE_LIMITED',
    McpErrorCode.internal => 'INTERNAL_ERROR',
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
}
