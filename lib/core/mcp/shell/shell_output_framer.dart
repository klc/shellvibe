import 'dart:async';
import 'dart:convert';

import '../../../features/mcp/domain/models/mcp_models.dart';

/// The three pieces of information carried by one sentinel line: the command
/// finished, with this exit code, in this working directory.
class SentinelMatch {
  final int exitCode;
  final String cwd;

  const SentinelMatch({required this.exitCode, required this.cwd});
}

/// Incremental byte scanner for one command's output.
///
/// A fresh instance is created per command (and per recovery probe) with
/// that command's nonce baked in at construction, rather than a `reset()`
/// method on a shared instance — this makes "which nonce ends this command"
/// a compile-time-obvious property instead of a piece of mutable state that
/// could be left stale.
///
/// ## Problem 1 — false-positive sentinel
///
/// Command output can legitimately contain marker-shaped text (a build log
/// echoing another tool's framing, or an adversarial command trying to spoof
/// completion). The nonce is 16 random hex chars generated fresh for this
/// command only, so [feedStdout] can only ever complete [sentinel] for a
/// line carrying *this* instance's exact nonce — a stale or forged marker
/// for any other nonce is just ordinary output to this scanner.
///
/// ## Problem 2 — output overflow must not stop the drain
///
/// A runaway command (`yes`, a verbose build, a binary dumped to stdout) can
/// produce far more than [capBytes] before the sentinel ever arrives.
/// Buffering all of it would exhaust memory before any timeout fires, but
/// simply stopping the read once the cap is hit is worse: the channel is one
/// continuous byte stream shared by every command that will ever run on this
/// session, and if a reader stops consuming mid-command, the bytes still in
/// flight — the rest of this command's output, or its sentinel line itself —
/// land at the front of the *next* command's read and get permanently
/// misattributed to it. There is no re-sync point after that. So capping
/// only ever stops *storing* bytes (see [_CappedAccumulator]); [feedStdout]
/// and [feedStderr] keep scanning and counting every byte the channel
/// produces until this nonce's sentinel is found.
class ShellOutputFramer {
  ShellOutputFramer({required this.nonce, this.capBytes = 100 * 1024})
    : _stdoutAcc = _CappedAccumulator(capBytes),
      _stderrAcc = _CappedAccumulator(capBytes),
      _markerPrefix = utf8.encode('\n__TERLY_${nonce}__');

  final String nonce;
  final int capBytes;

  final List<int> _markerPrefix;

  final _CappedAccumulator _stdoutAcc;
  final _CappedAccumulator _stderrAcc;

  /// Bytes held back at a chunk boundary because they could be the start of
  /// a marker that completes in the next chunk.
  final List<int> _pending = [];

  bool _capturingSentinel = false;

  /// Bytes collected after the marker prefix, up to (and not including) the
  /// sentinel line's trailing newline.
  final List<int> _sentinelTail = [];

  final Completer<SentinelMatch> _sentinelCompleter =
      Completer<SentinelMatch>();

  /// Completes once this command's sentinel line has fully arrived on
  /// stdout. Never completes for any other nonce's marker-shaped text.
  Future<SentinelMatch> get sentinel => _sentinelCompleter.future;

  bool get isDone => _sentinelCompleter.isCompleted;

  /// Command stdout collected so far (or ever, once [isDone]), with the
  /// middle dropped and marked if it exceeded [capBytes].
  String get stdout => _stdoutAcc.decode();

  /// Command stderr collected so far, capped the same way as [stdout].
  String get stderr => _stderrAcc.decode();

  /// Combined truncation info across stdout and stderr, or null if neither
  /// stream exceeded [capBytes]. The two streams are capped independently —
  /// each can hold up to [capBytes] before its middle is dropped — because
  /// they arrive on two independent channels with no shared ordering; a
  /// single combined byte budget would require interleaving them by
  /// arrival time, which would make the kept prefix/suffix of each stream
  /// dependent on network timing instead of content.
  OutputTruncation? get truncation {
    if (!_stdoutAcc.truncated && !_stderrAcc.truncated) return null;
    return OutputTruncation(
      originalBytes: _stdoutAcc.originalBytes + _stderrAcc.originalBytes,
      keptBytes: _stdoutAcc.keptBytes + _stderrAcc.keptBytes,
    );
  }

  /// Feeds one chunk of stdout bytes. Must be called for every chunk the
  /// channel produces for as long as the caller keeps listening — including
  /// after [isDone] is briefly false but about to flip true within this same
  /// call — see the class docstring on why the drain must never stop early.
  void feedStdout(List<int> chunk) {
    if (isDone) return;

    if (_capturingSentinel) {
      _feedSentinelTail(chunk);
      return;
    }

    final buf = _pending.isEmpty ? chunk : [..._pending, ...chunk];
    final matchIndex = _indexOfMarker(buf);

    if (matchIndex == -1) {
      // No full marker in this window. A match could still be starting in
      // the last (markerPrefix.length - 1) bytes and complete on the next
      // chunk, so those are held back; everything before them is confirmed
      // real command output and can be released to the accumulator now.
      final holdBack = _markerPrefix.length - 1;
      if (buf.length <= holdBack) {
        _pending
          ..clear()
          ..addAll(buf);
      } else {
        final safe = buf.sublist(0, buf.length - holdBack);
        _stdoutAcc.add(safe);
        _pending
          ..clear()
          ..addAll(buf.sublist(buf.length - holdBack));
      }
      return;
    }

    // Marker found: everything before it is real stdout; everything from
    // the end of the prefix onward is the start of the sentinel line.
    _stdoutAcc.add(buf.sublist(0, matchIndex));
    _pending.clear();
    _capturingSentinel = true;
    _feedSentinelTail(buf.sublist(matchIndex + _markerPrefix.length));
  }

