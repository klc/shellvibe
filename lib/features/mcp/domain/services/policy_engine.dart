import '../../../../shared/database/app_database.dart';
import '../../../../shared/database/daos/mcp_dao.dart';
import '../../data/repositories/mcp_approval_repository.dart';
import '../../data/repositories/mcp_grant_repository.dart';
import '../models/mcp_enums.dart';
import '../models/mcp_models.dart';
import 'command_classifier.dart';

/// Turns one command, in the context it is about to run in, into a
/// [PolicyDecision] — the single place every other MCP tool asks "may this
/// happen?" before it happens.
///
/// See `docs/mcp_plan.md`, "Faz 4 — Politika motoru", for the design this
/// class implements verbatim: the evaluation order, the risk-category
/// decision matrix, and the production override.
class PolicyEngine {
  final McpGrantRepository grants;
  final McpApprovalRepository approvals;
  final McpDao dao;
  final CommandClassifier classifier;

  const PolicyEngine({
    required this.grants,
    required this.approvals,
    required this.dao,
    this.classifier = const CommandClassifier(),
  });

  /// Evaluates [ctx] against the full policy stack, in exactly this order
  /// (mirrors the plan's "Değerlendirme sırası" list — do not reorder):
  ///
  /// 1. Does a live [McpGrantRepository] grant exist for (client, host)? If
  ///    not, the agent never asked for access — throw
  ///    [McpErrorCode.hostAccessRequired] rather than opening a dialog on its
  ///    behalf.
  /// 2. Is the command [RiskCategory.interactive]? If so, refuse with
  ///    [PolicyAction.rejectInteractive] and hand back the classifier's
  ///    batch-mode hint. This is checked *before* user policy rules on
  ///    purpose: an interactive command cannot run over a PTY-less channel no
  ///    matter what a rule says — there is nothing a rule could allow here.
  /// 3. User-defined policy rules for the workspace (`McpPolicyRules`),
  ///    ascending `priority`; the first enabled rule whose scope and pattern
  ///    match wins outright.
  /// 4. Is there a remembered approval for this exact `(client, host, cwd,
  ///    normalized command)` tuple? If so, allow, flagged
  ///    [PolicyDecision.fromRememberedApproval].
  /// 5. Classify the command into a [RiskCategory]. (Implementation note:
  ///    the classification is actually computed once, up front, and reused
  ///    for both step 2 and this step — the command only ever goes through
  ///    the regex classifier a single time per call.)
  /// 6. Look up (category × mode) in the decision matrix — see
  ///    [_matrixAction] — to get [PolicyAction.allow], `.confirm` or `.deny`.
  ///
  /// The production override in [_applyProductionOverride] is layered on top
  /// of step 6's result only — never on top of a user rule or a remembered
  /// approval, matching the plan's "matrisin üstüne biner" (sits on top of
  /// the matrix) wording precisely. It is the one rule that survives every
  /// mode: a `deny` is never upgraded, and no destructive category or
  /// `opaqueExec` may come out of the matrix as `allow` on a production host.
  Future<PolicyDecision> evaluate(
    CommandContext ctx, {
    required String workspaceId,
    DateTime? now,
  }) async {
    // 1. Grant.
    final mode = await grants.effectiveMode(ctx.clientId, ctx.hostId, now: now);
    if (mode == null) {
      throw McpToolException(
        McpErrorCode.hostAccessRequired,
        'No access has been granted for this host yet. Call '
        'request_host_access before running commands on it.',
        details: {'hostId': ctx.hostId},
      );
    }

    // Classified once, reused by both the interactive check (step 2) and the
    // matrix lookup (steps 5-6).
    final classification = classifier.classify(ctx.command, cwd: ctx.cwd);

    // 2. Interactive commands are refused unconditionally, before any rule
    // gets a say.
    if (classification.category == RiskCategory.interactive) {
      return PolicyDecision(
        action: PolicyAction.rejectInteractive,
        category: RiskCategory.interactive,
        message: _interactiveMessage(ctx.command, classification),
        hint: classification.batchAlternative,
      );
    }

    // 3. User-defined policy rules, ascending priority, first match wins.
    final rules = await dao.getPolicyRulesForWorkspace(workspaceId);
    final ruleAction = _matchUserRule(rules, ctx);
    if (ruleAction != null) {
      // The production override sits above user rules, not beside them. The
      // plan's rule is unconditional — "no destructive category passes
      // without approval on prod, whatever the mode" — and a rule that
      // auto-allows is exactly a destructive category passing without
      // approval. The rule still decides *what* happens; production only
      // insists a human sees it first.
      return _finish(
        _applyProductionOverride(
          PolicyDecision(action: ruleAction, category: classification.category),
          ctx.environment,
        ),
        ctx,
      );
    }

    // 4. Remembered approval for this exact (client, host, cwd, command).
    final remembered = await approvals.hasApproval(
      clientId: ctx.clientId,
      hostId: ctx.hostId,
      cwd: ctx.cwd,
      command: ctx.command,
      now: now,
    );
    if (remembered) {
      // The override applies here too. An approval is only refused storage
      // while the host is *currently* production (see [canRemember]) — but a
      // host gets re-tagged, and an approval recorded while it was `dev`
      // would otherwise keep auto-running a destructive command on it after
      // the tag changed. The environment is read at decision time, so a host
      // becoming production immediately re-arms the prompt.
      return _finish(
        _applyProductionOverride(
          PolicyDecision(
            action: PolicyAction.allow,
            category: classification.category,
            fromRememberedApproval: true,
          ),
          ctx.environment,
        ),
        ctx,
      );
    }

    // 5 & 6. (category × mode) matrix, then the production override on top.
    final matrixAction = _matrixAction(classification.category, mode);
    final withOverride = _applyProductionOverride(
      PolicyDecision(action: matrixAction, category: classification.category),
      ctx.environment,
    );
    return _finish(withOverride, ctx);
  }

