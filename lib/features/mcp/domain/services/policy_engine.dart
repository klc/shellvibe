import '../../../../shared/database/app_database.dart';
import '../../../../shared/database/daos/mcp_dao.dart';
import '../../data/repositories/mcp_approval_repository.dart';
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
  final McpApprovalRepository approvals;
  final McpDao dao;
  final CommandClassifier classifier;

  const PolicyEngine({
    required this.approvals,
    required this.dao,
    this.classifier = const CommandClassifier(),
  });

  /// Evaluates [ctx] against the full policy stack, in exactly this order
  /// (mirrors the plan's "Değerlendirme sırası" list — do not reorder):
  ///
  /// 1. The grant. Checked by the caller (`run_command` throws
  ///    `HOST_ACCESS_REQUIRED` and hands the live mode in as [CommandContext.mode])
  ///    so the grant is read once per call, not once here and once there.
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
  ///    [PolicyDecision.fromRememberedApproval]. Skipped for the categories
  ///    that are asked about every time ([canRemember]), so a stored row
  ///    cannot outrank that rule.
  /// 5. Classify the command into a [RiskCategory]. (Implementation note:
  ///    the classification is actually computed once, up front, and reused
  ///    for both step 2 and this step — the command only ever goes through
  ///    the regex classifier a single time per call.)
  /// 6. Look up (category × mode) in the decision matrix — see
  ///    [_matrixAction] — to get [PolicyAction.allow], `.confirm` or `.deny`.
  Future<PolicyDecision> evaluate(
    CommandContext ctx, {
    required String workspaceId,
    DateTime? now,
  }) async {
    // 1. Grant — see the docstring; [ctx.mode] is the live grant.
    final mode = ctx.mode;

    // Classified once, reused by both the interactive check (step 2) and the
    // matrix lookup (steps 5-6).
    final classification = classifier.classify(ctx.command);

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
      return _finish(
        PolicyDecision(action: ruleAction, category: classification.category),
        ctx,
      );
    }

    // 4. Remembered approval for this exact (client, host, cwd, command).
    // A category that is asked about every time is never answered by a
    // stored approval, including one recorded before that rule existed.
    final remembered =
        !_alwaysAsks(classification.category) &&
        await approvals.hasApproval(
          clientId: ctx.clientId,
          hostId: ctx.hostId,
          cwd: ctx.cwd,
          command: ctx.command,
          connectionScopeId: ctx.connectionScopeId,
          now: now,
        );
    if (remembered) {
      return _finish(
        PolicyDecision(
          action: PolicyAction.allow,
          category: classification.category,
          fromRememberedApproval: true,
        ),
        ctx,
      );
    }

    // 5 & 6. (category × mode) matrix.
    return _finish(
      PolicyDecision(
        action: _matrixAction(classification.category, mode),
        category: classification.category,
      ),
      ctx,
    );
  }

  /// Whether an approval for this category may be remembered at all —
  /// independent of which [ApprovalScope] the user picks in the dialog.
  ///
  /// These exceptions are non-negotiable:
  ///
  /// - [RiskCategory.opaqueExec] must be looked at every single time,
  ///   everywhere, because the classifier could not read what it actually
  ///   runs — remembering it would mean trusting a blank check forever.
  /// - [RiskCategory.secretRead] must be looked at every single time,
  ///   everywhere. The matrix never auto-allows it, and a remembered
  ///   approval would turn one "yes" into an agent that reads the same
  ///   credentials unasked from then on.
  bool canRemember(RiskCategory category) => !_alwaysAsks(category);

  /// Categories a human is asked about on every call.
  static bool _alwaysAsks(RiskCategory category) =>
      category == RiskCategory.opaqueExec ||
      category == RiskCategory.secretRead;

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
        // matrix rather than matching on a guess. A host with several tags
        // matches when any one of them is the rule's group.
        return scopeId != null && ctx.hostGroupIds.contains(scopeId);
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
  /// `unclassified` and every category that is not
  /// [RiskCategory.readonlySafe], [RiskCategory.opaqueExec],
  /// [RiskCategory.secretRead] or [RiskCategory.interactive] (i.e.
  /// `destructiveFs`, `privilege`, `serviceControl`, `package`,
  /// `identityPerm`, `networkFw`, `database`, `vcs`, `container`) share one
  /// deny/confirm/allow shape across readonly/guarded/autonomous — the plan's
  /// table collapses all of these into a single "yıkıcı kategoriler"
  /// (destructive categories) row. `readonlySafe` always allows.
  /// `opaqueExec` never reaches `allow` from this matrix (deny/deny/confirm).
  /// `secretRead` never does either (deny/confirm/confirm): output masking
  /// only catches the secret shapes it knows, so reading a credential file is
  /// always a human's call. `interactive` is handled in step 2 and never
  /// reaches this switch; the case exists only to keep it exhaustive.
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
      case RiskCategory.secretRead:
        return switch (mode) {
          McpAccessMode.readonly => PolicyAction.deny,
          McpAccessMode.guarded => PolicyAction.confirm,
          McpAccessMode.autonomous => PolicyAction.confirm,
        };
      case RiskCategory.interactive:
        return PolicyAction.rejectInteractive;
      case RiskCategory.unclassified:
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
    );
  }

  String? _messageFor(PolicyDecision decision, CommandContext ctx) {
    final categoryLabel = decision.category.wireName;
    switch (decision.action) {
      case PolicyAction.allow:
        return null;
      case PolicyAction.rejectInteractive:
        // Populated directly where rejectInteractive is constructed, since
        // that message needs the classifier's batch-mode hint, not just the
        // category name.
        return null;
      case PolicyAction.deny:
        return 'This command was refused in ${ctx.mode.name} mode '
            '(category: $categoryLabel).';
      case PolicyAction.confirm:
        return 'This command needs user confirmation in ${ctx.mode.name} '
            'mode (category: $categoryLabel).';
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
}
