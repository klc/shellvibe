import 'dart:convert';
import 'dart:typed_data';

/// Wire version used by the first Device Link protocol.
const int deviceLinkProtocolVersion = 1;

/// Raised when a Device Link control or binary frame is malformed.
class DeviceLinkProtocolException implements Exception {
  final String code;
  final String message;

  const DeviceLinkProtocolException(this.code, this.message);

  @override
  String toString() => 'DeviceLinkProtocolException($code): $message';
}

/// Raised when a peer speaks a protocol version this client does not support.
class DeviceLinkUnsupportedVersionException
    extends DeviceLinkProtocolException {
  final int version;

  const DeviceLinkUnsupportedVersionException(this.version)
    : super('unsupported_version', 'Unsupported Device Link protocol version');
}

/// One session advertised by the desktop in hello_ack.
final class DeviceLinkSessionInfo {
  final String id;
  final String title;
  final String type;

  const DeviceLinkSessionInfo({
    required this.id,
    required this.title,
    required this.type,
  });

  factory DeviceLinkSessionInfo.fromJson(Object? value) {
    final object = _asObject(value);
    return DeviceLinkSessionInfo(
      id: _requiredString(object, 'id'),
      title: _requiredString(object, 'title'),
      type: _requiredString(object, 'type'),
    );
  }

  Map<String, Object?> toJson() => {'id': id, 'title': title, 'type': type};
}

/// Base class for all text-frame control messages.
sealed class DeviceLinkControlMessage {
  const DeviceLinkControlMessage();

  String get type;

  Map<String, Object?> toJson();

  String encode() => jsonEncode(toJson());

  static DeviceLinkControlMessage decode(String encoded) {
    final Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException {
      throw const DeviceLinkProtocolException(
        'invalid_json',
        'Control frame is not valid JSON',
      );
    }
    return fromJson(decoded);
  }

  static DeviceLinkControlMessage fromJson(Object? value) {
    final object = _asObject(value);
    final version = _requiredInt(object, 'v');
    if (version != deviceLinkProtocolVersion) {
      throw DeviceLinkUnsupportedVersionException(version);
    }

    final type = _requiredString(object, 't');
    return switch (type) {
      'hello' => DeviceLinkHello.fromJsonObject(object),
      'hello_ack' => DeviceLinkHelloAck.fromJsonObject(object),
      'pair' => DeviceLinkPair.fromJsonObject(object),
      'paired' => DeviceLinkPaired.fromJsonObject(object),
      'attach' => DeviceLinkAttach.fromJsonObject(object),
      'attached' => DeviceLinkAttached.fromJsonObject(object),
      'resize' => DeviceLinkResize.fromJsonObject(object),
      'detach' => DeviceLinkDetach.fromJsonObject(object),
      'reclaimed' => DeviceLinkReclaimed.fromJsonObject(object),
      'error' => DeviceLinkError.fromJsonObject(object),
      _ => throw const DeviceLinkProtocolException(
        'unknown_message_type',
        'Unknown Device Link control message type',
      ),
    };
  }
}

final class DeviceLinkHello extends DeviceLinkControlMessage {
  final String deviceId;
  final String deviceName;
  final String? secret;

  const DeviceLinkHello({
    required this.deviceId,
    required this.deviceName,
    this.secret,
  });

  @override
  String get type => 'hello';

  @override
  Map<String, Object?> toJson() => {
    't': type,
    'v': deviceLinkProtocolVersion,
    'deviceId': deviceId,
    'deviceName': deviceName,
    if (secret != null) 'secret': secret,
  };

  static DeviceLinkHello fromJsonObject(Map<String, Object?> object) {
    return DeviceLinkHello(
      deviceId: _requiredString(object, 'deviceId'),
      deviceName: _requiredString(object, 'deviceName'),
      secret: _optionalString(object, 'secret'),
    );
  }
}

final class DeviceLinkHelloAck extends DeviceLinkControlMessage {
  final String appVersion;
  final List<DeviceLinkSessionInfo> sessions;

  DeviceLinkHelloAck({
    required this.appVersion,
    required List<DeviceLinkSessionInfo> sessions,
  }) : sessions = List.unmodifiable(sessions);

  @override
  String get type => 'hello_ack';

  @override
  Map<String, Object?> toJson() => {
    't': type,
    'v': deviceLinkProtocolVersion,
    'appVersion': appVersion,
    'sessions': sessions.map((session) => session.toJson()).toList(),
  };

  static DeviceLinkHelloAck fromJsonObject(Map<String, Object?> object) {
    final rawSessions = _requiredList(object, 'sessions');
    return DeviceLinkHelloAck(
      appVersion: _requiredString(object, 'appVersion'),
      sessions: rawSessions.map(DeviceLinkSessionInfo.fromJson).toList(),
    );
  }
}

final class DeviceLinkPair extends DeviceLinkControlMessage {
  final String token;
  final String deviceName;
  final String devicePublicKey;
  final String? platform;

