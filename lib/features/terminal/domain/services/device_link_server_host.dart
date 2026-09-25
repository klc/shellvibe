import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;

import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/device_link/device_discovery.dart';
import '../../../../core/network/device_link/device_link_identity.dart';
import '../../../../core/network/device_link/device_link_server.dart';
import '../../../../core/network/device_link/device_link_session_transport.dart';
import '../../../../shared/storage/secure_storage_service.dart';
import '../../../device_link/data/repositories/device_link_pairing_repository.dart';

/// Hosts the desktop-side Device Link listener on behalf of
/// `TerminalTabsNotifier`: starts and stops the [DeviceLinkServer], keeps its
/// mDNS advertisement in step with it, and persists the TLS identity it
/// presents to pairing phones.
///
/// Knows nothing about Riverpod or the tabs whose sessions it exposes: the
/// notifier hands both in through the constructor as plain callbacks, so a
/// vault lock, a paired-device lookup, or the current live sessions all cross
/// a narrow, explicit boundary instead of a shared `ref`.
class DeviceLinkServerHost {
  DeviceLinkServerHost({
    required this.pairingRepository,
    required this.secureStorage,
    required this.isVaultAvailable,
    required this.sessionTransportsProvider,
  });

  final DeviceLinkPairingRepository Function() pairingRepository;
  final SecureStorageService Function() secureStorage;
  final bool Function() isVaultAvailable;
  final List<DeviceLinkSessionTransport> Function() sessionTransportsProvider;

  DeviceLinkServer? _deviceLinkServer;
  nsd.Registration? _deviceLinkMdnsRegistration;
  Future<DeviceLinkServer>? _deviceLinkServerStartup;
  Future<void>? _deviceLinkServerStop;
  int _lifecycleGeneration = 0;
  bool _disposed = false;

  final StreamController<void> _pairingEvents =
      StreamController<void>.broadcast();

  Stream<void> get pairingEvents => _pairingEvents.stream;

  bool get isRunning => _deviceLinkServer?.isRunning ?? false;

  /// Starts (or reuses) the listener and creates the short-lived QR payload
  /// used by the first pairing flow. The server stays alive after the QR
  /// screen closes so the newly paired connection can keep using the same
  /// listener.
  Future<DeviceLinkQrPayload> createPairingPayload() async {
    final server = await _ensureServer();
    final registeredName = _deviceLinkMdnsRegistration?.service.name;
    final mdnsName = registeredName == null
        ? null
        : '$registeredName.$deviceLinkMdnsServiceType.local';
    return server.createPairingPayload(mdnsName: mdnsName);
  }

  /// Ensures the listener exists when a previous QR pairing is already
  /// persisted. A clean install must not open a LAN listener merely because
  /// the app was launched.
  Future<void> ensureServerForPairedDevices() async {
    if (!isVaultAvailable()) return;
    final pairedDevices = await pairingRepository().getAll();
    if (pairedDevices.isEmpty) return;
    if (!isVaultAvailable()) return;
    await _ensureServer();
  }

  /// Stops the listener, all authenticated connections, and its mDNS
  /// advertisement. The lifecycle generation also cancels a startup that is
  /// still loading the identity or registering mDNS, preventing an orphan
  /// server/registration from being published after the vault is locked.
  Future<void> stop() {
    final existingStop = _deviceLinkServerStop;
    if (existingStop != null) return existingStop;

    ++_lifecycleGeneration;
    final startup = _deviceLinkServerStartup;
    final server = _deviceLinkServer;
    _deviceLinkServer = null;
    final registration = _deviceLinkMdnsRegistration;
    _deviceLinkMdnsRegistration = null;

    final stopFuture = () async {
      // Let an in-flight start observe the new generation before closing any
      // server instance it may have created.
      try {
        await startup;
      } on Object catch (_) {}

      await server?.close();
      if (registration != null) {
        await _unregisterMdnsRegistration(registration);
      }
    }();

    late final Future<void> trackedStop;
    trackedStop = stopFuture.whenComplete(() {
      if (identical(_deviceLinkServerStop, trackedStop)) {
        _deviceLinkServerStop = null;
      }
    });
    _deviceLinkServerStop = trackedStop;
    return trackedStop;
  }

  Future<DeviceLinkServer> _ensureServer() async {
    if (!isVaultAvailable()) {
      throw StateError('Device Link is unavailable while the vault is locked');
    }

    final stop = _deviceLinkServerStop;
    if (stop != null) await stop;
    if (_disposed || !isVaultAvailable()) {
      throw StateError('Device Link startup cancelled');
    }

    final existing = _deviceLinkServer;
    if (existing != null && existing.isRunning) return Future.value(existing);

    final inFlight = _deviceLinkServerStartup;
    if (inFlight != null) return inFlight;

    final startup = _startServer(_lifecycleGeneration);
    late final Future<DeviceLinkServer> trackedStartup;
    trackedStartup = startup.whenComplete(() {
      if (identical(_deviceLinkServerStartup, trackedStartup)) {
        _deviceLinkServerStartup = null;
      }
    });
    _deviceLinkServerStartup = trackedStartup;
    return trackedStartup;
  }

