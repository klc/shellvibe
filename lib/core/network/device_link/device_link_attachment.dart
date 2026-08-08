/// Runtime ownership of a terminal session by one Device Link client.
///
/// This is deliberately not persisted. It records the dimensions that must be
/// restored when the phone detaches, reclaims the session, or disappears.
final class DeviceLinkAttachment {
  final String deviceId;
  final int previousColumns;
  final int previousRows;
  final DateTime attachedAt;

  DeviceLinkAttachment({
    required this.deviceId,
    required this.previousColumns,
    required this.previousRows,
    required this.attachedAt,
  }) {
    if (deviceId.isEmpty) throw ArgumentError.value(deviceId, 'deviceId');
    if (previousColumns <= 0) {
      throw ArgumentError.value(previousColumns, 'previousColumns');
    }
    if (previousRows <= 0) {
      throw ArgumentError.value(previousRows, 'previousRows');
    }
  }
}
