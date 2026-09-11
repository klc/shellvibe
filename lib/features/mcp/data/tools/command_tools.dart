import 'dart:convert';

import 'package:cryptography/dart.dart';

import '../../../../core/mcp/mcp_protocol.dart';
import '../../../../shared/database/daos/hosts_dao.dart';
import '../../domain/models/mcp_enums.dart';
import '../../domain/models/mcp_models.dart';
import '../../domain/services/approval_coordinator.dart';
import '../../domain/services/mcp_session_mirror.dart';
import '../../domain/services/output_redactor.dart';
import '../../domain/services/policy_engine.dart';
import '../mcp_session_pool.dart';
import '../repositories/mcp_approval_repository.dart';
import '../repositories/mcp_audit_repository.dart';
import '../repositories/mcp_grant_repository.dart';
import 'mcp_tool_handler.dart';

/// `run_command` — the only way an agent ever executes anything.
///
/// Every call is a straight pipe through the policy engine before it ever
/// touches the shell: resolve the session, ask [PolicyEngine] what to do,
/// obey it (deny outright, reject with a self-correction hint, ask the user,
/// or just run it), then mask secrets in the output before it leaves this
/// process. Nothing here second-guesses [PolicyEngine]'s decision — this
/// class only ever adds the plumbing (session/host lookup, redaction,
/// remembering an approval, auditing) around whatever it decided.
class RunCommandTool with McpArgReaders implements McpToolHandler {
  final McpSessionPool sessionPool;
  final HostsDao hostsDao;
  final McpGrantRepository grantRepository;
  final McpApprovalRepository approvalRepository;
  final McpAuditRepository auditRepository;
  final PolicyEngine policyEngine;
  final ApprovalCoordinator approvalCoordinator;
  final OutputRedactor redactor;

  const RunCommandTool({
    required this.sessionPool,
    required this.hostsDao,
    required this.grantRepository,
    required this.approvalRepository,
    required this.auditRepository,
    required this.policyEngine,
    required this.approvalCoordinator,
    required this.redactor,
  });

  static const int _defaultTimeoutSeconds = 60;
  static const int _maxTimeoutSeconds = 600;

  @override
  String get name => 'run_command';

  @override
  McpToolDefinition get definition => McpToolDefinition(
    name: name,
    description:
        'Runs one shell command over an already-open session (see '
        'open_session). The command is checked against this host\'s access '
        'policy before it runs: it may execute immediately, be denied '
        'outright (POLICY_DENIED), be rejected because it needs a terminal '
        '(INTERACTIVE_COMMAND — the error message gives you a batch-mode '
        'command to retry with instead), or pause while the user is asked '
        'to approve it. `cd` and environment persist across calls on the '
        'same session; the response always reports the resulting working '
        'directory. stdout/stderr are scanned and secrets are masked as '
        '`[REDACTED:type]` before being returned.',
    inputSchema: const {
      'type': 'object',
      'properties': {
        'sessionId': {
          'type': 'string',
          'description': 'The sessionId returned by open_session.',
        },
        'command': {
          'type': 'string',
          'description':
              'The full shell command to run, exactly as it should be typed '
              'at a prompt. Runs in the session\'s current working '
              'directory; use `cd` within the command to change it.',
        },
        'timeoutSeconds': {
          'type': 'integer',
          'minimum': 1,
          'maximum': _maxTimeoutSeconds,
          'description':
              'How long to wait for the command before attempting recovery '
              '(Ctrl-C, then reopening the shell if that does not work). '
              'Defaults to $_defaultTimeoutSeconds; clamped to a maximum of '
              '$_maxTimeoutSeconds.',
        },
      },
      'required': ['sessionId', 'command'],
      'additionalProperties': false,
    },
  );

