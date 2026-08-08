import 'dart:async';
import 'dart:io';

import 'package:nsd/nsd.dart' as nsd;

import 'device_link_server.dart';

/// An mDNS service discovered on the local network.
final class DeviceLinkDiscoveredService {
  final String? name;
  final String? host;
  final int port;
  final List<String> addresses;

  const DeviceLinkDiscoveredService({
    required this.name,
    required this.host,
    required this.port,
    required this.addresses,
  });

  factory DeviceLinkDiscoveredService.fromNsd(nsd.Service service) {
    return DeviceLinkDiscoveredService(
      name: service.name,
      host: service.host,
      port: service.port ?? 0,
      addresses: [...?service.addresses?.map((address) => address.address)],
    );
  }
}

/// Thin nsd wrapper used by the Device Link presentation layer.
final class DeviceDiscovery {
  /// nsd 5.0.1 has no Linux implementation. Callers must use QR candidates
  /// or another explicit address on Linux instead of receiving a fake result.
  bool get supportsMdns =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows;

  Future<nsd.Discovery> startDiscovery() async {
    _ensureSupported();
    return nsd.startDiscovery(
      deviceLinkMdnsServiceType,
      ipLookupType: nsd.IpLookupType.any,
    );
  }

  Future<void> stopDiscovery(nsd.Discovery discovery) {
    return nsd.stopDiscovery(discovery);
  }

  Future<nsd.Registration> register({
    required String name,
    required int port,
  }) async {
    _ensureSupported();
    if (name.trim().isEmpty || port <= 0 || port > 65535) {
      throw const DeviceLinkDiscoveryException(
        'mDNS registration has invalid name or port',
      );
    }
    return nsd.register(
      nsd.Service(name: name, type: deviceLinkMdnsServiceType, port: port),
    );
  }

  Future<void> unregister(nsd.Registration registration) {
    return nsd.unregister(registration);
  }

  /// Collects services for a bounded discovery window and always releases it.
  Future<List<DeviceLinkDiscoveredService>> discover({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final discovery = await startDiscovery();
    try {
      if (timeout > Duration.zero) {
        await Future<void>.delayed(timeout);
      }
      return discovery.services
          .map(DeviceLinkDiscoveredService.fromNsd)
          .toList(growable: false);
    } finally {
      await stopDiscovery(discovery);
    }
  }

  void _ensureSupported() {
    if (!supportsMdns) {
      throw const DeviceLinkDiscoveryException(
        'mDNS is not supported on this platform; use QR candidate addresses',
      );
    }
  }
}

class DeviceLinkDiscoveryException implements Exception {
  final String message;

  const DeviceLinkDiscoveryException(this.message);

  @override
  String toString() => 'DeviceLinkDiscoveryException: $message';
}
