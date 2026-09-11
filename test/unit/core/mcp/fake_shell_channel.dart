import 'dart:async';
import 'dart:convert';

import 'package:shellvibe/core/mcp/shell/shell_channel.dart';

/// A programmable [ShellChannel] that stands in for a real SSH shell.
///
/// The sentinel protocol's hard cases — a hang, a Ctrl-C that unsticks it, a
/// marker split across chunk boundaries, a runaway stream that blows the
/// output cap — all depend on *timing and framing*, not on SSH. Reproducing
/// them against a real server would be slow and flaky; reproducing them here
/// is exact and instant.
///
/// The fake reads the nonce back out of each command envelope the session
/// writes, so it can answer with a correctly-formed sentinel without the test
/// having to know how nonces are generated.
class FakeShellChannel implements ShellChannel {
  FakeShellChannel({this.autoRespond = true, this.cwd = '/home/agent'});

  /// When true, every command envelope is answered immediately with exit 0.
  /// Tests that need to control a specific command turn this off (or use
  /// [holdNext]) and drive the response by hand.
  bool autoRespond;

  /// Suppresses the automatic answer for the next envelope only, so a test
  /// can simulate one hung command in an otherwise healthy session.
  bool holdNext = false;

  /// When true, the fake answers only after it has seen an interrupt signal
  /// — the "command was stuck until interrupted" case, on a server that
  /// honours the SSH `signal` request.
  bool answerOnlyAfterInterrupt = false;

  /// The cwd reported in the next sentinel. Assigning it simulates the remote
  /// shell having changed directory.
  String cwd;

  /// Exit code reported in the next sentinel.
  int nextExitCode = 0;

  final _stdout = StreamController<List<int>>.broadcast();
  final _stderr = StreamController<List<int>>.broadcast();

  /// Everything the session has written, decoded, in order.
  final List<String> writes = [];

  /// Every command envelope seen, in order (writes that are not envelopes —
  /// the `exec /bin/sh` and `export` lines, a bare Ctrl-C — are excluded).
  final List<String> envelopes = [];

  /// Nonces parsed out of [envelopes], in the same order.
  final List<String> nonces = [];

  int interruptCount = 0;
  bool _closed = false;

  static final _noncePattern = RegExp(r'__TERLY_%s__%s\|%s\\n. "([0-9a-f]+)"');

  /// The command text inside an envelope, i.e. what the agent actually asked
  /// for. Used to assert that the session sends what the caller passed.
  static final _commandPattern = RegExp(r'^\{ (.*) ; \} ;');

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  bool get isClosed => _closed;

  @override
  void sendInterrupt() {
    interruptCount++;
    if (answerOnlyAfterInterrupt && nonces.isNotEmpty) {
      answerOnlyAfterInterrupt = false;
      scheduleMicrotask(() => emitSentinel(nonces.last));
    }
  }

  @override
  void write(List<int> data) {
    final text = utf8.decode(data, allowMalformed: true);
    writes.add(text);

    final match = _noncePattern.firstMatch(text);
    if (match == null) return;

    envelopes.add(text);
    nonces.add(match.group(1)!);

    if (answerOnlyAfterInterrupt) return;
    if (holdNext) {
      holdNext = false;
      return;
    }
    if (!autoRespond) return;

    scheduleMicrotask(() => emitSentinel(nonces.last));
  }

  /// The command text carried by the [index]th envelope.
  String commandAt(int index) {
    final match = _commandPattern.firstMatch(envelopes[index]);
    return match?.group(1) ?? envelopes[index];
  }

  /// The nonce of the envelope the session is currently waiting on.
  String get pendingNonce => nonces.last;

  void emitStdout(String text) {
    if (_closed) return;
    _stdout.add(utf8.encode(text));
  }

  void emitStdoutBytes(List<int> bytes) {
    if (_closed) return;
    _stdout.add(bytes);
  }

  void emitStderr(String text) {
    if (_closed) return;
    _stderr.add(utf8.encode(text));
  }

  /// Emits a well-formed sentinel line for [nonce], matching the envelope the
  /// session writes.
  void emitSentinel(String nonce, {int? exitCode, String? cwd}) {
    if (_closed) return;
    _stdout.add(
      utf8.encode(
        '\n__TERLY_${nonce}__${exitCode ?? nextExitCode}|'
        '${cwd ?? this.cwd}\n',
      ),
    );
  }

  /// Emits a sentinel split across two chunks, to exercise the framer's
  /// hold-back buffer through the full session path.
  void emitSentinelSplit(String nonce, {int? exitCode, String? cwd}) {
    if (_closed) return;
    final line =
        '\n__TERLY_${nonce}__${exitCode ?? nextExitCode}|${cwd ?? this.cwd}\n';
    final at = line.length ~/ 2;
    _stdout.add(utf8.encode(line.substring(0, at)));
    _stdout.add(utf8.encode(line.substring(at)));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _stdout.close();
    await _stderr.close();
  }
}
