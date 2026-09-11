import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../../../features/mcp/domain/models/mcp_enums.dart';
import '../../../features/mcp/domain/models/mcp_models.dart';
import 'shell_channel.dart';
import 'shell_output_framer.dart';

/// A PTY-less remote shell kept alive across many commands, framed with a
/// sentinel protocol so `cd` and environment survive between calls.
///
/// This is `docs/mcp_plan.md` Faz 2's "kalıcı shell protokolü" — the
/// highest-risk piece of the MCP shell layer, because a bug here does not
/// fail loudly, it desyncs silently: a later command's output gets
/// attributed to an earlier one and the agent acts on wrong data. Two
/// properties make that failure mode survivable:
///
/// ## Ordering (problem 3 in the plan)
///
/// Exactly one command runs at a time per session. [run] calls are queued
/// on [_enqueue], a hand-rolled Future chain rather than a mutex package —
/// each call waits for the previous call's Future to complete before its
/// own body starts, and publishes its own completion as the new tail of the
/// chain. This is deliberately *not* a queue of pending commands with
/// cancellation or priority; MCP tool calls are already serialized by the
/// agent's own tool-call protocol, so the only property needed is "second
/// caller waits for the first," which a plain Future chain gives for free.
/// Different [PersistentShellSession] instances (different sessions) have
/// independent chains and run fully in parallel.
///
/// ## Hang recovery (problem 1 in the plan)
///
/// See the recovery chain inside [_runLocked] for the four-step escalation
/// (timeout → Ctrl-C → fresh probe → channel reopen) and why each step is
/// tried before the next.
class PersistentShellSession {
  PersistentShellSession({
    required ShellChannel channel,
    required Future<ShellChannel> Function() reopen,
    this.outputCapBytes = 100 * 1024,
    // A named parameter cannot start with an underscore, so these two fields
    // cannot be expressed as initializing formals while staying private.
    // ignore: prefer_initializing_formals
  }) : _channel = channel,
       // ignore: prefer_initializing_formals
       _reopen = reopen {
    _attachListeners();
  }

  final int outputCapBytes;
  final Future<ShellChannel> Function() _reopen;

  ShellChannel _channel;

  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;

  /// Bumped by every [interrupt]. A [run] captures it before it starts
  /// waiting and compares afterwards, which is how it tells "my sentinel
  /// never came" apart from "someone pulled the channel out from under me".
  int _interruptCount = 0;

  /// Completed by [interrupt] to wake a run that is waiting on a sentinel
  /// the torn-down channel can no longer deliver. Replaced with a fresh
  /// completer each time, so the re-normalization that follows the teardown
  /// waits on its own sentinels normally.
  Completer<void> _interruptSignal = Completer<void>();

  /// The channel rebuild [interrupt] is currently running, so the run it
  /// interrupted can wait for a usable session before it returns rather than
  /// handing the queue on to a command that would write into a half-open
  /// channel.
  Future<void>? _interruptReset;

  /// Framers currently eligible to receive bytes from the channel. Normally
  /// holds exactly one entry (the in-flight command); during hang recovery
  /// it briefly holds two (the original command's framer plus a fresh probe
  /// framer) so that a merely-delayed original sentinel is still recognized
  /// instead of being silently dropped the instant recovery escalates.
  final List<ShellOutputFramer> _liveFramers = [];

  String _cwd = '';

  /// Working directory as of the last sentinel line read from this session,
  /// updated by every call — `initialize`, `run`, and the recovery probes.
  String get cwd => _cwd;

  bool _busy = false;

  /// True while a command is running (including while it is stuck in the
  /// hang-recovery chain). Second `run` calls do not flip this early; they
  /// simply wait in [_enqueue] until it is available.
  bool get isBusy => _busy;

  /// Serializes [run] calls: each new call chains onto this Future and
  /// replaces it with its own completion, so calls execute strictly in
  /// arrival order. See the ordering section of the class docstring.
  Future<void> _mutex = Future<void>.value();

  static const _kMaxTimeout = Duration(seconds: 600);
  static const _kRecoveryWait = Duration(seconds: 3);
  static const _kProbeTimeout = Duration(seconds: 10);

