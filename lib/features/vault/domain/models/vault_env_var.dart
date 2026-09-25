/// Domain entity for one workspace-scoped environment variable stored in the
/// vault. Named `Model` to keep it distinct from Drift's generated
/// `VaultEnvVar` row class (`shared/database/app_database.g.dart`).
class VaultEnvVarModel {
  final String id;
  final String workspaceId;
  final String name;

  /// Decrypted value. Null when it was not requested (a list built without
  /// decrypting) or could not be decrypted with the current vault key —
  /// [VaultEnvRepository] tells those two cases apart itself; this model only
  /// carries the result.
  final String? value;
  final DateTime createdAt;

  const VaultEnvVarModel({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.value,
    required this.createdAt,
  });

  VaultEnvVarModel copyWith({
    String? id,
    String? workspaceId,
    String? name,
    String? value,
    DateTime? createdAt,
  }) {
    return VaultEnvVarModel(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      value: value ?? this.value,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VaultEnvVarModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          workspaceId == other.workspaceId &&
          name == other.name &&
          value == other.value &&
          createdAt == other.createdAt;

  @override
  int get hashCode =>
      id.hashCode ^
      workspaceId.hashCode ^
      name.hashCode ^
      value.hashCode ^
      createdAt.hashCode;
}
