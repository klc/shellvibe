import 'package:shellvibe/core/network/device_link/device_link_server.dart';

/// Stands in for the desktop's paired-device table.
///
/// Secrets are kept in the clear: the real repository hashes them, and that
/// is its own test's business.
final class InMemoryPairedDevices {
  final Map<String, String> secrets = {};
  final List<String> removed = [];

  bool authenticate(String deviceId, String secret) =>
      secrets[deviceId] == secret;

  void save(DeviceLinkPairedDeviceRecord record) =>
      secrets[record.id] = record.secret;

  void remove(String deviceId) {
    secrets.remove(deviceId);
    removed.add(deviceId);
  }
}