  @override
  Future<Object?> execute(McpToolContext ctx, Map<String, Object?> args) async {
    final sessionId = requireString(args, 'sessionId');
    final command = requireString(args, 'command');
    final rawTimeout =
        optionalInt(args, 'timeoutSeconds') ?? _defaultTimeoutSeconds;
    final timeoutSeconds = rawTimeout < 1
        ? 1
        : (rawTimeout > _maxTimeoutSeconds ? _maxTimeoutSeconds : rawTimeout);

    final session = sessionPool.find(sessionId);
    if (session == null || session.clientId != ctx.clientId) {
      throw McpToolException(
        McpErrorCode.sessionNotFound,
        'No open session with id "$sessionId" for this client.',
      );
    }

    // Re-checked here rather than trusted from `open_session` time: a grant
    // can expire, be revoked, or enter cooldown while a session stays open
    // for the idle-timeout window (default 30 minutes), and `McpSession`
    // itself carries no mode of its own (see mcp_session_pool.dart) — the
    // grant is the single source of truth for "what may run here right now."
    final mode = await grantRepository.effectiveMode(
      ctx.clientId,
      session.hostId,
    );
    if (mode == null) {
      throw McpToolException(
        McpErrorCode.hostAccessRequired,
        'Access to host "${session.hostId}" is no longer granted. Call '
        'request_host_access again before running more commands.',
      );
    }

    final hostRow = await hostsDao.getHostById(session.hostId);
    // A host row that vanished mid-session (deleted, or a workspace swapped
    // underneath) is treated as production, not as dev. `dev` is the loosest
    // environment there is, so guessing it here would quietly drop the one
    // override that keeps destructive commands in front of a human.
    final environment = hostRow == null
        ? HostEnvironment.prod
        : HostEnvironment.fromName(hostRow.environment);

    final commandContext = CommandContext(
      command: command,
      cwd: session.shell.cwd,
      mode: mode,
      environment: environment,
      hostId: session.hostId,
      clientId: ctx.clientId,
      hostGroupId: hostRow?.groupId,
    );

    final decision = await policyEngine.evaluate(
      commandContext,
      workspaceId: ctx.workspaceId,
    );

    // The command text itself can contain a literal secret (`mysql
    // -ppassword`, a curl with a bearer header, ...) — the audit log's
    // `args` must be the redacted form exactly like the output is, per
    // `McpAuditRepository`'s own contract that it performs no masking of
    // its own.
    final redactedCommand = redactor.redact(command).text;

    switch (decision.action) {
      case PolicyAction.deny:
        await _audit(
          ctx: ctx,
          session: session,
          redactedCommand: redactedCommand,
          timeoutSeconds: timeoutSeconds,
          decision: AuditDecision.denied,
          category: decision.category,
        );
        _notifyRefused(session, command, 'denied by policy');
        return {
          'error': 'POLICY_DENIED',
          'category': decision.category.wireName,
          'message': decision.message ?? 'This command was denied by policy.',
        };

      case PolicyAction.rejectInteractive:
        await _audit(
          ctx: ctx,
          session: session,
          redactedCommand: redactedCommand,
          timeoutSeconds: timeoutSeconds,
          decision: AuditDecision.denied,
          category: decision.category,
        );
        _notifyRefused(session, command, 'needs a terminal — refused');
        return {
          'error': 'INTERACTIVE_COMMAND',
          'message': _interactiveRejectionMessage(decision),
        };

      case PolicyAction.confirm:
        final approvalRequest = CommandApprovalRequest(
          clientId: ctx.clientId,
          clientName: ctx.clientName,
          hostId: session.hostId,
          hostLabel: session.hostLabel,
          environment: environment,
          command: command,
          cwd: session.shell.cwd,
          category: decision.category,
          canRemember: policyEngine.canRemember(decision.category, environment),
        );
        final approval = await approvalCoordinator.requestCommandApproval(
          approvalRequest,
        );
        if (!approval.approved) {
          await _audit(
            ctx: ctx,
            session: session,
            redactedCommand: redactedCommand,
            timeoutSeconds: timeoutSeconds,
            decision: AuditDecision.denied,
            category: decision.category,
          );
          _notifyRefused(session, command, 'you declined it');
          return {
            'error': 'POLICY_DENIED',
            'category': decision.category.wireName,
            'message': 'The user declined to approve this command.',
          };
        }
        if (approval.scope != ApprovalScope.once) {
          await approvalRepository.remember(
            clientId: ctx.clientId,
            hostId: session.hostId,
            cwd: session.shell.cwd,
            command: command,
            scope: approval.scope,
            connectionScopeId: ctx.connectionScopeId,
          );
        }
        return _runAndAudit(
          ctx: ctx,
          session: session,
          command: command,
          redactedCommand: redactedCommand,
          timeoutSeconds: timeoutSeconds,
          category: decision.category,
          successDecision: AuditDecision.confirmed,
        );

      case PolicyAction.allow:
        return _runAndAudit(
          ctx: ctx,
          session: session,
          command: command,
          redactedCommand: redactedCommand,
          timeoutSeconds: timeoutSeconds,
          category: decision.category,
          successDecision: AuditDecision.allowed,
        );
    }
    // No fallback needed: the switch covers every `PolicyAction`, so adding a
    // new action upstream turns this into a compile error rather than a
    // silently-skipped branch — which is the failure mode worth having.
  }

