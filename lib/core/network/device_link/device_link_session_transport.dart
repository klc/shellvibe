import 'dart:async';
import 'dart:typed_data';

import 'device_link_attachment.dart';
import 'device_link_protocol.dart';
import 'device_link_server.dart';

typedef DeviceLinkAttachCallback =
    DeviceLinkAttachment Function(String deviceId, int columns, int rows);

typedef DeviceLinkDetachCallback = DeviceLinkAttachment? Function();
typedef DeviceLinkResizeCallback = void Function(int columns, int rows);

/// Resolves a session id after the authenticated hello handshake.
typedef DeviceLinkSessionTransportResolver =
    FutureOr<DeviceLinkSessionTransport?> Function(String sessionId);

/// Supplies the sessions visible to the authenticated Device Link client.
typedef DeviceLinkSessionTransportListProvider =
    FutureOr<List<DeviceLinkSessionTransport>> Function();

/// The narrow core contract used by [DeviceLinkServer].
///
/// The interface deliberately contains no Flutter or feature-layer types.
/// Feature code adapts its live tab/session to this contract, while the server
/// remains usable by tests and future SSH transports.
abstract interface class DeviceLinkSessionTransport {
  DeviceLinkSessionInfo get info;

  bool get isAttached;

  Future<DeviceLinkSessionAttachResult> attach({
    required DeviceLinkServerConnection connection,
    required DeviceLinkAttach request,
    required FutureOr<void> Function() onDesktopInput,
  });

  Future<void> writeInput({
    required DeviceLinkServerConnection connection,
    required Uint8List bytes,
  });

  Future<void> resize({
    required DeviceLinkServerConnection connection,
    required int columns,
    required int rows,
  });

  Future<DeviceLinkAttachment?> detach({
    required DeviceLinkServerConnection connection,
  });

  Future<void> dispose();
}

final class DeviceLinkSessionAttachResult {
  final DeviceLinkAttached attached;
  final Uint8List snapshotPayload;

  DeviceLinkSessionAttachResult({
    required this.attached,
    required List<int> snapshotPayload,
  }) : snapshotPayload = Uint8List.fromList(snapshotPayload);
}

class DeviceLinkSessionException implements Exception {
  final String code;
  final String message;
  final Object? cause;

  const DeviceLinkSessionException(this.code, this.message, [this.cause]);

  @override
  String toString() => 'DeviceLinkSessionException($code): $message';
}
