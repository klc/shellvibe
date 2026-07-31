/// Domain model representing a Host Group (folder/category).
class HostGroupModel {
  final String id;
  final String workspaceId;
  final String? parentId;
  final String name;
  final String? colorTag;

  const HostGroupModel({
    required this.id,
    required this.workspaceId,
    this.parentId,
    required this.name,
    this.colorTag,
  });

  HostGroupModel copyWith({
    String? id,
    String? workspaceId,
    String? parentId,
    String? name,
    String? colorTag,
  }) {
    return HostGroupModel(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      parentId: parentId ?? this.parentId,
      name: name ?? this.name,
      colorTag: colorTag ?? this.colorTag,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HostGroupModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          workspaceId == other.workspaceId &&
          parentId == other.parentId &&
          name == other.name &&
          colorTag == other.colorTag;

  @override
  int get hashCode =>
      id.hashCode ^
      workspaceId.hashCode ^
      parentId.hashCode ^
      name.hashCode ^
      colorTag.hashCode;
}
