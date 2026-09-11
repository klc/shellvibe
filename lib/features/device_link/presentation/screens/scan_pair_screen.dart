import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/network/device_link/device_link_client.dart';
import '../../../../core/network/device_link/device_link_protocol.dart';
import '../../../../core/network/device_link/device_link_server.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../../terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../data/repositories/device_link_pairing_storage.dart';
import '../../domain/models/device_link_pairing_profile.dart';
import '../controllers/linked_session_controller.dart';
import '../notifiers/device_link_notifier.dart';
import '../widgets/session_picker_sheet.dart';
import 'linked_session_screen.dart';

/// Mobile QR scanner for the first Device Link pairing.
final class DeviceLinkScanPairScreen extends StatefulWidget {
  final FutureOr<void> Function(DeviceLinkQrPayload payload) onPayload;

  const DeviceLinkScanPairScreen({super.key, required this.onPayload});

  @override
  State<DeviceLinkScanPairScreen> createState() =>
      _DeviceLinkScanPairScreenState();
}

/// Coordinates scan → hello → one-time pair → session selection.
///
/// Pairing credentials are written to secure storage after the one-time pairing
/// exchange; the scanner itself never owns a durable credential.
final class DeviceLinkPairingFlowScreen extends ConsumerStatefulWidget {
  const DeviceLinkPairingFlowScreen({super.key});

  @override
  ConsumerState<DeviceLinkPairingFlowScreen> createState() =>
      _DeviceLinkPairingFlowScreenState();
}

class _DeviceLinkPairingFlowScreenState
    extends ConsumerState<DeviceLinkPairingFlowScreen> {
  DeviceLinkClientConnection? _connection;
  bool _handedOff = false;

  @override
  void dispose() {
    if (!_handedOff) unawaited(_connection?.close());
    super.dispose();
  }

  Future<void> _pair(DeviceLinkQrPayload payload) async {
    final pairingStorage = DeviceLinkPairingStorage(
      ref.read(secureStorageServiceProvider),
    );
    // Stable across pairings: a new id per scan makes this phone a stranger to
    // the desktop every time, one that cannot be handed back the session its
    // own previous identity is still holding.
    final deviceId = await pairingStorage.deviceId();
    // A previous connection to this desktop may still be live —
    // auto-reconnect keeps one running in the background. Close it before
    // pairing, or the desktop is being asked for a session this very phone
    // already owns.
    await ref
        .read(deviceLinkProvider.notifier)
        .releaseActiveController(payload.spki);
    final connection = await DeviceLinkClient().connectToQrPayload(payload);
    _connection = connection;
    try {
      await connection.sendHello(
        DeviceLinkHello(
          deviceId: deviceId,
          deviceName: '${defaultTargetPlatform.name} device',
        ),
      );
      final hello = await connection.nextControl();
      if (hello is! DeviceLinkHelloAck) {
        throw StateError('Desktop did not accept the Device Link hello');
      }

      // Read before the pairing prunes them: these profiles carry the ids this
      // phone used with this desktop before, and the secrets that prove each
      // one was ours. Without them the desktop keeps an authorization row per
      // identity this phone ever had, and its paired list grows one row per
      // scan that predates the client id becoming durable.
      final supersedes = await pairingStorage.supersededDeviceClaims(
        spki: payload.spki,
        deviceId: deviceId,
      );

      await connection.sendPair(
        DeviceLinkPair(
          token: payload.token,
          deviceName: '${defaultTargetPlatform.name} device',
          supersedes: supersedes,
          // mTLS is a later hardening step. The v1 bearer secret is the
          // authentication material persisted by the desktop and phone.
          devicePublicKey: 'ephemeral-$deviceId',
          platform: defaultTargetPlatform.name.toLowerCase(),
        ),
      );
      final pairedMessage = await connection.nextControl();
      if (pairedMessage is! DeviceLinkPaired) {
        throw StateError('Desktop rejected the pairing request');
      }

      final authenticatedHello = await connection.nextControl();
      if (authenticatedHello is DeviceLinkError) {
        throw DeviceLinkTransportException(
          authenticatedHello.code,
          authenticatedHello.message,
        );
      }
      if (authenticatedHello is! DeviceLinkHelloAck) {
        throw StateError('Desktop did not return sessions after pairing');
      }

      if (!mounted) return;
      final session = await DeviceLinkSessionPickerSheet.show(
        context,
        sessions: authenticatedHello.sessions,
      );
      if (session == null || !mounted) return;

      final profile = DeviceLinkPairingProfile.fromQr(
        deviceId: deviceId,
        // The saved pairing describes the *desktop*, so it carries the
        // desktop's own name and platform. Storing this phone's here is what
        // made the "Saved desktops" list show the phone back to the user.
        name: pairedMessage.hostName.isNotEmpty
            ? pairedMessage.hostName
            : payload.host,
        platform: 'desktop',
        secret: pairedMessage.secret,
        payload: payload,
        sessionId: session.id,
      );
      final controller = DeviceLinkLinkedSessionController(
        connection: connection,
        session: session,
        terminalTabId: 'device-link-${profile.id}',
      );
      // Terminal ownership outlives this route. Capture the notifier while
      // the widget is mounted so a later tab close never reads a disposed ref.
      final terminalTabsNotifier = ref.read(terminalTabsProvider.notifier);
      final deviceLinkNotifier = ref.read(deviceLinkProvider.notifier);
      var registered = false;
      terminalTabsNotifier.registerDeviceLinkSession(
        controller.terminalSession,
        onClose: () => deviceLinkNotifier.closeRegisteredController(
          profile.id,
          controller,
        ),
      );
      deviceLinkNotifier.registerActiveController(profile.id, controller);
      registered = true;
      _handedOff = true;

      try {
        // Saved only once this connection is the registered one for the
        // profile. Auto-reconnect skips a profile that already has a
        // controller, so a connectivity callback landing between the two would
        // otherwise open a second connection to the session this one is about
        // to attach to — and one of them would be told the session is in use.
        await pairingStorage.save(profile);
        await pairingStorage.pruneSupersededProfiles(
          keepId: profile.id,
          spki: profile.spki,
        );
        if (!mounted) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (context) => DeviceLinkLinkedSessionScreen(
              controller: controller,
              onClosed: () => Navigator.of(context).pop(),
            ),
          ),
        );
      } finally {
        if (registered && mounted) {
          await ref
              .read(terminalTabsProvider.notifier)
              .closeTab(controller.terminalSession.id);
        }
        await controller.close();
        if (mounted) {
          ref
              .read(deviceLinkProvider.notifier)
              .unregisterActiveController(profile.id, controller);
        }
      }
    } finally {
      if (!_handedOff) {
        await connection.close();
        _connection = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DeviceLinkScanPairScreen(onPayload: _pair);
  }
}