  const DeviceLinkPair({
    required this.token,
    required this.deviceName,
    required this.devicePublicKey,
    this.platform,
  });

  @override
  String get type => 'pair';

  @override
  Map<String, Object?> toJson() => {
    't': type,
    'v': deviceLinkProtocolVersion,
    'token': token,
    'deviceName': deviceName,
    'devicePublicKey': devicePublicKey,
    if (platform != null) 'platform': platform,
  };

  static DeviceLinkPair fromJsonObject(Map<String, Object?> object) {
    return DeviceLinkPair(
      token: _requiredString(object, 'token'),
      deviceName: _requiredString(object, 'deviceName'),
      devicePublicKey: _requiredString(object, 'devicePublicKey'),
      platform: _optionalString(object, 'platform'),
    );
  }
}

final class DeviceLinkPaired extends DeviceLinkControlMessage {
  final String secret;
  final String hostName;

  const DeviceLinkPaired({required this.secret, required this.hostName});

  @override
  String get type => 'paired';

  @override
  Map<String, Object?> toJson() => {
    't': type,
    'v': deviceLinkProtocolVersion,
    'secret': secret,
    'hostName': hostName,
  };

  static DeviceLinkPaired fromJsonObject(Map<String, Object?> object) {
    return DeviceLinkPaired(
      secret: _requiredString(object, 'secret'),
      hostName: _requiredString(object, 'hostName'),
    );
  }
}

final class DeviceLinkAttach extends DeviceLinkControlMessage {
  final String sessionId;
  final int cols;
  final int rows;

  const DeviceLinkAttach({
    required this.sessionId,
    required this.cols,
    required this.rows,
  });

  @override
  String get type => 'attach';

  @override
  Map<String, Object?> toJson() => {
    't': type,
    'v': deviceLinkProtocolVersion,
    'sessionId': sessionId,
    'cols': cols,
    'rows': rows,
  };

  static DeviceLinkAttach fromJsonObject(Map<String, Object?> object) {
    return DeviceLinkAttach(
      sessionId: _requiredString(object, 'sessionId'),
      cols: _positiveInt(object, 'cols'),
      rows: _positiveInt(object, 'rows'),
    );
  }
}

final class DeviceLinkAttached extends DeviceLinkControlMessage {
  final String sessionId;
  final int cols;
  final int rows;
  final bool alt;
  final bool bracketedPaste;
  final int scrollbackLines;

  const DeviceLinkAttached({
    required this.sessionId,
    required this.cols,
    required this.rows,
    required this.alt,
    required this.bracketedPaste,
    required this.scrollbackLines,
  });

  @override
  String get type => 'attached';

  @override
  Map<String, Object?> toJson() => {
    't': type,
    'v': deviceLinkProtocolVersion,
    'sessionId': sessionId,
    'cols': cols,
    'rows': rows,
    'alt': alt,
    'bracketedPaste': bracketedPaste,
    'scrollbackLines': scrollbackLines,
  };

  static DeviceLinkAttached fromJsonObject(Map<String, Object?> object) {
    return DeviceLinkAttached(
      sessionId: _requiredString(object, 'sessionId'),
      cols: _positiveInt(object, 'cols'),
      rows: _positiveInt(object, 'rows'),
      alt: _requiredBool(object, 'alt'),
      bracketedPaste: _requiredBool(object, 'bracketedPaste'),
      scrollbackLines: _nonNegativeInt(object, 'scrollbackLines'),
    );
  }
}

final class DeviceLinkResize extends DeviceLinkControlMessage {
  final int cols;
  final int rows;

  const DeviceLinkResize({required this.cols, required this.rows});

  @override
  String get type => 'resize';

  @override
  Map<String, Object?> toJson() => {
    't': type,
    'v': deviceLinkProtocolVersion,
    'cols': cols,
    'rows': rows,
  };

  static DeviceLinkResize fromJsonObject(Map<String, Object?> object) {
    return DeviceLinkResize(
      cols: _positiveInt(object, 'cols'),
      rows: _positiveInt(object, 'rows'),
    );
  }
}

final class DeviceLinkDetach extends DeviceLinkControlMessage {
  const DeviceLinkDetach();

  @override
  String get type => 'detach';

  @override
  Map<String, Object?> toJson() => {'t': type, 'v': deviceLinkProtocolVersion};

  static DeviceLinkDetach fromJsonObject(Map<String, Object?> object) {
    return const DeviceLinkDetach();
  }
}

final class DeviceLinkReclaimed extends DeviceLinkControlMessage {
  final int cols;
  final int rows;

  const DeviceLinkReclaimed({required this.cols, required this.rows});

  @override
  String get type => 'reclaimed';

  @override
  Map<String, Object?> toJson() => {
    't': type,
    'v': deviceLinkProtocolVersion,
    'cols': cols,
    'rows': rows,
  };

