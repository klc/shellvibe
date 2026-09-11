import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:xterm3/xterm.dart';

import 'package:shellvibe/core/network/device_link/device_link_client.dart';
import 'package:shellvibe/core/network/device_link/device_link_protocol.dart';
import 'package:shellvibe/core/network/device_link/device_link_server.dart';
import 'package:shellvibe/core/network/device_link/device_link_snapshot.dart';
import 'package:shellvibe/core/utils/platform_capabilities.dart';
import 'package:shellvibe/features/device_link/presentation/controllers/linked_session_controller.dart';
import 'package:shellvibe/features/device_link/presentation/screens/linked_session_screen.dart';
import 'package:shellvibe/features/device_link/presentation/screens/pairing_qr_screen.dart';
import 'package:shellvibe/features/device_link/presentation/screens/scan_pair_screen.dart';
import 'package:shellvibe/features/device_link/presentation/widgets/compose_sheet.dart';
import 'package:shellvibe/features/device_link/presentation/widgets/session_picker_sheet.dart';
import 'package:shellvibe/features/terminal/presentation/widgets/mobile_extra_keys_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => debugPlatformCapabilitiesOverride = null);

  test('bracketed paste wraps a multi-line submission once', () {
    expect(
      deviceLinkBracketedPaste('echo one\necho two'),
      '\x1b[200~echo one\necho two\x1b[201~',
    );
  });

  test(
    'chunks a large PTY paste without changing frame order or bytes',
    () async {
      final connection = _FakeDeviceLinkConnection();
      final controller = DeviceLinkLinkedSessionController(
        connection: connection,
        session: const DeviceLinkSessionInfo(
          id: 'local-1',
          title: 'Desktop shell',
          type: 'local',
        ),
      );
      addTearDown(controller.close);

      await controller.connect();
      connection.controls.add(
        const DeviceLinkAttached(
          sessionId: 'local-1',
          cols: 52,
          rows: 30,
          alt: false,
          bracketedPaste: false,
          scrollbackLines: 0,
        ),
      );
      await pumpEventQueue();

      final input = Uint8List.fromList(
        List<int>.generate(
          deviceLinkMaxPtyInputPayloadLength * 2 + 7,
          (index) => index % 256,
        ),
      );
      await controller.sendInput(input);

      expect(
        connection.sentBinary.map((frame) => frame.type),
        everyElement(DeviceLinkBinaryFrameType.ptyInput),
      );
      expect(connection.sentBinary.map((frame) => frame.payload.length), [
        deviceLinkMaxPtyInputPayloadLength,
        deviceLinkMaxPtyInputPayloadLength,
        7,
      ]);
      expect(
        connection.sentBinary.expand((frame) => frame.payload),
        orderedEquals(input),
      );
    },
  );

  test(
    'keeps concurrent large PTY inputs FIFO across every binary frame',
    () async {
      final connection = _FakeDeviceLinkConnection(
        sendBinaryDelay: const Duration(milliseconds: 1),
      );
      final controller = DeviceLinkLinkedSessionController(
        connection: connection,
        session: const DeviceLinkSessionInfo(
          id: 'local-1',
          title: 'Desktop shell',
          type: 'local',
        ),
      );
      addTearDown(controller.close);

      await controller.connect();
      connection.controls.add(
        const DeviceLinkAttached(
          sessionId: 'local-1',
          cols: 52,
          rows: 30,
          alt: false,
          bracketedPaste: false,
          scrollbackLines: 0,
        ),
      );
      await pumpEventQueue();

      final firstInput = Uint8List.fromList(
        List<int>.generate(
          deviceLinkMaxPtyInputPayloadLength * 2 + 3,
          (index) => index % 251,
        ),
      );
      final secondInput = Uint8List.fromList(
        List<int>.generate(
          deviceLinkMaxPtyInputPayloadLength + 5,
          (index) => (index + 17) % 251,
        ),
      );

      await Future.wait([
        controller.sendInput(firstInput),
        controller.sendInput(secondInput),
      ]);

      expect(connection.sentBinary.map((frame) => frame.payload.length), [
        deviceLinkMaxPtyInputPayloadLength,
        deviceLinkMaxPtyInputPayloadLength,
        3,
        deviceLinkMaxPtyInputPayloadLength,
        5,
      ]);
      expect(
        connection.sentBinary.expand((frame) => frame.payload),
        orderedEquals([...firstInput, ...secondInput]),
      );
    },
  );

  test(
    'rejects input that would exceed the bounded outbound byte budget',
    () async {
      final connection = _FakeDeviceLinkConnection(
        sendBinaryDelay: const Duration(milliseconds: 1),
      );
      final controller = DeviceLinkLinkedSessionController(
        connection: connection,
        session: const DeviceLinkSessionInfo(
          id: 'local-1',
          title: 'Desktop shell',
          type: 'local',
        ),
      );
      addTearDown(controller.close);

      await _attachController(controller, connection);

      final acceptedInput = Uint8List.fromList(
        List<int>.generate(
          deviceLinkMaxQueuedInputBytes - 1,
          (index) => index % 251,
        ),
      );
      final rejectedInput = Uint8List.fromList([1, 2]);
      final acceptedFuture = controller.sendInput(acceptedInput);

      // Reservation happens before the first send yields to the slow
      // connection, so the second logical operation sees the full budget.
      expect(controller.queuedInputBytes, deviceLinkMaxQueuedInputBytes - 1);
      await controller.sendInput(rejectedInput);
      await acceptedFuture;

      expect(controller.queuedInputBytes, 0);
      expect(controller.rejectedInputBytes, rejectedInput.length);
      expect(controller.status, DeviceLinkLinkedSessionStatus.attached);
      expect(
        connection.sentBinary.expand((frame) => frame.payload),
        orderedEquals(acceptedInput),
      );
    },
  );

  test(
    'detach still reaches the peer after it has reclaimed the session',
    () async {
      final connection = _FakeDeviceLinkConnection();
      final controller = DeviceLinkLinkedSessionController(
        connection: connection,
        session: const DeviceLinkSessionInfo(
          id: 'local-1',
          title: 'Desktop shell',
          type: 'local',
        ),
      );
      addTearDown(controller.close);

      await _attachController(controller, connection);
      connection.controls.add(const DeviceLinkReclaimed(cols: 80, rows: 24));
      await pumpEventQueue();

      await controller.detach();

      // A reclaimed session is read-only for input but still attached on the
      // desktop: the disconnect button has to release it there rather than
      // leaving the socket to be dropped.
      expect(connection.sentDetach, hasLength(1));
      expect(controller.status, DeviceLinkLinkedSessionStatus.detached);
      expect(controller.terminalSession.isConnected, isFalse);
    },
  );

  test('detach still reaches a read-only connection', () async {
    final connection = _FakeDeviceLinkConnection(readOnly: true);
    final controller = DeviceLinkLinkedSessionController(
      connection: connection,
      session: const DeviceLinkSessionInfo(
        id: 'local-1',
        title: 'Desktop shell',
        type: 'local',
      ),
    );
    addTearDown(controller.close);

    await _attachController(controller, connection);
    await controller.detach();

    expect(connection.sentDetach, hasLength(1));
    expect(controller.status, DeviceLinkLinkedSessionStatus.detached);
    expect(controller.terminalSession.isConnected, isFalse);
  });

  test('detach is a no-op once the session is already detached', () async {
    final connection = _FakeDeviceLinkConnection();
    final controller = DeviceLinkLinkedSessionController(
      connection: connection,
      session: const DeviceLinkSessionInfo(
        id: 'local-1',
        title: 'Desktop shell',
        type: 'local',
      ),
    );
    addTearDown(controller.close);

    await _attachController(controller, connection);
    await controller.detach();
    await controller.detach();

    expect(connection.sentDetach, hasLength(1));
    expect(controller.status, DeviceLinkLinkedSessionStatus.detached);
  });

  test(
    'detach is a no-op after a fatal error or disconnected connection',
    () async {
      final errorConnection = _FakeDeviceLinkConnection();
      final errorController = DeviceLinkLinkedSessionController(
        connection: errorConnection,
        session: const DeviceLinkSessionInfo(
          id: 'local-1',
          title: 'Desktop shell',
          type: 'local',
        ),
      );
      addTearDown(errorController.close);
      await _attachController(errorController, errorConnection);
      errorConnection.controls.add(
        const DeviceLinkError(
          code: 'session_gone',
          message: 'The requested terminal session is no longer available',
        ),
      );
      await pumpEventQueue();

      await errorController.detach();

      expect(errorConnection.sentDetach, isEmpty);
      expect(errorController.status, DeviceLinkLinkedSessionStatus.error);
      expect(errorController.isReadOnly, isTrue);
      expect(errorController.terminalSession.isConnected, isFalse);

      final disconnectedConnection = _FakeDeviceLinkConnection();
      final disconnectedController = DeviceLinkLinkedSessionController(
        connection: disconnectedConnection,
        session: const DeviceLinkSessionInfo(
          id: 'local-1',
          title: 'Desktop shell',
          type: 'local',
        ),
      );
      addTearDown(disconnectedController.close);
      await _attachController(disconnectedController, disconnectedConnection);
      await disconnectedConnection.disconnect();
      await pumpEventQueue();

      await disconnectedController.detach();

      expect(disconnectedConnection.sentDetach, isEmpty);
      expect(
        disconnectedController.status,
        DeviceLinkLinkedSessionStatus.disconnected,
      );
      expect(disconnectedController.isReadOnly, isTrue);
      expect(disconnectedController.terminalSession.isConnected, isFalse);
    },
  );

  test('detach after controller close does not write to the peer', () async {
    final connection = _FakeDeviceLinkConnection();
    final controller = DeviceLinkLinkedSessionController(
      connection: connection,
      session: const DeviceLinkSessionInfo(
        id: 'local-1',
        title: 'Desktop shell',
        type: 'local',
      ),
    );

    await _attachController(controller, connection);
    await controller.close();
    await controller.detach();

    expect(connection.sentDetach, isEmpty);
    expect(connection.closed, isTrue);
  });

  test(
    'attached writable session keeps the ordered detach operation',
    () async {
      final connection = _FakeDeviceLinkConnection();
      final controller = DeviceLinkLinkedSessionController(
        connection: connection,
        session: const DeviceLinkSessionInfo(
          id: 'local-1',
          title: 'Desktop shell',
          type: 'local',
        ),
      );
      addTearDown(controller.close);

      await _attachController(controller, connection);
      await controller.detach();

      expect(connection.sentDetach, hasLength(1));
      expect(controller.status, DeviceLinkLinkedSessionStatus.detached);
      expect(controller.isReadOnly, isTrue);
      expect(controller.terminalSession.isConnected, isFalse);
    },
  );

  test('a transient server error does not end the session', () async {
    final connection = _FakeDeviceLinkConnection();
    final controller = DeviceLinkLinkedSessionController(
      connection: connection,
      session: const DeviceLinkSessionInfo(
        id: 'local-1',
        title: 'Desktop shell',
        type: 'local',
      ),
    );
    addTearDown(controller.close);

    await controller.connect();
    connection.controls.add(
      const DeviceLinkAttached(
        sessionId: 'local-1',
        cols: 52,
        rows: 30,
        alt: false,
        bracketedPaste: false,
        scrollbackLines: 0,
      ),
    );
    await pumpEventQueue();

    // One PTY write that failed says nothing about the link. Treating it as
    // fatal has the notifier close the connection and the tab over a single
    // dropped keystroke.
    connection.controls.add(
      const DeviceLinkError(
        code: 'input_failed',
        message: 'Could not write Device Link input to the PTY',
      ),
    );
    await pumpEventQueue();

    expect(controller.status, DeviceLinkLinkedSessionStatus.attached);
    expect(controller.canSendInput, isTrue);
    expect(controller.errorMessage, contains('input_failed'));

    // A verdict about the session itself still ends it.
    connection.controls.add(
      const DeviceLinkError(
        code: 'session_gone',
        message: 'The requested terminal session is no longer available',
      ),
    );
    await pumpEventQueue();

    expect(controller.status, DeviceLinkLinkedSessionStatus.error);
    expect(controller.canSendInput, isFalse);
  });

  test(
    'an oversized snapshot puts the linked session in a fatal error state',
    () async {
      final connection = _FakeDeviceLinkConnection();
      final controller = DeviceLinkLinkedSessionController(
        connection: connection,
        session: const DeviceLinkSessionInfo(
          id: 'local-1',
          title: 'Desktop shell',
          type: 'local',
        ),
      );
      addTearDown(controller.close);

      await controller.connect();
      connection.controls.add(
        const DeviceLinkAttached(
          sessionId: 'local-1',
          cols: 52,
          rows: 30,
          alt: false,
          bracketedPaste: false,
          scrollbackLines: 0,
        ),
      );
      await pumpEventQueue();

      connection.controls.add(
        const DeviceLinkError(
          code: 'snapshot_too_large',
          message: 'The terminal snapshot is too large',
        ),
      );
      await pumpEventQueue();

      expect(controller.status, DeviceLinkLinkedSessionStatus.error);
      expect(controller.isReadOnly, isTrue);
      expect(controller.canSendInput, isFalse);
      expect(controller.terminalSession.isConnecting, isFalse);
      expect(controller.terminalSession.isConnected, isFalse);
      expect(
        controller.terminalSession.errorMessage,
        contains('snapshot_too_large'),
      );
      expect(controller.errorMessage, contains('snapshot_too_large'));
      // The controller reports the fatal attach error without closing the
      // transport, so the server may still accept a later re-attach.
      expect(connection.closed, isFalse);
    },
  );

  test(
    'the phone does not answer queries the desktop already answers',
    () async {
      final connection = _FakeDeviceLinkConnection();
      final controller = DeviceLinkLinkedSessionController(
        connection: connection,
        session: const DeviceLinkSessionInfo(
          id: 'local-1',
          title: 'Desktop shell',
          type: 'local',
        ),
      );
      addTearDown(controller.close);

      await controller.connect();
      connection.controls.add(
        const DeviceLinkAttached(
          sessionId: 'local-1',
          cols: 52,
          rows: 30,
          alt: false,
          bracketedPaste: false,
          scrollbackLines: 0,
        ),
      );
      await pumpEventQueue();

      // A full-screen program (Claude Code, vim, …) probes the terminal on
      // startup. Both terminals parse that byte stream, but only the desktop's
      // is the one the program is talking to: a second reply from the phone
      // would arrive as unsolicited input.
      connection.binaries.add(
        DeviceLinkBinaryFrame(
          type: DeviceLinkBinaryFrameType.ptyOutput,
          payload: Uint8List.fromList('\x1b[c\x1b[6n\x1b[>q'.codeUnits),
        ),
      );
      await pumpEventQueue();

      expect(
        connection.sentBinary.where(
          (frame) => frame.type == DeviceLinkBinaryFrameType.ptyInput,
        ),
        isEmpty,
      );

      // Typing still reaches the desktop.
      await controller.sendText('ls');
      expect(
        connection.sentBinary
            .where((frame) => frame.type == DeviceLinkBinaryFrameType.ptyInput)
            .map((frame) => utf8.decode(frame.payload))
            .join(),
        'ls',
      );
    },
  );

  test('linked session renders live PTY output after the snapshot', () async {
    final connection = _FakeDeviceLinkConnection();
    final controller = DeviceLinkLinkedSessionController(
      connection: connection,
      session: const DeviceLinkSessionInfo(
        id: 'local-1',
        title: 'Desktop shell',
        type: 'local',
      ),
    );
    addTearDown(controller.close);

    await controller.connect();
    connection.controls.add(
      const DeviceLinkAttached(
        sessionId: 'local-1',
        cols: 52,
        rows: 30,
        alt: false,
        bracketedPaste: false,
        scrollbackLines: 0,
      ),
    );
    final source = Terminal(maxLines: 100);
    source.resize(52, 30);
    source.write('snapshot prompt');
    final snapshot = DeviceLinkSnapshot.capture(source);
    connection.binaries.add(
      DeviceLinkBinaryFrame(
        type: DeviceLinkBinaryFrameType.snapshot,
        payload: snapshot.toUtf8Bytes(),
      ),
    );
    await pumpEventQueue();

    connection.binaries.add(
      DeviceLinkBinaryFrame(
        type: DeviceLinkBinaryFrameType.ptyOutput,
        payload: Uint8List.fromList('live output\r\n'.codeUnits),
      ),
    );
    await pumpEventQueue();

    final rendered = controller.terminal.buffer.lines
        .toList()
        .map((line) => line.toString())
        .join('\n');
    expect(rendered, contains('live output'));
  });

  test('the phone keeps its own terminal size across the snapshot', () async {
    final connection = _FakeDeviceLinkConnection();
    final controller = DeviceLinkLinkedSessionController(
      connection: connection,
      session: const DeviceLinkSessionInfo(
        id: 'local-1',
        title: 'Desktop shell',
        type: 'local',
      ),
    );
    addTearDown(controller.close);

    // What the terminal view does on its first layout: it imposes the phone's
    // own grid, well before the attach goes out.
    controller.terminal.resize(40, 62);
    await controller.connect();

    // The attach carries the phone's dimensions, not the placeholder ones.
    expect(connection.sentAttaches.single.cols, 40);
    expect(connection.sentAttaches.single.rows, 62);

    connection.controls.add(
      const DeviceLinkAttached(
        sessionId: 'local-1',
        cols: 40,
        rows: 62,
        alt: false,
        bracketedPaste: false,
        scrollbackLines: 0,
      ),
    );
    await pumpEventQueue();

    // A snapshot taken at the desktop's own size must not leave the phone's
    // grid smaller than the space it is painted in — a half-empty screen in
    // portrait, a quarter-empty one in landscape.
    final source = Terminal(maxLines: 100);
    source.resize(120, 30);
    source.write('snapshot prompt');
    connection.binaries.add(
      DeviceLinkBinaryFrame(
        type: DeviceLinkBinaryFrameType.snapshot,
        payload: DeviceLinkSnapshot.capture(source).toUtf8Bytes(),
      ),
    );
    await pumpEventQueue();

    expect(controller.terminal.viewWidth, 40);
    expect(controller.terminal.viewHeight, 62);
    expect(connection.sentResizes.last.cols, 40);
    expect(connection.sentResizes.last.rows, 62);
  });

  testWidgets('compose sheet emits one bracketed multi-line submission', (
    tester,
  ) async {
    String? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeviceLinkComposeSheet(
            onSubmit: (value) {
              submitted = value;
            },
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('device_link_compose_field')),
      'first\nsecond',
    );
    await tester.tap(find.byKey(const Key('device_link_compose_submit')));
    await tester.pump();

    expect(submitted, '\x1b[200~first\nsecond\x1b[201~');
  });

  testWidgets('compose sheet clears its input after a successful send', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Navigator(
            onGenerateRoute: (_) => _NonPoppingPageRoute(
              builder: (_) => DeviceLinkComposeSheet(onSubmit: (_) async {}),
            ),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('device_link_compose_field')),
      'pwd',
    );
    await tester.tap(find.byKey(const Key('device_link_compose_submit')));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const Key('device_link_compose_field')),
    );
    expect(field.controller?.text, isEmpty);
  });

  testWidgets('session picker returns the selected hello_ack session', (
    tester,
  ) async {
    const sessions = [
      DeviceLinkSessionInfo(
        id: 'local-1',
        title: 'Desktop shell',
        type: 'local',
      ),
      DeviceLinkSessionInfo(id: 'ssh-1', title: 'Build host', type: 'ssh'),
    ];
    DeviceLinkSessionInfo? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                selected = await DeviceLinkSessionPickerSheet.show(
                  context,
                  sessions: sessions,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device_link_session_ssh-1')));
    await tester.pumpAndSettle();

    expect(selected?.id, 'ssh-1');
  });

  testWidgets('desktop pairing QR shows payload and hides expired code', (
    tester,
  ) async {
    debugPlatformCapabilitiesOverride = TargetPlatform.macOS;
    final payload = DeviceLinkQrPayload(
      version: 1,
      host: 'desktop-host',
      addresses: const ['192.168.1.20'],
      mdns: 'desktop-host._shellvibe._tcp.local',
      port: 47823,
      spki: 'pinned-spki',
      token: 'one-time-token',
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 1)),
    );

    await tester.pumpWidget(
      MaterialApp(home: DeviceLinkPairingQrScreen(payload: payload)),
    );
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.byKey(const Key('device_link_qr_host')), findsOneWidget);
    expect(find.text('desktop-host'), findsOneWidget);

    final expired = DeviceLinkQrPayload(
      version: payload.version,
      host: payload.host,
      addresses: payload.addresses,
      mdns: payload.mdns,
      port: payload.port,
      spki: payload.spki,
      token: payload.token,
      expiresAt: DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
    );
    await tester.pumpWidget(
      MaterialApp(home: DeviceLinkPairingQrScreen(payload: expired)),
    );
    expect(find.text('QR code expired'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets('desktop pairing QR closes after pairing completes', (
    tester,
  ) async {
    debugPlatformCapabilitiesOverride = TargetPlatform.macOS;
    final pairingEvents = StreamController<void>.broadcast();
    addTearDown(pairingEvents.close);
    final payload = DeviceLinkQrPayload(
      version: 1,
      host: 'desktop-host',
      addresses: const ['192.168.1.20'],
      mdns: 'desktop-host._shellvibe._tcp.local',
      port: 47823,
      spki: 'pinned-spki',
      token: 'one-time-token',
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 1)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DeviceLinkPairingQrScreen(
                    payload: payload,
                    pairingEvents: pairingEvents.stream,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('device_link_qr')), findsOneWidget);

    pairingEvents.add(null);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('device_link_qr')), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('scan screen explains that desktop scanning is unsupported', (
    tester,
  ) async {
    debugPlatformCapabilitiesOverride = TargetPlatform.macOS;
    await tester.pumpWidget(
      MaterialApp(home: DeviceLinkScanPairScreen(onPayload: (_) async {})),
    );

    expect(
      find.textContaining('QR scanning is available on iOS and Android'),
      findsOneWidget,
    );
  });

  testWidgets('opening the phone keyboard does not resize the desktop PTY', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final connection = _FakeDeviceLinkConnection();
    addTearDown(connection.close);

    final controller = DeviceLinkLinkedSessionController(
      connection: connection,
      session: const DeviceLinkSessionInfo(
        id: 'local-1',
        title: 'Desktop shell',
        type: 'local',
      ),
    );
    addTearDown(controller.close);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: DeviceLinkLinkedSessionScreen(
            controller: controller,
            showExtraKeys: true,
          ),
        ),
      ),
    );
    await tester.pump();
    connection.controls.add(
      const DeviceLinkAttached(
        sessionId: 'local-1',
        cols: 52,
        rows: 30,
        alt: false,
        bracketedPaste: false,
        scrollbackLines: 0,
      ),
    );
    await tester.pumpAndSettle();

    final rowsBeforeKeyboard = controller.terminal.viewHeight;
    final columnsBeforeKeyboard = controller.terminal.viewWidth;
    final terminalHeightBeforeKeyboard = tester
        .getRect(find.byType(TerminalView))
        .height;
    connection.sentResizes.clear();

    // The soft keyboard claims the bottom of the screen. The visible height
    // shrinks, but the PTY belongs to the desktop until the phone explicitly
    // resizes, so no resize may leave the device.
    tester.view.viewInsets = const FakeViewPadding(bottom: 1000);
    await tester.pumpAndSettle();

    expect(connection.sentResizes, isEmpty);
    expect(controller.terminal.viewHeight, rowsBeforeKeyboard);
    expect(controller.terminal.viewWidth, columnsBeforeKeyboard);
    // The extra-key bar has to ride above the keyboard; otherwise keeping the
    // layout stable would simply bury it.
    expect(find.byType(MobileExtraKeysBar), findsOneWidget);
    final barRect = tester.getRect(find.byType(MobileExtraKeysBar));
    final keyboardTop =
        tester.view.physicalSize.height / tester.view.devicePixelRatio -
        1000 / tester.view.devicePixelRatio;
    expect(barRect.bottom, lessThanOrEqualTo(keyboardTop + 0.5));

    // Keeping the row count stable must not bury the prompt: the terminal
    // holds its height (so the PTY does not move) but is clipped from the top,
    // which leaves its last row — the one with the cursor on it — above the
    // bar rather than behind the keyboard.
    final terminalRect = tester.getRect(find.byType(TerminalView));
    expect(terminalRect.height, terminalHeightBeforeKeyboard);
    expect(terminalRect.bottom, lessThanOrEqualTo(barRect.top + 0.5));
  });

  testWidgets('an extra-key press sends the word the keyboard still holds', (
    tester,
  ) async {
    final connection = _FakeDeviceLinkConnection();
    addTearDown(connection.close);

    final controller = DeviceLinkLinkedSessionController(
      connection: connection,
      session: const DeviceLinkSessionInfo(
        id: 'local-1',
        title: 'Desktop shell',
        type: 'local',
      ),
    );
    addTearDown(controller.close);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: DeviceLinkLinkedSessionScreen(
            controller: controller,
            showExtraKeys: true,
          ),
        ),
      ),
    );
    await tester.pump();
    connection.controls.add(
      const DeviceLinkAttached(
        sessionId: 'local-1',
        cols: 80,
        rows: 24,
        alt: false,
        bracketedPaste: false,
        scrollbackLines: 0,
      ),
    );
    await tester.pumpAndSettle();

    String sentInput() => connection.sentBinary
        .where((frame) => frame.type == DeviceLinkBinaryFrameType.ptyInput)
        .map((frame) => utf8.decode(frame.payload))
        .join();

    await tester.tap(find.byType(TerminalView));
    await tester.pump();

    // The user has typed a path fragment. It is still an open composition, so
    // the desktop has not received a byte of it.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '  www',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 2, end: 5),
      ),
    );
    await tester.pump();
    expect(sentInput(), isEmpty);

    // Tab from the extra-key bar has to complete `www`, which means the word
    // must reach the desktop first and in that order.
    await tester.tap(find.byKey(const Key('key_tab')));
    await tester.pump();

    expect(sentInput(), 'www\t');
  });

  testWidgets('linked screen becomes read-only when attach is rejected', (
    tester,
  ) async {
    final connection = _FakeDeviceLinkConnection();
    addTearDown(connection.close);

    final controller = DeviceLinkLinkedSessionController(
      connection: connection,
      session: const DeviceLinkSessionInfo(
        id: 'missing-session',
        title: 'Missing',
        type: 'local',
      ),
    );
    addTearDown(controller.close);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: DeviceLinkLinkedSessionScreen(
            controller: controller,
            showExtraKeys: false,
          ),
        ),
      ),
    );
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).resizeToAvoidBottomInset,
      isFalse,
    );
    await tester.pump();
    connection.controls.add(
      const DeviceLinkAttached(
        sessionId: 'missing-session',
        cols: 52,
        rows: 30,
        alt: false,
        bracketedPaste: false,
        scrollbackLines: 0,
      ),
    );
    await tester.pump();
    expect(controller.status, DeviceLinkLinkedSessionStatus.attached);

    connection.controls.add(const DeviceLinkReclaimed(cols: 80, rows: 24));
    await tester.pump();

    expect(controller.status, DeviceLinkLinkedSessionStatus.reclaimed);
    expect(controller.isReadOnly, isTrue);
    expect(find.byKey(const Key('device_link_status')), findsOneWidget);
  });
}

