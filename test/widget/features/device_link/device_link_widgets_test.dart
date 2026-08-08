import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:terly2/core/network/device_link/device_link_client.dart';
import 'package:terly2/core/network/device_link/device_link_protocol.dart';
import 'package:terly2/core/network/device_link/device_link_server.dart';
import 'package:terly2/core/utils/platform_capabilities.dart';
import 'package:terly2/features/device_link/presentation/controllers/linked_session_controller.dart';
import 'package:terly2/features/device_link/presentation/screens/linked_session_screen.dart';
import 'package:terly2/features/device_link/presentation/screens/pairing_qr_screen.dart';
import 'package:terly2/features/device_link/presentation/screens/scan_pair_screen.dart';
import 'package:terly2/features/device_link/presentation/widgets/compose_sheet.dart';
import 'package:terly2/features/device_link/presentation/widgets/session_picker_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => debugPlatformCapabilitiesOverride = null);

  test('bracketed paste wraps a multi-line submission once', () {
    expect(
      deviceLinkBracketedPaste('echo one\necho two'),
      '\x1b[200~echo one\necho two\x1b[201~',
    );
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
      mdns: 'desktop-host._terly._tcp.local',
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

final class _FakeDeviceLinkConnection implements DeviceLinkConnection {
  final StreamController<DeviceLinkControlMessage> controls =
      StreamController<DeviceLinkControlMessage>.broadcast();
  final StreamController<DeviceLinkBinaryFrame> binaries =
      StreamController<DeviceLinkBinaryFrame>.broadcast();
  final List<DeviceLinkBinaryFrame> sentBinary = [];
  bool closed = false;

  @override
  Stream<DeviceLinkControlMessage> get controlMessages => controls.stream;

  @override
  Stream<DeviceLinkBinaryFrame> get binaryFrames => binaries.stream;

  @override
  bool get isClosed => closed;

  @override
  bool get isReadOnly => false;

  @override
  Future<void> sendAttach(DeviceLinkAttach message) async {}

  @override
  Future<void> sendResize(DeviceLinkResize message) async {}

  @override
  Future<void> sendDetach() async {}

  @override
  Future<void> sendBinary(DeviceLinkBinaryFrame frame) async {
    sentBinary.add(frame);
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await controls.close();
    await binaries.close();
  }
}
