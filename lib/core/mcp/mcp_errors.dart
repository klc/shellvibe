/// Machine-readable failure codes returned to the agent.
///
/// The agent reads these to correct itself, so each one has a distinct,
/// actionable meaning; `internal` is the only catch-all.
enum McpErrorCode {
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

  /// No runbook with that id in this client's workspace.
  runbookNotFound,

  /// No run with that id that this client started.
  runNotFound,

  /// A runbook run is already in progress; only one runs at a time.
  runbookBusy,

  /// The variables passed to a runbook are not acceptable.
  invalidVariables,

  /// Anything not covered above.
  internal;

  String get wireName => switch (this) {
    McpErrorCode.hostAccessRequired => 'HOST_ACCESS_REQUIRED',
    McpErrorCode.policyDenied => 'POLICY_DENIED',
    McpErrorCode.interactiveCommand => 'INTERACTIVE_COMMAND',
    McpErrorCode.sessionNotFound => 'SESSION_NOT_FOUND',
    McpErrorCode.sessionLimitReached => 'SESSION_LIMIT_REACHED',
    McpErrorCode.shellUnsupported => 'SHELL_UNSUPPORTED',
    McpErrorCode.hostKeyUntrusted => 'HOST_KEY_UNTRUSTED',
    McpErrorCode.hostNotVisible => 'HOST_NOT_VISIBLE',
    McpErrorCode.runbookNotFound => 'RUNBOOK_NOT_FOUND',
    McpErrorCode.runNotFound => 'RUN_NOT_FOUND',
    McpErrorCode.runbookBusy => 'RUNBOOK_BUSY',
    McpErrorCode.invalidVariables => 'INVALID_VARIABLES',
    McpErrorCode.internal => 'INTERNAL_ERROR',
  };
}

/// A failure an MCP tool reports back to the agent.
///
/// Carries a machine-readable [code] the agent can branch on and a
/// human-readable [message] it can relay to the user or act on — the
/// interactive-command hints depend on the agent actually reading this text.
class McpToolException implements Exception {
  final McpErrorCode code;
  final String message;

  /// Extra fields merged into the error payload, e.g. `category` on a policy
  /// denial or `hint` on an interactive rejection.
  final Map<String, Object?> details;

  const McpToolException(this.code, this.message, {this.details = const {}});

  Map<String, Object?> toJson() => {
    'error': code.wireName,
    'message': message,
    ...details,
  };

  @override
  String toString() => 'McpToolException(${code.wireName}): $message';
}
