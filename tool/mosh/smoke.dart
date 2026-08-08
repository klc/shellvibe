// Faz 0 wire-compatibility check for `dart_mosh` against a real `mosh-server`.
//
// This is a manual harness, not a test: it needs the Docker container from
// tool/mosh/docker-compose.yml to be up. See tool/mosh/README.md.
//
//   docker compose -f tool/mosh/docker-compose.yml up -d --build
//   dart run tool/mosh/smoke.dart
//
// Exits 0 when every check passes, 1 on the first failure.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mosh/dart_mosh.dart';
import 'package:dartssh2/dartssh2.dart';

const _sshHost = '127.0.0.1';
const _sshPort = 2222;
const _sshUser = 'mosh';
const _sshPassword = 'mosh';

/// The range published 1:1 by docker-compose. `mosh-server` must pick a port
/// inside it or the datagrams never reach the container.
const _udpPortStart = 60000;
const _udpPortEnd = 60010;

/// Every await in the run is bounded so a silent protocol mismatch fails
/// instead of hanging the terminal.
const _step = Duration(seconds: 15);

Future<void> main() async {
  final checks = _Checks();
  SSHClient? client;
  MoshSession? session;

  try {
    stdout.writeln('→ SSH $_sshUser@$_sshHost:$_sshPort');
    client = SSHClient(
      await SSHSocket.connect(_sshHost, _sshPort).timeout(_step),
      username: _sshUser,
      onPasswordRequest: () => _sshPassword,
    );

    // 1. Bootstrap: the exact command the app will run over its own SSH client.
    final bootstrap = const MoshSshBootstrap(
      term: 'xterm-256color',
      locale: 'en_US.UTF-8',
      serverPort: _udpPortStart,
      serverPortEnd: _udpPortEnd,
    ).command();
    stdout.writeln('→ bootstrap: $bootstrap');

    final result = await client.runWithResult(bootstrap).timeout(_step);
    final output = utf8.decode(result.output, allowMalformed: true);
    checks.expect(
      'mosh-server exits 0',
      result.exitCode == 0,
      'exitCode=${result.exitCode} output=${output.trim()}',
    );
    if (result.exitCode != 0) return;

    // 2. Parse: the MOSH CONNECT line carries the UDP port and the session key.
    final config = MoshServerConfig.parse(output, host: _sshHost);
    stdout.writeln('→ MOSH CONNECT port=${config.port}');
    checks.expect(
      'port is inside the published range',
      config.port >= _udpPortStart && config.port <= _udpPortEnd,
      'port=${config.port}',
    );

    // 3. UDP session. The address is passed explicitly for the same reason the
    // app will: never resolve the host a second time.
    session = await MoshSession.connect(
      server: config,
      cipher: MoshPacketCipher.aesOcb(config.key),
      address: InternetAddress(_sshHost),
      columns: 100,
      rows: 30,
    ).timeout(_step);

    // Tracked from the moment the socket opens: `done` completing early means
    // the server shut the session down under us.
    var sessionClosed = false;
    unawaited(session.done.then((_) => sessionClosed = true));

    final screen = StringBuffer();
    final firstFrame = Completer<void>();
    session.stdout.listen((bytes) {
      screen.write(utf8.decode(bytes, allowMalformed: true));
      if (!firstFrame.isCompleted) firstFrame.complete();
    });
    session.errors.listen((error) => stderr.writeln('  [mosh error] $error'));

    await checks.guard(
      'server sends a first frame',
      () => firstFrame.future.timeout(_step),
    );

    // 4. Round trip: a marker echoed back proves the SSP state machine agrees
    // in both directions, not just that packets decrypt.
    const marker = 'terly2-mosh-ok';
    session.send(utf8.encode("printf '%s\\n' $marker\r"));
    await checks.guard(
      'marker comes back on the screen',
      () => _waitFor(screen, marker),
    );

    // 5. Resize, then rehome onto a fresh local socket — the roaming primitive
    // Faz 2 is built on. The session must survive and keep answering.
    session.resize(120, 40);
    await session.rehome().timeout(_step);
    stdout.writeln('→ rehomed onto a new local port');

    const afterRehome = 'terly2-rehome-ok';
    session.send(utf8.encode("printf '%s\\n' $afterRehome\r"));
    await checks.guard(
      'session answers after rehome',
      () => _waitFor(screen, afterRehome),
    );

    checks.expect(
      'session is still open',
      !sessionClosed,
      'done completed before close()',
    );

    final rtt = session.smoothedRtt;
    stdout.writeln('→ smoothed RTT: ${rtt?.inMilliseconds ?? '-'} ms');
  } on TimeoutException catch (e) {
    checks.fail('timed out', '$e');
  } catch (e, s) {
    checks.fail('unexpected error', '$e\n$s');
  } finally {
    await session?.close();
    client?.close();
  }

  stdout.writeln('');
  stdout.writeln(checks.summary);
  exitCode = checks.passed ? 0 : 1;
}

/// Polls [screen] until [needle] shows up. `mosh-server` repaints the whole
/// screen, so the marker can arrive split across frames.
Future<void> _waitFor(StringBuffer screen, String needle) async {
  final deadline = DateTime.now().add(_step);
  while (DateTime.now().isBefore(deadline)) {
    if (screen.toString().contains(needle)) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('"$needle" never appeared');
}

class _Checks {
  final _failures = <String>[];
  var _total = 0;

  bool get passed => _failures.isEmpty;

  void expect(String name, bool condition, [String detail = '']) {
    _total++;
    if (condition) {
      stdout.writeln('  ✓ $name');
    } else {
      fail(name, detail, counted: true);
    }
  }

  Future<void> guard(String name, Future<void> Function() body) async {
    _total++;
    try {
      await body();
      stdout.writeln('  ✓ $name');
    } catch (e) {
      fail(name, '$e', counted: true);
    }
  }

  void fail(String name, String detail, {bool counted = false}) {
    if (!counted) _total++;
    _failures.add(name);
    stdout.writeln('  ✗ $name${detail.isEmpty ? '' : ' — $detail'}');
  }

  String get summary => passed
      ? '$_total/$_total passed — dart_mosh is wire-compatible with mosh-server.'
      : '${_total - _failures.length}/$_total passed — failed: '
            '${_failures.join(', ')}';
}
