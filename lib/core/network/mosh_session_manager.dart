import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mosh/dart_mosh.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

/// How often the manager re-evaluates link liveness. Mosh's own heartbeat
/// interval is 3s, so checking on the same cadence keeps [MoshLinkState.silence]
/// from lagging behind reality.
const _kHeartbeatInterval = Duration(seconds: 3);

/// Silence after which the link is reported [MoshLinkStatus.stale]. Two missed
/// heartbeats: one lost datagram is normal, a quiet second window is worth
/// telling the user about.
const _kStaleThreshold = Duration(seconds: 6);

/// Network-change events arrive in bursts (interface down, then up, then a new
/// address). Collapsing them into one rebind avoids a rehome per event.
const _kRehomeDebounce = Duration(milliseconds: 300);

/// Liveness of a Mosh link.
///
/// Unlike SSH, [stale] is **not** a failure: a Mosh session survives arbitrary
/// silence, and the state exists so the UI can say "quiet for 12s" instead of
/// pretending the tab is dead. Only [serverShutdown] ends a session.
enum MoshLinkStatus { live, stale, serverShutdown }

/// Snapshot of a Mosh link's liveness.
@immutable
class MoshLinkState {
  final MoshLinkStatus status;

  /// How long the server has been silent. [Duration.zero] before the first
  /// datagram has been accounted for.
  final Duration silence;

  const MoshLinkState(this.status, {this.silence = Duration.zero});

  @override
  bool operator ==(Object other) =>
      other is MoshLinkState &&
      other.status == status &&
      other.silence == silence;

  @override
  int get hashCode => Object.hash(status, silence);

  @override
  String toString() => 'MoshLinkState($status, silence: $silence)';
}

/// Thrown when `mosh-server` could not be started over SSH.
///
/// [output] is kept verbatim: exit code 127 means the binary is missing, but
/// everything else is the server's own words and is more useful to the user
/// than anything this layer could paraphrase.
class MoshBootstrapException implements Exception {
  final String message;
  final int? exitCode;
  final String output;

  const MoshBootstrapException(this.message, {this.exitCode, this.output = ''});

  @override
  String toString() => output.isEmpty
      ? 'MoshBootstrapException: $message'
      : 'MoshBootstrapException: $message\n$output';
}

/// The slice of [MoshSession] this layer drives.
///
/// [MoshSession] can only be built by opening a real UDP socket, so the manager
/// and the bridge talk to this instead and tests substitute a fake.
abstract class MoshTransport {
  Stream<List<int>> get stdout;
  Stream<int> get echoAcks;
  Stream<Object> get errors;
  Future<void> get done;

  /// Time since the last datagram from the server, or null before the first.
  Duration? get sinceLastHeard;

  /// True only when the server announced a shutdown — a local close does not
  /// set this, which is what separates the two ways [done] can complete.
  bool get isServerShutdown;

  Duration? get smoothedRtt;

  int send(List<int> data);
  int resize(int columns, int rows);

  /// Rebinds the local UDP socket, keeping session state.
  Future<void> rehome();

  Future<void> close();
}

/// [MoshTransport] backed by a real [MoshSession].
class MoshSessionTransport implements MoshTransport {
  final MoshSession session;

  MoshSessionTransport(this.session);

  @override
  Stream<List<int>> get stdout => session.stdout;

  @override
  Stream<int> get echoAcks => session.echoAcks;

  @override
  Stream<Object> get errors => session.errors;

  @override
  Future<void> get done => session.done;

  @override
  Duration? get sinceLastHeard => session.sinceLastHeard;

  @override
  bool get isServerShutdown => session.isServerShutdown;

  @override
  Duration? get smoothedRtt => session.smoothedRtt;

  @override
  int send(List<int> data) => session.send(data);

  @override
  int resize(int columns, int rows) => session.resize(columns, rows);

  @override
  Future<void> rehome() => session.rehome();

  @override
  Future<void> close() => session.close();
}

/// Opens the UDP transport. Injected so tests can drive the manager without a
/// socket.
typedef MoshTransportConnector =
    Future<MoshTransport> Function({
      required MoshServerConfig server,
      required InternetAddress address,
      required int columns,
      required int rows,
    });

