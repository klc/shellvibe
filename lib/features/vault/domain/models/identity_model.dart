/// Domain entity representing a user identity (credentials, SSH keys, agent).
class IdentityModel {
  final String id;
  final String workspaceId;
  final String title;
  final String username;
  final String authType; // 'password', 'key', 'agent'
  final String? password;
  final String? privateKey;
  final String? passphrase;
  final DateTime createdAt;

  /// True when at least one stored secret could not be decrypted with the
  /// current vault key. Distinguishes "no secret stored" from "secret is
  /// unreadable", which would otherwise both look like a null field.
  final bool hasUndecryptableSecrets;

  const IdentityModel({
    required this.id,
    required this.workspaceId,
    required this.title,
    required this.username,
    required this.authType,
    this.password,
    this.privateKey,
    this.passphrase,
    required this.createdAt,
    this.hasUndecryptableSecrets = false,
  });

  IdentityModel copyWith({
    String? id,
    String? workspaceId,
    String? title,
    String? username,
    String? authType,
    String? password,
    String? privateKey,
    String? passphrase,
    DateTime? createdAt,
    bool? hasUndecryptableSecrets,
  }) {
    return IdentityModel(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      title: title ?? this.title,
      username: username ?? this.username,
      authType: authType ?? this.authType,
      password: password ?? this.password,
      privateKey: privateKey ?? this.privateKey,
      passphrase: passphrase ?? this.passphrase,
      createdAt: createdAt ?? this.createdAt,
      hasUndecryptableSecrets:
          hasUndecryptableSecrets ?? this.hasUndecryptableSecrets,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IdentityModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          workspaceId == other.workspaceId &&
          title == other.title &&
          username == other.username &&
          authType == other.authType &&
          password == other.password &&
          privateKey == other.privateKey &&
          passphrase == other.passphrase &&
          createdAt == other.createdAt &&
          hasUndecryptableSecrets == other.hasUndecryptableSecrets;

  @override
  int get hashCode =>
      id.hashCode ^
      workspaceId.hashCode ^
      title.hashCode ^
      username.hashCode ^
      authType.hashCode ^
      password.hashCode ^
      privateKey.hashCode ^
      passphrase.hashCode ^
      createdAt.hashCode ^
      hasUndecryptableSecrets.hashCode;
}
