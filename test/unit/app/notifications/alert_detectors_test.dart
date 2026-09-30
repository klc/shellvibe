import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/notifications/alert_detectors.dart';
import 'package:shellvibe/core/network/tunnel_engine.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_tab_session.dart';

void main() {
  group('SessionDropDetector', () {
    TabLiveness tab(
      String id, {
      bool connected = true,
      TerminalDisconnectCause? cause,
    }) => (id: id, connected: connected, cause: cause);

    test('reports a tab that was connected and is not now', () {
      final detector = SessionDropDetector();
      expect(detector.scan([tab('a')]), isEmpty);

      final ended = detector.scan([
        tab(
          'a',
          connected: false,
          cause: TerminalDisconnectCause.connectionLost,
        ),
      ]);
      expect(ended, [(id: 'a', cause: TerminalDisconnectCause.connectionLost)]);
    });

    test('reports it once, not on every later emission', () {
      final detector = SessionDropDetector();
      detector.scan([tab('a')]);
      final dropped = tab(
        'a',
        connected: false,
        cause: TerminalDisconnectCause.remoteExit,
      );
      expect(detector.scan([dropped]), hasLength(1));
      expect(detector.scan([dropped]), isEmpty);
    });

    test('a tab first seen disconnected is not a drop', () {
      final detector = SessionDropDetector();
      expect(
        detector.scan([
          tab(
            'a',
            connected: false,
            cause: TerminalDisconnectCause.connectionLost,
          ),
        ]),
        isEmpty,
      );
    });

    test('a reconnect, which clears the cause, is not a drop', () {
      final detector = SessionDropDetector();
      detector.scan([tab('a')]);
      expect(detector.scan([tab('a', connected: false)]), isEmpty);
    });

    test('a tab the user closed is gone from the list, not dropped', () {
      final detector = SessionDropDetector();
      detector.scan([tab('a'), tab('b')]);
      expect(detector.scan([tab('b')]), isEmpty);
    });

    test('a dropped tab that reconnects and drops again is reported again', () {
      final detector = SessionDropDetector();
      final lost = tab(
        'a',
        connected: false,
        cause: TerminalDisconnectCause.connectionLost,
      );
      detector.scan([tab('a')]);
      expect(detector.scan([lost]), hasLength(1));
      detector.scan([tab('a')]);
      expect(detector.scan([lost]), hasLength(1));
    });
  });

  group('TunnelFailureDetector', () {
    ActiveTunnel tunnel(String id, {bool active = true, String? error}) =>
        ActiveTunnel(
          ruleId: id,
          hostId: 'h',
          type: 'local',
          localPort: 8080,
          isActive: active,
          error: error,
        );

    test('reports a forward that stopped with an error, once', () {
      final detector = TunnelFailureDetector();
      expect(detector.scan([tunnel('r1')]), isEmpty);

      final failed = tunnel('r1', active: false, error: 'port in use');
      expect(detector.scan([failed]).map((t) => t.ruleId), ['r1']);
      // The engine re-emits the list on every transfer tick.
      expect(detector.scan([failed]), isEmpty);
    });

    test('a forward the user stopped leaves the list and reports nothing', () {
      final detector = TunnelFailureDetector();
      detector.scan([tunnel('r1')]);
      expect(detector.scan(const []), isEmpty);
    });

    test('a forward that fails again after coming up is reported again', () {
      final detector = TunnelFailureDetector();
      final failed = tunnel('r1', active: false, error: 'port in use');
      expect(detector.scan([failed]), hasLength(1));
      detector.scan([tunnel('r1')]);
      expect(detector.scan([failed]), hasLength(1));
    });

    test('an inactive forward with no error is not a failure', () {
      final detector = TunnelFailureDetector();
      expect(detector.scan([tunnel('r1', active: false)]), isEmpty);
    });
  });
}
