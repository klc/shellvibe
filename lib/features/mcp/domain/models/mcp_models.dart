import 'mcp_enums.dart';

/// Value types exchanged between the MCP components.
///
/// Every type here is plain data with no Flutter or database dependency, so
/// the domain services can be unit tested without a widget binding.

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

/// How much of a command's output was dropped to stay under the size cap.
class OutputTruncation {
  final int originalBytes;
  final int keptBytes;

  const OutputTruncation({
    required this.originalBytes,
    required this.keptBytes,
  });

  Map<String, Object?> toJson() => {
    'originalBytes': originalBytes,
    'keptBytes': keptBytes,
  };
}

/// The result of running one command over a persistent shell session.
class ShellCommandResult {
  final String stdout;
  final String stderr;
  final int exitCode;

  /// Working directory after the command ran, read from the sentinel line.
  ///
  /// Returned on every call so the agent always knows where it is; this alone
  /// removes a large class of hallucinated paths.
  final String cwd;

  final int durationMs;

  /// Set when output exceeded the cap and the middle was dropped.
  final OutputTruncation? truncated;

  /// Number of secrets masked in [stdout] and [stderr] combined.
  ///
  /// Reported even when zero-valued fields are omitted elsewhere: an agent
  /// that does not know something was hidden will reason from incomplete data.
  final int redactedCount;

  /// The command did not finish on its own and was interrupted with Ctrl-C.
  final bool interrupted;

  /// The shell channel could not be recovered and was reopened, so any shell
  /// state the agent had built up (variables, `cd`, background jobs) is gone.
  final bool sessionReset;

  const ShellCommandResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.cwd,
    required this.durationMs,
    this.truncated,
    this.redactedCount = 0,
    this.interrupted = false,
    this.sessionReset = false,
  });

  Map<String, Object?> toJson() => {
    'stdout': stdout,
    'stderr': stderr,
    'exitCode': exitCode,
    'cwd': cwd,
    'durationMs': durationMs,
    if (truncated != null) 'truncated': truncated!.toJson(),
    if (redactedCount > 0) 'redacted': {'count': redactedCount},
    if (interrupted) 'interrupted': true,
    if (sessionReset) 'sessionReset': true,
  };
}

/// Text with its secrets masked, plus how many were masked.
class RedactionResult {
  final String text;
  final int count;

  const RedactionResult(this.text, this.count);
}

/// One command's classification, including the self-correction hint that makes
/// an interactive rejection useful instead of merely blocking.
class CommandClassification {
  final RiskCategory category;

  /// For [RiskCategory.interactive], the batch-mode command to suggest
  /// instead — `top -b -n1` for `top`, `tail -n 200` for `tail -f`.
  final String? batchAlternative;

  /// Human-readable reason, used in approval dialogs and audit rows.
  final String? reason;

  const CommandClassification(
    this.category, {
    this.batchAlternative,
    this.reason,
  });
}

/// What the policy engine decided about one command, and why.
class PolicyDecision {
  final PolicyAction action;
  final RiskCategory category;

  /// Message handed to the agent on a refusal.
  final String? message;

  /// Batch-mode suggestion carried over from the classification.
  final String? hint;

  /// True when the decision came from an approval the user already gave for
  /// this exact command, host and cwd.
  final bool fromRememberedApproval;

  /// True when the production override forced a confirmation that the mode
  /// alone would have allowed.
  final bool productionOverride;

  const PolicyDecision({
    required this.action,
    required this.category,
    this.message,
    this.hint,
    this.fromRememberedApproval = false,
    this.productionOverride = false,
  });
}

/// The context a command is judged in.
///
/// The same command is not the same risk everywhere: `rm -rf *` in
/// `/tmp/build` and in `/` differ only by [cwd], which the persistent shell
/// always knows.
class CommandContext {
  final String command;
  final String cwd;
  final McpAccessMode mode;
  final HostEnvironment environment;
  final String hostId;
  final String clientId;

  /// The host's group, when it belongs to one.
  ///
  /// Carried here so a `group`-scoped policy rule can be evaluated at all.
  /// Without it such a rule silently never matches, which is worse than not
  /// offering group scoping: the user writes a rule, sees it saved, and it
  /// does nothing.
  final String? hostGroupId;

  const CommandContext({
    required this.command,
    required this.cwd,
    required this.mode,
    required this.environment,
    required this.hostId,
    required this.clientId,
    this.hostGroupId,
  });
}

/// One host in an agent's access request, as answered by the user.
class HostAccessGrant {
  final String hostId;
  final McpAccessMode mode;
  final DateTime? expiresAt;

  const HostAccessGrant({
    required this.hostId,
    required this.mode,
    this.expiresAt,
  });

  Map<String, Object?> toJson() => {
    'hostId': hostId,
    'mode': mode.name,
    if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
  };
}

/// A host the user did not grant, and why — the agent needs this to plan
/// around what it cannot reach instead of retrying blindly.
class HostAccessDenial {
  final String hostId;

  /// `user_denied` · `cooldown` · `not_visible` · `timeout`
  final String reason;

  const HostAccessDenial({required this.hostId, required this.reason});

  Map<String, Object?> toJson() => {'hostId': hostId, 'reason': reason};
}

/// The answer to one `request_host_access` call. Partial approval is the
/// normal case, not an edge case.
class HostAccessResult {
  final List<HostAccessGrant> granted;
  final List<HostAccessDenial> denied;

  const HostAccessResult({required this.granted, required this.denied});

  Map<String, Object?> toJson() => {
    'granted': granted.map((g) => g.toJson()).toList(),
    'denied': denied.map((d) => d.toJson()).toList(),
  };
}

/// The user's answer to a single command approval prompt.
class ApprovalDecision {
  final bool approved;

  /// How long to remember an approval. Ignored when [approved] is false, and
  /// forced to [ApprovalScope.once] when the command may not be remembered.
  final ApprovalScope scope;

  const ApprovalDecision({
    required this.approved,
    this.scope = ApprovalScope.once,
  });

  static const denied = ApprovalDecision(approved: false);
}

/// A pending command approval handed to the UI.
class CommandApprovalRequest {
  final String clientId;
  final String clientName;
  final String hostId;
  final String hostLabel;
  final HostEnvironment environment;
  final String command;
  final String cwd;
  final RiskCategory category;

  /// False when this command may not be remembered: a destructive category on
  /// a production host, or anything the classifier cannot read. The dialog
  /// greys out the remember options rather than hiding them, so the user can
  /// see the rule exists.
  final bool canRemember;

  const CommandApprovalRequest({
    required this.clientId,
    required this.clientName,
    required this.hostId,
    required this.hostLabel,
    required this.environment,
    required this.command,
    required this.cwd,
    required this.category,
    required this.canRemember,
  });
}

/// A pending host-access approval handed to the UI.
class HostAccessRequest {
  final String clientId;
  final String clientName;
  final String reason;
  final List<HostAccessCandidate> candidates;

  const HostAccessRequest({
    required this.clientId,
    required this.clientName,
    required this.reason,
    required this.candidates,
  });
}

/// One row in the host-access approval window, pre-filled with the host's own
/// default mode so the safe answer is the default answer.
class HostAccessCandidate {
  final String hostId;
  final String label;
  final HostEnvironment environment;
  final McpAccessMode suggestedMode;

  const HostAccessCandidate({
    required this.hostId,
    required this.label,
    required this.environment,
    required this.suggestedMode,
  });
}
