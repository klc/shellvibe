import 'dart:async';

/// The user-visible surface an MCP session mirrors itself onto: the
/// read-only "AI" tab that appears in ShellVibe's own tab bar for as long as
/// an agent holds a session open.
///
/// This exists so `docs/mcp_plan.md`'s "AI oturumu = görünür sekme" is a
/// property of the session itself rather than of any one tool: whether the
/// user can watch must not depend on which code path ran the command. The
/// data layer therefore talks to this interface and never to the terminal
/// feature directly — the pool has no business importing widgets, and a
/// headless context (tests, the server running before any UI exists) gets
/// [NullMcpSessionMirror] instead of a broken dependency.
///
/// Every method is best-effort by contract: a mirror that fails, or that has
/// no surface to draw on, must never take a session down with it. Visibility
/// is a feature; the session is the product.
abstract class McpSessionMirror {
  /// Opens the surface for a session and returns its id, or null when this
  /// mirror has none to give.
  ///
  /// [onUserClosed] is invoked if the *user* closes the surface — the plan's
  /// "sekmeyi kapatmak oturumu öldürür". Implementations must not call it
  /// when the surface is closed through [close], which is the opposite
  /// direction: the session ending and taking its surface with it.
  Future<String?> open({
    required String sessionId,
    required String hostLabel,
    required String cwd,
    required String clientName,
    required String mode,
    required FutureOr<void> Function() onUserClosed,
  });

  /// Shows the command an agent is about to run, as it would look typed at a
  /// prompt.
  void writeCommand(
    String surfaceId, {
    required String command,
    required String cwd,
  });

  /// Shows one command's outcome.
  ///
  /// [stdout] and [stderr] are the *redacted* text — what the agent actually
  /// received. Mirroring the raw output instead would put secrets the
  /// redactor deliberately withheld into a scrollback the user may well
  /// screenshot, and would misrepresent what the agent learned, which is the
  /// one question this tab exists to answer.
  void writeResult(
    String surfaceId, {
    required String stdout,
    required String stderr,
    required int exitCode,
    required int durationMs,
  });

  /// Shows something that happened to the session other than a command: a
  /// policy refusal, an interrupt, a shell that had to be rebuilt.
  void writeNotice(String surfaceId, String message);

  /// Tears the surface down because the session ended.
  Future<void> close(String surfaceId, {String? reason});
}

/// A mirror with nowhere to draw: every call is a no-op and [open] hands back
/// no id, which is what makes `tabId` null on a session nobody can watch.
class NullMcpSessionMirror implements McpSessionMirror {
  const NullMcpSessionMirror();

  @override
  Future<String?> open({
    required String sessionId,
    required String hostLabel,
    required String cwd,
    required String clientName,
    required String mode,
    required FutureOr<void> Function() onUserClosed,
  }) async => null;

  @override
  void writeCommand(
    String surfaceId, {
    required String command,
    required String cwd,
  }) {}

  @override
  void writeResult(
    String surfaceId, {
    required String stdout,
    required String stderr,
    required int exitCode,
    required int durationMs,
  }) {}

  @override
  void writeNotice(String surfaceId, String message) {}

  @override
  Future<void> close(String surfaceId, {String? reason}) async {}
}
