import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../../app/router/app_router.dart';
import '../../data/repositories/mcp_repository_providers.dart';
import '../../domain/models/mcp_models.dart';
import '../../domain/services/approval_coordinator.dart';
import '../../domain/services/mcp_service_providers.dart';
import '../dialogs/mcp_command_approval_dialog.dart';
import '../dialogs/mcp_host_access_dialog.dart';

/// Brings the app window to the front on desktop, no-op everywhere else.
///
/// The user is usually talking to the agent in some other application when
/// an approval request lands — ShellVibe is in the background. Per
/// docs/mcp_plan.md "Uygulama arka plandayken", a prompt nobody sees is a
/// prompt that silently times out and fails closed, so every approval
/// request pulls the window forward before its dialog goes up. Mobile and
/// web have no such window to raise, so this is a deliberate no-op there.
Future<void> bringMcpApprovalWindowForward() async {
  if (kIsWeb) return;
  final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  if (!isDesktop) return;
  try {
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.show();
    await windowManager.focus();
  } catch (_) {
    // Same posture as syncWindowChromeToTheme in app/window/window_chrome.dart:
    // a headless test harness or a platform without a live window channel
    // must never take the approval flow down over a chrome call.
  }
}

/// Mounted once, high in the widget tree, this is what turns a pending
/// [ApprovalCoordinator] request into an actual dialog on screen. Without it
/// every `confirm` decision times out and fails closed — nothing shows the
/// prompt the coordinator is waiting on an answer to.
///
/// Only one dialog is ever on screen at a time; further requests queue and
/// are shown in the order they were made, oldest first, regardless of which
/// of the two request kinds they are.
///
/// **Fail-closed by construction.** Both dialogs already resolve every
/// non-approval exit (barrier, Escape, back gesture, their own countdown) to
/// a refusal internally — see their class docs. This widget adds one more
/// layer on top: if `showDialog` ever returns without a value at all (for
/// instance a route popped by something outside either dialog's own
/// control), the `?? denied` fallback below still means the only way any
/// request is granted is that specific dialog's own explicit "Approve"
/// button.
/// Request ids whose dialog is currently on screen, shared across every
/// [McpApprovalHost] instance.
///
/// The per-instance guard is not enough on its own. This widget is mounted
/// through `ShadApp.router`'s `builder`, so a rebuild of the app shell can
/// recreate its [State] while a request is still pending — the fresh
/// `initState` then sees an unclaimed slot and pushes a *second* dialog for
/// a request the previous state is already showing. Keying the latch to the
/// request itself, not to whoever happens to be displaying it, makes a
/// duplicate impossible regardless of how many hosts exist.
final Set<String> _dialogsOnScreen = <String>{};

class McpApprovalHost extends ConsumerStatefulWidget {
  final Widget child;

  const McpApprovalHost({super.key, required this.child});

  @override
  ConsumerState<McpApprovalHost> createState() => _McpApprovalHostState();
}

class _McpApprovalHostState extends ConsumerState<McpApprovalHost> {
  StreamSubscription<List<PendingCommandApproval>>? _commandSub;
  StreamSubscription<List<PendingHostAccessApproval>>? _hostAccessSub;

  List<PendingCommandApproval> _commands = const [];
  List<PendingHostAccessApproval> _hostAccess = const [];

  /// id of the request whose dialog is currently on screen, or null between
  /// dialogs. Guards against showing a second dialog while one is already up.
  String? _activeId;

  @override
  void initState() {
    super.initState();
    final coordinator = ref.read(approvalCoordinatorProvider);
    _commands = coordinator.currentCommands;
    _hostAccess = coordinator.currentHostAccess;
    _commandSub = coordinator.pendingCommands.listen(_onCommandsChanged);
    _hostAccessSub = coordinator.pendingHostAccess.listen(_onHostAccessChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowNext());
  }

  @override
  void dispose() {
    _commandSub?.cancel();
    _hostAccessSub?.cancel();
    super.dispose();
  }

  void _onCommandsChanged(List<PendingCommandApproval> list) {
    if (!mounted) return;
    setState(() => _commands = list);
    _closeActiveIfAbandoned();
    _maybeShowNext();
  }

  void _onHostAccessChanged(List<PendingHostAccessApproval> list) {
    if (!mounted) return;
    setState(() => _hostAccess = list);
    _closeActiveIfAbandoned();
    _maybeShowNext();
  }