/// Owns a Mosh session's lifecycle: bootstrap over an existing SSH connection,
/// UDP transport, liveness reporting, and roaming.
///
/// Deliberately parallel to `SSHSessionManager` — connect, publish state, close
/// — with one behavioural difference that matters: a silent link is reported,
/// never torn down. The SSH manager's keep-alive path exists to detect a dead
/// connection; Mosh has no such thing to detect, and treating silence as death
/// would throw away the only reason to run this protocol.
class MoshSessionManager {
  /// Bootstrap over SSH, then hand the UDP work to [connector].
  MoshSessionManager({
    MoshTransportConnector? connector,
    this.heartbeatInterval = _kHeartbeatInterval,
    this.staleThreshold = _kStaleThreshold,
    this.rehomeDebounce = _kRehomeDebounce,
  }) : _connect = connector ?? _defaultConnector;

  final MoshTransportConnector _connect;
  final Duration heartbeatInterval;
  final Duration staleThreshold;
  final Duration rehomeDebounce;

  MoshTransport? _transport;
  MoshServerConfig? _serverConfig;
  Timer? _heartbeatTimer;
  Timer? _rehomeTimer;
  Completer<void>? _pendingRehome;
  bool _rehomeRunning = false;
  bool _rehomeAgain = false;
  bool _closed = false;

  var _linkState = const MoshLinkState(MoshLinkStatus.live);
  StreamController<MoshLinkState> _linkStates =
      StreamController<MoshLinkState>.broadcast();
  StreamController<Object> _errors = StreamController<Object>.broadcast();

  /// The live transport, or null before [connect] or after [close].
  MoshTransport? get transport => _transport;

  /// Port and key `mosh-server` reported, kept for diagnostics.
  MoshServerConfig? get serverConfig => _serverConfig;

  bool get isConnected => _transport != null && !_closed;

  /// Latest liveness snapshot.
  MoshLinkState get linkState => _linkState;

  /// Liveness updates. Emits on every status change and on each heartbeat while
  /// stale, so a "quiet for Ns" badge can count up.
  Stream<MoshLinkState> get linkStates => _linkStates.stream;

  /// Non-fatal transport and rehome failures. Nothing here ends the session.
  Stream<Object> get errors => _errors.stream;