  /// Normalizes the remote login shell into a known-good, script-friendly
  /// `/bin/sh`, then confirms it is actually responding before returning.
  ///
  /// `exec /bin/sh` runs first because the login shell may be fish or csh,
  /// where the `export VAR=` lines below are syntax errors, not no-ops —
  /// normalizing must not depend on which shell the user happens to have
  /// configured.
  ///
  /// History is disabled in two portable steps rather than a bare
  /// `set +o history`. On Debian and Ubuntu `/bin/sh` is dash, which has no
  /// `history` option at all: `set` is a POSIX *special* builtin, so the
  /// error is not a failed command the shell shrugs off but a fatal one that
  /// makes a non-interactive shell exit outright — taking the channel with
  /// it before the probe below can ever answer. `||` does not save it; only
  /// keeping the failure inside a subshell does. `unset HISTFILE` covers the
  /// same ground portably, and the guarded `set` still turns the option off
  /// on shells that actually have it.
  ///
  /// If the probe never responds, this throws
  /// [McpErrorCode.shellUnsupported] rather than returning with a shell that
  /// might be half-normalized: a session that silently skipped `TERM=dumb`
  /// or `set +o history` would misbehave in ways far harder to diagnose
  /// than an upfront refusal to open at all.
  Future<void> initialize() async {
    _channel.write(utf8.encode('exec /bin/sh\n'));
    _channel.write(
      utf8.encode(
        'export PS1= PS2= TERM=dumb PAGER=cat GIT_PAGER=cat LESS=FRX\n'
        'export DEBIAN_FRONTEND=noninteractive\n'
        'unset HISTFILE\n'
        '(set +o history) 2>/dev/null && set +o history 2>/dev/null\n',
      ),
    );

    final nonce = _newNonce();
    final framer = ShellOutputFramer(nonce: nonce, capBytes: outputCapBytes);
    _liveFramers.add(framer);
    try {
      _channel.write(utf8.encode(_buildEnvelope('true', nonce)));
      final match = await _waitSentinel(framer, _kProbeTimeout);
      if (match == null) {
        throw const McpToolException(
          McpErrorCode.shellUnsupported,
          'Shell did not respond to the normalization probe in time. The '
          'host may not have a POSIX /bin/sh, or the session is stuck; a '
          'half-normalized session is worse than none, so it was not opened.',
        );
      }
      _cwd = match.cwd;
    } finally {
      _liveFramers.remove(framer);
    }
  }

  /// Runs one command over the persistent shell and returns its result.
  ///
  /// [timeout] is capped at 600 seconds regardless of what the caller
  /// requests — an unbounded wait would let one stuck agent tool call block
  /// the session (and the mutex behind it) indefinitely.
  Future<ShellCommandResult> run(
    String command, {
    Duration timeout = const Duration(seconds: 60),
  }) {
    final effectiveTimeout = timeout > _kMaxTimeout ? _kMaxTimeout : timeout;
    return _enqueue(() => _runLocked(command, effectiveTimeout));
  }

  /// Stops whatever [run] call is currently in flight, from outside the run
  /// queue — it must not wait behind the very call it is meant to interrupt,
  /// so it deliberately does not take the mutex.
  ///
  /// The SSH `signal` request is tried first because it is cheap and leaves
  /// the session intact when the server honours it. It usually does not:
  /// OpenSSH ignores the request, and without a PTY there is no line
  /// discipline to turn a `0x03` byte into SIGINT either — which is why this
  /// then tears the channel down and rebuilds it. That is the only mechanism
  /// that reliably stops a running command here, and it is what makes the
  /// promise this tool makes to the agent a true one.
  ///
  /// Any in-flight [run] is woken immediately rather than left waiting out a
  /// timeout on a channel that no longer exists, and comes back with
  /// `interrupted` and `sessionReset` both set.
  Future<void> interrupt() async {
    _channel.sendInterrupt();
    _interruptCount++;
    final waiter = _interruptSignal;
    _interruptSignal = Completer<void>();
    final reset = _resetChannel();
    _interruptReset = reset;
    if (!waiter.isCompleted) waiter.complete();
    try {
      await reset;
    } finally {
      if (identical(_interruptReset, reset)) _interruptReset = null;
    }
  }

