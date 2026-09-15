/// Domain model representing a server host configuration.
class HostModel {
  final String id;
  final String workspaceId;
  final String? groupId;
  final String? identityId;
  final String label;
  final String hostname;
  final String? username;
  final int port;
  final String protocol; // 'ssh', 'mosh', 'local'

  /// Remote `mosh-server` executable, when it is not on the login PATH.
  /// Null means `mosh-server`. Only read when [protocol] is `'mosh'`.
  final String? moshServerPath;

  /// UDP range `mosh-server` is asked to bind, as `start:end`. Null means the
  /// mosh default of 60000:61000.
  final String? moshPortRange;

  final String? colorTag;
  final String? jumpHostId;
  final DateTime createdAt;

  const HostModel({
    required this.id,
    required this.workspaceId,
    this.groupId,
    this.identityId,
    required this.label,
    required this.hostname,
    this.username,
    this.port = 22,
    this.protocol = 'ssh',
    this.moshServerPath,
    this.moshPortRange,
    this.colorTag,
    this.jumpHostId,
    required this.createdAt,
  });

  HostModel copyWith({
    String? id,
    String? workspaceId,
    String? groupId,
    String? identityId,
    String? label,
    String? hostname,
    String? username,
    int? port,
    String? protocol,
    String? moshServerPath,
    String? moshPortRange,
    String? colorTag,
    String? jumpHostId,
    DateTime? createdAt,
  }) {
    return HostModel(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      groupId: groupId ?? this.groupId,
      identityId: identityId ?? this.identityId,
      label: label ?? this.label,
      hostname: hostname ?? this.hostname,
      username: username ?? this.username,
      port: port ?? this.port,
      protocol: protocol ?? this.protocol,
      moshServerPath: moshServerPath ?? this.moshServerPath,
      moshPortRange: moshPortRange ?? this.moshPortRange,
      colorTag: colorTag ?? this.colorTag,
      jumpHostId: jumpHostId ?? this.jumpHostId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HostModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          workspaceId == other.workspaceId &&
          groupId == other.groupId &&
          identityId == other.identityId &&
          label == other.label &&
          hostname == other.hostname &&
          username == other.username &&
          port == other.port &&
          protocol == other.protocol &&
          moshServerPath == other.moshServerPath &&
          moshPortRange == other.moshPortRange &&
          colorTag == other.colorTag &&
          jumpHostId == other.jumpHostId &&
          createdAt == other.createdAt;

  @override
  int get hashCode =>
      id.hashCode ^
      workspaceId.hashCode ^
      groupId.hashCode ^
      identityId.hashCode ^
      label.hashCode ^
      hostname.hashCode ^
      username.hashCode ^
      port.hashCode ^
      protocol.hashCode ^
      moshServerPath.hashCode ^
      moshPortRange.hashCode ^
      colorTag.hashCode ^
      jumpHostId.hashCode ^
      createdAt.hashCode;
}

/// Whether [host] should be listed for the free-text search [query].
///
/// Shared so the host list and the pickers that open over it agree on what a
/// query means: an empty query matches everything, and anything else is matched
/// case-insensitively against the fields a person would type from memory — what
/// they called it, where it is, who they log in as, and how.
///
/// [query] is matched as given, so a caller that already lower-cased it is not
/// charged for doing so twice per host.
bool hostMatchesQuery(HostModel host, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  return host.label.toLowerCase().contains(needle) ||
      host.hostname.toLowerCase().contains(needle) ||
      (host.username ?? '').toLowerCase().contains(needle) ||
      host.protocol.toLowerCase().contains(needle);
}