class _DeviceLinkScanPairScreenState extends State<DeviceLinkScanPairScreen> {
  late final MobileScannerController _scannerController;
  String? _errorMessage;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
  }

  @override
  void dispose() {
    unawaited(_scannerController.dispose());
    super.dispose();
  }

  Future<void> _handleCapture(BarcodeCapture capture) async {
    if (_processing) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      await _handleRawPayload(raw);
      if (_processing || _errorMessage != null) return;
    }
  }

  Future<void> _handleRawPayload(String raw) async {
    setState(() {
      _processing = true;
      _errorMessage = null;
    });
    await _scannerController.stop();
    try {
      final value = jsonDecode(raw);
      final payload = DeviceLinkQrPayload.fromJson(value);
      await widget.onPayload(payload);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _errorMessage =
            'This is not a valid ShellVibe Device Link QR code.\n$error';
      });
    }
  }

  Future<void> _retry() async {
    setState(() {
      _processing = false;
      _errorMessage = null;
    });
    await _scannerController.start();
  }

  @override
  Widget build(BuildContext context) {
    if (!isMobilePlatform) {
      return Scaffold(
        appBar: AppBar(title: const Text('Device Link')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'QR scanning is available on iOS and Android.\n'
              'On desktop, display the pairing QR code instead.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final error = _errorMessage;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Device Link QR')),
      body: error != null
          ? _buildErrorState(context, error)
          : Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: _handleCapture,
                  errorBuilder: (context, error) =>
                      _buildCameraError(context, error),
                ),
                IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 260,
                      height: 260,
                      // Deliberately outside the token system: this sits on the
                      // live camera feed, not on a themed surface, so it has to
                      // stay readable against whatever the lens is pointed at.
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 3),
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),
                ),
                if (_processing)
                  const Center(
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  ),
                const Positioned(
                  left: 24,
                  right: 24,
                  bottom: 32,
                  child: Text(
                    'Point the camera at the QR code on your desktop.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildErrorState(BuildContext context, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_2, size: 42),
            const SizedBox(height: 12),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ShellVibeButton(
              key: const Key('device_link_scan_retry'),
              label: 'Scan again',
              icon: LucideIcons.refreshCw,
              onPressed: _retry,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraError(BuildContext context, MobileScannerException error) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.no_photography_outlined,
                size: 42,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              const Text(
                'Camera access is required to scan a Device Link QR code.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                error.errorCode.name,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