  static DeviceLinkReclaimed fromJsonObject(Map<String, Object?> object) {
    return DeviceLinkReclaimed(
      cols: _positiveInt(object, 'cols'),
      rows: _positiveInt(object, 'rows'),
    );
  }
}

final class DeviceLinkError extends DeviceLinkControlMessage {
  final String code;
  final String message;

  const DeviceLinkError({required this.code, required this.message});

  @override
  String get type => 'error';

  @override
  Map<String, Object?> toJson() => {
    't': type,
    'v': deviceLinkProtocolVersion,
    'code': code,
    'message': message,
  };

  static DeviceLinkError fromJsonObject(Map<String, Object?> object) {
    return DeviceLinkError(
      code: _requiredString(object, 'code'),
      message: _requiredString(object, 'message'),
    );
  }
}

/// Binary frame types used after a WebSocket connection is established.
enum DeviceLinkBinaryFrameType {
  ptyOutput(0x01),
  ptyInput(0x02),
  snapshot(0x03);

  final int prefix;

  const DeviceLinkBinaryFrameType(this.prefix);

  static DeviceLinkBinaryFrameType fromPrefix(int prefix) {
    for (final type in values) {
      if (type.prefix == prefix) return type;
    }
    throw const DeviceLinkProtocolException(
      'unknown_binary_frame_type',
      'Unknown Device Link binary frame type',
    );
  }
}

/// A binary Device Link frame with an opaque payload.
final class DeviceLinkBinaryFrame {
  final DeviceLinkBinaryFrameType type;
  final Uint8List _payload;

  DeviceLinkBinaryFrame({required this.type, required List<int> payload})
    : _payload = Uint8List.fromList(payload);

  Uint8List get payload => Uint8List.fromList(_payload);

  Uint8List encode() {
    final frame = Uint8List(_payload.length + 1);
    frame[0] = type.prefix;
    frame.setRange(1, frame.length, _payload);
    return frame;
  }

  static DeviceLinkBinaryFrame decode(List<int> frame) {
    if (frame.isEmpty) {
      throw const DeviceLinkProtocolException(
        'empty_binary_frame',
        'Device Link binary frame is empty',
      );
    }
    return DeviceLinkBinaryFrame(
      type: DeviceLinkBinaryFrameType.fromPrefix(frame.first),
      payload: frame.sublist(1),
    );
  }
}

Map<String, Object?> _asObject(Object? value) {
  if (value is Map<String, dynamic>) {
    return value.map((key, nested) => MapEntry(key, nested));
  }
  if (value is Map<String, Object?>) return value;
  throw const DeviceLinkProtocolException(
    'invalid_object',
    'Control message must be a JSON object',
  );
}

Object? _field(Map<String, Object?> object, String name) {
  if (!object.containsKey(name)) {
    throw DeviceLinkProtocolException(
      'missing_field',
      'Missing required control message field: $name',
    );
  }
  return object[name];
}

String _requiredString(Map<String, Object?> object, String name) {
  final value = _field(object, name);
  if (value is! String || value.isEmpty) {
    throw DeviceLinkProtocolException(
      'invalid_field_type',
      'Control message field $name must be a non-empty string',
    );
  }
  return value;
}

String? _optionalString(Map<String, Object?> object, String name) {
  if (!object.containsKey(name) || object[name] == null) return null;
  final value = object[name];
  if (value is! String || value.isEmpty) {
    throw DeviceLinkProtocolException(
      'invalid_field_type',
      'Optional control message field $name must be a non-empty string',
    );
  }
  return value;
}

int _requiredInt(Map<String, Object?> object, String name) {
  final value = _field(object, name);
  if (value is! int) {
    throw DeviceLinkProtocolException(
      'invalid_field_type',
      'Control message field $name must be an integer',
    );
  }
  return value;
}

int _positiveInt(Map<String, Object?> object, String name) {
  final value = _requiredInt(object, name);
  if (value <= 0) {
    throw DeviceLinkProtocolException(
      'invalid_field_value',
      'Control message field $name must be positive',
    );
  }
  return value;
}

int _nonNegativeInt(Map<String, Object?> object, String name) {
  final value = _requiredInt(object, name);
  if (value < 0) {
    throw DeviceLinkProtocolException(
      'invalid_field_value',
      'Control message field $name must not be negative',
    );
  }
  return value;
}

bool _requiredBool(Map<String, Object?> object, String name) {
  final value = _field(object, name);
  if (value is! bool) {
    throw DeviceLinkProtocolException(
      'invalid_field_type',
      'Control message field $name must be a boolean',
    );
  }
  return value;
}

List<Object?> _requiredList(Map<String, Object?> object, String name) {
  final value = _field(object, name);
  if (value is! List<Object?>) {
    throw DeviceLinkProtocolException(
      'invalid_field_type',
      'Control message field $name must be a list',
    );
  }
  return value;
}
