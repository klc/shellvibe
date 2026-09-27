import 'dart:async';
import 'dart:io';

import 'package:dart_mosh/dart_mosh.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/network/mosh_session_manager.dart';

import 'mosh_test_doubles.dart';

/// A well-formed `mosh-server new` banner. The key is the 22-character base64
/// form mosh uses for its 16-byte session key.
const _connectBanner =
    'MOSH CONNECT 60001 AAECAwQFBgcICQoLDA0ODw\n';

final _address = InternetAddress('192.0.2.10');

void main() {
  group('MoshSessionManager', () {
    late FakeMoshTransport transport;
    late MoshSessionManager manager;
    MoshServerConfig? connectorServer;
    InternetAddress? connectorAddress;
    int? connectorColumns;
    int? connectorRows;

    /// Short intervals so liveness transitions happen inside a test run instead
    /// of on mosh's real 3s cadence.
    MoshSessionManager buildManager() => MoshSessionManager(
      heartbeatInterval: const Duration(milliseconds: 10),
      staleThreshold: const Duration(milliseconds: 40),
      rehomeDebounce: const Duration(milliseconds: 20),
      connector:
          ({
            required MoshServerConfig server,
            required InternetAddress address,
            required int columns,
            required int rows,
          }) async {
            connectorServer = server;
            connectorAddress = address;
            connectorColumns = columns;
            connectorRows = rows;
            return transport;
          },
    );

    setUp(() {
      transport = FakeMoshTransport();
      manager = buildManager();
      connectorServer = null;
      connectorAddress = null;
      connectorColumns = null;
      connectorRows = null;
    });

    tearDown(() async {
      await manager.close();
    });

    group('bootstrap', () {
      test('runs the mosh-server command over the given SSH client', () async {
        final client = FakeBootstrapClient(output: _connectBanner);

        await manager.connect(
          client: client,
          address: _address,
          columns: 100,
          rows: 30,
        );

        expect(client.commands, hasLength(1));
        expect(client.commands.single, contains('mosh-server new'));
        expect(connectorColumns, equals(100));
        expect(connectorRows, equals(30));
      });

      test('passes the already-resolved address, never the hostname', () async {
        // Behind round-robin DNS a second lookup can land on a different
        // machine than the one that just started mosh-server.
        await manager.connect(
          client: FakeBootstrapClient(output: _connectBanner),
          address: _address,
        );

        expect(connectorAddress, same(_address));
        expect(connectorServer!.host, equals('192.0.2.10'));
        expect(connectorServer!.port, equals(60001));
      });

      test('reports a missing mosh-server distinctly', () async {
        final client = FakeBootstrapClient(
          output: 'bash: mosh-server: command not found',
          exitCode: 127,
        );

        await expectLater(
          manager.connect(client: client, address: _address),
          throwsA(
            isA<MoshBootstrapException>()
                .having((e) => e.exitCode, 'exitCode', 127)
                .having((e) => e.message, 'message', contains('not found'))
                // The server's own words survive: they are more useful to the
                // user than anything this layer could paraphrase.
                .having((e) => e.output, 'output', contains('command not found')),
          ),
        );
        expect(manager.isConnected, isFalse);
      });

      test('a non-zero exit keeps the server output verbatim', () async {
        final client = FakeBootstrapClient(
          output: 'mosh-server: Could not bind any port in range 60000-61000',
          exitCode: 1,
        );

        await expectLater(
          manager.connect(client: client, address: _address),
          throwsA(
            isA<MoshBootstrapException>()
                .having((e) => e.exitCode, 'exitCode', 1)
                .having((e) => e.output, 'output', contains('Could not bind')),
          ),
        );
      });

      test('an unparseable banner fails instead of connecting', () async {
        final client = FakeBootstrapClient(output: 'Welcome to Ubuntu\n');

        await expectLater(
          manager.connect(client: client, address: _address),
          throwsA(isA<MoshBootstrapException>()),
        );
        expect(manager.transport, isNull);
      });

      test('an SSH failure is wrapped, not leaked raw', () async {
        final client = FakeBootstrapClient(
          error: const SocketException('channel closed'),
        );

        await expectLater(
          manager.connect(client: client, address: _address),
          throwsA(isA<MoshBootstrapException>()),
        );
      });
    });

    group('liveness', () {
      test('starts live', () async {
        await manager.connect(
          client: FakeBootstrapClient(output: _connectBanner),
          address: _address,
        );

        expect(manager.linkState.status, equals(MoshLinkStatus.live));
        expect(manager.isConnected, isTrue);
      });

      test('silence reports stale and does NOT close the session', () async {
        // The whole point of Mosh: a quiet link is not a dead one. The SSH
        // manager's equivalent path tears the session down; this one must not.
        await manager.connect(
          client: FakeBootstrapClient(output: _connectBanner),
          address: _address,
        );

        final states = <MoshLinkState>[];
        manager.linkStates.listen(states.add);

        transport.setSilence(const Duration(seconds: 12));
        await Future.delayed(const Duration(milliseconds: 60));

        expect(states.map((s) => s.status), contains(MoshLinkStatus.stale));
        expect(transport.isClosed, isFalse);
        expect(manager.isConnected, isTrue);
      });

      test('a stale link keeps reporting a growing silence', () async {
        await manager.connect(
          client: FakeBootstrapClient(output: _connectBanner),
          address: _address,
        );

        final silences = <Duration>[];
        manager.linkStates
            .where((s) => s.status == MoshLinkStatus.stale)
            .listen((s) => silences.add(s.silence));

        transport.setSilence(const Duration(seconds: 7));
        await Future.delayed(const Duration(milliseconds: 30));
        transport.setSilence(const Duration(seconds: 9));
        await Future.delayed(const Duration(milliseconds: 30));

        expect(silences, containsAllInOrder(const [
          Duration(seconds: 7),
          Duration(seconds: 9),
        ]));
      });

      test('the link returns to live once the server is heard again', () async {
        await manager.connect(
          client: FakeBootstrapClient(output: _connectBanner),
          address: _address,
        );

        transport.setSilence(const Duration(seconds: 12));
        await Future.delayed(const Duration(milliseconds: 40));
        expect(manager.linkState.status, equals(MoshLinkStatus.stale));

        transport.setSilence(Duration.zero);
        await Future.delayed(const Duration(milliseconds: 40));

        expect(manager.linkState.status, equals(MoshLinkStatus.live));
      });

      test('a server shutdown ends the session', () async {
        await manager.connect(
          client: FakeBootstrapClient(output: _connectBanner),
          address: _address,
        );

        final states = <MoshLinkState>[];
        manager.linkStates.listen(states.add);

        transport.serverShutdown();
        await Future.delayed(const Duration(milliseconds: 30));

        expect(
          states.map((s) => s.status),
          contains(MoshLinkStatus.serverShutdown),
        );
      });

      test('a local close does not report a server shutdown', () async {
        await manager.connect(
          client: FakeBootstrapClient(output: _connectBanner),
          address: _address,
        );

        final states = <MoshLinkState>[];
        manager.linkStates.listen(states.add);

        await manager.close();
        await Future.delayed(const Duration(milliseconds: 30));

        expect(
          states.map((s) => s.status),
          isNot(contains(MoshLinkStatus.serverShutdown)),
        );
        expect(transport.isClosed, isTrue);
      });

      test('transport errors are forwarded without ending the session',
          () async {
        await manager.connect(
          client: FakeBootstrapClient(output: _connectBanner),
          address: _address,
        );

        final errors = <Object>[];
        manager.errors.listen(errors.add);

        transport.emitError('packet failed to decrypt');
        await Future.delayed(const Duration(milliseconds: 20));

        expect(errors, contains('packet failed to decrypt'));
        expect(manager.isConnected, isTrue);
      });
    });

    group('rehome', () {
      test('collapses a burst of requests into one rebind', () async {
        // Connectivity changes arrive in clusters: interface down, up, new
        // address. One rebind is enough for the whole burst.
        await manager.connect(
          client: FakeBootstrapClient(output: _connectBanner),
          address: _address,
        );

        final futures = [manager.rehome(), manager.rehome(), manager.rehome()];
        await Future.wait(futures);

        expect(transport.rehomeCount, equals(1));
      });

      test('a request during a rebind triggers one more afterwards', () async {
        // The package's own guard drops a concurrent call, which would strand
        // the session on the network path it had before the newest change.
        await manager.connect(
          client: FakeBootstrapClient(output: _connectBanner),
          address: _address,
        );

        final gate = Completer<void>();
        transport.rehomeGate = gate;
        final first = manager.rehome();
        await Future.delayed(const Duration(milliseconds: 30));
        expect(transport.rehomeCount, equals(1));

        transport.rehomeGate = null;
        final second = manager.rehome();
        await Future.delayed(const Duration(milliseconds: 30));
        gate.complete();
        await Future.wait([first, second]);
        await Future.delayed(const Duration(milliseconds: 20));

        expect(transport.rehomeCount, equals(2));
      });

      test('a failed rebind is reported and left for the next attempt',
          () async {
        await manager.connect(
          client: FakeBootstrapClient(output: _connectBanner),
          address: _address,
        );

        final errors = <Object>[];
        manager.errors.listen(errors.add);
        transport.rehomeError = const SocketException('no route to host');

        // Completes normally: callers are lifecycle and connectivity handlers
        // with nowhere to put an exception.
        await manager.rehome();
        await Future.delayed(const Duration(milliseconds: 20));

        expect(errors, hasLength(1));
        expect(manager.isConnected, isTrue);
      });

      test('is a no-op before connect and after close', () async {
        await manager.rehome();
        expect(transport.rehomeCount, equals(0));

        await manager.connect(
          client: FakeBootstrapClient(output: _connectBanner),
          address: _address,
        );
        await manager.close();
        await manager.rehome();
        await Future.delayed(const Duration(milliseconds: 40));

        expect(transport.rehomeCount, equals(0));
      });
    });

    test('close stops the heartbeat and releases the transport', () async {
      await manager.connect(
        client: FakeBootstrapClient(output: _connectBanner),
        address: _address,
      );

      await manager.close();

      expect(manager.transport, isNull);
      expect(manager.serverConfig, isNull);
      expect(manager.isConnected, isFalse);
      expect(transport.isClosed, isTrue);
    });

    test('reconnecting after a close works', () async {
      await manager.connect(
        client: FakeBootstrapClient(output: _connectBanner),
        address: _address,
      );
      await manager.close();

      transport = FakeMoshTransport();
      await manager.connect(
        client: FakeBootstrapClient(output: _connectBanner),
        address: _address,
      );

      expect(manager.isConnected, isTrue);
      expect(manager.linkState.status, equals(MoshLinkStatus.live));
    });
  });
}