  /// Whether an approval for this (category, environment) pair may be
  /// remembered at all — independent of which [ApprovalScope] the user
  /// picks in the dialog.
  ///
  /// These two exceptions are the only thing standing between an "approve
  /// everything" reflex and production, and they are non-negotiable:
  ///
  /// - A destructive category ([RiskCategory.isDestructive]) on a
  ///   [HostEnvironment.prod] host must be looked at every single time.
  /// - [RiskCategory.opaqueExec] must be looked at every single time,
  ///   everywhere, because the classifier could not read what it actually
  ///   runs — remembering it would mean trusting a blank check forever.
  bool canRemember(RiskCategory category, HostEnvironment environment) {
    if (environment == HostEnvironment.prod && category.isDestructive) {
      return false;
    }
    if (category == RiskCategory.opaqueExec) {
      return false;
    }
    return true;
  }

  // -------------------------------------------------------------------
  // Step 3 — user policy rules.
  // -------------------------------------------------------------------

  PolicyAction? _matchUserRule(List<McpPolicyRule> rules, CommandContext ctx) {
    for (final rule in rules) {
      if (!rule.enabled) continue;
      if (!_scopeMatches(rule.scopeType, rule.scopeId, ctx)) continue;
      if (!_patternMatches(rule.matchType, rule.pattern, ctx.command)) continue;
      return _actionFromName(rule.action);
    }
    return null;
  }

  bool _scopeMatches(String scopeType, String? scopeId, CommandContext ctx) {
    switch (scopeType) {
      case 'global':
        return true;
      case 'host':
        return scopeId == ctx.hostId;
      case 'group':
        // A host outside every group cannot match a group-scoped rule, and a
        // rule with no group id is malformed — both fall through to the
        // matrix rather than matching on a guess.
        if (scopeId == null || ctx.hostGroupId == null) return false;
        return scopeId == ctx.hostGroupId;
      default:
        return false;
    }
  }

  bool _patternMatches(String matchType, String pattern, String command) {
    switch (matchType) {
      case 'exact':
        return command.trim() == pattern;
      case 'prefix':
        return command.trimLeft().startsWith(pattern);
      case 'regex':
        try {
          return RegExp(pattern).hasMatch(command);
        } catch (_) {
          // A malformed regex must never crash policy evaluation, and must
          // never be treated as "matches everything" either — "no match"
          // falls through to the matrix, the strictest of the remaining
          // options.
          return false;
        }
      default:
        return false;
    }
  }

  PolicyAction _actionFromName(String action) => switch (action) {
    'allow' => PolicyAction.allow,
    'confirm' => PolicyAction.confirm,
    'deny' => PolicyAction.deny,
    // An unknown persisted value must never widen access.
    _ => PolicyAction.deny,
  };

  // -------------------------------------------------------------------
  // Steps 5 & 6 — category x mode matrix.
  // -------------------------------------------------------------------