  Future<void> close() async {
    await _detachListeners();
    await _channel.close();
  }

  Future<ShellCommandResult> _runLocked(
    String command,
    Duration timeout,
  ) async {
    final stopwatch = Stopwatch()..start();
    final framer = ShellOutputFramer(
      nonce: _newNonce(),
      capBytes: outputCapBytes,
    );
    _liveFramers.add(framer);

    try {
      _channel.write(utf8.encode(_buildEnvelope(command, framer.nonce)));

      final epoch = _interruptCount;
      var match = await _waitSentinel(framer, timeout);
      if (match != null) {
        _cwd = match.cwd;
        return _resultFrom(framer, match, stopwatch.elapsedMilliseconds);
      }

      // [interrupt] tore the channel down while this command was running.
      // Waiting for the rebuild before returning keeps the queue honest: the
      // next command must not be handed a channel that is still being
      // re-normalized.
      if (_interruptCount != epoch) {
        await _interruptReset;
        return ShellCommandResult(
          stdout: framer.stdout,
          stderr: framer.stderr,
          exitCode: -1,
          cwd: _cwd,
          durationMs: stopwatch.elapsedMilliseconds,
          truncated: framer.truncation,
          interrupted: true,
          sessionReset: true,
        );
      }

      // --- Hang-recovery chain -------------------------------------------
      //
      // The sentinel never arriving means the command never released the
      // shell's control of stdin: an editor, `read` with no input, an
      // unterminated heredoc or quote. Each step below is strictly more
      // destructive than the last, tried in the order a human at a real
      // terminal would try them, and the caller is told exactly how far we
      // had to go — silently recovering and continuing would leave the
      // agent reasoning about shell state that no longer exists.

      // Step 1: ask the server to signal the shell. On the servers that
      // honour the request this kills the foreground process cleanly and the
      // sentinel already queued behind the command fires as the shell
      // regains stdin. Sending a raw `0x03` byte instead would do nothing of
      // the sort on this PTY-less channel — with no line discipline to read
      // it as Ctrl-C it is just input the shell later tries to execute,
      // splicing itself into the next command and desyncing the protocol.
      _channel.sendInterrupt();
      match = await _waitSentinel(framer, _kRecoveryWait);
      if (match != null) {
        _cwd = match.cwd;
        return _resultFrom(
          framer,
          match,
          stopwatch.elapsedMilliseconds,
          interrupted: true,
        );
      }

      // Step 2: probe with a fresh sentinel. Ctrl-C can land on a subshell
      // or a process that ignores SIGINT while the outer shell is actually
      // fine; a brand new envelope tells us whether the *shell* is still
      // alive, independent of whether the original command's own sentinel
      // will ever come. The original framer stays live (see _liveFramers
      // docstring) so a merely-delayed original sentinel is still caught.
      final probeFramer = ShellOutputFramer(
        nonce: _newNonce(),
        capBytes: outputCapBytes,
      );
      _liveFramers.add(probeFramer);
      try {
        _channel.write(utf8.encode(_buildEnvelope('true', probeFramer.nonce)));
        final probeMatch = await _waitSentinel(probeFramer, _kRecoveryWait);
        if (probeMatch != null) {
          _cwd = probeMatch.cwd;
          // The original command's exit code is genuinely unknown — only
          // reporting -1 here (rather than the probe's own, always-zero
          // exit code) keeps the result honest about what we do not know.
          return _resultFrom(
            framer,
            SentinelMatch(exitCode: -1, cwd: probeMatch.cwd),
            stopwatch.elapsedMilliseconds,
            interrupted: true,
          );
        }
      } finally {
        _liveFramers.remove(probeFramer);
      }

      // Step 3: the shell itself is gone. Reading further from a channel
      // nothing will ever write to again just hangs the caller a second
      // time, so we tear down and rebuild instead of retrying further.
      // `sessionReset: true` is the honest signal the plan requires: every
      // shell variable, `cd`, and background job the agent built up is
      // gone, and it must replan rather than assume continuity.
      await _resetChannel();
      return ShellCommandResult(
        stdout: framer.stdout,
        stderr: framer.stderr,
        exitCode: -1,
        cwd: _cwd,
        durationMs: stopwatch.elapsedMilliseconds,
        truncated: framer.truncation,
        sessionReset: true,
      );
    } finally {
      _liveFramers.remove(framer);
    }
  }

