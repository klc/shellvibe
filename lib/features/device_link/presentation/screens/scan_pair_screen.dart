import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/network/device_link/device_link_client.dart';
import '../../../../core/network/device_link/device_link_protocol.dart';
import '../../../../core/network/device_link/device_link_server.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../data/repositories/device_link_pairing_storage.dart';
import '../../domain/models/device_link_pairing_profile.dart';
import '../notifiers/device_link_notifier.dart';
import '../../../terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../controllers/linked_session_controller.dart';
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
    final deviceId = const Uuid().v4();
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

      await connection.sendPair(
        DeviceLinkPair(
          token: payload.token,
          deviceName: '${defaultTargetPlatform.name} device',
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
        id: deviceId,
        name: '${defaultTargetPlatform.name} device',
        platform: defaultTargetPlatform.name.toLowerCase(),
        secret: pairedMessage.secret,
        payload: payload,
        sessionId: session.id,
      );
      await DeviceLinkPairingStorage(
        ref.read(secureStorageServiceProvider),
      ).save(profile);
      if (!mounted) return;

      final controller = DeviceLinkLinkedSessionController(
        connection: connection,
        session: session,
        terminalTabId: 'device-link-$deviceId',
      );
      var registered = false;
      ref
          .read(terminalTabsProvider.notifier)
          .registerDeviceLinkSession(controller.terminalSession);
      ref
          .read(deviceLinkProvider.notifier)
          .registerActiveController(deviceId, controller);
      registered = true;
      _handedOff = true;
      try {
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
              .unregisterActiveController(deviceId, controller);
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
            'This is not a valid Terly Device Link QR code.\n$error';
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
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 3),
                        borderRadius: BorderRadius.circular(20),
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
            FilledButton.icon(
              key: const Key('device_link_scan_retry'),
              onPressed: _retry,
              icon: const Icon(Icons.refresh),
              label: const Text('Scan again'),
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