  /// The (category × mode) part of the decision matrix.
  ///
  /// `unclassified`, `secretRead`, and every category that is not
  /// [RiskCategory.readonlySafe], [RiskCategory.opaqueExec] or
  /// [RiskCategory.interactive] (i.e. `destructiveFs`, `privilege`,
  /// `serviceControl`, `package`, `identityPerm`, `networkFw`, `database`,
  /// `vcs`, `container`) share one deny/confirm/allow shape across
  /// readonly/guarded/autonomous — the plan's table collapses all of these
  /// into a single "yıkıcı kategoriler" (destructive categories) row.
  /// `readonlySafe` always allows. `opaqueExec` never reaches `allow` from
  /// this matrix (deny/deny/confirm). `interactive` is handled in step 2 and
  /// never reaches this switch; the case exists only to keep it exhaustive.
  PolicyAction _matrixAction(RiskCategory category, McpAccessMode mode) {
    switch (category) {
      case RiskCategory.readonlySafe:
        return PolicyAction.allow;
      case RiskCategory.opaqueExec:
        return switch (mode) {
          McpAccessMode.readonly => PolicyAction.deny,
          McpAccessMode.guarded => PolicyAction.deny,
          McpAccessMode.autonomous => PolicyAction.confirm,
        };
      case RiskCategory.interactive:
        return PolicyAction.rejectInteractive;
      case RiskCategory.unclassified:
      case RiskCategory.secretRead:
      case RiskCategory.destructiveFs:
      case RiskCategory.privilege:
      case RiskCategory.serviceControl:
      case RiskCategory.package:
      case RiskCategory.identityPerm:
      case RiskCategory.networkFw:
      case RiskCategory.database:
      case RiskCategory.vcs:
      case RiskCategory.container:
        return switch (mode) {
          McpAccessMode.readonly => PolicyAction.deny,
          McpAccessMode.guarded => PolicyAction.confirm,
          McpAccessMode.autonomous => PolicyAction.allow,
        };
    }
  }

  /// The production override: the one rule that survives every mode.
  ///
  /// On a [HostEnvironment.prod] host, nothing the matrix classified as a
  /// destructive category ([RiskCategory.isDestructive]) or as
  /// [RiskCategory.opaqueExec] may come out as [PolicyAction.allow] — it is
  /// downgraded to [PolicyAction.confirm] and [PolicyDecision.productionOverride]
  /// is set so the UI can say *why* a mode that would normally auto-approve
  /// still stopped to ask. A [PolicyAction.deny] is never upgraded by this
  /// step; the override only ever makes a decision stricter, never looser.
  PolicyDecision _applyProductionOverride(
    PolicyDecision decision,
    HostEnvironment environment,
  ) {
    if (environment != HostEnvironment.prod) return decision;
    if (decision.action != PolicyAction.allow) return decision;
    final overridable =
        decision.category.isDestructive ||
        decision.category == RiskCategory.opaqueExec;
    if (!overridable) return decision;
    return PolicyDecision(
      action: PolicyAction.confirm,
      category: decision.category,
      message: decision.message,
      hint: decision.hint,
      fromRememberedApproval: decision.fromRememberedApproval,
      productionOverride: true,
    );
  }

  // -------------------------------------------------------------------
  // Messages — populated on every refusal so the agent has something it
  // can read and act on, not just a bare rejection.
  // -------------------------------------------------------------------

  PolicyDecision _finish(PolicyDecision decision, CommandContext ctx) {
    if (decision.message != null) return decision;
    return PolicyDecision(
      action: decision.action,
      category: decision.category,
      message: _messageFor(decision, ctx),
      hint: decision.hint,
      fromRememberedApproval: decision.fromRememberedApproval,
      productionOverride: decision.productionOverride,
    );
  }

  String? _messageFor(PolicyDecision decision, CommandContext ctx) {
    final categoryLabel = decision.category.wireName;
    final envLabel = _envLabel(ctx.environment);
    switch (decision.action) {
      case PolicyAction.allow:
        return null;
      case PolicyAction.rejectInteractive:
        // Populated directly where rejectInteractive is constructed, since
        // that message needs the classifier's batch-mode hint, not just the
        // category name.
        return null;
      case PolicyAction.deny:
        return 'This command was refused on a $envLabel host in '
            '${ctx.mode.name} mode (category: $categoryLabel).';
      case PolicyAction.confirm:
        if (decision.productionOverride) {
          return 'This command would normally run without asking in '
              '${ctx.mode.name} mode, but category $categoryLabel is never '
              'auto-approved on a $envLabel host — it needs explicit '
              'confirmation instead.';
        }
        return 'This command needs user confirmation on a $envLabel host in '
            '${ctx.mode.name} mode (category: $categoryLabel).';
    }
  }

  String _interactiveMessage(
    String command,
    CommandClassification classification,
  ) {
    final alt = classification.batchAlternative;
    final reason = classification.reason ?? 'needs an interactive terminal';
    if (alt != null) {
      return '`$command` $reason. Use a batch-mode alternative instead: '
          '`$alt`.';
    }
    return '`$command` $reason and cannot run over this channel.';
  }

  String _envLabel(HostEnvironment environment) => switch (environment) {
    HostEnvironment.dev => 'development',
    HostEnvironment.staging => 'staging',
    HostEnvironment.prod => 'production',
  };
}