  /// Closes the dead channel, opens a new one via [_reopen], re-normalizes
  /// it, and restores the working directory the agent was in — everything
  /// except that `cd` (variables, background jobs) is gone for good.
  Future<void> _resetChannel() async {
    final previousCwd = _cwd;
    _liveFramers.clear();
    await _detachListeners();
    await _channel.close();
    _channel = await _reopen();
    _attachListeners();
    await initialize();
    await _restoreCwd(previousCwd);
  }

  Future<void> _restoreCwd(String previousCwd) async {
    if (previousCwd.isEmpty) return;
    final framer = ShellOutputFramer(
      nonce: _newNonce(),
      capBytes: outputCapBytes,
    );
    _liveFramers.add(framer);
    try {
      _channel.write(
        utf8.encode(
          _buildEnvelope('cd ${_shellQuote(previousCwd)}', framer.nonce),
        ),
      );
      final match = await _waitSentinel(framer, _kProbeTimeout);
      // If even this does not respond, `cwd` stays whatever initialize()
      // reported (the shell's own login directory) — a known-wrong cwd,
      // communicated honestly via the already-returned `sessionReset: true`,
      // beats silently pretending the restore worked.
      if (match != null) {
        _cwd = match.cwd;
      }
    } finally {
      _liveFramers.remove(framer);
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final previous = _mutex;
    final gate = Completer<void>();
    _mutex = gate.future;
    return previous.then((_) async {
      _busy = true;
      try {
        return await action();
      } finally {
        _busy = false;
        gate.complete();
      }
    });
  }

  void _attachListeners() {
    _stdoutSub = _channel.stdout.listen((chunk) {
      for (final framer in _liveFramers) {
        framer.feedStdout(chunk);
      }
    });
    _stderrSub = _channel.stderr.listen((chunk) {
      for (final framer in _liveFramers) {
        framer.feedStderr(chunk);
      }
    });
  }

  Future<void> _detachListeners() async {
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
  }

  Future<SentinelMatch?> _waitSentinel(
    ShellOutputFramer framer,
    Duration wait,
  ) async {
    final interrupted = _interruptSignal.future;
    try {
      return await Future.any<SentinelMatch?>([
        framer.sentinel,
        interrupted.then<SentinelMatch?>((_) => null),
      ]).timeout(wait);
    } on TimeoutException {
      return null;
    }
  }

  ShellCommandResult _resultFrom(
    ShellOutputFramer framer,
    SentinelMatch match,
    int durationMs, {
    bool interrupted = false,
  }) {
    return ShellCommandResult(
      stdout: framer.stdout,
      stderr: framer.stderr,
      exitCode: match.exitCode,
      cwd: match.cwd,
      durationMs: durationMs,
      truncated: framer.truncation,
      interrupted: interrupted,
    );
  }

  String _newNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(8, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Wraps [command] so its completion, exit code and resulting cwd can be
  /// read back deterministically, as
  /// `{ CMD ; } ; printf '\n__TERLY_%s__%s|%s\n' "NONCE" "$?" "$PWD"`.
  /// The braces mean `$?` reflects the command's own exit status even when
  /// the command spans multiple statements.
  String _buildEnvelope(String command, String nonce) {
    return '{ $command ; } ; printf \'\\n__TERLY_%s__%s|%s\\n\' "$nonce" "\$?" "\$PWD"\n';
  }

  /// POSIX single-quote escaping for interpolating [value] (a path) into a
  /// shell command literally, without word-splitting or glob expansion.
  String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";
}