  /// Runs [command] on [session], redacts its output, audits the outcome,
  /// and returns the payload the agent sees. Shared by the `allow` path and
  /// the post-approval half of the `confirm` path — both end up doing
  /// exactly this once the decision to run is made.
  Future<Object?> _runAndAudit({
    required McpToolContext ctx,
    required McpSession session,
    required String command,
    required String redactedCommand,
    required int timeoutSeconds,
    required RiskCategory category,
    required AuditDecision successDecision,
  }) async {
    // Echoed before the command runs, not after it returns: the watching
    // user has to see a long-running command while it is still running, not
    // learn about it once it is already done.
    _mirror(
      session,
    )?.writeCommand(session.tabId!, command: command, cwd: session.shell.cwd);
    try {
      final raw = await session.shell.run(
        command,
        timeout: Duration(seconds: timeoutSeconds),
      );
      session.lastActivityAt = DateTime.now();

      final stdoutRedaction = redactor.redact(raw.stdout);
      final stderrRedaction = redactor.redact(raw.stderr);
      final result = ShellCommandResult(
        stdout: stdoutRedaction.text,
        stderr: stderrRedaction.text,
        exitCode: raw.exitCode,
        cwd: raw.cwd,
        durationMs: raw.durationMs,
        truncated: raw.truncated,
        redactedCount: stdoutRedaction.count + stderrRedaction.count,
        interrupted: raw.interrupted,
        sessionReset: raw.sessionReset,
      );

      _mirror(session)?.writeResult(
        session.tabId!,
        stdout: result.stdout,
        stderr: result.stderr,
        exitCode: result.exitCode,
        durationMs: result.durationMs,
      );
      if (result.interrupted || result.sessionReset) {
        _mirror(session)?.writeNotice(
          session.tabId!,
          result.sessionReset
              ? 'shell was rebuilt — variables and background jobs are gone'
              : 'command was interrupted',
        );
      }

      final outputBytes =
          utf8.encode(result.stdout).length + utf8.encode(result.stderr).length;
      final outputSha256 = _sha256Hex('${result.stdout} ${result.stderr}');

      await _audit(
        ctx: ctx,
        session: session,
        redactedCommand: redactedCommand,
        timeoutSeconds: timeoutSeconds,
        decision: successDecision,
        category: category,
        exitCode: result.exitCode,
        durationMs: result.durationMs,
        outputBytes: outputBytes,
        outputSha256: outputSha256,
      );

      return result.toJson();
    } catch (_) {
      await _audit(
        ctx: ctx,
        session: session,
        redactedCommand: redactedCommand,
        timeoutSeconds: timeoutSeconds,
        decision: AuditDecision.error,
        category: category,
      );
      rethrow;
    }
  }

  Future<void> _audit({
    required McpToolContext ctx,
    required McpSession session,
    required String redactedCommand,
    required int timeoutSeconds,
    required AuditDecision decision,
    RiskCategory? category,
    int? exitCode,
    int? durationMs,
    int? outputBytes,
    String? outputSha256,
  }) {
    return auditRepository.record(
      clientId: ctx.clientId,
      clientName: ctx.clientName,
      hostId: session.hostId,
      hostLabel: session.hostLabel,
      tool: name,
      args: {
        'sessionId': session.sessionId,
        'command': redactedCommand,
        'timeoutSeconds': timeoutSeconds,
      },
      decision: decision,
      category: category,
      exitCode: exitCode,
      durationMs: durationMs,
      outputBytes: outputBytes,
      outputSha256: outputSha256,
    );
  }

  /// Builds the one message in the whole tool surface an agent is expected
  /// to read and act on programmatically: which command was rejected, why,
  /// and exactly what to retry with. Imperative and concrete on purpose —
  /// see `docs/mcp_plan.md`'s own worked example (`top` → `top -b -n1`).
  /// The session's watchable surface, or null when nobody is watching this
  /// one — an agent connected before the UI existed, or a mirror that could
  /// not open a tab. Every call site is guarded by this rather than by a
  /// flag, so an unwatched session simply skips the mirroring.
  McpSessionMirror? _mirror(McpSession session) =>
      session.tabId == null ? null : sessionPool.mirror;

  /// Shows a command that was never run. The user watching this tab has to
  /// see the attempt, not just the commands that made it past the policy —
  /// what an agent tried is at least as interesting as what it managed.
  void _notifyRefused(McpSession session, String command, String reason) {
    final mirror = _mirror(session);
    if (mirror == null) return;
    mirror.writeCommand(
      session.tabId!,
      command: command,
      cwd: session.shell.cwd,
    );
    mirror.writeNotice(session.tabId!, reason);
  }

  /// The refusal text for an interactive command.
  ///
  /// [PolicyEngine] already writes the whole thing — what was rejected, why,
  /// and the batch-mode command to retry with — so this only supplies a
  /// fallback for a decision that somehow carries no message. Appending the
  /// hint here as well would state the alternative twice in one sentence
  /// pair, which is exactly what the agent reads as two different
  /// suggestions.
  String _interactiveRejectionMessage(PolicyDecision decision) {
    final lead = decision.message?.trim();
    if (lead != null && lead.isNotEmpty) return lead;
    final hint = decision.hint?.trim();
    if (hint != null && hint.isNotEmpty) {
      return 'This command needs a terminal and would block the session. '
          'Retry in non-interactive/batch mode instead: `$hint`.';
    }
    return 'This command needs a terminal and would block the session. There '
        'is no scripted batch-mode alternative for it in this tool surface.';
  }

  String _sha256Hex(String text) {
    final digest = const DartSha256().hashSync(utf8.encode(text));
    return digest.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