  Future<DeviceLinkServer> _startServer(int generation) async {
    var server = _deviceLinkServer;
    if (server == null) {
      final repository = pairingRepository();
      final identity = await _loadIdentity();
      if (_disposed || generation != _lifecycleGeneration) {
        throw StateError('Device Link notifier disposed during startup');
      }
      server = DeviceLinkServer(
        identity: identity,
        hostName: Platform.localHostname.isEmpty
            ? 'shellvibe-desktop'
            : Platform.localHostname,
        appVersion: AppConstants.appVersion,
        sessionTransportsProvider: sessionTransportsProvider,
        pairedDeviceAuthenticator: repository.authenticate,
        pairedDevicePersister: (record) => repository.savePairedDevice(
          id: record.id,
          name: record.name,
          platform: record.platform,
          secret: record.secret,
          publicKey: record.publicKey,
          pairedAt: record.pairedAt,
        ),
        // Only reached for an id the phone authenticated as its own, so this
        // deletes the row the same phone left behind under an older identity.
        pairedDeviceRemover: repository.remove,
        onPairingCompleted: () {
          if (!_pairingEvents.isClosed) {
            _pairingEvents.add(null);
          }
        },
      );
      await server.start();
      if (_disposed || generation != _lifecycleGeneration) {
        await server.close();
        throw StateError('Device Link notifier disposed during startup');
      }
      _deviceLinkServer = server;
    } else if (!server.isRunning) {
      await server.start();
      if (_disposed || generation != _lifecycleGeneration) {
        await server.close();
        throw StateError('Device Link startup cancelled');
      }
    }

    await _ensureMdnsRegistration(server, generation);
    if (_disposed || generation != _lifecycleGeneration) {
      if (identical(_deviceLinkServer, server)) _deviceLinkServer = null;
      await server.close();
      throw StateError('Device Link startup cancelled');
    }
    return server;
  }

  Future<void> _ensureMdnsRegistration(
    DeviceLinkServer server,
    int generation,
  ) async {
    if (_deviceLinkMdnsRegistration != null) return;
    final discovery = DeviceDiscovery();
    if (!discovery.supportsMdns) return;
    try {
      final registration = await discovery.register(
        name: server.hostName,
        port: server.port,
      );
      if (_disposed || generation != _lifecycleGeneration) {
        await _unregisterMdnsRegistration(registration, discovery: discovery);
        return;
      }
      _deviceLinkMdnsRegistration = registration;
    } on Object catch (error) {
      // Direct QR addresses remain valid when mDNS is unavailable (Linux,
      // missing permission, or an isolated Wi-Fi network).
      debugPrint('[Device Link] mDNS registration unavailable: $error');
    }
  }

  Future<void> _unregisterMdnsRegistration(
    nsd.Registration registration, {
    DeviceDiscovery? discovery,
  }) async {
    try {
      await (discovery ?? DeviceDiscovery()).unregister(registration);
    } on Object catch (error) {
      debugPrint('[Device Link] mDNS unregistration unavailable: $error');
    }
  }

  Future<DeviceLinkIdentity> _loadIdentity() async {
    final storage = secureStorage();
    final stored = await storage.getToken(
      SecureStorageKeys.deviceLinkServerIdentity,
    );
    if (stored != null) {
      try {
        final object = jsonDecode(stored);
        if (object is Map<String, dynamic> &&
            object['certificatePem'] is String &&
            object['privateKeyPem'] is String) {
          return DeviceLinkIdentity.fromPem(
            certificatePem: object['certificatePem'] as String,
            privateKeyPem: object['privateKeyPem'] as String,
          );
        }
      } catch (_) {
        await storage.deleteToken(SecureStorageKeys.deviceLinkServerIdentity);
      }
    }

    final identity = DeviceLinkIdentity.generate();
    await storage.saveToken(
      SecureStorageKeys.deviceLinkServerIdentity,
      jsonEncode({
        'certificatePem': identity.certificatePem,
        'privateKeyPem': identity.privateKeyPem,
      }),
    );
    return identity;
  }

  /// Tears everything down for `ref.onDispose`, which cannot await: flips the
  /// disposed flag and bumps the generation synchronously, then kicks off
  /// (without awaiting) the server close, the mDNS unregistration, and
  /// closing the pairing-events stream.
  void dispose() {
    _disposed = true;
    ++_lifecycleGeneration;
    final server = _deviceLinkServer;
    _deviceLinkServer = null;
    _deviceLinkServerStartup = null;
    if (server != null) unawaited(server.close());
    final registration = _deviceLinkMdnsRegistration;
    _deviceLinkMdnsRegistration = null;
    if (registration != null) {
      unawaited(_unregisterMdnsRegistration(registration));
    }
    unawaited(_pairingEvents.close());
  }
}
