import 'package:flutter/foundation.dart';

/// Domain entity representing a Port Forwarding Rule.
@immutable
class TunnelRuleModel {
  final String id;
  final String hostId;
  final String type; // 'local', 'remote', 'dynamic'
  final int localPort;
  final String? remoteHost;
  final int? remotePort;
  final bool autoStart;

  const TunnelRuleModel({
    required this.id,
    required this.hostId,
    required this.type,
    required this.localPort,
    this.remoteHost,
    this.remotePort,
    this.autoStart = false,
  });

  bool get isLocal => type == 'local';
  bool get isRemote => type == 'remote';
  bool get isDynamic => type == 'dynamic';

  TunnelRuleModel copyWith({
    String? id,
    String? hostId,
    String? type,
    int? localPort,
    String? remoteHost,
    int? remotePort,
    bool? autoStart,
  }) {
    return TunnelRuleModel(
      id: id ?? this.id,
      hostId: hostId ?? this.hostId,
      type: type ?? this.type,
      localPort: localPort ?? this.localPort,
      remoteHost: remoteHost ?? this.remoteHost,
      remotePort: remotePort ?? this.remotePort,
      autoStart: autoStart ?? this.autoStart,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TunnelRuleModel &&
        other.id == id &&
        other.hostId == hostId &&
        other.type == type &&
        other.localPort == localPort &&
        other.remoteHost == remoteHost &&
        other.remotePort == remotePort &&
        other.autoStart == autoStart;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      hostId,
      type,
      localPort,
      remoteHost,
      remotePort,
      autoStart,
    );
  }

  @override
  String toString() {
    return 'TunnelRuleModel(id: $id, hostId: $hostId, type: $type, localPort: $localPort, remoteHost: $remoteHost, remotePort: $remotePort, autoStart: $autoStart)';
  }
}