  /// Feeds one chunk of stderr bytes. Stderr never carries the sentinel —
  /// the envelope's `printf` writes it to stdout — so this only needs the
  /// size cap, not marker scanning.
  void feedStderr(List<int> chunk) {
    if (isDone) return;
    _stderrAcc.add(chunk);
  }

  void _feedSentinelTail(List<int> chunk) {
    _sentinelTail.addAll(chunk);
    final newlineIndex = _sentinelTail.indexOf(0x0A);
    if (newlineIndex == -1) return;

    final line = utf8.decode(
      _sentinelTail.sublist(0, newlineIndex),
      allowMalformed: true,
    );
    final pipeIndex = line.indexOf('|');
    // The envelope always produces `<exitCode>|<cwd>` here; a malformed line
    // should be unreachable, but a stream callback must never throw, so this
    // degrades to an explicit "unknown" result instead of crashing the
    // session.
    final exitCode = pipeIndex == -1
        ? -1
        : int.tryParse(line.substring(0, pipeIndex)) ?? -1;
    final cwd = pipeIndex == -1 ? '' : line.substring(pipeIndex + 1);

    if (!_sentinelCompleter.isCompleted) {
      _sentinelCompleter.complete(SentinelMatch(exitCode: exitCode, cwd: cwd));
    }
  }

  int _indexOfMarker(List<int> buf) {
    if (buf.length < _markerPrefix.length) return -1;
    final limit = buf.length - _markerPrefix.length;
    outer:
    for (var i = 0; i <= limit; i++) {
      for (var j = 0; j < _markerPrefix.length; j++) {
        if (buf[i + j] != _markerPrefix[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}

/// Bounded-memory accumulator for one output stream: keeps the first and
/// last `capBytes ~/ 5` bytes (20 KB of a 100 KB default cap, matching
/// `docs/mcp_plan.md`'s "ilk 20 KB + son 20 KB"), and tracks how many bytes
/// were dropped from the middle without ever storing them.
///
/// Memory stays bounded to a small constant multiple of [capBytes]
/// regardless of how much the remote actually sends — this is what makes it
/// safe for [ShellOutputFramer] to keep draining a runaway command instead
/// of stopping the read (problem 2 in the class docstring above).
class _CappedAccumulator {
  _CappedAccumulator(this.capBytes)
    : _keepBytes = (capBytes ~/ 5).clamp(1, 1 << 30);

  final int capBytes;
  final int _keepBytes;

  final List<int> _head = [];
  List<int> _tail = [];
  int _originalBytes = 0;

  bool get truncated => _originalBytes > capBytes;

  int get originalBytes => _originalBytes;

  int get keptBytes => _head.length + _tailKept.length;

  void add(List<int> bytes) {
    _originalBytes += bytes.length;
    var remaining = bytes;

    if (_head.length < _keepBytes) {
      final room = _keepBytes - _head.length;
      if (remaining.length <= room) {
        _head.addAll(remaining);
        return;
      }
      _head.addAll(remaining.take(room));
      remaining = remaining.sublist(room);
    }

    _tail.addAll(remaining);
    // Bound tail memory: once it is comfortably larger than what will ever
    // be kept, drop everything except the last _keepBytes bytes. The slack
    // factor avoids re-slicing the list on every single small chunk.
    if (_tail.length > _keepBytes * 4) {
      _tail = _tail.sublist(_tail.length - _keepBytes);
    }
  }

  List<int> get _tailKept => _tail.length > _keepBytes
      ? _tail.sublist(_tail.length - _keepBytes)
      : _tail;

  String decode() {
    if (!truncated) {
      return utf8.decode([..._head, ..._tail], allowMalformed: true);
    }
    final tailKept = _tailKept;
    final droppedBytes = _originalBytes - _head.length - tailKept.length;
    return utf8.decode(_head, allowMalformed: true) +
        _formatDroppedMarker(droppedBytes) +
        utf8.decode(tailKept, allowMalformed: true);
  }
}

/// Formats the dropped-bytes marker with a human-readable size, e.g.
/// `[… 4.2 MB kırpıldı …]` for a 4.2 MB gap.
String _formatDroppedMarker(int droppedBytes) {
  final String size;
  if (droppedBytes < 1024) {
    size = '$droppedBytes B';
  } else if (droppedBytes < 1024 * 1024) {
    size = '${(droppedBytes / 1024).toStringAsFixed(1)} KB';
  } else {
    size = '${(droppedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '[… $size kırpıldı …]';
}