  /// If the request currently on screen has left both pending lists, the
  /// coordinator's own fail-closed timer already resolved it — nobody
  /// answered in time. Close the now-stale dialog rather than leave the user
  /// looking at a prompt for a request that is already gone; the resolve()
  /// call that follows the dialog's Future becomes a harmless no-op, since
  /// [ApprovalCoordinator.resolveCommand] / [resolveHostAccess] only act on
  /// requests that are still pending.
  void _closeActiveIfAbandoned() {
    final activeId = _activeId;
    if (activeId == null) return;
    final stillPending =
        _commands.any((c) => c.id == activeId) ||
        _hostAccess.any((h) => h.id == activeId);
    if (stillPending) return;
    // Same reason as in [_maybeShowNext]: this widget sits above the
    // Navigator, so it can only reach it through the router's key.
    final navigator = rootNavigatorKey.currentState;
    if (navigator != null && navigator.canPop()) navigator.pop();
  }

  Future<void> _maybeShowNext() async {
    if (_activeId != null) return;
    if (_commands.isEmpty && _hostAccess.isEmpty) return;

    final nextCommand = _oldest(_commands, (c) => c.requestedAt);
    final nextHostAccess = _oldest(_hostAccess, (h) => h.requestedAt);

    final showCommandFirst =
        nextHostAccess == null ||
        (nextCommand != null &&
            nextCommand.requestedAt.isBefore(nextHostAccess.requestedAt));

    // Claim the slot synchronously, before any `await`, so a stream event
    // that fires while `bringMcpApprovalWindowForward` is in flight sees
    // `_activeId` already set and does not race a second dialog open.
    final String claimedId;
    if (showCommandFirst && nextCommand != null) {
      claimedId = nextCommand.id;
    } else if (nextHostAccess != null) {
      claimedId = nextHostAccess.id;
    } else {
      return;
    }
    if (!_dialogsOnScreen.add(claimedId)) return;
    _activeId = claimedId;

    await bringMcpApprovalWindowForward();
    if (!mounted) {
      _dialogsOnScreen.remove(claimedId);
      return;
    }

    final coordinator = ref.read(approvalCoordinatorProvider);

    // NOT `context`: this widget is mounted through `ShadApp.router`'s
    // `builder`, which wraps the Navigator rather than living under it, so
    // `Navigator.of(context)` from here throws "context does not include a
    // Navigator" and no dialog ever appears — the request then times out and
    // fails closed with nothing on screen to explain it.
    final navigatorContext = rootNavigatorKey.currentContext;
    if (navigatorContext == null || !navigatorContext.mounted) {
      _dialogsOnScreen.remove(claimedId);
      return;
    }

    if (showCommandFirst && nextCommand != null) {
      final decision = await McpCommandApprovalDialog.show(
        navigatorContext,
        request: nextCommand.request,
        expiresAt: nextCommand.expiresAt,
      );
      coordinator.resolveCommand(
        nextCommand.id,
        decision ?? ApprovalDecision.denied,
      );
    } else if (nextHostAccess != null) {
      final outcome = await McpHostAccessDialog.show(
        navigatorContext,
        request: nextHostAccess.request,
        expiresAt: nextHostAccess.expiresAt,
      );
      final result = outcome?.result ?? _allDenied(nextHostAccess.request);
      coordinator.resolveHostAccess(nextHostAccess.id, result);
      if (outcome?.suspendClient ?? false) {
        await ref
            .read(mcpClientRepositoryProvider)
            .revokeClient(nextHostAccess.request.clientId);
      }
    }

    // Drop the request we just resolved from the local snapshots *before*
    // releasing the latch. The coordinator's pending lists are broadcast
    // streams, so the updated list that no longer contains this request only
    // arrives in a later microtask — until then `_commands`/`_hostAccess`
    // still hold it. Re-entering `_maybeShowNext` against that stale
    // snapshot re-claims the same id (the latch having just been released)
    // and puts a second, identical dialog on screen for a request that is
    // already answered: the user approves, the agent gets its answer, and
    // the prompt stays up until it is dismissed a second time.
    _commands = _commands.where((c) => c.id != claimedId).toList();
    _hostAccess = _hostAccess.where((h) => h.id != claimedId).toList();
    _dialogsOnScreen.remove(claimedId);
    _activeId = null;
    if (mounted) unawaited(_maybeShowNext());
  }

  T? _oldest<T>(List<T> items, DateTime Function(T) requestedAt) {
    if (items.isEmpty) return null;
    return items.reduce(
      (a, b) => requestedAt(a).isBefore(requestedAt(b)) ? a : b,
    );
  }

  /// Same fallback the dialog itself resolves to if it is ever dismissed
  /// with no outcome at all (see [McpApprovalHost]'s class doc).
  HostAccessResult _allDenied(HostAccessRequest request) => HostAccessResult(
    granted: const [],
    denied: request.candidates
        .map((c) => HostAccessDenial(hostId: c.hostId, reason: 'user_denied'))
        .toList(),
  );

  @override
  Widget build(BuildContext context) => widget.child;
}