  /// Starts `mosh-server` over [client] and opens the UDP session to it.
  ///
  /// [client] stays connected afterwards: SFTP and tunnels keep using it, and
  /// a failed bootstrap leaves the caller with a live SSH client to fall back
  /// to.
  ///
  /// [address] must be the address the SSH connection already resolved. Mosh is
  /// never given a second chance to resolve the hostname — behind round-robin
  /// DNS a fresh lookup can point at a different machine than the one running
  /// the `mosh-server` we just started.
  Future<MoshTransport> connect({
    required SSHClient client,
    required InternetAddress address,
    MoshSshBootstrap bootstrap = const MoshSshBootstrap(),
    int columns = 80,
    int rows = 24,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    await close();
    _closed = false;
    if (_linkStates.isClosed) {
      _linkStates = StreamController<MoshLinkState>.broadcast();
    }
    if (_errors.isClosed) {
      _errors = StreamController<Object>.broadcast();
    }

    final SSHRunResult result;
    try {
      result = await client.runWithResult(bootstrap.command()).timeout(timeout);
    } on TimeoutException {
      throw MoshBootstrapException(
        'Starting mosh-server timed out after ${timeout.inSeconds}s.',
      );
    } catch (e) {
      throw MoshBootstrapException('Could not run mosh-server: $e');
    }

    final output = utf8.decode(result.output, allowMalformed: true);
    if (result.exitCode != 0) {
      throw MoshBootstrapException(
        result.exitCode == 127
            ? 'mosh-server was not found on the remote host.'
            : 'mosh-server exited with code ${result.exitCode}.',
        exitCode: result.exitCode,
        output: output.trim(),
      );
    }

    final MoshServerConfig config;
    try {
      config = MoshServerConfig.parse(output, host: address.address);
    } catch (e) {
      throw MoshBootstrapException(
        'mosh-server started but did not report a usable MOSH CONNECT line: $e',
        exitCode: result.exitCode,
        output: output.trim(),
      );
    }

    final transport = await _connect(
      server: config,
      address: address,
      columns: columns,
      rows: rows,
    );

    if (_closed) {
      // close() ran while the socket was being opened; do not leave a live
      // session behind for a tab that is already gone.
      await transport.close();
      throw StateError('Mosh session was closed during connect.');
    }

    _transport = transport;
    _serverConfig = config;
    _setLinkState(const MoshLinkState(MoshLinkStatus.live));

    transport.errors.listen(_forwardError);
    unawaited(transport.done.then((_) => _handleDone()));
    _heartbeatTimer = Timer.periodic(
      heartbeatInterval,
      (_) => _checkLiveness(),
    );

    return transport;
  }

  void _checkLiveness() {
    final transport = _transport;
    if (transport == null || _closed) return;
    if (_linkState.status == MoshLinkStatus.serverShutdown) return;

    final silence = transport.sinceLastHeard ?? Duration.zero;
    if (silence >= staleThreshold) {
      // Emitted on every tick, not only on the transition: the badge shows how
      // long the silence has lasted, so a repeated `stale` with a larger
      // duration is new information.
      _setLinkState(MoshLinkState(MoshLinkStatus.stale, silence: silence));
    } else if (_linkState.status != MoshLinkStatus.live) {
      _setLinkState(const MoshLinkState(MoshLinkStatus.live));
    }
  }

  void _handleDone() {
    if (_closed) return;
    final transport = _transport;
    if (transport == null) return;
    if (!transport.isServerShutdown) return;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _setLinkState(const MoshLinkState(MoshLinkStatus.serverShutdown));
  }

  void _setLinkState(MoshLinkState state) {
    if (state == _linkState) return;
    _linkState = state;
    if (!_linkStates.isClosed) _linkStates.add(state);
  }

  void _forwardError(Object error) {
    if (!_errors.isClosed) _errors.add(error);
  }

  /// Rebinds the UDP socket onto the current network path.
  ///
  /// Calls made inside [rehomeDebounce] of each other collapse into one rebind.
  /// The returned future always completes normally — a failed rebind is
  /// reported on [errors] and left for the next network event to retry, since
  /// callers are lifecycle and connectivity handlers that have nowhere to put
  /// an exception.
  Future<void> rehome() {
    if (_closed || _transport == null) return Future<void>.value();
    final completer = _pendingRehome ??= Completer<void>();
    _rehomeTimer?.cancel();
    _rehomeTimer = Timer(rehomeDebounce, _drainRehome);
    return completer.future;
  }

  Future<void> _drainRehome() async {
    if (_rehomeRunning) {
      // A request landed mid-rebind. The package's own guard would drop it, so
      // remember to run once more against the newest network path.
      _rehomeAgain = true;
      return;
    }
    _rehomeRunning = true;
    try {
      do {
        _rehomeAgain = false;
        final completer = _pendingRehome;
        _pendingRehome = null;
        final transport = _transport;
        if (transport == null || _closed) {
          completer?.complete();
          return;
        }
        try {
          await transport.rehome();
        } catch (e) {
          _forwardError(e);
        }
        completer?.complete();
      } while (_rehomeAgain);
    } finally {
      _rehomeRunning = false;
    }
  }

  /// Closes the UDP session and stops all timers. The SSH client is left alone:
  /// it is owned by the caller and other features are still using it.
  Future<void> close() async {
    _closed = true;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _rehomeTimer?.cancel();
    _rehomeTimer = null;
    _pendingRehome?.complete();
    _pendingRehome = null;

    final transport = _transport;
    _transport = null;
    _serverConfig = null;
    if (transport != null) {
      try {
        await transport.close();
      } catch (_) {}
    }

    if (!_linkStates.isClosed) await _linkStates.close();
    if (!_errors.isClosed) await _errors.close();
  }
}

Future<MoshTransport> _defaultConnector({
  required MoshServerConfig server,
  required InternetAddress address,
  required int columns,
  required int rows,
}) async {
  final session = await MoshSession.connect(
    server: server,
    cipher: MoshPacketCipher.aesOcb(server.key),
    address: address,
    columns: columns,
    rows: rows,
  );
  return MoshSessionTransport(session);
}
