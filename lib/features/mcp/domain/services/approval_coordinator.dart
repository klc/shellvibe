import 'dart:async';

import 'package:uuid/uuid.dart';

import '../models/mcp_enums.dart';
import '../models/mcp_models.dart';

/// A command approval waiting on a human answer.
class PendingCommandApproval {
  final String id;
  final CommandApprovalRequest request;
  final DateTime requestedAt;
  final DateTime expiresAt;

  const PendingCommandApproval({
    required this.id,
    required this.request,
    required this.requestedAt,
    required this.expiresAt,
  });
}

/// A host-access request waiting on a human answer.
class PendingHostAccessApproval {
  final String id;
  final HostAccessRequest request;
  final DateTime requestedAt;
  final DateTime expiresAt;

  const PendingHostAccessApproval({
    required this.id,
    required this.request,
    required this.requestedAt,
    required this.expiresAt,
  });
}

class _PendingCommand {
  final PendingCommandApproval pending;
  final Completer<ApprovalDecision> completer;
  final Timer timer;

  _PendingCommand({
    required this.pending,
    required this.completer,
    required this.timer,
  });
}

class _PendingHostAccess {
  final PendingHostAccessApproval pending;
  final Completer<HostAccessResult> completer;
  final Timer timer;

  _PendingHostAccess({
    required this.pending,
    required this.completer,
    required this.timer,
  });
}

/// The seam between the headless policy layer and the UI.
///
/// Nothing in this class knows about widgets: a request comes in as plain
/// data, goes out on a [Stream] the UI watches, and the UI's eventual answer
/// comes back in through [resolveCommand] / [resolveHostAccess] to complete
/// the [Future] the caller (a tool handler, deep in `domain/services`, with
/// no `BuildContext` anywhere near it) is awaiting. This is deliberate, per
/// `docs/mcp_plan.md`'s AGENTS.md-alignment section: no class under
/// `domain/services` may take a `BuildContext` or import Flutter.
///
/// **Every timeout is fail-closed.** An unanswered command approval resolves
/// to [ApprovalDecision.denied]; an unanswered host-access request resolves
/// to every candidate denied with reason `"timeout"`. An unanswered prompt
/// is a refusal, never a grant — the agent can always ask again, but a
/// command that ran unattended on a production host cannot be un-run.
class ApprovalCoordinator {
  final Uuid _uuid = const Uuid();

  final Map<String, _PendingCommand> _commands = {};
  final Map<String, _PendingHostAccess> _hostAccess = {};

  final StreamController<List<PendingCommandApproval>> _commandsController =
      StreamController<List<PendingCommandApproval>>.broadcast();
  final StreamController<List<PendingHostAccessApproval>>
  _hostAccessController =
      StreamController<List<PendingHostAccessApproval>>.broadcast();

  Stream<List<PendingCommandApproval>> get pendingCommands =>
      _commandsController.stream;
  Stream<List<PendingHostAccessApproval>> get pendingHostAccess =>
      _hostAccessController.stream;

  List<PendingCommandApproval> get currentCommands =>
      _commands.values.map((c) => c.pending).toList(growable: false);
  List<PendingHostAccessApproval> get currentHostAccess =>
      _hostAccess.values.map((h) => h.pending).toList(growable: false);

  /// Registers one command approval and returns a [Future] that completes
  /// when the user answers, or with [ApprovalDecision.denied] if [timeout]
  /// elapses first.
  Future<ApprovalDecision> requestCommandApproval(
    CommandApprovalRequest request, {
    Duration timeout = const Duration(seconds: 120),
  }) {
    final id = _uuid.v4();
    final requestedAt = DateTime.now().toUtc();
    final pending = PendingCommandApproval(
      id: id,
      request: request,
      requestedAt: requestedAt,
      expiresAt: requestedAt.add(timeout),
    );
    final completer = Completer<ApprovalDecision>();
    final timer = Timer(timeout, () {
      _completeCommand(id, ApprovalDecision.denied);
    });
    _commands[id] = _PendingCommand(
      pending: pending,
      completer: completer,
      timer: timer,
    );
    _emitCommands();
    return completer.future;
  }

