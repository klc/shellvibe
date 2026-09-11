import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

/// Transport abstraction the persistent-shell / sentinel protocol runs over.
///
/// [PersistentShellSession] talks to this interface only, never to
/// `package:dartssh2` directly, so the sentinel protocol — the highest-risk
/// piece of the MCP shell layer — can be exercised in a plain unit test
/// against a fake channel that never opens a socket. See
/// `docs/mcp_plan.md` Faz 0's "doğrulama harness'ı" for the intended
/// `FakeShellChannel` counterpart.
abstract class ShellChannel {
  /// Bytes the remote shell wrote to its stdout, including the sentinel
  /// lines the session writes after every command.
  Stream<List<int>> get stdout;

  /// Bytes the remote shell wrote to its stderr. The persistent shell always
  /// opens without a PTY (`docs/mcp_plan.md` Faz 2), which is precisely what
  /// keeps stderr on its own channel instead of being merged into stdout.
  Stream<List<int>> get stderr;

  /// Writes raw bytes to the remote shell's stdin — an enveloped command or
  /// a bootstrap line.
  void write(List<int> data);

  /// Best-effort request that the remote shell be interrupted (SIGINT).
  ///
  /// Deliberately not "write a `0x03` byte to stdin": that only means
  /// Ctrl-C when a *terminal* line discipline is there to translate it, and
  /// this channel never has one (see [SshShellChannel]). Without a PTY the
  /// byte is just data the shell will later try to run as a command, which
  /// desyncs the sentinel protocol instead of interrupting anything.
  ///
  /// Callers must treat this as advisory: it travels as an SSH `signal`
  /// channel request, which OpenSSH's server has historically ignored, so
  /// nothing may happen at all. Anything that must actually stop has to fall
  /// back to tearing the channel down.
  void sendInterrupt();

  /// Closes the channel. Must be idempotent: the hang-recovery chain in
  /// [PersistentShellSession] may call this on a channel that already died
  /// on its own, and a second close must not throw.
  Future<void> close();

  /// True once the channel is closed, whether via [close] or because the
  /// remote end hung up by itself (e.g. the shell process exited).
  bool get isClosed;
}

/// [ShellChannel] backed by a `dartssh2` [SSHSession] — a PTY-less shell
/// opened over an already-authenticated [SSHClient].
///
/// `SSHSession.stdout` / `SSHSession.stderr` are separate `Stream<Uint8List>`
/// (see `docs/mcp_context.md` §2), which is exactly the split this interface
/// needs; this wrapper only adapts types and closedness bookkeeping.
class SshShellChannel implements ShellChannel {
  SshShellChannel(this._session) {
    // The remote can end the channel on its own — the shell process dying,
    // the network dropping — without anyone calling [close] first. Without
    // this listener, [isClosed] would keep reporting false forever and the
    // hang-recovery chain would never realize the channel is already dead.
    _session.done.then((_) => _closed = true);
  }

  final SSHSession _session;
  bool _closed = false;

  @override
  Stream<List<int>> get stdout => _session.stdout;

  @override
  Stream<List<int>> get stderr => _session.stderr;

  @override
  void write(List<int> data) => _session.write(Uint8List.fromList(data));

  @override
  void sendInterrupt() {
    // Swallowed on purpose: a server that does not implement the `signal`
    // request may answer with a channel failure, and this is only ever the
    // cheap first attempt before a caller falls back to a channel reset.
    try {
      _session.kill(SSHSignal.INT);
    } catch (_) {}
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _session.close();
  }

  @override
  bool get isClosed => _closed;
}