Future<void> _attachController(
  DeviceLinkLinkedSessionController controller,
  _FakeDeviceLinkConnection connection,
) async {
  await controller.connect();
  connection.controls.add(
    const DeviceLinkAttached(
      sessionId: 'local-1',
      cols: 52,
      rows: 30,
      alt: false,
      bracketedPaste: false,
      scrollbackLines: 0,
    ),
  );
  await pumpEventQueue();
}

final class _NonPoppingPageRoute extends PageRouteBuilder<Object?> {
  _NonPoppingPageRoute({required WidgetBuilder builder})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            child,
      );

  @override
  bool didPop(Object? result) {
    super.didPop(result);
    return false;
  }
}

final class _FakeDeviceLinkConnection implements DeviceLinkConnection {
  final Duration sendBinaryDelay;
  final StreamController<DeviceLinkControlMessage> controls =
      StreamController<DeviceLinkControlMessage>.broadcast();
  final StreamController<DeviceLinkBinaryFrame> binaries =
      StreamController<DeviceLinkBinaryFrame>.broadcast();
  final List<DeviceLinkBinaryFrame> sentBinary = [];
  final List<DeviceLinkResize> sentResizes = [];
  final List<DeviceLinkAttach> sentAttaches = [];
  final List<DeviceLinkDetach> sentDetach = [];
  final bool readOnly;
  bool closed = false;

  _FakeDeviceLinkConnection({
    this.sendBinaryDelay = Duration.zero,
    this.readOnly = false,
  });

  @override
  Stream<DeviceLinkControlMessage> get controlMessages => controls.stream;

  @override
  Stream<DeviceLinkBinaryFrame> get binaryFrames => binaries.stream;

  @override
  bool get isClosed => closed;

  @override
  bool get isReadOnly => readOnly;

  @override
  Future<void> sendAttach(DeviceLinkAttach message) async {
    sentAttaches.add(message);
  }

  @override
  Future<void> sendResize(DeviceLinkResize message) async {
    sentResizes.add(message);
  }

  @override
  Future<void> sendDetach() async {
    sentDetach.add(const DeviceLinkDetach());
  }

  @override
  Future<void> sendBinary(DeviceLinkBinaryFrame frame) async {
    sentBinary.add(frame);
    if (sendBinaryDelay > Duration.zero) {
      await Future<void>.delayed(sendBinaryDelay);
    }
  }

  Future<void> disconnect() async {
    if (closed) return;
    closed = true;
    await controls.close();
    await binaries.close();
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await controls.close();
    await binaries.close();
  }
}