  /// Registers one host-access request and returns a [Future] that completes
  /// when the user answers, or with every candidate denied (reason
  /// `"timeout"`) if [timeout] elapses first.
  Future<HostAccessResult> requestHostAccess(
    HostAccessRequest request, {
    Duration timeout = const Duration(seconds: 120),
  }) {
    final id = _uuid.v4();
    final requestedAt = DateTime.now().toUtc();
    final pending = PendingHostAccessApproval(
      id: id,
      request: request,
      requestedAt: requestedAt,
      expiresAt: requestedAt.add(timeout),
    );
    final completer = Completer<HostAccessResult>();
    final timer = Timer(timeout, () {
      _completeHostAccess(id, _allDenied(request, 'timeout'));
    });
    _hostAccess[id] = _PendingHostAccess(
      pending: pending,
      completer: completer,
      timer: timer,
    );
    _emitHostAccess();
    return completer.future;
  }

  HostAccessResult _allDenied(HostAccessRequest request, String reason) {
    return HostAccessResult(
      granted: const [],
      denied: request.candidates
          .map((c) => HostAccessDenial(hostId: c.hostId, reason: reason))
          .toList(),
    );
  }

  /// Answers a pending command approval, e.g. from the approval dialog.
  ///
  /// When [PendingCommandApproval.request]'s `canRemember` is false, the
  /// incoming [decision]'s scope is forced down to [ApprovalScope.once]
  /// here, unconditionally. The dialog greys the remember options out for
  /// exactly this case, but this coordinator does not trust the UI layer to
  /// have actually enforced that — the production-safety rule in
  /// `PolicyEngine.canRemember` only holds if nothing downstream of it can
  /// be talked out of it.
  void resolveCommand(String id, ApprovalDecision decision) {
    final entry = _commands[id];
    if (entry == null) return; // already resolved or timed out.
    final safeDecision = entry.pending.request.canRemember
        ? decision
        : ApprovalDecision(
            approved: decision.approved,
            scope: ApprovalScope.once,
          );
    _completeCommand(id, safeDecision);
  }

  void _completeCommand(String id, ApprovalDecision decision) {
    final entry = _commands.remove(id);
    if (entry == null) return;
    entry.timer.cancel();
    if (!entry.completer.isCompleted) entry.completer.complete(decision);
    _emitCommands();
  }

  /// Answers a pending host-access request.
  ///
  /// Partial approval is the normal path, not an edge case: [result] may
  /// grant some candidates and deny others, each granted candidate with its
  /// own [McpAccessMode].
  void resolveHostAccess(String id, HostAccessResult result) {
    _completeHostAccess(id, result);
  }

  void _completeHostAccess(String id, HostAccessResult result) {
    final entry = _hostAccess.remove(id);
    if (entry == null) return;
    entry.timer.cancel();
    if (!entry.completer.isCompleted) entry.completer.complete(result);
    _emitHostAccess();
  }

  /// Resolves every outstanding prompt to a refusal immediately, instead of
  /// waiting out its own timer. Used for a vault lock and the panic button —
  /// both need every open prompt gone right now. Same fail-closed rule as a
  /// timeout: nothing produced here is ever a grant.
  void cancelAll() {
    for (final id in _commands.keys.toList()) {
      _completeCommand(id, ApprovalDecision.denied);
    }
    for (final id in _hostAccess.keys.toList()) {
      final entry = _hostAccess[id];
      if (entry == null) continue;
      _completeHostAccess(id, _allDenied(entry.pending.request, 'cancelled'));
    }
  }

  void _emitCommands() {
    if (_commandsController.isClosed) return;
    _commandsController.add(currentCommands);
  }

  void _emitHostAccess() {
    if (_hostAccessController.isClosed) return;
    _hostAccessController.add(currentHostAccess);
  }

  void dispose() {
    cancelAll();
    _commandsController.close();
    _hostAccessController.close();
  }
}
