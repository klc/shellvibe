// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $WorkspacesTable extends Workspaces
    with TableInfo<$WorkspacesTable, Workspace> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkspacesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorCodeMeta = const VerificationMeta(
    'colorCode',
  );
  @override
  late final GeneratedColumn<String> colorCode = GeneratedColumn<String>(
    'color_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, colorCode, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'workspaces';
  @override
  VerificationContext validateIntegrity(
    Insertable<Workspace> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color_code')) {
      context.handle(
        _colorCodeMeta,
        colorCode.isAcceptableOrUnknown(data['color_code']!, _colorCodeMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Workspace map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Workspace(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      colorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color_code'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $WorkspacesTable createAlias(String alias) {
    return $WorkspacesTable(attachedDatabase, alias);
  }
}

class Workspace extends DataClass implements Insertable<Workspace> {
  final String id;
  final String name;
  final String? colorCode;
  final DateTime createdAt;
  const Workspace({
    required this.id,
    required this.name,
    this.colorCode,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || colorCode != null) {
      map['color_code'] = Variable<String>(colorCode);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  WorkspacesCompanion toCompanion(bool nullToAbsent) {
    return WorkspacesCompanion(
      id: Value(id),
      name: Value(name),
      colorCode: colorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(colorCode),
      createdAt: Value(createdAt),
    );
  }

  factory Workspace.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Workspace(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      colorCode: serializer.fromJson<String?>(json['colorCode']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'colorCode': serializer.toJson<String?>(colorCode),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Workspace copyWith({
    String? id,
    String? name,
    Value<String?> colorCode = const Value.absent(),
    DateTime? createdAt,
  }) => Workspace(
    id: id ?? this.id,
    name: name ?? this.name,
    colorCode: colorCode.present ? colorCode.value : this.colorCode,
    createdAt: createdAt ?? this.createdAt,
  );
  Workspace copyWithCompanion(WorkspacesCompanion data) {
    return Workspace(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      colorCode: data.colorCode.present ? data.colorCode.value : this.colorCode,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Workspace(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorCode: $colorCode, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, colorCode, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Workspace &&
          other.id == this.id &&
          other.name == this.name &&
          other.colorCode == this.colorCode &&
          other.createdAt == this.createdAt);
}

class WorkspacesCompanion extends UpdateCompanion<Workspace> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> colorCode;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const WorkspacesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.colorCode = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WorkspacesCompanion.insert({
    required String id,
    required String name,
    this.colorCode = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt);
  static Insertable<Workspace> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? colorCode,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (colorCode != null) 'color_code': colorCode,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WorkspacesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? colorCode,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return WorkspacesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      colorCode: colorCode ?? this.colorCode,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (colorCode.present) {
      map['color_code'] = Variable<String>(colorCode.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkspacesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorCode: $colorCode, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $IdentitiesTable extends Identities
    with TableInfo<$IdentitiesTable, Identity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $IdentitiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES workspaces (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authTypeMeta = const VerificationMeta(
    'authType',
  );
  @override
  late final GeneratedColumn<String> authType = GeneratedColumn<String>(
    'auth_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _passwordEncryptedMeta = const VerificationMeta(
    'passwordEncrypted',
  );
  @override
  late final GeneratedColumn<String> passwordEncrypted =
      GeneratedColumn<String>(
        'password_encrypted',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _privateKeyEncryptedMeta =
      const VerificationMeta('privateKeyEncrypted');
  @override
  late final GeneratedColumn<String> privateKeyEncrypted =
      GeneratedColumn<String>(
        'private_key_encrypted',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _passphraseEncryptedMeta =
      const VerificationMeta('passphraseEncrypted');
  @override
  late final GeneratedColumn<String> passphraseEncrypted =
      GeneratedColumn<String>(
        'passphrase_encrypted',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    title,
    username,
    authType,
    passwordEncrypted,
    privateKeyEncrypted,
    passphraseEncrypted,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'identities';
  @override
  VerificationContext validateIntegrity(
    Insertable<Identity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('auth_type')) {
      context.handle(
        _authTypeMeta,
        authType.isAcceptableOrUnknown(data['auth_type']!, _authTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_authTypeMeta);
    }
    if (data.containsKey('password_encrypted')) {
      context.handle(
        _passwordEncryptedMeta,
        passwordEncrypted.isAcceptableOrUnknown(
          data['password_encrypted']!,
          _passwordEncryptedMeta,
        ),
      );
    }
    if (data.containsKey('private_key_encrypted')) {
      context.handle(
        _privateKeyEncryptedMeta,
        privateKeyEncrypted.isAcceptableOrUnknown(
          data['private_key_encrypted']!,
          _privateKeyEncryptedMeta,
        ),
      );
    }
    if (data.containsKey('passphrase_encrypted')) {
      context.handle(
        _passphraseEncryptedMeta,
        passphraseEncrypted.isAcceptableOrUnknown(
          data['passphrase_encrypted']!,
          _passphraseEncryptedMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Identity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Identity(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      authType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}auth_type'],
      )!,
      passwordEncrypted: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}password_encrypted'],
      ),
      privateKeyEncrypted: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}private_key_encrypted'],
      ),
      passphraseEncrypted: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}passphrase_encrypted'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $IdentitiesTable createAlias(String alias) {
    return $IdentitiesTable(attachedDatabase, alias);
  }
}

class Identity extends DataClass implements Insertable<Identity> {
  final String id;
  final String workspaceId;
  final String title;
  final String username;
  final String authType;
  final String? passwordEncrypted;
  final String? privateKeyEncrypted;
  final String? passphraseEncrypted;
  final DateTime createdAt;
  const Identity({
    required this.id,
    required this.workspaceId,
    required this.title,
    required this.username,
    required this.authType,
    this.passwordEncrypted,
    this.privateKeyEncrypted,
    this.passphraseEncrypted,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['title'] = Variable<String>(title);
    map['username'] = Variable<String>(username);
    map['auth_type'] = Variable<String>(authType);
    if (!nullToAbsent || passwordEncrypted != null) {
      map['password_encrypted'] = Variable<String>(passwordEncrypted);
    }
    if (!nullToAbsent || privateKeyEncrypted != null) {
      map['private_key_encrypted'] = Variable<String>(privateKeyEncrypted);
    }
    if (!nullToAbsent || passphraseEncrypted != null) {
      map['passphrase_encrypted'] = Variable<String>(passphraseEncrypted);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  IdentitiesCompanion toCompanion(bool nullToAbsent) {
    return IdentitiesCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      title: Value(title),
      username: Value(username),
      authType: Value(authType),
      passwordEncrypted: passwordEncrypted == null && nullToAbsent
          ? const Value.absent()
          : Value(passwordEncrypted),
      privateKeyEncrypted: privateKeyEncrypted == null && nullToAbsent
          ? const Value.absent()
          : Value(privateKeyEncrypted),
      passphraseEncrypted: passphraseEncrypted == null && nullToAbsent
          ? const Value.absent()
          : Value(passphraseEncrypted),
      createdAt: Value(createdAt),
    );
  }

  factory Identity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Identity(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      title: serializer.fromJson<String>(json['title']),
      username: serializer.fromJson<String>(json['username']),
      authType: serializer.fromJson<String>(json['authType']),
      passwordEncrypted: serializer.fromJson<String?>(
        json['passwordEncrypted'],
      ),
      privateKeyEncrypted: serializer.fromJson<String?>(
        json['privateKeyEncrypted'],
      ),
      passphraseEncrypted: serializer.fromJson<String?>(
        json['passphraseEncrypted'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'title': serializer.toJson<String>(title),
      'username': serializer.toJson<String>(username),
      'authType': serializer.toJson<String>(authType),
      'passwordEncrypted': serializer.toJson<String?>(passwordEncrypted),
      'privateKeyEncrypted': serializer.toJson<String?>(privateKeyEncrypted),
      'passphraseEncrypted': serializer.toJson<String?>(passphraseEncrypted),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Identity copyWith({
    String? id,
    String? workspaceId,
    String? title,
    String? username,
    String? authType,
    Value<String?> passwordEncrypted = const Value.absent(),
    Value<String?> privateKeyEncrypted = const Value.absent(),
    Value<String?> passphraseEncrypted = const Value.absent(),
    DateTime? createdAt,
  }) => Identity(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    title: title ?? this.title,
    username: username ?? this.username,
    authType: authType ?? this.authType,
    passwordEncrypted: passwordEncrypted.present
        ? passwordEncrypted.value
        : this.passwordEncrypted,
    privateKeyEncrypted: privateKeyEncrypted.present
        ? privateKeyEncrypted.value
        : this.privateKeyEncrypted,
    passphraseEncrypted: passphraseEncrypted.present
        ? passphraseEncrypted.value
        : this.passphraseEncrypted,
    createdAt: createdAt ?? this.createdAt,
  );
  Identity copyWithCompanion(IdentitiesCompanion data) {
    return Identity(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      title: data.title.present ? data.title.value : this.title,
      username: data.username.present ? data.username.value : this.username,
      authType: data.authType.present ? data.authType.value : this.authType,
      passwordEncrypted: data.passwordEncrypted.present
          ? data.passwordEncrypted.value
          : this.passwordEncrypted,
      privateKeyEncrypted: data.privateKeyEncrypted.present
          ? data.privateKeyEncrypted.value
          : this.privateKeyEncrypted,
      passphraseEncrypted: data.passphraseEncrypted.present
          ? data.passphraseEncrypted.value
          : this.passphraseEncrypted,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Identity(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('title: $title, ')
          ..write('username: $username, ')
          ..write('authType: $authType, ')
          ..write('passwordEncrypted: $passwordEncrypted, ')
          ..write('privateKeyEncrypted: $privateKeyEncrypted, ')
          ..write('passphraseEncrypted: $passphraseEncrypted, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    title,
    username,
    authType,
    passwordEncrypted,
    privateKeyEncrypted,
    passphraseEncrypted,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Identity &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.title == this.title &&
          other.username == this.username &&
          other.authType == this.authType &&
          other.passwordEncrypted == this.passwordEncrypted &&
          other.privateKeyEncrypted == this.privateKeyEncrypted &&
          other.passphraseEncrypted == this.passphraseEncrypted &&
          other.createdAt == this.createdAt);
}

class IdentitiesCompanion extends UpdateCompanion<Identity> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> title;
  final Value<String> username;
  final Value<String> authType;
  final Value<String?> passwordEncrypted;
  final Value<String?> privateKeyEncrypted;
  final Value<String?> passphraseEncrypted;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const IdentitiesCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.title = const Value.absent(),
    this.username = const Value.absent(),
    this.authType = const Value.absent(),
    this.passwordEncrypted = const Value.absent(),
    this.privateKeyEncrypted = const Value.absent(),
    this.passphraseEncrypted = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  IdentitiesCompanion.insert({
    required String id,
    required String workspaceId,
    required String title,
    required String username,
    required String authType,
    this.passwordEncrypted = const Value.absent(),
    this.privateKeyEncrypted = const Value.absent(),
    this.passphraseEncrypted = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       title = Value(title),
       username = Value(username),
       authType = Value(authType),
       createdAt = Value(createdAt);
  static Insertable<Identity> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? title,
    Expression<String>? username,
    Expression<String>? authType,
    Expression<String>? passwordEncrypted,
    Expression<String>? privateKeyEncrypted,
    Expression<String>? passphraseEncrypted,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (title != null) 'title': title,
      if (username != null) 'username': username,
      if (authType != null) 'auth_type': authType,
      if (passwordEncrypted != null) 'password_encrypted': passwordEncrypted,
      if (privateKeyEncrypted != null)
        'private_key_encrypted': privateKeyEncrypted,
      if (passphraseEncrypted != null)
        'passphrase_encrypted': passphraseEncrypted,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  IdentitiesCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? title,
    Value<String>? username,
    Value<String>? authType,
    Value<String?>? passwordEncrypted,
    Value<String?>? privateKeyEncrypted,
    Value<String?>? passphraseEncrypted,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return IdentitiesCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      title: title ?? this.title,
      username: username ?? this.username,
      authType: authType ?? this.authType,
      passwordEncrypted: passwordEncrypted ?? this.passwordEncrypted,
      privateKeyEncrypted: privateKeyEncrypted ?? this.privateKeyEncrypted,
      passphraseEncrypted: passphraseEncrypted ?? this.passphraseEncrypted,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (authType.present) {
      map['auth_type'] = Variable<String>(authType.value);
    }
    if (passwordEncrypted.present) {
      map['password_encrypted'] = Variable<String>(passwordEncrypted.value);
    }
    if (privateKeyEncrypted.present) {
      map['private_key_encrypted'] = Variable<String>(
        privateKeyEncrypted.value,
      );
    }
    if (passphraseEncrypted.present) {
      map['passphrase_encrypted'] = Variable<String>(passphraseEncrypted.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IdentitiesCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('title: $title, ')
          ..write('username: $username, ')
          ..write('authType: $authType, ')
          ..write('passwordEncrypted: $passwordEncrypted, ')
          ..write('privateKeyEncrypted: $privateKeyEncrypted, ')
          ..write('passphraseEncrypted: $passphraseEncrypted, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HostGroupsTable extends HostGroups
    with TableInfo<$HostGroupsTable, HostGroup> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HostGroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES workspaces (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES host_groups (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorTagMeta = const VerificationMeta(
    'colorTag',
  );
  @override
  late final GeneratedColumn<String> colorTag = GeneratedColumn<String>(
    'color_tag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    parentId,
    name,
    colorTag,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'host_groups';
  @override
  VerificationContext validateIntegrity(
    Insertable<HostGroup> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color_tag')) {
      context.handle(
        _colorTagMeta,
        colorTag.isAcceptableOrUnknown(data['color_tag']!, _colorTagMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HostGroup map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HostGroup(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      colorTag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color_tag'],
      ),
    );
  }

  @override
  $HostGroupsTable createAlias(String alias) {
    return $HostGroupsTable(attachedDatabase, alias);
  }
}

class HostGroup extends DataClass implements Insertable<HostGroup> {
  final String id;
  final String workspaceId;
  final String? parentId;
  final String name;
  final String? colorTag;
  const HostGroup({
    required this.id,
    required this.workspaceId,
    this.parentId,
    required this.name,
    this.colorTag,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || colorTag != null) {
      map['color_tag'] = Variable<String>(colorTag);
    }
    return map;
  }

  HostGroupsCompanion toCompanion(bool nullToAbsent) {
    return HostGroupsCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      name: Value(name),
      colorTag: colorTag == null && nullToAbsent
          ? const Value.absent()
          : Value(colorTag),
    );
  }

  factory HostGroup.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HostGroup(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      name: serializer.fromJson<String>(json['name']),
      colorTag: serializer.fromJson<String?>(json['colorTag']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'parentId': serializer.toJson<String?>(parentId),
      'name': serializer.toJson<String>(name),
      'colorTag': serializer.toJson<String?>(colorTag),
    };
  }

  HostGroup copyWith({
    String? id,
    String? workspaceId,
    Value<String?> parentId = const Value.absent(),
    String? name,
    Value<String?> colorTag = const Value.absent(),
  }) => HostGroup(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    parentId: parentId.present ? parentId.value : this.parentId,
    name: name ?? this.name,
    colorTag: colorTag.present ? colorTag.value : this.colorTag,
  );
  HostGroup copyWithCompanion(HostGroupsCompanion data) {
    return HostGroup(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      name: data.name.present ? data.name.value : this.name,
      colorTag: data.colorTag.present ? data.colorTag.value : this.colorTag,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HostGroup(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('colorTag: $colorTag')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, workspaceId, parentId, name, colorTag);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HostGroup &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.parentId == this.parentId &&
          other.name == this.name &&
          other.colorTag == this.colorTag);
}

class HostGroupsCompanion extends UpdateCompanion<HostGroup> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String?> parentId;
  final Value<String> name;
  final Value<String?> colorTag;
  final Value<int> rowid;
  const HostGroupsCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.parentId = const Value.absent(),
    this.name = const Value.absent(),
    this.colorTag = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HostGroupsCompanion.insert({
    required String id,
    required String workspaceId,
    this.parentId = const Value.absent(),
    required String name,
    this.colorTag = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       name = Value(name);
  static Insertable<HostGroup> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? parentId,
    Expression<String>? name,
    Expression<String>? colorTag,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (parentId != null) 'parent_id': parentId,
      if (name != null) 'name': name,
      if (colorTag != null) 'color_tag': colorTag,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HostGroupsCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String?>? parentId,
    Value<String>? name,
    Value<String?>? colorTag,
    Value<int>? rowid,
  }) {
    return HostGroupsCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      parentId: parentId ?? this.parentId,
      name: name ?? this.name,
      colorTag: colorTag ?? this.colorTag,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (colorTag.present) {
      map['color_tag'] = Variable<String>(colorTag.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HostGroupsCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('colorTag: $colorTag, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HostsTable extends Hosts with TableInfo<$HostsTable, Host> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HostsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES workspaces (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES host_groups (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _identityIdMeta = const VerificationMeta(
    'identityId',
  );
  @override
  late final GeneratedColumn<String> identityId = GeneratedColumn<String>(
    'identity_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES identities (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostnameMeta = const VerificationMeta(
    'hostname',
  );
  @override
  late final GeneratedColumn<String> hostname = GeneratedColumn<String>(
    'hostname',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _portMeta = const VerificationMeta('port');
  @override
  late final GeneratedColumn<int> port = GeneratedColumn<int>(
    'port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(22),
  );
  static const VerificationMeta _protocolMeta = const VerificationMeta(
    'protocol',
  );
  @override
  late final GeneratedColumn<String> protocol = GeneratedColumn<String>(
    'protocol',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('ssh'),
  );
  static const VerificationMeta _moshServerPathMeta = const VerificationMeta(
    'moshServerPath',
  );
  @override
  late final GeneratedColumn<String> moshServerPath = GeneratedColumn<String>(
    'mosh_server_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _moshPortRangeMeta = const VerificationMeta(
    'moshPortRange',
  );
  @override
  late final GeneratedColumn<String> moshPortRange = GeneratedColumn<String>(
    'mosh_port_range',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorTagMeta = const VerificationMeta(
    'colorTag',
  );
  @override
  late final GeneratedColumn<String> colorTag = GeneratedColumn<String>(
    'color_tag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _jumpHostIdMeta = const VerificationMeta(
    'jumpHostId',
  );
  @override
  late final GeneratedColumn<String> jumpHostId = GeneratedColumn<String>(
    'jump_host_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES hosts (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _environmentMeta = const VerificationMeta(
    'environment',
  );
  @override
  late final GeneratedColumn<String> environment = GeneratedColumn<String>(
    'environment',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('dev'),
  );
  static const VerificationMeta _mcpVisibleMeta = const VerificationMeta(
    'mcpVisible',
  );
  @override
  late final GeneratedColumn<bool> mcpVisible = GeneratedColumn<bool>(
    'mcp_visible',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("mcp_visible" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _mcpDefaultModeMeta = const VerificationMeta(
    'mcpDefaultMode',
  );
  @override
  late final GeneratedColumn<String> mcpDefaultMode = GeneratedColumn<String>(
    'mcp_default_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('readonly'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    groupId,
    identityId,
    label,
    hostname,
    username,
    port,
    protocol,
    moshServerPath,
    moshPortRange,
    colorTag,
    jumpHostId,
    createdAt,
    environment,
    mcpVisible,
    mcpDefaultMode,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'hosts';
  @override
  VerificationContext validateIntegrity(
    Insertable<Host> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    }
    if (data.containsKey('identity_id')) {
      context.handle(
        _identityIdMeta,
        identityId.isAcceptableOrUnknown(data['identity_id']!, _identityIdMeta),
      );
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('hostname')) {
      context.handle(
        _hostnameMeta,
        hostname.isAcceptableOrUnknown(data['hostname']!, _hostnameMeta),
      );
    } else if (isInserting) {
      context.missing(_hostnameMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    }
    if (data.containsKey('port')) {
      context.handle(
        _portMeta,
        port.isAcceptableOrUnknown(data['port']!, _portMeta),
      );
    }
    if (data.containsKey('protocol')) {
      context.handle(
        _protocolMeta,
        protocol.isAcceptableOrUnknown(data['protocol']!, _protocolMeta),
      );
    }
    if (data.containsKey('mosh_server_path')) {
      context.handle(
        _moshServerPathMeta,
        moshServerPath.isAcceptableOrUnknown(
          data['mosh_server_path']!,
          _moshServerPathMeta,
        ),
      );
    }
    if (data.containsKey('mosh_port_range')) {
      context.handle(
        _moshPortRangeMeta,
        moshPortRange.isAcceptableOrUnknown(
          data['mosh_port_range']!,
          _moshPortRangeMeta,
        ),
      );
    }
    if (data.containsKey('color_tag')) {
      context.handle(
        _colorTagMeta,
        colorTag.isAcceptableOrUnknown(data['color_tag']!, _colorTagMeta),
      );
    }
    if (data.containsKey('jump_host_id')) {
      context.handle(
        _jumpHostIdMeta,
        jumpHostId.isAcceptableOrUnknown(
          data['jump_host_id']!,
          _jumpHostIdMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('environment')) {
      context.handle(
        _environmentMeta,
        environment.isAcceptableOrUnknown(
          data['environment']!,
          _environmentMeta,
        ),
      );
    }
    if (data.containsKey('mcp_visible')) {
      context.handle(
        _mcpVisibleMeta,
        mcpVisible.isAcceptableOrUnknown(data['mcp_visible']!, _mcpVisibleMeta),
      );
    }
    if (data.containsKey('mcp_default_mode')) {
      context.handle(
        _mcpDefaultModeMeta,
        mcpDefaultMode.isAcceptableOrUnknown(
          data['mcp_default_mode']!,
          _mcpDefaultModeMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Host map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Host(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      ),
      identityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identity_id'],
      ),
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      hostname: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hostname'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      ),
      port: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}port'],
      )!,
      protocol: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}protocol'],
      )!,
      moshServerPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mosh_server_path'],
      ),
      moshPortRange: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mosh_port_range'],
      ),
      colorTag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color_tag'],
      ),
      jumpHostId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}jump_host_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      environment: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}environment'],
      )!,
      mcpVisible: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}mcp_visible'],
      )!,
      mcpDefaultMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mcp_default_mode'],
      )!,
    );
  }

  @override
  $HostsTable createAlias(String alias) {
    return $HostsTable(attachedDatabase, alias);
  }
}

class Host extends DataClass implements Insertable<Host> {
  final String id;
  final String workspaceId;
  final String? groupId;
  final String? identityId;
  final String label;
  final String hostname;
  final String? username;
  final int port;
  final String protocol;

  /// Remote `mosh-server` executable, when it is not on the login PATH.
  final String? moshServerPath;

  /// UDP range `mosh-server` is asked to bind, as `start:end`. Null means the
  /// mosh default (60000:61000).
  final String? moshPortRange;
  final String? colorTag;
  final String? jumpHostId;
  final DateTime createdAt;

  /// 'dev' | 'staging' | 'prod' — the policy engine's criticality signal.
  final String environment;

  /// False hides this host entirely from MCP `list_hosts` output.
  final bool mcpVisible;

  /// Mode preselected in the MCP access-approval window.
  final String mcpDefaultMode;
  const Host({
    required this.id,
    required this.workspaceId,
    this.groupId,
    this.identityId,
    required this.label,
    required this.hostname,
    this.username,
    required this.port,
    required this.protocol,
    this.moshServerPath,
    this.moshPortRange,
    this.colorTag,
    this.jumpHostId,
    required this.createdAt,
    required this.environment,
    required this.mcpVisible,
    required this.mcpDefaultMode,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    if (!nullToAbsent || groupId != null) {
      map['group_id'] = Variable<String>(groupId);
    }
    if (!nullToAbsent || identityId != null) {
      map['identity_id'] = Variable<String>(identityId);
    }
    map['label'] = Variable<String>(label);
    map['hostname'] = Variable<String>(hostname);
    if (!nullToAbsent || username != null) {
      map['username'] = Variable<String>(username);
    }
    map['port'] = Variable<int>(port);
    map['protocol'] = Variable<String>(protocol);
    if (!nullToAbsent || moshServerPath != null) {
      map['mosh_server_path'] = Variable<String>(moshServerPath);
    }
    if (!nullToAbsent || moshPortRange != null) {
      map['mosh_port_range'] = Variable<String>(moshPortRange);
    }
    if (!nullToAbsent || colorTag != null) {
      map['color_tag'] = Variable<String>(colorTag);
    }
    if (!nullToAbsent || jumpHostId != null) {
      map['jump_host_id'] = Variable<String>(jumpHostId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['environment'] = Variable<String>(environment);
    map['mcp_visible'] = Variable<bool>(mcpVisible);
    map['mcp_default_mode'] = Variable<String>(mcpDefaultMode);
    return map;
  }

  HostsCompanion toCompanion(bool nullToAbsent) {
    return HostsCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      groupId: groupId == null && nullToAbsent
          ? const Value.absent()
          : Value(groupId),
      identityId: identityId == null && nullToAbsent
          ? const Value.absent()
          : Value(identityId),
      label: Value(label),
      hostname: Value(hostname),
      username: username == null && nullToAbsent
          ? const Value.absent()
          : Value(username),
      port: Value(port),
      protocol: Value(protocol),
      moshServerPath: moshServerPath == null && nullToAbsent
          ? const Value.absent()
          : Value(moshServerPath),
      moshPortRange: moshPortRange == null && nullToAbsent
          ? const Value.absent()
          : Value(moshPortRange),
      colorTag: colorTag == null && nullToAbsent
          ? const Value.absent()
          : Value(colorTag),
      jumpHostId: jumpHostId == null && nullToAbsent
          ? const Value.absent()
          : Value(jumpHostId),
      createdAt: Value(createdAt),
      environment: Value(environment),
      mcpVisible: Value(mcpVisible),
      mcpDefaultMode: Value(mcpDefaultMode),
    );
  }

  factory Host.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Host(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      groupId: serializer.fromJson<String?>(json['groupId']),
      identityId: serializer.fromJson<String?>(json['identityId']),
      label: serializer.fromJson<String>(json['label']),
      hostname: serializer.fromJson<String>(json['hostname']),
      username: serializer.fromJson<String?>(json['username']),
      port: serializer.fromJson<int>(json['port']),
      protocol: serializer.fromJson<String>(json['protocol']),
      moshServerPath: serializer.fromJson<String?>(json['moshServerPath']),
      moshPortRange: serializer.fromJson<String?>(json['moshPortRange']),
      colorTag: serializer.fromJson<String?>(json['colorTag']),
      jumpHostId: serializer.fromJson<String?>(json['jumpHostId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      environment: serializer.fromJson<String>(json['environment']),
      mcpVisible: serializer.fromJson<bool>(json['mcpVisible']),
      mcpDefaultMode: serializer.fromJson<String>(json['mcpDefaultMode']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'groupId': serializer.toJson<String?>(groupId),
      'identityId': serializer.toJson<String?>(identityId),
      'label': serializer.toJson<String>(label),
      'hostname': serializer.toJson<String>(hostname),
      'username': serializer.toJson<String?>(username),
      'port': serializer.toJson<int>(port),
      'protocol': serializer.toJson<String>(protocol),
      'moshServerPath': serializer.toJson<String?>(moshServerPath),
      'moshPortRange': serializer.toJson<String?>(moshPortRange),
      'colorTag': serializer.toJson<String?>(colorTag),
      'jumpHostId': serializer.toJson<String?>(jumpHostId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'environment': serializer.toJson<String>(environment),
      'mcpVisible': serializer.toJson<bool>(mcpVisible),
      'mcpDefaultMode': serializer.toJson<String>(mcpDefaultMode),
    };
  }

  Host copyWith({
    String? id,
    String? workspaceId,
    Value<String?> groupId = const Value.absent(),
    Value<String?> identityId = const Value.absent(),
    String? label,
    String? hostname,
    Value<String?> username = const Value.absent(),
    int? port,
    String? protocol,
    Value<String?> moshServerPath = const Value.absent(),
    Value<String?> moshPortRange = const Value.absent(),
    Value<String?> colorTag = const Value.absent(),
    Value<String?> jumpHostId = const Value.absent(),
    DateTime? createdAt,
    String? environment,
    bool? mcpVisible,
    String? mcpDefaultMode,
  }) => Host(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    groupId: groupId.present ? groupId.value : this.groupId,
    identityId: identityId.present ? identityId.value : this.identityId,
    label: label ?? this.label,
    hostname: hostname ?? this.hostname,
    username: username.present ? username.value : this.username,
    port: port ?? this.port,
    protocol: protocol ?? this.protocol,
    moshServerPath: moshServerPath.present
        ? moshServerPath.value
        : this.moshServerPath,
    moshPortRange: moshPortRange.present
        ? moshPortRange.value
        : this.moshPortRange,
    colorTag: colorTag.present ? colorTag.value : this.colorTag,
    jumpHostId: jumpHostId.present ? jumpHostId.value : this.jumpHostId,
    createdAt: createdAt ?? this.createdAt,
    environment: environment ?? this.environment,
    mcpVisible: mcpVisible ?? this.mcpVisible,
    mcpDefaultMode: mcpDefaultMode ?? this.mcpDefaultMode,
  );
  Host copyWithCompanion(HostsCompanion data) {
    return Host(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      identityId: data.identityId.present
          ? data.identityId.value
          : this.identityId,
      label: data.label.present ? data.label.value : this.label,
      hostname: data.hostname.present ? data.hostname.value : this.hostname,
      username: data.username.present ? data.username.value : this.username,
      port: data.port.present ? data.port.value : this.port,
      protocol: data.protocol.present ? data.protocol.value : this.protocol,
      moshServerPath: data.moshServerPath.present
          ? data.moshServerPath.value
          : this.moshServerPath,
      moshPortRange: data.moshPortRange.present
          ? data.moshPortRange.value
          : this.moshPortRange,
      colorTag: data.colorTag.present ? data.colorTag.value : this.colorTag,
      jumpHostId: data.jumpHostId.present
          ? data.jumpHostId.value
          : this.jumpHostId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      environment: data.environment.present
          ? data.environment.value
          : this.environment,
      mcpVisible: data.mcpVisible.present
          ? data.mcpVisible.value
          : this.mcpVisible,
      mcpDefaultMode: data.mcpDefaultMode.present
          ? data.mcpDefaultMode.value
          : this.mcpDefaultMode,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Host(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('groupId: $groupId, ')
          ..write('identityId: $identityId, ')
          ..write('label: $label, ')
          ..write('hostname: $hostname, ')
          ..write('username: $username, ')
          ..write('port: $port, ')
          ..write('protocol: $protocol, ')
          ..write('moshServerPath: $moshServerPath, ')
          ..write('moshPortRange: $moshPortRange, ')
          ..write('colorTag: $colorTag, ')
          ..write('jumpHostId: $jumpHostId, ')
          ..write('createdAt: $createdAt, ')
          ..write('environment: $environment, ')
          ..write('mcpVisible: $mcpVisible, ')
          ..write('mcpDefaultMode: $mcpDefaultMode')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    groupId,
    identityId,
    label,
    hostname,
    username,
    port,
    protocol,
    moshServerPath,
    moshPortRange,
    colorTag,
    jumpHostId,
    createdAt,
    environment,
    mcpVisible,
    mcpDefaultMode,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Host &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.groupId == this.groupId &&
          other.identityId == this.identityId &&
          other.label == this.label &&
          other.hostname == this.hostname &&
          other.username == this.username &&
          other.port == this.port &&
          other.protocol == this.protocol &&
          other.moshServerPath == this.moshServerPath &&
          other.moshPortRange == this.moshPortRange &&
          other.colorTag == this.colorTag &&
          other.jumpHostId == this.jumpHostId &&
          other.createdAt == this.createdAt &&
          other.environment == this.environment &&
          other.mcpVisible == this.mcpVisible &&
          other.mcpDefaultMode == this.mcpDefaultMode);
}

class HostsCompanion extends UpdateCompanion<Host> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String?> groupId;
  final Value<String?> identityId;
  final Value<String> label;
  final Value<String> hostname;
  final Value<String?> username;
  final Value<int> port;
  final Value<String> protocol;
  final Value<String?> moshServerPath;
  final Value<String?> moshPortRange;
  final Value<String?> colorTag;
  final Value<String?> jumpHostId;
  final Value<DateTime> createdAt;
  final Value<String> environment;
  final Value<bool> mcpVisible;
  final Value<String> mcpDefaultMode;
  final Value<int> rowid;
  const HostsCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.groupId = const Value.absent(),
    this.identityId = const Value.absent(),
    this.label = const Value.absent(),
    this.hostname = const Value.absent(),
    this.username = const Value.absent(),
    this.port = const Value.absent(),
    this.protocol = const Value.absent(),
    this.moshServerPath = const Value.absent(),
    this.moshPortRange = const Value.absent(),
    this.colorTag = const Value.absent(),
    this.jumpHostId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.environment = const Value.absent(),
    this.mcpVisible = const Value.absent(),
    this.mcpDefaultMode = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HostsCompanion.insert({
    required String id,
    required String workspaceId,
    this.groupId = const Value.absent(),
    this.identityId = const Value.absent(),
    required String label,
    required String hostname,
    this.username = const Value.absent(),
    this.port = const Value.absent(),
    this.protocol = const Value.absent(),
    this.moshServerPath = const Value.absent(),
    this.moshPortRange = const Value.absent(),
    this.colorTag = const Value.absent(),
    this.jumpHostId = const Value.absent(),
    required DateTime createdAt,
    this.environment = const Value.absent(),
    this.mcpVisible = const Value.absent(),
    this.mcpDefaultMode = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       label = Value(label),
       hostname = Value(hostname),
       createdAt = Value(createdAt);
  static Insertable<Host> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? groupId,
    Expression<String>? identityId,
    Expression<String>? label,
    Expression<String>? hostname,
    Expression<String>? username,
    Expression<int>? port,
    Expression<String>? protocol,
    Expression<String>? moshServerPath,
    Expression<String>? moshPortRange,
    Expression<String>? colorTag,
    Expression<String>? jumpHostId,
    Expression<DateTime>? createdAt,
    Expression<String>? environment,
    Expression<bool>? mcpVisible,
    Expression<String>? mcpDefaultMode,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (groupId != null) 'group_id': groupId,
      if (identityId != null) 'identity_id': identityId,
      if (label != null) 'label': label,
      if (hostname != null) 'hostname': hostname,
      if (username != null) 'username': username,
      if (port != null) 'port': port,
      if (protocol != null) 'protocol': protocol,
      if (moshServerPath != null) 'mosh_server_path': moshServerPath,
      if (moshPortRange != null) 'mosh_port_range': moshPortRange,
      if (colorTag != null) 'color_tag': colorTag,
      if (jumpHostId != null) 'jump_host_id': jumpHostId,
      if (createdAt != null) 'created_at': createdAt,
      if (environment != null) 'environment': environment,
      if (mcpVisible != null) 'mcp_visible': mcpVisible,
      if (mcpDefaultMode != null) 'mcp_default_mode': mcpDefaultMode,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HostsCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String?>? groupId,
    Value<String?>? identityId,
    Value<String>? label,
    Value<String>? hostname,
    Value<String?>? username,
    Value<int>? port,
    Value<String>? protocol,
    Value<String?>? moshServerPath,
    Value<String?>? moshPortRange,
    Value<String?>? colorTag,
    Value<String?>? jumpHostId,
    Value<DateTime>? createdAt,
    Value<String>? environment,
    Value<bool>? mcpVisible,
    Value<String>? mcpDefaultMode,
    Value<int>? rowid,
  }) {
    return HostsCompanion(
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
      environment: environment ?? this.environment,
      mcpVisible: mcpVisible ?? this.mcpVisible,
      mcpDefaultMode: mcpDefaultMode ?? this.mcpDefaultMode,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (identityId.present) {
      map['identity_id'] = Variable<String>(identityId.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (hostname.present) {
      map['hostname'] = Variable<String>(hostname.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (port.present) {
      map['port'] = Variable<int>(port.value);
    }
    if (protocol.present) {
      map['protocol'] = Variable<String>(protocol.value);
    }
    if (moshServerPath.present) {
      map['mosh_server_path'] = Variable<String>(moshServerPath.value);
    }
    if (moshPortRange.present) {
      map['mosh_port_range'] = Variable<String>(moshPortRange.value);
    }
    if (colorTag.present) {
      map['color_tag'] = Variable<String>(colorTag.value);
    }
    if (jumpHostId.present) {
      map['jump_host_id'] = Variable<String>(jumpHostId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (environment.present) {
      map['environment'] = Variable<String>(environment.value);
    }
    if (mcpVisible.present) {
      map['mcp_visible'] = Variable<bool>(mcpVisible.value);
    }
    if (mcpDefaultMode.present) {
      map['mcp_default_mode'] = Variable<String>(mcpDefaultMode.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HostsCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('groupId: $groupId, ')
          ..write('identityId: $identityId, ')
          ..write('label: $label, ')
          ..write('hostname: $hostname, ')
          ..write('username: $username, ')
          ..write('port: $port, ')
          ..write('protocol: $protocol, ')
          ..write('moshServerPath: $moshServerPath, ')
          ..write('moshPortRange: $moshPortRange, ')
          ..write('colorTag: $colorTag, ')
          ..write('jumpHostId: $jumpHostId, ')
          ..write('createdAt: $createdAt, ')
          ..write('environment: $environment, ')
          ..write('mcpVisible: $mcpVisible, ')
          ..write('mcpDefaultMode: $mcpDefaultMode, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $KnownHostsTable extends KnownHosts
    with TableInfo<$KnownHostsTable, KnownHost> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KnownHostsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostnameMeta = const VerificationMeta(
    'hostname',
  );
  @override
  late final GeneratedColumn<String> hostname = GeneratedColumn<String>(
    'hostname',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _portMeta = const VerificationMeta('port');
  @override
  late final GeneratedColumn<int> port = GeneratedColumn<int>(
    'port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keyTypeMeta = const VerificationMeta(
    'keyType',
  );
  @override
  late final GeneratedColumn<String> keyType = GeneratedColumn<String>(
    'key_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fingerprintSha256Meta = const VerificationMeta(
    'fingerprintSha256',
  );
  @override
  late final GeneratedColumn<String> fingerprintSha256 =
      GeneratedColumn<String>(
        'fingerprint_sha256',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _firstSeenAtMeta = const VerificationMeta(
    'firstSeenAt',
  );
  @override
  late final GeneratedColumn<DateTime> firstSeenAt = GeneratedColumn<DateTime>(
    'first_seen_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    hostname,
    port,
    keyType,
    fingerprintSha256,
    firstSeenAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'known_hosts';
  @override
  VerificationContext validateIntegrity(
    Insertable<KnownHost> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('hostname')) {
      context.handle(
        _hostnameMeta,
        hostname.isAcceptableOrUnknown(data['hostname']!, _hostnameMeta),
      );
    } else if (isInserting) {
      context.missing(_hostnameMeta);
    }
    if (data.containsKey('port')) {
      context.handle(
        _portMeta,
        port.isAcceptableOrUnknown(data['port']!, _portMeta),
      );
    } else if (isInserting) {
      context.missing(_portMeta);
    }
    if (data.containsKey('key_type')) {
      context.handle(
        _keyTypeMeta,
        keyType.isAcceptableOrUnknown(data['key_type']!, _keyTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_keyTypeMeta);
    }
    if (data.containsKey('fingerprint_sha256')) {
      context.handle(
        _fingerprintSha256Meta,
        fingerprintSha256.isAcceptableOrUnknown(
          data['fingerprint_sha256']!,
          _fingerprintSha256Meta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fingerprintSha256Meta);
    }
    if (data.containsKey('first_seen_at')) {
      context.handle(
        _firstSeenAtMeta,
        firstSeenAt.isAcceptableOrUnknown(
          data['first_seen_at']!,
          _firstSeenAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_firstSeenAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {hostname, port},
  ];
  @override
  KnownHost map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KnownHost(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      hostname: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hostname'],
      )!,
      port: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}port'],
      )!,
      keyType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key_type'],
      )!,
      fingerprintSha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint_sha256'],
      )!,
      firstSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}first_seen_at'],
      )!,
    );
  }

  @override
  $KnownHostsTable createAlias(String alias) {
    return $KnownHostsTable(attachedDatabase, alias);
  }
}

class KnownHost extends DataClass implements Insertable<KnownHost> {
  final String id;
  final String hostname;
  final int port;
  final String keyType;
  final String fingerprintSha256;
  final DateTime firstSeenAt;
  const KnownHost({
    required this.id,
    required this.hostname,
    required this.port,
    required this.keyType,
    required this.fingerprintSha256,
    required this.firstSeenAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['hostname'] = Variable<String>(hostname);
    map['port'] = Variable<int>(port);
    map['key_type'] = Variable<String>(keyType);
    map['fingerprint_sha256'] = Variable<String>(fingerprintSha256);
    map['first_seen_at'] = Variable<DateTime>(firstSeenAt);
    return map;
  }

  KnownHostsCompanion toCompanion(bool nullToAbsent) {
    return KnownHostsCompanion(
      id: Value(id),
      hostname: Value(hostname),
      port: Value(port),
      keyType: Value(keyType),
      fingerprintSha256: Value(fingerprintSha256),
      firstSeenAt: Value(firstSeenAt),
    );
  }

  factory KnownHost.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KnownHost(
      id: serializer.fromJson<String>(json['id']),
      hostname: serializer.fromJson<String>(json['hostname']),
      port: serializer.fromJson<int>(json['port']),
      keyType: serializer.fromJson<String>(json['keyType']),
      fingerprintSha256: serializer.fromJson<String>(json['fingerprintSha256']),
      firstSeenAt: serializer.fromJson<DateTime>(json['firstSeenAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'hostname': serializer.toJson<String>(hostname),
      'port': serializer.toJson<int>(port),
      'keyType': serializer.toJson<String>(keyType),
      'fingerprintSha256': serializer.toJson<String>(fingerprintSha256),
      'firstSeenAt': serializer.toJson<DateTime>(firstSeenAt),
    };
  }

  KnownHost copyWith({
    String? id,
    String? hostname,
    int? port,
    String? keyType,
    String? fingerprintSha256,
    DateTime? firstSeenAt,
  }) => KnownHost(
    id: id ?? this.id,
    hostname: hostname ?? this.hostname,
    port: port ?? this.port,
    keyType: keyType ?? this.keyType,
    fingerprintSha256: fingerprintSha256 ?? this.fingerprintSha256,
    firstSeenAt: firstSeenAt ?? this.firstSeenAt,
  );
  KnownHost copyWithCompanion(KnownHostsCompanion data) {
    return KnownHost(
      id: data.id.present ? data.id.value : this.id,
      hostname: data.hostname.present ? data.hostname.value : this.hostname,
      port: data.port.present ? data.port.value : this.port,
      keyType: data.keyType.present ? data.keyType.value : this.keyType,
      fingerprintSha256: data.fingerprintSha256.present
          ? data.fingerprintSha256.value
          : this.fingerprintSha256,
      firstSeenAt: data.firstSeenAt.present
          ? data.firstSeenAt.value
          : this.firstSeenAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KnownHost(')
          ..write('id: $id, ')
          ..write('hostname: $hostname, ')
          ..write('port: $port, ')
          ..write('keyType: $keyType, ')
          ..write('fingerprintSha256: $fingerprintSha256, ')
          ..write('firstSeenAt: $firstSeenAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, hostname, port, keyType, fingerprintSha256, firstSeenAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KnownHost &&
          other.id == this.id &&
          other.hostname == this.hostname &&
          other.port == this.port &&
          other.keyType == this.keyType &&
          other.fingerprintSha256 == this.fingerprintSha256 &&
          other.firstSeenAt == this.firstSeenAt);
}

class KnownHostsCompanion extends UpdateCompanion<KnownHost> {
  final Value<String> id;
  final Value<String> hostname;
  final Value<int> port;
  final Value<String> keyType;
  final Value<String> fingerprintSha256;
  final Value<DateTime> firstSeenAt;
  final Value<int> rowid;
  const KnownHostsCompanion({
    this.id = const Value.absent(),
    this.hostname = const Value.absent(),
    this.port = const Value.absent(),
    this.keyType = const Value.absent(),
    this.fingerprintSha256 = const Value.absent(),
    this.firstSeenAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KnownHostsCompanion.insert({
    required String id,
    required String hostname,
    required int port,
    required String keyType,
    required String fingerprintSha256,
    required DateTime firstSeenAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       hostname = Value(hostname),
       port = Value(port),
       keyType = Value(keyType),
       fingerprintSha256 = Value(fingerprintSha256),
       firstSeenAt = Value(firstSeenAt);
  static Insertable<KnownHost> custom({
    Expression<String>? id,
    Expression<String>? hostname,
    Expression<int>? port,
    Expression<String>? keyType,
    Expression<String>? fingerprintSha256,
    Expression<DateTime>? firstSeenAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (hostname != null) 'hostname': hostname,
      if (port != null) 'port': port,
      if (keyType != null) 'key_type': keyType,
      if (fingerprintSha256 != null) 'fingerprint_sha256': fingerprintSha256,
      if (firstSeenAt != null) 'first_seen_at': firstSeenAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KnownHostsCompanion copyWith({
    Value<String>? id,
    Value<String>? hostname,
    Value<int>? port,
    Value<String>? keyType,
    Value<String>? fingerprintSha256,
    Value<DateTime>? firstSeenAt,
    Value<int>? rowid,
  }) {
    return KnownHostsCompanion(
      id: id ?? this.id,
      hostname: hostname ?? this.hostname,
      port: port ?? this.port,
      keyType: keyType ?? this.keyType,
      fingerprintSha256: fingerprintSha256 ?? this.fingerprintSha256,
      firstSeenAt: firstSeenAt ?? this.firstSeenAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (hostname.present) {
      map['hostname'] = Variable<String>(hostname.value);
    }
    if (port.present) {
      map['port'] = Variable<int>(port.value);
    }
    if (keyType.present) {
      map['key_type'] = Variable<String>(keyType.value);
    }
    if (fingerprintSha256.present) {
      map['fingerprint_sha256'] = Variable<String>(fingerprintSha256.value);
    }
    if (firstSeenAt.present) {
      map['first_seen_at'] = Variable<DateTime>(firstSeenAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KnownHostsCompanion(')
          ..write('id: $id, ')
          ..write('hostname: $hostname, ')
          ..write('port: $port, ')
          ..write('keyType: $keyType, ')
          ..write('fingerprintSha256: $fingerprintSha256, ')
          ..write('firstSeenAt: $firstSeenAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PortForwardRulesTable extends PortForwardRules
    with TableInfo<$PortForwardRulesTable, PortForwardRule> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PortForwardRulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostIdMeta = const VerificationMeta('hostId');
  @override
  late final GeneratedColumn<String> hostId = GeneratedColumn<String>(
    'host_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES hosts (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localPortMeta = const VerificationMeta(
    'localPort',
  );
  @override
  late final GeneratedColumn<int> localPort = GeneratedColumn<int>(
    'local_port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remoteHostMeta = const VerificationMeta(
    'remoteHost',
  );
  @override
  late final GeneratedColumn<String> remoteHost = GeneratedColumn<String>(
    'remote_host',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _remotePortMeta = const VerificationMeta(
    'remotePort',
  );
  @override
  late final GeneratedColumn<int> remotePort = GeneratedColumn<int>(
    'remote_port',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _autoStartMeta = const VerificationMeta(
    'autoStart',
  );
  @override
  late final GeneratedColumn<bool> autoStart = GeneratedColumn<bool>(
    'auto_start',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("auto_start" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    hostId,
    type,
    localPort,
    remoteHost,
    remotePort,
    autoStart,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'port_forward_rules';
  @override
  VerificationContext validateIntegrity(
    Insertable<PortForwardRule> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('host_id')) {
      context.handle(
        _hostIdMeta,
        hostId.isAcceptableOrUnknown(data['host_id']!, _hostIdMeta),
      );
    } else if (isInserting) {
      context.missing(_hostIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('local_port')) {
      context.handle(
        _localPortMeta,
        localPort.isAcceptableOrUnknown(data['local_port']!, _localPortMeta),
      );
    } else if (isInserting) {
      context.missing(_localPortMeta);
    }
    if (data.containsKey('remote_host')) {
      context.handle(
        _remoteHostMeta,
        remoteHost.isAcceptableOrUnknown(data['remote_host']!, _remoteHostMeta),
      );
    }
    if (data.containsKey('remote_port')) {
      context.handle(
        _remotePortMeta,
        remotePort.isAcceptableOrUnknown(data['remote_port']!, _remotePortMeta),
      );
    }
    if (data.containsKey('auto_start')) {
      context.handle(
        _autoStartMeta,
        autoStart.isAcceptableOrUnknown(data['auto_start']!, _autoStartMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PortForwardRule map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PortForwardRule(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      hostId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      localPort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_port'],
      )!,
      remoteHost: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_host'],
      ),
      remotePort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}remote_port'],
      ),
      autoStart: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}auto_start'],
      )!,
    );
  }

  @override
  $PortForwardRulesTable createAlias(String alias) {
    return $PortForwardRulesTable(attachedDatabase, alias);
  }
}

class PortForwardRule extends DataClass implements Insertable<PortForwardRule> {
  final String id;
  final String hostId;
  final String type;
  final int localPort;
  final String? remoteHost;
  final int? remotePort;
  final bool autoStart;
  const PortForwardRule({
    required this.id,
    required this.hostId,
    required this.type,
    required this.localPort,
    this.remoteHost,
    this.remotePort,
    required this.autoStart,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['host_id'] = Variable<String>(hostId);
    map['type'] = Variable<String>(type);
    map['local_port'] = Variable<int>(localPort);
    if (!nullToAbsent || remoteHost != null) {
      map['remote_host'] = Variable<String>(remoteHost);
    }
    if (!nullToAbsent || remotePort != null) {
      map['remote_port'] = Variable<int>(remotePort);
    }
    map['auto_start'] = Variable<bool>(autoStart);
    return map;
  }

  PortForwardRulesCompanion toCompanion(bool nullToAbsent) {
    return PortForwardRulesCompanion(
      id: Value(id),
      hostId: Value(hostId),
      type: Value(type),
      localPort: Value(localPort),
      remoteHost: remoteHost == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteHost),
      remotePort: remotePort == null && nullToAbsent
          ? const Value.absent()
          : Value(remotePort),
      autoStart: Value(autoStart),
    );
  }

  factory PortForwardRule.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PortForwardRule(
      id: serializer.fromJson<String>(json['id']),
      hostId: serializer.fromJson<String>(json['hostId']),
      type: serializer.fromJson<String>(json['type']),
      localPort: serializer.fromJson<int>(json['localPort']),
      remoteHost: serializer.fromJson<String?>(json['remoteHost']),
      remotePort: serializer.fromJson<int?>(json['remotePort']),
      autoStart: serializer.fromJson<bool>(json['autoStart']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'hostId': serializer.toJson<String>(hostId),
      'type': serializer.toJson<String>(type),
      'localPort': serializer.toJson<int>(localPort),
      'remoteHost': serializer.toJson<String?>(remoteHost),
      'remotePort': serializer.toJson<int?>(remotePort),
      'autoStart': serializer.toJson<bool>(autoStart),
    };
  }

  PortForwardRule copyWith({
    String? id,
    String? hostId,
    String? type,
    int? localPort,
    Value<String?> remoteHost = const Value.absent(),
    Value<int?> remotePort = const Value.absent(),
    bool? autoStart,
  }) => PortForwardRule(
    id: id ?? this.id,
    hostId: hostId ?? this.hostId,
    type: type ?? this.type,
    localPort: localPort ?? this.localPort,
    remoteHost: remoteHost.present ? remoteHost.value : this.remoteHost,
    remotePort: remotePort.present ? remotePort.value : this.remotePort,
    autoStart: autoStart ?? this.autoStart,
  );
  PortForwardRule copyWithCompanion(PortForwardRulesCompanion data) {
    return PortForwardRule(
      id: data.id.present ? data.id.value : this.id,
      hostId: data.hostId.present ? data.hostId.value : this.hostId,
      type: data.type.present ? data.type.value : this.type,
      localPort: data.localPort.present ? data.localPort.value : this.localPort,
      remoteHost: data.remoteHost.present
          ? data.remoteHost.value
          : this.remoteHost,
      remotePort: data.remotePort.present
          ? data.remotePort.value
          : this.remotePort,
      autoStart: data.autoStart.present ? data.autoStart.value : this.autoStart,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PortForwardRule(')
          ..write('id: $id, ')
          ..write('hostId: $hostId, ')
          ..write('type: $type, ')
          ..write('localPort: $localPort, ')
          ..write('remoteHost: $remoteHost, ')
          ..write('remotePort: $remotePort, ')
          ..write('autoStart: $autoStart')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    hostId,
    type,
    localPort,
    remoteHost,
    remotePort,
    autoStart,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PortForwardRule &&
          other.id == this.id &&
          other.hostId == this.hostId &&
          other.type == this.type &&
          other.localPort == this.localPort &&
          other.remoteHost == this.remoteHost &&
          other.remotePort == this.remotePort &&
          other.autoStart == this.autoStart);
}

class PortForwardRulesCompanion extends UpdateCompanion<PortForwardRule> {
  final Value<String> id;
  final Value<String> hostId;
  final Value<String> type;
  final Value<int> localPort;
  final Value<String?> remoteHost;
  final Value<int?> remotePort;
  final Value<bool> autoStart;
  final Value<int> rowid;
  const PortForwardRulesCompanion({
    this.id = const Value.absent(),
    this.hostId = const Value.absent(),
    this.type = const Value.absent(),
    this.localPort = const Value.absent(),
    this.remoteHost = const Value.absent(),
    this.remotePort = const Value.absent(),
    this.autoStart = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PortForwardRulesCompanion.insert({
    required String id,
    required String hostId,
    required String type,
    required int localPort,
    this.remoteHost = const Value.absent(),
    this.remotePort = const Value.absent(),
    this.autoStart = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       hostId = Value(hostId),
       type = Value(type),
       localPort = Value(localPort);
  static Insertable<PortForwardRule> custom({
    Expression<String>? id,
    Expression<String>? hostId,
    Expression<String>? type,
    Expression<int>? localPort,
    Expression<String>? remoteHost,
    Expression<int>? remotePort,
    Expression<bool>? autoStart,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (hostId != null) 'host_id': hostId,
      if (type != null) 'type': type,
      if (localPort != null) 'local_port': localPort,
      if (remoteHost != null) 'remote_host': remoteHost,
      if (remotePort != null) 'remote_port': remotePort,
      if (autoStart != null) 'auto_start': autoStart,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PortForwardRulesCompanion copyWith({
    Value<String>? id,
    Value<String>? hostId,
    Value<String>? type,
    Value<int>? localPort,
    Value<String?>? remoteHost,
    Value<int?>? remotePort,
    Value<bool>? autoStart,
    Value<int>? rowid,
  }) {
    return PortForwardRulesCompanion(
      id: id ?? this.id,
      hostId: hostId ?? this.hostId,
      type: type ?? this.type,
      localPort: localPort ?? this.localPort,
      remoteHost: remoteHost ?? this.remoteHost,
      remotePort: remotePort ?? this.remotePort,
      autoStart: autoStart ?? this.autoStart,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (hostId.present) {
      map['host_id'] = Variable<String>(hostId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (localPort.present) {
      map['local_port'] = Variable<int>(localPort.value);
    }
    if (remoteHost.present) {
      map['remote_host'] = Variable<String>(remoteHost.value);
    }
    if (remotePort.present) {
      map['remote_port'] = Variable<int>(remotePort.value);
    }
    if (autoStart.present) {
      map['auto_start'] = Variable<bool>(autoStart.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PortForwardRulesCompanion(')
          ..write('id: $id, ')
          ..write('hostId: $hostId, ')
          ..write('type: $type, ')
          ..write('localPort: $localPort, ')
          ..write('remoteHost: $remoteHost, ')
          ..write('remotePort: $remotePort, ')
          ..write('autoStart: $autoStart, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SnippetsTable extends Snippets with TableInfo<$SnippetsTable, Snippet> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SnippetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES workspaces (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tagsMeta = const VerificationMeta('tags');
  @override
  late final GeneratedColumn<String> tags = GeneratedColumn<String>(
    'tags',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [id, workspaceId, title, code, tags];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'snippets';
  @override
  VerificationContext validateIntegrity(
    Insertable<Snippet> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('tags')) {
      context.handle(
        _tagsMeta,
        tags.isAcceptableOrUnknown(data['tags']!, _tagsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Snippet map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Snippet(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      tags: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags'],
      ),
    );
  }

  @override
  $SnippetsTable createAlias(String alias) {
    return $SnippetsTable(attachedDatabase, alias);
  }
}

class Snippet extends DataClass implements Insertable<Snippet> {
  final String id;
  final String workspaceId;
  final String title;
  final String code;
  final String? tags;
  const Snippet({
    required this.id,
    required this.workspaceId,
    required this.title,
    required this.code,
    this.tags,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['title'] = Variable<String>(title);
    map['code'] = Variable<String>(code);
    if (!nullToAbsent || tags != null) {
      map['tags'] = Variable<String>(tags);
    }
    return map;
  }

  SnippetsCompanion toCompanion(bool nullToAbsent) {
    return SnippetsCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      title: Value(title),
      code: Value(code),
      tags: tags == null && nullToAbsent ? const Value.absent() : Value(tags),
    );
  }

  factory Snippet.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Snippet(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      title: serializer.fromJson<String>(json['title']),
      code: serializer.fromJson<String>(json['code']),
      tags: serializer.fromJson<String?>(json['tags']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'title': serializer.toJson<String>(title),
      'code': serializer.toJson<String>(code),
      'tags': serializer.toJson<String?>(tags),
    };
  }

  Snippet copyWith({
    String? id,
    String? workspaceId,
    String? title,
    String? code,
    Value<String?> tags = const Value.absent(),
  }) => Snippet(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    title: title ?? this.title,
    code: code ?? this.code,
    tags: tags.present ? tags.value : this.tags,
  );
  Snippet copyWithCompanion(SnippetsCompanion data) {
    return Snippet(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      title: data.title.present ? data.title.value : this.title,
      code: data.code.present ? data.code.value : this.code,
      tags: data.tags.present ? data.tags.value : this.tags,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Snippet(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('title: $title, ')
          ..write('code: $code, ')
          ..write('tags: $tags')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, workspaceId, title, code, tags);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Snippet &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.title == this.title &&
          other.code == this.code &&
          other.tags == this.tags);
}

class SnippetsCompanion extends UpdateCompanion<Snippet> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> title;
  final Value<String> code;
  final Value<String?> tags;
  final Value<int> rowid;
  const SnippetsCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.title = const Value.absent(),
    this.code = const Value.absent(),
    this.tags = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SnippetsCompanion.insert({
    required String id,
    required String workspaceId,
    required String title,
    required String code,
    this.tags = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       title = Value(title),
       code = Value(code);
  static Insertable<Snippet> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? title,
    Expression<String>? code,
    Expression<String>? tags,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (title != null) 'title': title,
      if (code != null) 'code': code,
      if (tags != null) 'tags': tags,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SnippetsCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? title,
    Value<String>? code,
    Value<String?>? tags,
    Value<int>? rowid,
  }) {
    return SnippetsCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      title: title ?? this.title,
      code: code ?? this.code,
      tags: tags ?? this.tags,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (tags.present) {
      map['tags'] = Variable<String>(tags.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SnippetsCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('title: $title, ')
          ..write('code: $code, ')
          ..write('tags: $tags, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RunbooksTable extends Runbooks with TableInfo<$RunbooksTable, Runbook> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RunbooksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES workspaces (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    title,
    description,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'runbooks';
  @override
  VerificationContext validateIntegrity(
    Insertable<Runbook> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Runbook map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Runbook(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $RunbooksTable createAlias(String alias) {
    return $RunbooksTable(attachedDatabase, alias);
  }
}

class Runbook extends DataClass implements Insertable<Runbook> {
  final String id;
  final String workspaceId;
  final String title;
  final String? description;
  final DateTime createdAt;
  const Runbook({
    required this.id,
    required this.workspaceId,
    required this.title,
    this.description,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  RunbooksCompanion toCompanion(bool nullToAbsent) {
    return RunbooksCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      title: Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      createdAt: Value(createdAt),
    );
  }

  factory Runbook.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Runbook(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Runbook copyWith({
    String? id,
    String? workspaceId,
    String? title,
    Value<String?> description = const Value.absent(),
    DateTime? createdAt,
  }) => Runbook(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    title: title ?? this.title,
    description: description.present ? description.value : this.description,
    createdAt: createdAt ?? this.createdAt,
  );
  Runbook copyWithCompanion(RunbooksCompanion data) {
    return Runbook(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Runbook(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, workspaceId, title, description, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Runbook &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.title == this.title &&
          other.description == this.description &&
          other.createdAt == this.createdAt);
}

class RunbooksCompanion extends UpdateCompanion<Runbook> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> title;
  final Value<String?> description;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const RunbooksCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RunbooksCompanion.insert({
    required String id,
    required String workspaceId,
    required String title,
    this.description = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       title = Value(title),
       createdAt = Value(createdAt);
  static Insertable<Runbook> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? title,
    Expression<String>? description,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RunbooksCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? title,
    Value<String?>? description,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return RunbooksCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RunbooksCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RunbookStepsTable extends RunbookSteps
    with TableInfo<$RunbookStepsTable, RunbookStep> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RunbookStepsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _runbookIdMeta = const VerificationMeta(
    'runbookId',
  );
  @override
  late final GeneratedColumn<String> runbookId = GeneratedColumn<String>(
    'runbook_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES runbooks (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _stepOrderMeta = const VerificationMeta(
    'stepOrder',
  );
  @override
  late final GeneratedColumn<int> stepOrder = GeneratedColumn<int>(
    'step_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _commandMeta = const VerificationMeta(
    'command',
  );
  @override
  late final GeneratedColumn<String> command = GeneratedColumn<String>(
    'command',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expectedExitCodeMeta = const VerificationMeta(
    'expectedExitCode',
  );
  @override
  late final GeneratedColumn<int> expectedExitCode = GeneratedColumn<int>(
    'expected_exit_code',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _expectedOutputPatternMeta =
      const VerificationMeta('expectedOutputPattern');
  @override
  late final GeneratedColumn<String> expectedOutputPattern =
      GeneratedColumn<String>(
        'expected_output_pattern',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _timeoutSecondsMeta = const VerificationMeta(
    'timeoutSeconds',
  );
  @override
  late final GeneratedColumn<int> timeoutSeconds = GeneratedColumn<int>(
    'timeout_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(30),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    runbookId,
    stepOrder,
    command,
    expectedExitCode,
    expectedOutputPattern,
    timeoutSeconds,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'runbook_steps';
  @override
  VerificationContext validateIntegrity(
    Insertable<RunbookStep> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('runbook_id')) {
      context.handle(
        _runbookIdMeta,
        runbookId.isAcceptableOrUnknown(data['runbook_id']!, _runbookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_runbookIdMeta);
    }
    if (data.containsKey('step_order')) {
      context.handle(
        _stepOrderMeta,
        stepOrder.isAcceptableOrUnknown(data['step_order']!, _stepOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_stepOrderMeta);
    }
    if (data.containsKey('command')) {
      context.handle(
        _commandMeta,
        command.isAcceptableOrUnknown(data['command']!, _commandMeta),
      );
    } else if (isInserting) {
      context.missing(_commandMeta);
    }
    if (data.containsKey('expected_exit_code')) {
      context.handle(
        _expectedExitCodeMeta,
        expectedExitCode.isAcceptableOrUnknown(
          data['expected_exit_code']!,
          _expectedExitCodeMeta,
        ),
      );
    }
    if (data.containsKey('expected_output_pattern')) {
      context.handle(
        _expectedOutputPatternMeta,
        expectedOutputPattern.isAcceptableOrUnknown(
          data['expected_output_pattern']!,
          _expectedOutputPatternMeta,
        ),
      );
    }
    if (data.containsKey('timeout_seconds')) {
      context.handle(
        _timeoutSecondsMeta,
        timeoutSeconds.isAcceptableOrUnknown(
          data['timeout_seconds']!,
          _timeoutSecondsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RunbookStep map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RunbookStep(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      runbookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}runbook_id'],
      )!,
      stepOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}step_order'],
      )!,
      command: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}command'],
      )!,
      expectedExitCode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expected_exit_code'],
      )!,
      expectedOutputPattern: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}expected_output_pattern'],
      ),
      timeoutSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timeout_seconds'],
      )!,
    );
  }

  @override
  $RunbookStepsTable createAlias(String alias) {
    return $RunbookStepsTable(attachedDatabase, alias);
  }
}

class RunbookStep extends DataClass implements Insertable<RunbookStep> {
  final String id;
  final String runbookId;
  final int stepOrder;
  final String command;
  final int expectedExitCode;
  final String? expectedOutputPattern;
  final int timeoutSeconds;
  const RunbookStep({
    required this.id,
    required this.runbookId,
    required this.stepOrder,
    required this.command,
    required this.expectedExitCode,
    this.expectedOutputPattern,
    required this.timeoutSeconds,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['runbook_id'] = Variable<String>(runbookId);
    map['step_order'] = Variable<int>(stepOrder);
    map['command'] = Variable<String>(command);
    map['expected_exit_code'] = Variable<int>(expectedExitCode);
    if (!nullToAbsent || expectedOutputPattern != null) {
      map['expected_output_pattern'] = Variable<String>(expectedOutputPattern);
    }
    map['timeout_seconds'] = Variable<int>(timeoutSeconds);
    return map;
  }

  RunbookStepsCompanion toCompanion(bool nullToAbsent) {
    return RunbookStepsCompanion(
      id: Value(id),
      runbookId: Value(runbookId),
      stepOrder: Value(stepOrder),
      command: Value(command),
      expectedExitCode: Value(expectedExitCode),
      expectedOutputPattern: expectedOutputPattern == null && nullToAbsent
          ? const Value.absent()
          : Value(expectedOutputPattern),
      timeoutSeconds: Value(timeoutSeconds),
    );
  }

  factory RunbookStep.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RunbookStep(
      id: serializer.fromJson<String>(json['id']),
      runbookId: serializer.fromJson<String>(json['runbookId']),
      stepOrder: serializer.fromJson<int>(json['stepOrder']),
      command: serializer.fromJson<String>(json['command']),
      expectedExitCode: serializer.fromJson<int>(json['expectedExitCode']),
      expectedOutputPattern: serializer.fromJson<String?>(
        json['expectedOutputPattern'],
      ),
      timeoutSeconds: serializer.fromJson<int>(json['timeoutSeconds']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'runbookId': serializer.toJson<String>(runbookId),
      'stepOrder': serializer.toJson<int>(stepOrder),
      'command': serializer.toJson<String>(command),
      'expectedExitCode': serializer.toJson<int>(expectedExitCode),
      'expectedOutputPattern': serializer.toJson<String?>(
        expectedOutputPattern,
      ),
      'timeoutSeconds': serializer.toJson<int>(timeoutSeconds),
    };
  }

  RunbookStep copyWith({
    String? id,
    String? runbookId,
    int? stepOrder,
    String? command,
    int? expectedExitCode,
    Value<String?> expectedOutputPattern = const Value.absent(),
    int? timeoutSeconds,
  }) => RunbookStep(
    id: id ?? this.id,
    runbookId: runbookId ?? this.runbookId,
    stepOrder: stepOrder ?? this.stepOrder,
    command: command ?? this.command,
    expectedExitCode: expectedExitCode ?? this.expectedExitCode,
    expectedOutputPattern: expectedOutputPattern.present
        ? expectedOutputPattern.value
        : this.expectedOutputPattern,
    timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
  );
  RunbookStep copyWithCompanion(RunbookStepsCompanion data) {
    return RunbookStep(
      id: data.id.present ? data.id.value : this.id,
      runbookId: data.runbookId.present ? data.runbookId.value : this.runbookId,
      stepOrder: data.stepOrder.present ? data.stepOrder.value : this.stepOrder,
      command: data.command.present ? data.command.value : this.command,
      expectedExitCode: data.expectedExitCode.present
          ? data.expectedExitCode.value
          : this.expectedExitCode,
      expectedOutputPattern: data.expectedOutputPattern.present
          ? data.expectedOutputPattern.value
          : this.expectedOutputPattern,
      timeoutSeconds: data.timeoutSeconds.present
          ? data.timeoutSeconds.value
          : this.timeoutSeconds,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RunbookStep(')
          ..write('id: $id, ')
          ..write('runbookId: $runbookId, ')
          ..write('stepOrder: $stepOrder, ')
          ..write('command: $command, ')
          ..write('expectedExitCode: $expectedExitCode, ')
          ..write('expectedOutputPattern: $expectedOutputPattern, ')
          ..write('timeoutSeconds: $timeoutSeconds')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    runbookId,
    stepOrder,
    command,
    expectedExitCode,
    expectedOutputPattern,
    timeoutSeconds,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RunbookStep &&
          other.id == this.id &&
          other.runbookId == this.runbookId &&
          other.stepOrder == this.stepOrder &&
          other.command == this.command &&
          other.expectedExitCode == this.expectedExitCode &&
          other.expectedOutputPattern == this.expectedOutputPattern &&
          other.timeoutSeconds == this.timeoutSeconds);
}

class RunbookStepsCompanion extends UpdateCompanion<RunbookStep> {
  final Value<String> id;
  final Value<String> runbookId;
  final Value<int> stepOrder;
  final Value<String> command;
  final Value<int> expectedExitCode;
  final Value<String?> expectedOutputPattern;
  final Value<int> timeoutSeconds;
  final Value<int> rowid;
  const RunbookStepsCompanion({
    this.id = const Value.absent(),
    this.runbookId = const Value.absent(),
    this.stepOrder = const Value.absent(),
    this.command = const Value.absent(),
    this.expectedExitCode = const Value.absent(),
    this.expectedOutputPattern = const Value.absent(),
    this.timeoutSeconds = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RunbookStepsCompanion.insert({
    required String id,
    required String runbookId,
    required int stepOrder,
    required String command,
    this.expectedExitCode = const Value.absent(),
    this.expectedOutputPattern = const Value.absent(),
    this.timeoutSeconds = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       runbookId = Value(runbookId),
       stepOrder = Value(stepOrder),
       command = Value(command);
  static Insertable<RunbookStep> custom({
    Expression<String>? id,
    Expression<String>? runbookId,
    Expression<int>? stepOrder,
    Expression<String>? command,
    Expression<int>? expectedExitCode,
    Expression<String>? expectedOutputPattern,
    Expression<int>? timeoutSeconds,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (runbookId != null) 'runbook_id': runbookId,
      if (stepOrder != null) 'step_order': stepOrder,
      if (command != null) 'command': command,
      if (expectedExitCode != null) 'expected_exit_code': expectedExitCode,
      if (expectedOutputPattern != null)
        'expected_output_pattern': expectedOutputPattern,
      if (timeoutSeconds != null) 'timeout_seconds': timeoutSeconds,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RunbookStepsCompanion copyWith({
    Value<String>? id,
    Value<String>? runbookId,
    Value<int>? stepOrder,
    Value<String>? command,
    Value<int>? expectedExitCode,
    Value<String?>? expectedOutputPattern,
    Value<int>? timeoutSeconds,
    Value<int>? rowid,
  }) {
    return RunbookStepsCompanion(
      id: id ?? this.id,
      runbookId: runbookId ?? this.runbookId,
      stepOrder: stepOrder ?? this.stepOrder,
      command: command ?? this.command,
      expectedExitCode: expectedExitCode ?? this.expectedExitCode,
      expectedOutputPattern:
          expectedOutputPattern ?? this.expectedOutputPattern,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (runbookId.present) {
      map['runbook_id'] = Variable<String>(runbookId.value);
    }
    if (stepOrder.present) {
      map['step_order'] = Variable<int>(stepOrder.value);
    }
    if (command.present) {
      map['command'] = Variable<String>(command.value);
    }
    if (expectedExitCode.present) {
      map['expected_exit_code'] = Variable<int>(expectedExitCode.value);
    }
    if (expectedOutputPattern.present) {
      map['expected_output_pattern'] = Variable<String>(
        expectedOutputPattern.value,
      );
    }
    if (timeoutSeconds.present) {
      map['timeout_seconds'] = Variable<int>(timeoutSeconds.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RunbookStepsCompanion(')
          ..write('id: $id, ')
          ..write('runbookId: $runbookId, ')
          ..write('stepOrder: $stepOrder, ')
          ..write('command: $command, ')
          ..write('expectedExitCode: $expectedExitCode, ')
          ..write('expectedOutputPattern: $expectedOutputPattern, ')
          ..write('timeoutSeconds: $timeoutSeconds, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TemplatesTable extends Templates
    with TableInfo<$TemplatesTable, Template> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TemplatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES workspaces (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _activePaneIdMeta = const VerificationMeta(
    'activePaneId',
  );
  @override
  late final GeneratedColumn<String> activePaneId = GeneratedColumn<String>(
    'active_pane_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    name,
    description,
    activePaneId,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'templates';
  @override
  VerificationContext validateIntegrity(
    Insertable<Template> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('active_pane_id')) {
      context.handle(
        _activePaneIdMeta,
        activePaneId.isAcceptableOrUnknown(
          data['active_pane_id']!,
          _activePaneIdMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Template map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Template(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      activePaneId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}active_pane_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $TemplatesTable createAlias(String alias) {
    return $TemplatesTable(attachedDatabase, alias);
  }
}

class Template extends DataClass implements Insertable<Template> {
  final String id;
  final String workspaceId;
  final String name;
  final String? description;

  /// Template-local id of the pane that was focused at capture time, restored
  /// as the active pane once the whole layout is back up. Null when the capture
  /// had no focused pane.
  final String? activePaneId;
  final DateTime createdAt;
  const Template({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.description,
    this.activePaneId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || activePaneId != null) {
      map['active_pane_id'] = Variable<String>(activePaneId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  TemplatesCompanion toCompanion(bool nullToAbsent) {
    return TemplatesCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      activePaneId: activePaneId == null && nullToAbsent
          ? const Value.absent()
          : Value(activePaneId),
      createdAt: Value(createdAt),
    );
  }

  factory Template.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Template(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      activePaneId: serializer.fromJson<String?>(json['activePaneId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'activePaneId': serializer.toJson<String?>(activePaneId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Template copyWith({
    String? id,
    String? workspaceId,
    String? name,
    Value<String?> description = const Value.absent(),
    Value<String?> activePaneId = const Value.absent(),
    DateTime? createdAt,
  }) => Template(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    activePaneId: activePaneId.present ? activePaneId.value : this.activePaneId,
    createdAt: createdAt ?? this.createdAt,
  );
  Template copyWithCompanion(TemplatesCompanion data) {
    return Template(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      activePaneId: data.activePaneId.present
          ? data.activePaneId.value
          : this.activePaneId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Template(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('activePaneId: $activePaneId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, workspaceId, name, description, activePaneId, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Template &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.name == this.name &&
          other.description == this.description &&
          other.activePaneId == this.activePaneId &&
          other.createdAt == this.createdAt);
}

class TemplatesCompanion extends UpdateCompanion<Template> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> name;
  final Value<String?> description;
  final Value<String?> activePaneId;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const TemplatesCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.activePaneId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TemplatesCompanion.insert({
    required String id,
    required String workspaceId,
    required String name,
    this.description = const Value.absent(),
    this.activePaneId = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       name = Value(name),
       createdAt = Value(createdAt);
  static Insertable<Template> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? activePaneId,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (activePaneId != null) 'active_pane_id': activePaneId,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TemplatesCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? name,
    Value<String?>? description,
    Value<String?>? activePaneId,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return TemplatesCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      description: description ?? this.description,
      activePaneId: activePaneId ?? this.activePaneId,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (activePaneId.present) {
      map['active_pane_id'] = Variable<String>(activePaneId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TemplatesCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('activePaneId: $activePaneId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TemplatePanesTable extends TemplatePanes
    with TableInfo<$TemplatePanesTable, TemplatePane> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TemplatePanesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _templateIdMeta = const VerificationMeta(
    'templateId',
  );
  @override
  late final GeneratedColumn<String> templateId = GeneratedColumn<String>(
    'template_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES templates (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _paneOrderMeta = const VerificationMeta(
    'paneOrder',
  );
  @override
  late final GeneratedColumn<int> paneOrder = GeneratedColumn<int>(
    'pane_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parentPaneIdMeta = const VerificationMeta(
    'parentPaneId',
  );
  @override
  late final GeneratedColumn<String> parentPaneId = GeneratedColumn<String>(
    'parent_pane_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _splitDirectionMeta = const VerificationMeta(
    'splitDirection',
  );
  @override
  late final GeneratedColumn<String> splitDirection = GeneratedColumn<String>(
    'split_direction',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _splitRatioMeta = const VerificationMeta(
    'splitRatio',
  );
  @override
  late final GeneratedColumn<double> splitRatio = GeneratedColumn<double>(
    'split_ratio',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.5),
  );
  static const VerificationMeta _sessionTypeMeta = const VerificationMeta(
    'sessionType',
  );
  @override
  late final GeneratedColumn<String> sessionType = GeneratedColumn<String>(
    'session_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostIdMeta = const VerificationMeta('hostId');
  @override
  late final GeneratedColumn<String> hostId = GeneratedColumn<String>(
    'host_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    templateId,
    paneOrder,
    parentPaneId,
    splitDirection,
    splitRatio,
    sessionType,
    hostId,
    title,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'template_panes';
  @override
  VerificationContext validateIntegrity(
    Insertable<TemplatePane> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('template_id')) {
      context.handle(
        _templateIdMeta,
        templateId.isAcceptableOrUnknown(data['template_id']!, _templateIdMeta),
      );
    } else if (isInserting) {
      context.missing(_templateIdMeta);
    }
    if (data.containsKey('pane_order')) {
      context.handle(
        _paneOrderMeta,
        paneOrder.isAcceptableOrUnknown(data['pane_order']!, _paneOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_paneOrderMeta);
    }
    if (data.containsKey('parent_pane_id')) {
      context.handle(
        _parentPaneIdMeta,
        parentPaneId.isAcceptableOrUnknown(
          data['parent_pane_id']!,
          _parentPaneIdMeta,
        ),
      );
    }
    if (data.containsKey('split_direction')) {
      context.handle(
        _splitDirectionMeta,
        splitDirection.isAcceptableOrUnknown(
          data['split_direction']!,
          _splitDirectionMeta,
        ),
      );
    }
    if (data.containsKey('split_ratio')) {
      context.handle(
        _splitRatioMeta,
        splitRatio.isAcceptableOrUnknown(data['split_ratio']!, _splitRatioMeta),
      );
    }
    if (data.containsKey('session_type')) {
      context.handle(
        _sessionTypeMeta,
        sessionType.isAcceptableOrUnknown(
          data['session_type']!,
          _sessionTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sessionTypeMeta);
    }
    if (data.containsKey('host_id')) {
      context.handle(
        _hostIdMeta,
        hostId.isAcceptableOrUnknown(data['host_id']!, _hostIdMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TemplatePane map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TemplatePane(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      templateId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}template_id'],
      )!,
      paneOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pane_order'],
      )!,
      parentPaneId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_pane_id'],
      ),
      splitDirection: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}split_direction'],
      ),
      splitRatio: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}split_ratio'],
      )!,
      sessionType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_type'],
      )!,
      hostId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_id'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
    );
  }

  @override
  $TemplatePanesTable createAlias(String alias) {
    return $TemplatePanesTable(attachedDatabase, alias);
  }
}

class TemplatePane extends DataClass implements Insertable<TemplatePane> {
  final String id;
  final String templateId;
  final int paneOrder;

  /// Template-local reference to another pane of the same template.
  ///
  /// Deliberately not a foreign key: panes are always written and deleted as
  /// one batch per template, and a self-referencing FK would impose insert
  /// ordering constraints on that batch for no benefit.
  final String? parentPaneId;
  final String? splitDirection;
  final double splitRatio;
  final String sessionType;

  /// Host this pane connected to, or null for a local shell.
  ///
  /// Deliberately **not** a foreign key to [Hosts]: deleting a host must not
  /// silently rewrite or delete saved templates. A pane whose host no longer
  /// exists is skipped with a warning when the template runs.
  final String? hostId;
  final String? title;
  const TemplatePane({
    required this.id,
    required this.templateId,
    required this.paneOrder,
    this.parentPaneId,
    this.splitDirection,
    required this.splitRatio,
    required this.sessionType,
    this.hostId,
    this.title,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['template_id'] = Variable<String>(templateId);
    map['pane_order'] = Variable<int>(paneOrder);
    if (!nullToAbsent || parentPaneId != null) {
      map['parent_pane_id'] = Variable<String>(parentPaneId);
    }
    if (!nullToAbsent || splitDirection != null) {
      map['split_direction'] = Variable<String>(splitDirection);
    }
    map['split_ratio'] = Variable<double>(splitRatio);
    map['session_type'] = Variable<String>(sessionType);
    if (!nullToAbsent || hostId != null) {
      map['host_id'] = Variable<String>(hostId);
    }
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    return map;
  }

  TemplatePanesCompanion toCompanion(bool nullToAbsent) {
    return TemplatePanesCompanion(
      id: Value(id),
      templateId: Value(templateId),
      paneOrder: Value(paneOrder),
      parentPaneId: parentPaneId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentPaneId),
      splitDirection: splitDirection == null && nullToAbsent
          ? const Value.absent()
          : Value(splitDirection),
      splitRatio: Value(splitRatio),
      sessionType: Value(sessionType),
      hostId: hostId == null && nullToAbsent
          ? const Value.absent()
          : Value(hostId),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
    );
  }

  factory TemplatePane.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TemplatePane(
      id: serializer.fromJson<String>(json['id']),
      templateId: serializer.fromJson<String>(json['templateId']),
      paneOrder: serializer.fromJson<int>(json['paneOrder']),
      parentPaneId: serializer.fromJson<String?>(json['parentPaneId']),
      splitDirection: serializer.fromJson<String?>(json['splitDirection']),
      splitRatio: serializer.fromJson<double>(json['splitRatio']),
      sessionType: serializer.fromJson<String>(json['sessionType']),
      hostId: serializer.fromJson<String?>(json['hostId']),
      title: serializer.fromJson<String?>(json['title']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'templateId': serializer.toJson<String>(templateId),
      'paneOrder': serializer.toJson<int>(paneOrder),
      'parentPaneId': serializer.toJson<String?>(parentPaneId),
      'splitDirection': serializer.toJson<String?>(splitDirection),
      'splitRatio': serializer.toJson<double>(splitRatio),
      'sessionType': serializer.toJson<String>(sessionType),
      'hostId': serializer.toJson<String?>(hostId),
      'title': serializer.toJson<String?>(title),
    };
  }

  TemplatePane copyWith({
    String? id,
    String? templateId,
    int? paneOrder,
    Value<String?> parentPaneId = const Value.absent(),
    Value<String?> splitDirection = const Value.absent(),
    double? splitRatio,
    String? sessionType,
    Value<String?> hostId = const Value.absent(),
    Value<String?> title = const Value.absent(),
  }) => TemplatePane(
    id: id ?? this.id,
    templateId: templateId ?? this.templateId,
    paneOrder: paneOrder ?? this.paneOrder,
    parentPaneId: parentPaneId.present ? parentPaneId.value : this.parentPaneId,
    splitDirection: splitDirection.present
        ? splitDirection.value
        : this.splitDirection,
    splitRatio: splitRatio ?? this.splitRatio,
    sessionType: sessionType ?? this.sessionType,
    hostId: hostId.present ? hostId.value : this.hostId,
    title: title.present ? title.value : this.title,
  );
  TemplatePane copyWithCompanion(TemplatePanesCompanion data) {
    return TemplatePane(
      id: data.id.present ? data.id.value : this.id,
      templateId: data.templateId.present
          ? data.templateId.value
          : this.templateId,
      paneOrder: data.paneOrder.present ? data.paneOrder.value : this.paneOrder,
      parentPaneId: data.parentPaneId.present
          ? data.parentPaneId.value
          : this.parentPaneId,
      splitDirection: data.splitDirection.present
          ? data.splitDirection.value
          : this.splitDirection,
      splitRatio: data.splitRatio.present
          ? data.splitRatio.value
          : this.splitRatio,
      sessionType: data.sessionType.present
          ? data.sessionType.value
          : this.sessionType,
      hostId: data.hostId.present ? data.hostId.value : this.hostId,
      title: data.title.present ? data.title.value : this.title,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TemplatePane(')
          ..write('id: $id, ')
          ..write('templateId: $templateId, ')
          ..write('paneOrder: $paneOrder, ')
          ..write('parentPaneId: $parentPaneId, ')
          ..write('splitDirection: $splitDirection, ')
          ..write('splitRatio: $splitRatio, ')
          ..write('sessionType: $sessionType, ')
          ..write('hostId: $hostId, ')
          ..write('title: $title')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    templateId,
    paneOrder,
    parentPaneId,
    splitDirection,
    splitRatio,
    sessionType,
    hostId,
    title,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TemplatePane &&
          other.id == this.id &&
          other.templateId == this.templateId &&
          other.paneOrder == this.paneOrder &&
          other.parentPaneId == this.parentPaneId &&
          other.splitDirection == this.splitDirection &&
          other.splitRatio == this.splitRatio &&
          other.sessionType == this.sessionType &&
          other.hostId == this.hostId &&
          other.title == this.title);
}

class TemplatePanesCompanion extends UpdateCompanion<TemplatePane> {
  final Value<String> id;
  final Value<String> templateId;
  final Value<int> paneOrder;
  final Value<String?> parentPaneId;
  final Value<String?> splitDirection;
  final Value<double> splitRatio;
  final Value<String> sessionType;
  final Value<String?> hostId;
  final Value<String?> title;
  final Value<int> rowid;
  const TemplatePanesCompanion({
    this.id = const Value.absent(),
    this.templateId = const Value.absent(),
    this.paneOrder = const Value.absent(),
    this.parentPaneId = const Value.absent(),
    this.splitDirection = const Value.absent(),
    this.splitRatio = const Value.absent(),
    this.sessionType = const Value.absent(),
    this.hostId = const Value.absent(),
    this.title = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TemplatePanesCompanion.insert({
    required String id,
    required String templateId,
    required int paneOrder,
    this.parentPaneId = const Value.absent(),
    this.splitDirection = const Value.absent(),
    this.splitRatio = const Value.absent(),
    required String sessionType,
    this.hostId = const Value.absent(),
    this.title = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       templateId = Value(templateId),
       paneOrder = Value(paneOrder),
       sessionType = Value(sessionType);
  static Insertable<TemplatePane> custom({
    Expression<String>? id,
    Expression<String>? templateId,
    Expression<int>? paneOrder,
    Expression<String>? parentPaneId,
    Expression<String>? splitDirection,
    Expression<double>? splitRatio,
    Expression<String>? sessionType,
    Expression<String>? hostId,
    Expression<String>? title,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (templateId != null) 'template_id': templateId,
      if (paneOrder != null) 'pane_order': paneOrder,
      if (parentPaneId != null) 'parent_pane_id': parentPaneId,
      if (splitDirection != null) 'split_direction': splitDirection,
      if (splitRatio != null) 'split_ratio': splitRatio,
      if (sessionType != null) 'session_type': sessionType,
      if (hostId != null) 'host_id': hostId,
      if (title != null) 'title': title,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TemplatePanesCompanion copyWith({
    Value<String>? id,
    Value<String>? templateId,
    Value<int>? paneOrder,
    Value<String?>? parentPaneId,
    Value<String?>? splitDirection,
    Value<double>? splitRatio,
    Value<String>? sessionType,
    Value<String?>? hostId,
    Value<String?>? title,
    Value<int>? rowid,
  }) {
    return TemplatePanesCompanion(
      id: id ?? this.id,
      templateId: templateId ?? this.templateId,
      paneOrder: paneOrder ?? this.paneOrder,
      parentPaneId: parentPaneId ?? this.parentPaneId,
      splitDirection: splitDirection ?? this.splitDirection,
      splitRatio: splitRatio ?? this.splitRatio,
      sessionType: sessionType ?? this.sessionType,
      hostId: hostId ?? this.hostId,
      title: title ?? this.title,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (templateId.present) {
      map['template_id'] = Variable<String>(templateId.value);
    }
    if (paneOrder.present) {
      map['pane_order'] = Variable<int>(paneOrder.value);
    }
    if (parentPaneId.present) {
      map['parent_pane_id'] = Variable<String>(parentPaneId.value);
    }
    if (splitDirection.present) {
      map['split_direction'] = Variable<String>(splitDirection.value);
    }
    if (splitRatio.present) {
      map['split_ratio'] = Variable<double>(splitRatio.value);
    }
    if (sessionType.present) {
      map['session_type'] = Variable<String>(sessionType.value);
    }
    if (hostId.present) {
      map['host_id'] = Variable<String>(hostId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TemplatePanesCompanion(')
          ..write('id: $id, ')
          ..write('templateId: $templateId, ')
          ..write('paneOrder: $paneOrder, ')
          ..write('parentPaneId: $parentPaneId, ')
          ..write('splitDirection: $splitDirection, ')
          ..write('splitRatio: $splitRatio, ')
          ..write('sessionType: $sessionType, ')
          ..write('hostId: $hostId, ')
          ..write('title: $title, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PairedDevicesTable extends PairedDevices
    with TableInfo<$PairedDevicesTable, PairedDevice> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PairedDevicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _platformMeta = const VerificationMeta(
    'platform',
  );
  @override
  late final GeneratedColumn<String> platform = GeneratedColumn<String>(
    'platform',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _secretHashMeta = const VerificationMeta(
    'secretHash',
  );
  @override
  late final GeneratedColumn<String> secretHash = GeneratedColumn<String>(
    'secret_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _publicKeyMeta = const VerificationMeta(
    'publicKey',
  );
  @override
  late final GeneratedColumn<String> publicKey = GeneratedColumn<String>(
    'public_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pairedAtMeta = const VerificationMeta(
    'pairedAt',
  );
  @override
  late final GeneratedColumn<DateTime> pairedAt = GeneratedColumn<DateTime>(
    'paired_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSeenAtMeta = const VerificationMeta(
    'lastSeenAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeenAt = GeneratedColumn<DateTime>(
    'last_seen_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    platform,
    secretHash,
    publicKey,
    pairedAt,
    lastSeenAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'paired_devices';
  @override
  VerificationContext validateIntegrity(
    Insertable<PairedDevice> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('platform')) {
      context.handle(
        _platformMeta,
        platform.isAcceptableOrUnknown(data['platform']!, _platformMeta),
      );
    } else if (isInserting) {
      context.missing(_platformMeta);
    }
    if (data.containsKey('secret_hash')) {
      context.handle(
        _secretHashMeta,
        secretHash.isAcceptableOrUnknown(data['secret_hash']!, _secretHashMeta),
      );
    } else if (isInserting) {
      context.missing(_secretHashMeta);
    }
    if (data.containsKey('public_key')) {
      context.handle(
        _publicKeyMeta,
        publicKey.isAcceptableOrUnknown(data['public_key']!, _publicKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_publicKeyMeta);
    }
    if (data.containsKey('paired_at')) {
      context.handle(
        _pairedAtMeta,
        pairedAt.isAcceptableOrUnknown(data['paired_at']!, _pairedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_pairedAtMeta);
    }
    if (data.containsKey('last_seen_at')) {
      context.handle(
        _lastSeenAtMeta,
        lastSeenAt.isAcceptableOrUnknown(
          data['last_seen_at']!,
          _lastSeenAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastSeenAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PairedDevice map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PairedDevice(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      platform: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}platform'],
      )!,
      secretHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}secret_hash'],
      )!,
      publicKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}public_key'],
      )!,
      pairedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}paired_at'],
      )!,
      lastSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen_at'],
      )!,
    );
  }

  @override
  $PairedDevicesTable createAlias(String alias) {
    return $PairedDevicesTable(attachedDatabase, alias);
  }
}

class PairedDevice extends DataClass implements Insertable<PairedDevice> {
  final String id;
  final String name;
  final String platform;
  final String secretHash;
  final String publicKey;
  final DateTime pairedAt;
  final DateTime lastSeenAt;
  const PairedDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.secretHash,
    required this.publicKey,
    required this.pairedAt,
    required this.lastSeenAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['platform'] = Variable<String>(platform);
    map['secret_hash'] = Variable<String>(secretHash);
    map['public_key'] = Variable<String>(publicKey);
    map['paired_at'] = Variable<DateTime>(pairedAt);
    map['last_seen_at'] = Variable<DateTime>(lastSeenAt);
    return map;
  }

  PairedDevicesCompanion toCompanion(bool nullToAbsent) {
    return PairedDevicesCompanion(
      id: Value(id),
      name: Value(name),
      platform: Value(platform),
      secretHash: Value(secretHash),
      publicKey: Value(publicKey),
      pairedAt: Value(pairedAt),
      lastSeenAt: Value(lastSeenAt),
    );
  }

  factory PairedDevice.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PairedDevice(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      platform: serializer.fromJson<String>(json['platform']),
      secretHash: serializer.fromJson<String>(json['secretHash']),
      publicKey: serializer.fromJson<String>(json['publicKey']),
      pairedAt: serializer.fromJson<DateTime>(json['pairedAt']),
      lastSeenAt: serializer.fromJson<DateTime>(json['lastSeenAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'platform': serializer.toJson<String>(platform),
      'secretHash': serializer.toJson<String>(secretHash),
      'publicKey': serializer.toJson<String>(publicKey),
      'pairedAt': serializer.toJson<DateTime>(pairedAt),
      'lastSeenAt': serializer.toJson<DateTime>(lastSeenAt),
    };
  }

  PairedDevice copyWith({
    String? id,
    String? name,
    String? platform,
    String? secretHash,
    String? publicKey,
    DateTime? pairedAt,
    DateTime? lastSeenAt,
  }) => PairedDevice(
    id: id ?? this.id,
    name: name ?? this.name,
    platform: platform ?? this.platform,
    secretHash: secretHash ?? this.secretHash,
    publicKey: publicKey ?? this.publicKey,
    pairedAt: pairedAt ?? this.pairedAt,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
  );
  PairedDevice copyWithCompanion(PairedDevicesCompanion data) {
    return PairedDevice(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      platform: data.platform.present ? data.platform.value : this.platform,
      secretHash: data.secretHash.present
          ? data.secretHash.value
          : this.secretHash,
      publicKey: data.publicKey.present ? data.publicKey.value : this.publicKey,
      pairedAt: data.pairedAt.present ? data.pairedAt.value : this.pairedAt,
      lastSeenAt: data.lastSeenAt.present
          ? data.lastSeenAt.value
          : this.lastSeenAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PairedDevice(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('platform: $platform, ')
          ..write('secretHash: $secretHash, ')
          ..write('publicKey: $publicKey, ')
          ..write('pairedAt: $pairedAt, ')
          ..write('lastSeenAt: $lastSeenAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    platform,
    secretHash,
    publicKey,
    pairedAt,
    lastSeenAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PairedDevice &&
          other.id == this.id &&
          other.name == this.name &&
          other.platform == this.platform &&
          other.secretHash == this.secretHash &&
          other.publicKey == this.publicKey &&
          other.pairedAt == this.pairedAt &&
          other.lastSeenAt == this.lastSeenAt);
}

class PairedDevicesCompanion extends UpdateCompanion<PairedDevice> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> platform;
  final Value<String> secretHash;
  final Value<String> publicKey;
  final Value<DateTime> pairedAt;
  final Value<DateTime> lastSeenAt;
  final Value<int> rowid;
  const PairedDevicesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.platform = const Value.absent(),
    this.secretHash = const Value.absent(),
    this.publicKey = const Value.absent(),
    this.pairedAt = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PairedDevicesCompanion.insert({
    required String id,
    required String name,
    required String platform,
    required String secretHash,
    required String publicKey,
    required DateTime pairedAt,
    required DateTime lastSeenAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       platform = Value(platform),
       secretHash = Value(secretHash),
       publicKey = Value(publicKey),
       pairedAt = Value(pairedAt),
       lastSeenAt = Value(lastSeenAt);
  static Insertable<PairedDevice> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? platform,
    Expression<String>? secretHash,
    Expression<String>? publicKey,
    Expression<DateTime>? pairedAt,
    Expression<DateTime>? lastSeenAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (platform != null) 'platform': platform,
      if (secretHash != null) 'secret_hash': secretHash,
      if (publicKey != null) 'public_key': publicKey,
      if (pairedAt != null) 'paired_at': pairedAt,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PairedDevicesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? platform,
    Value<String>? secretHash,
    Value<String>? publicKey,
    Value<DateTime>? pairedAt,
    Value<DateTime>? lastSeenAt,
    Value<int>? rowid,
  }) {
    return PairedDevicesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      secretHash: secretHash ?? this.secretHash,
      publicKey: publicKey ?? this.publicKey,
      pairedAt: pairedAt ?? this.pairedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (platform.present) {
      map['platform'] = Variable<String>(platform.value);
    }
    if (secretHash.present) {
      map['secret_hash'] = Variable<String>(secretHash.value);
    }
    if (publicKey.present) {
      map['public_key'] = Variable<String>(publicKey.value);
    }
    if (pairedAt.present) {
      map['paired_at'] = Variable<DateTime>(pairedAt.value);
    }
    if (lastSeenAt.present) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PairedDevicesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('platform: $platform, ')
          ..write('secretHash: $secretHash, ')
          ..write('publicKey: $publicKey, ')
          ..write('pairedAt: $pairedAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $McpClientsTable extends McpClients
    with TableInfo<$McpClientsTable, McpClient> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $McpClientsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES workspaces (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tokenHashMeta = const VerificationMeta(
    'tokenHash',
  );
  @override
  late final GeneratedColumn<String> tokenHash = GeneratedColumn<String>(
    'token_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSeenAtMeta = const VerificationMeta(
    'lastSeenAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeenAt = GeneratedColumn<DateTime>(
    'last_seen_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
    'expires_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _revokedAtMeta = const VerificationMeta(
    'revokedAt',
  );
  @override
  late final GeneratedColumn<DateTime> revokedAt = GeneratedColumn<DateTime>(
    'revoked_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    name,
    tokenHash,
    createdAt,
    lastSeenAt,
    expiresAt,
    revokedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mcp_clients';
  @override
  VerificationContext validateIntegrity(
    Insertable<McpClient> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('token_hash')) {
      context.handle(
        _tokenHashMeta,
        tokenHash.isAcceptableOrUnknown(data['token_hash']!, _tokenHashMeta),
      );
    } else if (isInserting) {
      context.missing(_tokenHashMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('last_seen_at')) {
      context.handle(
        _lastSeenAtMeta,
        lastSeenAt.isAcceptableOrUnknown(
          data['last_seen_at']!,
          _lastSeenAtMeta,
        ),
      );
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    }
    if (data.containsKey('revoked_at')) {
      context.handle(
        _revokedAtMeta,
        revokedAt.isAcceptableOrUnknown(data['revoked_at']!, _revokedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  McpClient map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return McpClient(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      tokenHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}token_hash'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      lastSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen_at'],
      ),
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expires_at'],
      ),
      revokedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}revoked_at'],
      ),
    );
  }

  @override
  $McpClientsTable createAlias(String alias) {
    return $McpClientsTable(attachedDatabase, alias);
  }
}

class McpClient extends DataClass implements Insertable<McpClient> {
  final String id;
  final String workspaceId;
  final String name;

  /// SHA-256 hash of the token — not Argon2id. The token is 32 bytes of
  /// CSPRNG output, so there is no dictionary-attack surface a slow KDF would
  /// defend against, and this hash is checked on every JSON-RPC request; a
  /// slow KDF would burn latency on every call for no security gain.
  final String tokenHash;
  final DateTime createdAt;
  final DateTime? lastSeenAt;
  final DateTime? expiresAt;
  final DateTime? revokedAt;
  const McpClient({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.tokenHash,
    required this.createdAt,
    this.lastSeenAt,
    this.expiresAt,
    this.revokedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['name'] = Variable<String>(name);
    map['token_hash'] = Variable<String>(tokenHash);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || lastSeenAt != null) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt);
    }
    if (!nullToAbsent || expiresAt != null) {
      map['expires_at'] = Variable<DateTime>(expiresAt);
    }
    if (!nullToAbsent || revokedAt != null) {
      map['revoked_at'] = Variable<DateTime>(revokedAt);
    }
    return map;
  }

  McpClientsCompanion toCompanion(bool nullToAbsent) {
    return McpClientsCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      name: Value(name),
      tokenHash: Value(tokenHash),
      createdAt: Value(createdAt),
      lastSeenAt: lastSeenAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSeenAt),
      expiresAt: expiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresAt),
      revokedAt: revokedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(revokedAt),
    );
  }

  factory McpClient.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return McpClient(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      name: serializer.fromJson<String>(json['name']),
      tokenHash: serializer.fromJson<String>(json['tokenHash']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastSeenAt: serializer.fromJson<DateTime?>(json['lastSeenAt']),
      expiresAt: serializer.fromJson<DateTime?>(json['expiresAt']),
      revokedAt: serializer.fromJson<DateTime?>(json['revokedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'name': serializer.toJson<String>(name),
      'tokenHash': serializer.toJson<String>(tokenHash),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastSeenAt': serializer.toJson<DateTime?>(lastSeenAt),
      'expiresAt': serializer.toJson<DateTime?>(expiresAt),
      'revokedAt': serializer.toJson<DateTime?>(revokedAt),
    };
  }

  McpClient copyWith({
    String? id,
    String? workspaceId,
    String? name,
    String? tokenHash,
    DateTime? createdAt,
    Value<DateTime?> lastSeenAt = const Value.absent(),
    Value<DateTime?> expiresAt = const Value.absent(),
    Value<DateTime?> revokedAt = const Value.absent(),
  }) => McpClient(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    name: name ?? this.name,
    tokenHash: tokenHash ?? this.tokenHash,
    createdAt: createdAt ?? this.createdAt,
    lastSeenAt: lastSeenAt.present ? lastSeenAt.value : this.lastSeenAt,
    expiresAt: expiresAt.present ? expiresAt.value : this.expiresAt,
    revokedAt: revokedAt.present ? revokedAt.value : this.revokedAt,
  );
  McpClient copyWithCompanion(McpClientsCompanion data) {
    return McpClient(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      name: data.name.present ? data.name.value : this.name,
      tokenHash: data.tokenHash.present ? data.tokenHash.value : this.tokenHash,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastSeenAt: data.lastSeenAt.present
          ? data.lastSeenAt.value
          : this.lastSeenAt,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      revokedAt: data.revokedAt.present ? data.revokedAt.value : this.revokedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('McpClient(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('name: $name, ')
          ..write('tokenHash: $tokenHash, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('revokedAt: $revokedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    name,
    tokenHash,
    createdAt,
    lastSeenAt,
    expiresAt,
    revokedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is McpClient &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.name == this.name &&
          other.tokenHash == this.tokenHash &&
          other.createdAt == this.createdAt &&
          other.lastSeenAt == this.lastSeenAt &&
          other.expiresAt == this.expiresAt &&
          other.revokedAt == this.revokedAt);
}

class McpClientsCompanion extends UpdateCompanion<McpClient> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> name;
  final Value<String> tokenHash;
  final Value<DateTime> createdAt;
  final Value<DateTime?> lastSeenAt;
  final Value<DateTime?> expiresAt;
  final Value<DateTime?> revokedAt;
  final Value<int> rowid;
  const McpClientsCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.name = const Value.absent(),
    this.tokenHash = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.revokedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  McpClientsCompanion.insert({
    required String id,
    required String workspaceId,
    required String name,
    required String tokenHash,
    required DateTime createdAt,
    this.lastSeenAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.revokedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       name = Value(name),
       tokenHash = Value(tokenHash),
       createdAt = Value(createdAt);
  static Insertable<McpClient> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? name,
    Expression<String>? tokenHash,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? lastSeenAt,
    Expression<DateTime>? expiresAt,
    Expression<DateTime>? revokedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (name != null) 'name': name,
      if (tokenHash != null) 'token_hash': tokenHash,
      if (createdAt != null) 'created_at': createdAt,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (revokedAt != null) 'revoked_at': revokedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  McpClientsCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? name,
    Value<String>? tokenHash,
    Value<DateTime>? createdAt,
    Value<DateTime?>? lastSeenAt,
    Value<DateTime?>? expiresAt,
    Value<DateTime?>? revokedAt,
    Value<int>? rowid,
  }) {
    return McpClientsCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      tokenHash: tokenHash ?? this.tokenHash,
      createdAt: createdAt ?? this.createdAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      expiresAt: expiresAt ?? this.expiresAt,
      revokedAt: revokedAt ?? this.revokedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (tokenHash.present) {
      map['token_hash'] = Variable<String>(tokenHash.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastSeenAt.present) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
    }
    if (revokedAt.present) {
      map['revoked_at'] = Variable<DateTime>(revokedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('McpClientsCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('name: $name, ')
          ..write('tokenHash: $tokenHash, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('revokedAt: $revokedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $McpHostGrantsTable extends McpHostGrants
    with TableInfo<$McpHostGrantsTable, McpHostGrant> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $McpHostGrantsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clientIdMeta = const VerificationMeta(
    'clientId',
  );
  @override
  late final GeneratedColumn<String> clientId = GeneratedColumn<String>(
    'client_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES mcp_clients (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _hostIdMeta = const VerificationMeta('hostId');
  @override
  late final GeneratedColumn<String> hostId = GeneratedColumn<String>(
    'host_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES hosts (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _grantedAtMeta = const VerificationMeta(
    'grantedAt',
  );
  @override
  late final GeneratedColumn<DateTime> grantedAt = GeneratedColumn<DateTime>(
    'granted_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
    'expires_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _connectionScopeIdMeta = const VerificationMeta(
    'connectionScopeId',
  );
  @override
  late final GeneratedColumn<String> connectionScopeId =
      GeneratedColumn<String>(
        'connection_scope_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _cooldownUntilMeta = const VerificationMeta(
    'cooldownUntil',
  );
  @override
  late final GeneratedColumn<DateTime> cooldownUntil =
      GeneratedColumn<DateTime>(
        'cooldown_until',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    clientId,
    hostId,
    mode,
    grantedAt,
    expiresAt,
    connectionScopeId,
    cooldownUntil,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mcp_host_grants';
  @override
  VerificationContext validateIntegrity(
    Insertable<McpHostGrant> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('client_id')) {
      context.handle(
        _clientIdMeta,
        clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta),
      );
    } else if (isInserting) {
      context.missing(_clientIdMeta);
    }
    if (data.containsKey('host_id')) {
      context.handle(
        _hostIdMeta,
        hostId.isAcceptableOrUnknown(data['host_id']!, _hostIdMeta),
      );
    } else if (isInserting) {
      context.missing(_hostIdMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('granted_at')) {
      context.handle(
        _grantedAtMeta,
        grantedAt.isAcceptableOrUnknown(data['granted_at']!, _grantedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_grantedAtMeta);
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    }
    if (data.containsKey('connection_scope_id')) {
      context.handle(
        _connectionScopeIdMeta,
        connectionScopeId.isAcceptableOrUnknown(
          data['connection_scope_id']!,
          _connectionScopeIdMeta,
        ),
      );
    }
    if (data.containsKey('cooldown_until')) {
      context.handle(
        _cooldownUntilMeta,
        cooldownUntil.isAcceptableOrUnknown(
          data['cooldown_until']!,
          _cooldownUntilMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  McpHostGrant map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return McpHostGrant(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      clientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_id'],
      )!,
      hostId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_id'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      grantedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}granted_at'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expires_at'],
      ),
      connectionScopeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}connection_scope_id'],
      ),
      cooldownUntil: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cooldown_until'],
      ),
    );
  }

  @override
  $McpHostGrantsTable createAlias(String alias) {
    return $McpHostGrantsTable(attachedDatabase, alias);
  }
}

class McpHostGrant extends DataClass implements Insertable<McpHostGrant> {
  final String id;
  final String clientId;
  final String hostId;
  final String mode;
  final DateTime grantedAt;

  /// Null means a permanent grant. Otherwise the grant is invalid from this
  /// instant on.
  final DateTime? expiresAt;

  /// "This session" scope: the row is deleted once the MCP connection it was
  /// granted under drops.
  final String? connectionScopeId;

  /// Cooldown after a denied request. New requests are silently denied until
  /// this instant, so the agent can't loop and bury the user in approval
  /// windows.
  final DateTime? cooldownUntil;
  const McpHostGrant({
    required this.id,
    required this.clientId,
    required this.hostId,
    required this.mode,
    required this.grantedAt,
    this.expiresAt,
    this.connectionScopeId,
    this.cooldownUntil,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['client_id'] = Variable<String>(clientId);
    map['host_id'] = Variable<String>(hostId);
    map['mode'] = Variable<String>(mode);
    map['granted_at'] = Variable<DateTime>(grantedAt);
    if (!nullToAbsent || expiresAt != null) {
      map['expires_at'] = Variable<DateTime>(expiresAt);
    }
    if (!nullToAbsent || connectionScopeId != null) {
      map['connection_scope_id'] = Variable<String>(connectionScopeId);
    }
    if (!nullToAbsent || cooldownUntil != null) {
      map['cooldown_until'] = Variable<DateTime>(cooldownUntil);
    }
    return map;
  }

  McpHostGrantsCompanion toCompanion(bool nullToAbsent) {
    return McpHostGrantsCompanion(
      id: Value(id),
      clientId: Value(clientId),
      hostId: Value(hostId),
      mode: Value(mode),
      grantedAt: Value(grantedAt),
      expiresAt: expiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresAt),
      connectionScopeId: connectionScopeId == null && nullToAbsent
          ? const Value.absent()
          : Value(connectionScopeId),
      cooldownUntil: cooldownUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(cooldownUntil),
    );
  }

  factory McpHostGrant.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return McpHostGrant(
      id: serializer.fromJson<String>(json['id']),
      clientId: serializer.fromJson<String>(json['clientId']),
      hostId: serializer.fromJson<String>(json['hostId']),
      mode: serializer.fromJson<String>(json['mode']),
      grantedAt: serializer.fromJson<DateTime>(json['grantedAt']),
      expiresAt: serializer.fromJson<DateTime?>(json['expiresAt']),
      connectionScopeId: serializer.fromJson<String?>(
        json['connectionScopeId'],
      ),
      cooldownUntil: serializer.fromJson<DateTime?>(json['cooldownUntil']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'clientId': serializer.toJson<String>(clientId),
      'hostId': serializer.toJson<String>(hostId),
      'mode': serializer.toJson<String>(mode),
      'grantedAt': serializer.toJson<DateTime>(grantedAt),
      'expiresAt': serializer.toJson<DateTime?>(expiresAt),
      'connectionScopeId': serializer.toJson<String?>(connectionScopeId),
      'cooldownUntil': serializer.toJson<DateTime?>(cooldownUntil),
    };
  }

  McpHostGrant copyWith({
    String? id,
    String? clientId,
    String? hostId,
    String? mode,
    DateTime? grantedAt,
    Value<DateTime?> expiresAt = const Value.absent(),
    Value<String?> connectionScopeId = const Value.absent(),
    Value<DateTime?> cooldownUntil = const Value.absent(),
  }) => McpHostGrant(
    id: id ?? this.id,
    clientId: clientId ?? this.clientId,
    hostId: hostId ?? this.hostId,
    mode: mode ?? this.mode,
    grantedAt: grantedAt ?? this.grantedAt,
    expiresAt: expiresAt.present ? expiresAt.value : this.expiresAt,
    connectionScopeId: connectionScopeId.present
        ? connectionScopeId.value
        : this.connectionScopeId,
    cooldownUntil: cooldownUntil.present
        ? cooldownUntil.value
        : this.cooldownUntil,
  );
  McpHostGrant copyWithCompanion(McpHostGrantsCompanion data) {
    return McpHostGrant(
      id: data.id.present ? data.id.value : this.id,
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      hostId: data.hostId.present ? data.hostId.value : this.hostId,
      mode: data.mode.present ? data.mode.value : this.mode,
      grantedAt: data.grantedAt.present ? data.grantedAt.value : this.grantedAt,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      connectionScopeId: data.connectionScopeId.present
          ? data.connectionScopeId.value
          : this.connectionScopeId,
      cooldownUntil: data.cooldownUntil.present
          ? data.cooldownUntil.value
          : this.cooldownUntil,
    );
  }

  @override
  String toString() {
    return (StringBuffer('McpHostGrant(')
          ..write('id: $id, ')
          ..write('clientId: $clientId, ')
          ..write('hostId: $hostId, ')
          ..write('mode: $mode, ')
          ..write('grantedAt: $grantedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('connectionScopeId: $connectionScopeId, ')
          ..write('cooldownUntil: $cooldownUntil')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    clientId,
    hostId,
    mode,
    grantedAt,
    expiresAt,
    connectionScopeId,
    cooldownUntil,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is McpHostGrant &&
          other.id == this.id &&
          other.clientId == this.clientId &&
          other.hostId == this.hostId &&
          other.mode == this.mode &&
          other.grantedAt == this.grantedAt &&
          other.expiresAt == this.expiresAt &&
          other.connectionScopeId == this.connectionScopeId &&
          other.cooldownUntil == this.cooldownUntil);
}

class McpHostGrantsCompanion extends UpdateCompanion<McpHostGrant> {
  final Value<String> id;
  final Value<String> clientId;
  final Value<String> hostId;
  final Value<String> mode;
  final Value<DateTime> grantedAt;
  final Value<DateTime?> expiresAt;
  final Value<String?> connectionScopeId;
  final Value<DateTime?> cooldownUntil;
  final Value<int> rowid;
  const McpHostGrantsCompanion({
    this.id = const Value.absent(),
    this.clientId = const Value.absent(),
    this.hostId = const Value.absent(),
    this.mode = const Value.absent(),
    this.grantedAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.connectionScopeId = const Value.absent(),
    this.cooldownUntil = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  McpHostGrantsCompanion.insert({
    required String id,
    required String clientId,
    required String hostId,
    required String mode,
    required DateTime grantedAt,
    this.expiresAt = const Value.absent(),
    this.connectionScopeId = const Value.absent(),
    this.cooldownUntil = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       clientId = Value(clientId),
       hostId = Value(hostId),
       mode = Value(mode),
       grantedAt = Value(grantedAt);
  static Insertable<McpHostGrant> custom({
    Expression<String>? id,
    Expression<String>? clientId,
    Expression<String>? hostId,
    Expression<String>? mode,
    Expression<DateTime>? grantedAt,
    Expression<DateTime>? expiresAt,
    Expression<String>? connectionScopeId,
    Expression<DateTime>? cooldownUntil,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (clientId != null) 'client_id': clientId,
      if (hostId != null) 'host_id': hostId,
      if (mode != null) 'mode': mode,
      if (grantedAt != null) 'granted_at': grantedAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (connectionScopeId != null) 'connection_scope_id': connectionScopeId,
      if (cooldownUntil != null) 'cooldown_until': cooldownUntil,
      if (rowid != null) 'rowid': rowid,
    });
  }

  McpHostGrantsCompanion copyWith({
    Value<String>? id,
    Value<String>? clientId,
    Value<String>? hostId,
    Value<String>? mode,
    Value<DateTime>? grantedAt,
    Value<DateTime?>? expiresAt,
    Value<String?>? connectionScopeId,
    Value<DateTime?>? cooldownUntil,
    Value<int>? rowid,
  }) {
    return McpHostGrantsCompanion(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      hostId: hostId ?? this.hostId,
      mode: mode ?? this.mode,
      grantedAt: grantedAt ?? this.grantedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      connectionScopeId: connectionScopeId ?? this.connectionScopeId,
      cooldownUntil: cooldownUntil ?? this.cooldownUntil,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (hostId.present) {
      map['host_id'] = Variable<String>(hostId.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (grantedAt.present) {
      map['granted_at'] = Variable<DateTime>(grantedAt.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
    }
    if (connectionScopeId.present) {
      map['connection_scope_id'] = Variable<String>(connectionScopeId.value);
    }
    if (cooldownUntil.present) {
      map['cooldown_until'] = Variable<DateTime>(cooldownUntil.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('McpHostGrantsCompanion(')
          ..write('id: $id, ')
          ..write('clientId: $clientId, ')
          ..write('hostId: $hostId, ')
          ..write('mode: $mode, ')
          ..write('grantedAt: $grantedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('connectionScopeId: $connectionScopeId, ')
          ..write('cooldownUntil: $cooldownUntil, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $McpPolicyRulesTable extends McpPolicyRules
    with TableInfo<$McpPolicyRulesTable, McpPolicyRule> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $McpPolicyRulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES workspaces (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _scopeTypeMeta = const VerificationMeta(
    'scopeType',
  );
  @override
  late final GeneratedColumn<String> scopeType = GeneratedColumn<String>(
    'scope_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scopeIdMeta = const VerificationMeta(
    'scopeId',
  );
  @override
  late final GeneratedColumn<String> scopeId = GeneratedColumn<String>(
    'scope_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _matchTypeMeta = const VerificationMeta(
    'matchType',
  );
  @override
  late final GeneratedColumn<String> matchType = GeneratedColumn<String>(
    'match_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _patternMeta = const VerificationMeta(
    'pattern',
  );
  @override
  late final GeneratedColumn<String> pattern = GeneratedColumn<String>(
    'pattern',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    scopeType,
    scopeId,
    matchType,
    pattern,
    action,
    priority,
    enabled,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mcp_policy_rules';
  @override
  VerificationContext validateIntegrity(
    Insertable<McpPolicyRule> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('scope_type')) {
      context.handle(
        _scopeTypeMeta,
        scopeType.isAcceptableOrUnknown(data['scope_type']!, _scopeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeTypeMeta);
    }
    if (data.containsKey('scope_id')) {
      context.handle(
        _scopeIdMeta,
        scopeId.isAcceptableOrUnknown(data['scope_id']!, _scopeIdMeta),
      );
    }
    if (data.containsKey('match_type')) {
      context.handle(
        _matchTypeMeta,
        matchType.isAcceptableOrUnknown(data['match_type']!, _matchTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_matchTypeMeta);
    }
    if (data.containsKey('pattern')) {
      context.handle(
        _patternMeta,
        pattern.isAcceptableOrUnknown(data['pattern']!, _patternMeta),
      );
    } else if (isInserting) {
      context.missing(_patternMeta);
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    } else if (isInserting) {
      context.missing(_priorityMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  McpPolicyRule map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return McpPolicyRule(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      scopeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope_type'],
      )!,
      scopeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope_id'],
      ),
      matchType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}match_type'],
      )!,
      pattern: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pattern'],
      )!,
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $McpPolicyRulesTable createAlias(String alias) {
    return $McpPolicyRulesTable(attachedDatabase, alias);
  }
}

class McpPolicyRule extends DataClass implements Insertable<McpPolicyRule> {
  final String id;
  final String workspaceId;
  final String scopeType;
  final String? scopeId;
  final String matchType;
  final String pattern;
  final String action;
  final int priority;
  final bool enabled;
  final DateTime createdAt;
  const McpPolicyRule({
    required this.id,
    required this.workspaceId,
    required this.scopeType,
    this.scopeId,
    required this.matchType,
    required this.pattern,
    required this.action,
    required this.priority,
    required this.enabled,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['scope_type'] = Variable<String>(scopeType);
    if (!nullToAbsent || scopeId != null) {
      map['scope_id'] = Variable<String>(scopeId);
    }
    map['match_type'] = Variable<String>(matchType);
    map['pattern'] = Variable<String>(pattern);
    map['action'] = Variable<String>(action);
    map['priority'] = Variable<int>(priority);
    map['enabled'] = Variable<bool>(enabled);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  McpPolicyRulesCompanion toCompanion(bool nullToAbsent) {
    return McpPolicyRulesCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      scopeType: Value(scopeType),
      scopeId: scopeId == null && nullToAbsent
          ? const Value.absent()
          : Value(scopeId),
      matchType: Value(matchType),
      pattern: Value(pattern),
      action: Value(action),
      priority: Value(priority),
      enabled: Value(enabled),
      createdAt: Value(createdAt),
    );
  }

  factory McpPolicyRule.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return McpPolicyRule(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      scopeType: serializer.fromJson<String>(json['scopeType']),
      scopeId: serializer.fromJson<String?>(json['scopeId']),
      matchType: serializer.fromJson<String>(json['matchType']),
      pattern: serializer.fromJson<String>(json['pattern']),
      action: serializer.fromJson<String>(json['action']),
      priority: serializer.fromJson<int>(json['priority']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'scopeType': serializer.toJson<String>(scopeType),
      'scopeId': serializer.toJson<String?>(scopeId),
      'matchType': serializer.toJson<String>(matchType),
      'pattern': serializer.toJson<String>(pattern),
      'action': serializer.toJson<String>(action),
      'priority': serializer.toJson<int>(priority),
      'enabled': serializer.toJson<bool>(enabled),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  McpPolicyRule copyWith({
    String? id,
    String? workspaceId,
    String? scopeType,
    Value<String?> scopeId = const Value.absent(),
    String? matchType,
    String? pattern,
    String? action,
    int? priority,
    bool? enabled,
    DateTime? createdAt,
  }) => McpPolicyRule(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    scopeType: scopeType ?? this.scopeType,
    scopeId: scopeId.present ? scopeId.value : this.scopeId,
    matchType: matchType ?? this.matchType,
    pattern: pattern ?? this.pattern,
    action: action ?? this.action,
    priority: priority ?? this.priority,
    enabled: enabled ?? this.enabled,
    createdAt: createdAt ?? this.createdAt,
  );
  McpPolicyRule copyWithCompanion(McpPolicyRulesCompanion data) {
    return McpPolicyRule(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      scopeType: data.scopeType.present ? data.scopeType.value : this.scopeType,
      scopeId: data.scopeId.present ? data.scopeId.value : this.scopeId,
      matchType: data.matchType.present ? data.matchType.value : this.matchType,
      pattern: data.pattern.present ? data.pattern.value : this.pattern,
      action: data.action.present ? data.action.value : this.action,
      priority: data.priority.present ? data.priority.value : this.priority,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('McpPolicyRule(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('scopeType: $scopeType, ')
          ..write('scopeId: $scopeId, ')
          ..write('matchType: $matchType, ')
          ..write('pattern: $pattern, ')
          ..write('action: $action, ')
          ..write('priority: $priority, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    scopeType,
    scopeId,
    matchType,
    pattern,
    action,
    priority,
    enabled,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is McpPolicyRule &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.scopeType == this.scopeType &&
          other.scopeId == this.scopeId &&
          other.matchType == this.matchType &&
          other.pattern == this.pattern &&
          other.action == this.action &&
          other.priority == this.priority &&
          other.enabled == this.enabled &&
          other.createdAt == this.createdAt);
}

class McpPolicyRulesCompanion extends UpdateCompanion<McpPolicyRule> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> scopeType;
  final Value<String?> scopeId;
  final Value<String> matchType;
  final Value<String> pattern;
  final Value<String> action;
  final Value<int> priority;
  final Value<bool> enabled;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const McpPolicyRulesCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.scopeType = const Value.absent(),
    this.scopeId = const Value.absent(),
    this.matchType = const Value.absent(),
    this.pattern = const Value.absent(),
    this.action = const Value.absent(),
    this.priority = const Value.absent(),
    this.enabled = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  McpPolicyRulesCompanion.insert({
    required String id,
    required String workspaceId,
    required String scopeType,
    this.scopeId = const Value.absent(),
    required String matchType,
    required String pattern,
    required String action,
    required int priority,
    this.enabled = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       scopeType = Value(scopeType),
       matchType = Value(matchType),
       pattern = Value(pattern),
       action = Value(action),
       priority = Value(priority),
       createdAt = Value(createdAt);
  static Insertable<McpPolicyRule> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? scopeType,
    Expression<String>? scopeId,
    Expression<String>? matchType,
    Expression<String>? pattern,
    Expression<String>? action,
    Expression<int>? priority,
    Expression<bool>? enabled,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (scopeType != null) 'scope_type': scopeType,
      if (scopeId != null) 'scope_id': scopeId,
      if (matchType != null) 'match_type': matchType,
      if (pattern != null) 'pattern': pattern,
      if (action != null) 'action': action,
      if (priority != null) 'priority': priority,
      if (enabled != null) 'enabled': enabled,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  McpPolicyRulesCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? scopeType,
    Value<String?>? scopeId,
    Value<String>? matchType,
    Value<String>? pattern,
    Value<String>? action,
    Value<int>? priority,
    Value<bool>? enabled,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return McpPolicyRulesCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      scopeType: scopeType ?? this.scopeType,
      scopeId: scopeId ?? this.scopeId,
      matchType: matchType ?? this.matchType,
      pattern: pattern ?? this.pattern,
      action: action ?? this.action,
      priority: priority ?? this.priority,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (scopeType.present) {
      map['scope_type'] = Variable<String>(scopeType.value);
    }
    if (scopeId.present) {
      map['scope_id'] = Variable<String>(scopeId.value);
    }
    if (matchType.present) {
      map['match_type'] = Variable<String>(matchType.value);
    }
    if (pattern.present) {
      map['pattern'] = Variable<String>(pattern.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('McpPolicyRulesCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('scopeType: $scopeType, ')
          ..write('scopeId: $scopeId, ')
          ..write('matchType: $matchType, ')
          ..write('pattern: $pattern, ')
          ..write('action: $action, ')
          ..write('priority: $priority, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $McpApprovalsTable extends McpApprovals
    with TableInfo<$McpApprovalsTable, McpApproval> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $McpApprovalsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clientIdMeta = const VerificationMeta(
    'clientId',
  );
  @override
  late final GeneratedColumn<String> clientId = GeneratedColumn<String>(
    'client_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES mcp_clients (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _hostIdMeta = const VerificationMeta('hostId');
  @override
  late final GeneratedColumn<String> hostId = GeneratedColumn<String>(
    'host_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES hosts (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _cwdMeta = const VerificationMeta('cwd');
  @override
  late final GeneratedColumn<String> cwd = GeneratedColumn<String>(
    'cwd',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _commandNormalizedMeta = const VerificationMeta(
    'commandNormalized',
  );
  @override
  late final GeneratedColumn<String> commandNormalized =
      GeneratedColumn<String>(
        'command_normalized',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _commandSha256Meta = const VerificationMeta(
    'commandSha256',
  );
  @override
  late final GeneratedColumn<String> commandSha256 = GeneratedColumn<String>(
    'command_sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _approvedAtMeta = const VerificationMeta(
    'approvedAt',
  );
  @override
  late final GeneratedColumn<DateTime> approvedAt = GeneratedColumn<DateTime>(
    'approved_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
    'expires_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _connectionScopeIdMeta = const VerificationMeta(
    'connectionScopeId',
  );
  @override
  late final GeneratedColumn<String> connectionScopeId =
      GeneratedColumn<String>(
        'connection_scope_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    clientId,
    hostId,
    cwd,
    commandNormalized,
    commandSha256,
    approvedAt,
    expiresAt,
    connectionScopeId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mcp_approvals';
  @override
  VerificationContext validateIntegrity(
    Insertable<McpApproval> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('client_id')) {
      context.handle(
        _clientIdMeta,
        clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta),
      );
    } else if (isInserting) {
      context.missing(_clientIdMeta);
    }
    if (data.containsKey('host_id')) {
      context.handle(
        _hostIdMeta,
        hostId.isAcceptableOrUnknown(data['host_id']!, _hostIdMeta),
      );
    } else if (isInserting) {
      context.missing(_hostIdMeta);
    }
    if (data.containsKey('cwd')) {
      context.handle(
        _cwdMeta,
        cwd.isAcceptableOrUnknown(data['cwd']!, _cwdMeta),
      );
    } else if (isInserting) {
      context.missing(_cwdMeta);
    }
    if (data.containsKey('command_normalized')) {
      context.handle(
        _commandNormalizedMeta,
        commandNormalized.isAcceptableOrUnknown(
          data['command_normalized']!,
          _commandNormalizedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_commandNormalizedMeta);
    }
    if (data.containsKey('command_sha256')) {
      context.handle(
        _commandSha256Meta,
        commandSha256.isAcceptableOrUnknown(
          data['command_sha256']!,
          _commandSha256Meta,
        ),
      );
    } else if (isInserting) {
      context.missing(_commandSha256Meta);
    }
    if (data.containsKey('approved_at')) {
      context.handle(
        _approvedAtMeta,
        approvedAt.isAcceptableOrUnknown(data['approved_at']!, _approvedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_approvedAtMeta);
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    }
    if (data.containsKey('connection_scope_id')) {
      context.handle(
        _connectionScopeIdMeta,
        connectionScopeId.isAcceptableOrUnknown(
          data['connection_scope_id']!,
          _connectionScopeIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  McpApproval map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return McpApproval(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      clientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_id'],
      )!,
      hostId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_id'],
      )!,
      cwd: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cwd'],
      )!,
      commandNormalized: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}command_normalized'],
      )!,
      commandSha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}command_sha256'],
      )!,
      approvedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}approved_at'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expires_at'],
      ),
      connectionScopeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}connection_scope_id'],
      ),
    );
  }

  @override
  $McpApprovalsTable createAlias(String alias) {
    return $McpApprovalsTable(attachedDatabase, alias);
  }
}

class McpApproval extends DataClass implements Insertable<McpApproval> {
  final String id;
  final String clientId;
  final String hostId;
  final String cwd;
  final String commandNormalized;
  final String commandSha256;
  final DateTime approvedAt;
  final DateTime? expiresAt;
  final String? connectionScopeId;
  const McpApproval({
    required this.id,
    required this.clientId,
    required this.hostId,
    required this.cwd,
    required this.commandNormalized,
    required this.commandSha256,
    required this.approvedAt,
    this.expiresAt,
    this.connectionScopeId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['client_id'] = Variable<String>(clientId);
    map['host_id'] = Variable<String>(hostId);
    map['cwd'] = Variable<String>(cwd);
    map['command_normalized'] = Variable<String>(commandNormalized);
    map['command_sha256'] = Variable<String>(commandSha256);
    map['approved_at'] = Variable<DateTime>(approvedAt);
    if (!nullToAbsent || expiresAt != null) {
      map['expires_at'] = Variable<DateTime>(expiresAt);
    }
    if (!nullToAbsent || connectionScopeId != null) {
      map['connection_scope_id'] = Variable<String>(connectionScopeId);
    }
    return map;
  }

  McpApprovalsCompanion toCompanion(bool nullToAbsent) {
    return McpApprovalsCompanion(
      id: Value(id),
      clientId: Value(clientId),
      hostId: Value(hostId),
      cwd: Value(cwd),
      commandNormalized: Value(commandNormalized),
      commandSha256: Value(commandSha256),
      approvedAt: Value(approvedAt),
      expiresAt: expiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresAt),
      connectionScopeId: connectionScopeId == null && nullToAbsent
          ? const Value.absent()
          : Value(connectionScopeId),
    );
  }

  factory McpApproval.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return McpApproval(
      id: serializer.fromJson<String>(json['id']),
      clientId: serializer.fromJson<String>(json['clientId']),
      hostId: serializer.fromJson<String>(json['hostId']),
      cwd: serializer.fromJson<String>(json['cwd']),
      commandNormalized: serializer.fromJson<String>(json['commandNormalized']),
      commandSha256: serializer.fromJson<String>(json['commandSha256']),
      approvedAt: serializer.fromJson<DateTime>(json['approvedAt']),
      expiresAt: serializer.fromJson<DateTime?>(json['expiresAt']),
      connectionScopeId: serializer.fromJson<String?>(
        json['connectionScopeId'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'clientId': serializer.toJson<String>(clientId),
      'hostId': serializer.toJson<String>(hostId),
      'cwd': serializer.toJson<String>(cwd),
      'commandNormalized': serializer.toJson<String>(commandNormalized),
      'commandSha256': serializer.toJson<String>(commandSha256),
      'approvedAt': serializer.toJson<DateTime>(approvedAt),
      'expiresAt': serializer.toJson<DateTime?>(expiresAt),
      'connectionScopeId': serializer.toJson<String?>(connectionScopeId),
    };
  }

  McpApproval copyWith({
    String? id,
    String? clientId,
    String? hostId,
    String? cwd,
    String? commandNormalized,
    String? commandSha256,
    DateTime? approvedAt,
    Value<DateTime?> expiresAt = const Value.absent(),
    Value<String?> connectionScopeId = const Value.absent(),
  }) => McpApproval(
    id: id ?? this.id,
    clientId: clientId ?? this.clientId,
    hostId: hostId ?? this.hostId,
    cwd: cwd ?? this.cwd,
    commandNormalized: commandNormalized ?? this.commandNormalized,
    commandSha256: commandSha256 ?? this.commandSha256,
    approvedAt: approvedAt ?? this.approvedAt,
    expiresAt: expiresAt.present ? expiresAt.value : this.expiresAt,
    connectionScopeId: connectionScopeId.present
        ? connectionScopeId.value
        : this.connectionScopeId,
  );
  McpApproval copyWithCompanion(McpApprovalsCompanion data) {
    return McpApproval(
      id: data.id.present ? data.id.value : this.id,
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      hostId: data.hostId.present ? data.hostId.value : this.hostId,
      cwd: data.cwd.present ? data.cwd.value : this.cwd,
      commandNormalized: data.commandNormalized.present
          ? data.commandNormalized.value
          : this.commandNormalized,
      commandSha256: data.commandSha256.present
          ? data.commandSha256.value
          : this.commandSha256,
      approvedAt: data.approvedAt.present
          ? data.approvedAt.value
          : this.approvedAt,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      connectionScopeId: data.connectionScopeId.present
          ? data.connectionScopeId.value
          : this.connectionScopeId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('McpApproval(')
          ..write('id: $id, ')
          ..write('clientId: $clientId, ')
          ..write('hostId: $hostId, ')
          ..write('cwd: $cwd, ')
          ..write('commandNormalized: $commandNormalized, ')
          ..write('commandSha256: $commandSha256, ')
          ..write('approvedAt: $approvedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('connectionScopeId: $connectionScopeId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    clientId,
    hostId,
    cwd,
    commandNormalized,
    commandSha256,
    approvedAt,
    expiresAt,
    connectionScopeId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is McpApproval &&
          other.id == this.id &&
          other.clientId == this.clientId &&
          other.hostId == this.hostId &&
          other.cwd == this.cwd &&
          other.commandNormalized == this.commandNormalized &&
          other.commandSha256 == this.commandSha256 &&
          other.approvedAt == this.approvedAt &&
          other.expiresAt == this.expiresAt &&
          other.connectionScopeId == this.connectionScopeId);
}

class McpApprovalsCompanion extends UpdateCompanion<McpApproval> {
  final Value<String> id;
  final Value<String> clientId;
  final Value<String> hostId;
  final Value<String> cwd;
  final Value<String> commandNormalized;
  final Value<String> commandSha256;
  final Value<DateTime> approvedAt;
  final Value<DateTime?> expiresAt;
  final Value<String?> connectionScopeId;
  final Value<int> rowid;
  const McpApprovalsCompanion({
    this.id = const Value.absent(),
    this.clientId = const Value.absent(),
    this.hostId = const Value.absent(),
    this.cwd = const Value.absent(),
    this.commandNormalized = const Value.absent(),
    this.commandSha256 = const Value.absent(),
    this.approvedAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.connectionScopeId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  McpApprovalsCompanion.insert({
    required String id,
    required String clientId,
    required String hostId,
    required String cwd,
    required String commandNormalized,
    required String commandSha256,
    required DateTime approvedAt,
    this.expiresAt = const Value.absent(),
    this.connectionScopeId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       clientId = Value(clientId),
       hostId = Value(hostId),
       cwd = Value(cwd),
       commandNormalized = Value(commandNormalized),
       commandSha256 = Value(commandSha256),
       approvedAt = Value(approvedAt);
  static Insertable<McpApproval> custom({
    Expression<String>? id,
    Expression<String>? clientId,
    Expression<String>? hostId,
    Expression<String>? cwd,
    Expression<String>? commandNormalized,
    Expression<String>? commandSha256,
    Expression<DateTime>? approvedAt,
    Expression<DateTime>? expiresAt,
    Expression<String>? connectionScopeId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (clientId != null) 'client_id': clientId,
      if (hostId != null) 'host_id': hostId,
      if (cwd != null) 'cwd': cwd,
      if (commandNormalized != null) 'command_normalized': commandNormalized,
      if (commandSha256 != null) 'command_sha256': commandSha256,
      if (approvedAt != null) 'approved_at': approvedAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (connectionScopeId != null) 'connection_scope_id': connectionScopeId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  McpApprovalsCompanion copyWith({
    Value<String>? id,
    Value<String>? clientId,
    Value<String>? hostId,
    Value<String>? cwd,
    Value<String>? commandNormalized,
    Value<String>? commandSha256,
    Value<DateTime>? approvedAt,
    Value<DateTime?>? expiresAt,
    Value<String?>? connectionScopeId,
    Value<int>? rowid,
  }) {
    return McpApprovalsCompanion(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      hostId: hostId ?? this.hostId,
      cwd: cwd ?? this.cwd,
      commandNormalized: commandNormalized ?? this.commandNormalized,
      commandSha256: commandSha256 ?? this.commandSha256,
      approvedAt: approvedAt ?? this.approvedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      connectionScopeId: connectionScopeId ?? this.connectionScopeId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (hostId.present) {
      map['host_id'] = Variable<String>(hostId.value);
    }
    if (cwd.present) {
      map['cwd'] = Variable<String>(cwd.value);
    }
    if (commandNormalized.present) {
      map['command_normalized'] = Variable<String>(commandNormalized.value);
    }
    if (commandSha256.present) {
      map['command_sha256'] = Variable<String>(commandSha256.value);
    }
    if (approvedAt.present) {
      map['approved_at'] = Variable<DateTime>(approvedAt.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
    }
    if (connectionScopeId.present) {
      map['connection_scope_id'] = Variable<String>(connectionScopeId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('McpApprovalsCompanion(')
          ..write('id: $id, ')
          ..write('clientId: $clientId, ')
          ..write('hostId: $hostId, ')
          ..write('cwd: $cwd, ')
          ..write('commandNormalized: $commandNormalized, ')
          ..write('commandSha256: $commandSha256, ')
          ..write('approvedAt: $approvedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('connectionScopeId: $connectionScopeId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $McpAuditLogTable extends McpAuditLog
    with TableInfo<$McpAuditLogTable, McpAuditLogData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $McpAuditLogTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _atMeta = const VerificationMeta('at');
  @override
  late final GeneratedColumn<DateTime> at = GeneratedColumn<DateTime>(
    'at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clientIdMeta = const VerificationMeta(
    'clientId',
  );
  @override
  late final GeneratedColumn<String> clientId = GeneratedColumn<String>(
    'client_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clientNameMeta = const VerificationMeta(
    'clientName',
  );
  @override
  late final GeneratedColumn<String> clientName = GeneratedColumn<String>(
    'client_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostIdMeta = const VerificationMeta('hostId');
  @override
  late final GeneratedColumn<String> hostId = GeneratedColumn<String>(
    'host_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hostLabelMeta = const VerificationMeta(
    'hostLabel',
  );
  @override
  late final GeneratedColumn<String> hostLabel = GeneratedColumn<String>(
    'host_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _toolMeta = const VerificationMeta('tool');
  @override
  late final GeneratedColumn<String> tool = GeneratedColumn<String>(
    'tool',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _argsJsonMeta = const VerificationMeta(
    'argsJson',
  );
  @override
  late final GeneratedColumn<String> argsJson = GeneratedColumn<String>(
    'args_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _decisionMeta = const VerificationMeta(
    'decision',
  );
  @override
  late final GeneratedColumn<String> decision = GeneratedColumn<String>(
    'decision',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _exitCodeMeta = const VerificationMeta(
    'exitCode',
  );
  @override
  late final GeneratedColumn<int> exitCode = GeneratedColumn<int>(
    'exit_code',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _outputBytesMeta = const VerificationMeta(
    'outputBytes',
  );
  @override
  late final GeneratedColumn<int> outputBytes = GeneratedColumn<int>(
    'output_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _outputSha256Meta = const VerificationMeta(
    'outputSha256',
  );
  @override
  late final GeneratedColumn<String> outputSha256 = GeneratedColumn<String>(
    'output_sha256',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    at,
    clientId,
    clientName,
    hostId,
    hostLabel,
    tool,
    argsJson,
    decision,
    category,
    exitCode,
    durationMs,
    outputBytes,
    outputSha256,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mcp_audit_log';
  @override
  VerificationContext validateIntegrity(
    Insertable<McpAuditLogData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('at')) {
      context.handle(_atMeta, at.isAcceptableOrUnknown(data['at']!, _atMeta));
    } else if (isInserting) {
      context.missing(_atMeta);
    }
    if (data.containsKey('client_id')) {
      context.handle(
        _clientIdMeta,
        clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta),
      );
    } else if (isInserting) {
      context.missing(_clientIdMeta);
    }
    if (data.containsKey('client_name')) {
      context.handle(
        _clientNameMeta,
        clientName.isAcceptableOrUnknown(data['client_name']!, _clientNameMeta),
      );
    } else if (isInserting) {
      context.missing(_clientNameMeta);
    }
    if (data.containsKey('host_id')) {
      context.handle(
        _hostIdMeta,
        hostId.isAcceptableOrUnknown(data['host_id']!, _hostIdMeta),
      );
    }
    if (data.containsKey('host_label')) {
      context.handle(
        _hostLabelMeta,
        hostLabel.isAcceptableOrUnknown(data['host_label']!, _hostLabelMeta),
      );
    }
    if (data.containsKey('tool')) {
      context.handle(
        _toolMeta,
        tool.isAcceptableOrUnknown(data['tool']!, _toolMeta),
      );
    } else if (isInserting) {
      context.missing(_toolMeta);
    }
    if (data.containsKey('args_json')) {
      context.handle(
        _argsJsonMeta,
        argsJson.isAcceptableOrUnknown(data['args_json']!, _argsJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_argsJsonMeta);
    }
    if (data.containsKey('decision')) {
      context.handle(
        _decisionMeta,
        decision.isAcceptableOrUnknown(data['decision']!, _decisionMeta),
      );
    } else if (isInserting) {
      context.missing(_decisionMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    if (data.containsKey('exit_code')) {
      context.handle(
        _exitCodeMeta,
        exitCode.isAcceptableOrUnknown(data['exit_code']!, _exitCodeMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('output_bytes')) {
      context.handle(
        _outputBytesMeta,
        outputBytes.isAcceptableOrUnknown(
          data['output_bytes']!,
          _outputBytesMeta,
        ),
      );
    }
    if (data.containsKey('output_sha256')) {
      context.handle(
        _outputSha256Meta,
        outputSha256.isAcceptableOrUnknown(
          data['output_sha256']!,
          _outputSha256Meta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  McpAuditLogData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return McpAuditLogData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      at: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}at'],
      )!,
      clientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_id'],
      )!,
      clientName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_name'],
      )!,
      hostId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_id'],
      ),
      hostLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_label'],
      ),
      tool: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tool'],
      )!,
      argsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}args_json'],
      )!,
      decision: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}decision'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      ),
      exitCode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}exit_code'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      outputBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}output_bytes'],
      ),
      outputSha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}output_sha256'],
      ),
    );
  }

  @override
  $McpAuditLogTable createAlias(String alias) {
    return $McpAuditLogTable(attachedDatabase, alias);
  }
}

class McpAuditLogData extends DataClass implements Insertable<McpAuditLogData> {
  final String id;
  final DateTime at;
  final String clientId;
  final String clientName;
  final String? hostId;
  final String? hostLabel;
  final String tool;
  final String argsJson;
  final String decision;
  final String? category;
  final int? exitCode;
  final int? durationMs;
  final int? outputBytes;
  final String? outputSha256;
  const McpAuditLogData({
    required this.id,
    required this.at,
    required this.clientId,
    required this.clientName,
    this.hostId,
    this.hostLabel,
    required this.tool,
    required this.argsJson,
    required this.decision,
    this.category,
    this.exitCode,
    this.durationMs,
    this.outputBytes,
    this.outputSha256,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['at'] = Variable<DateTime>(at);
    map['client_id'] = Variable<String>(clientId);
    map['client_name'] = Variable<String>(clientName);
    if (!nullToAbsent || hostId != null) {
      map['host_id'] = Variable<String>(hostId);
    }
    if (!nullToAbsent || hostLabel != null) {
      map['host_label'] = Variable<String>(hostLabel);
    }
    map['tool'] = Variable<String>(tool);
    map['args_json'] = Variable<String>(argsJson);
    map['decision'] = Variable<String>(decision);
    if (!nullToAbsent || category != null) {
      map['category'] = Variable<String>(category);
    }
    if (!nullToAbsent || exitCode != null) {
      map['exit_code'] = Variable<int>(exitCode);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    if (!nullToAbsent || outputBytes != null) {
      map['output_bytes'] = Variable<int>(outputBytes);
    }
    if (!nullToAbsent || outputSha256 != null) {
      map['output_sha256'] = Variable<String>(outputSha256);
    }
    return map;
  }

  McpAuditLogCompanion toCompanion(bool nullToAbsent) {
    return McpAuditLogCompanion(
      id: Value(id),
      at: Value(at),
      clientId: Value(clientId),
      clientName: Value(clientName),
      hostId: hostId == null && nullToAbsent
          ? const Value.absent()
          : Value(hostId),
      hostLabel: hostLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(hostLabel),
      tool: Value(tool),
      argsJson: Value(argsJson),
      decision: Value(decision),
      category: category == null && nullToAbsent
          ? const Value.absent()
          : Value(category),
      exitCode: exitCode == null && nullToAbsent
          ? const Value.absent()
          : Value(exitCode),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      outputBytes: outputBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(outputBytes),
      outputSha256: outputSha256 == null && nullToAbsent
          ? const Value.absent()
          : Value(outputSha256),
    );
  }

  factory McpAuditLogData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return McpAuditLogData(
      id: serializer.fromJson<String>(json['id']),
      at: serializer.fromJson<DateTime>(json['at']),
      clientId: serializer.fromJson<String>(json['clientId']),
      clientName: serializer.fromJson<String>(json['clientName']),
      hostId: serializer.fromJson<String?>(json['hostId']),
      hostLabel: serializer.fromJson<String?>(json['hostLabel']),
      tool: serializer.fromJson<String>(json['tool']),
      argsJson: serializer.fromJson<String>(json['argsJson']),
      decision: serializer.fromJson<String>(json['decision']),
      category: serializer.fromJson<String?>(json['category']),
      exitCode: serializer.fromJson<int?>(json['exitCode']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      outputBytes: serializer.fromJson<int?>(json['outputBytes']),
      outputSha256: serializer.fromJson<String?>(json['outputSha256']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'at': serializer.toJson<DateTime>(at),
      'clientId': serializer.toJson<String>(clientId),
      'clientName': serializer.toJson<String>(clientName),
      'hostId': serializer.toJson<String?>(hostId),
      'hostLabel': serializer.toJson<String?>(hostLabel),
      'tool': serializer.toJson<String>(tool),
      'argsJson': serializer.toJson<String>(argsJson),
      'decision': serializer.toJson<String>(decision),
      'category': serializer.toJson<String?>(category),
      'exitCode': serializer.toJson<int?>(exitCode),
      'durationMs': serializer.toJson<int?>(durationMs),
      'outputBytes': serializer.toJson<int?>(outputBytes),
      'outputSha256': serializer.toJson<String?>(outputSha256),
    };
  }

  McpAuditLogData copyWith({
    String? id,
    DateTime? at,
    String? clientId,
    String? clientName,
    Value<String?> hostId = const Value.absent(),
    Value<String?> hostLabel = const Value.absent(),
    String? tool,
    String? argsJson,
    String? decision,
    Value<String?> category = const Value.absent(),
    Value<int?> exitCode = const Value.absent(),
    Value<int?> durationMs = const Value.absent(),
    Value<int?> outputBytes = const Value.absent(),
    Value<String?> outputSha256 = const Value.absent(),
  }) => McpAuditLogData(
    id: id ?? this.id,
    at: at ?? this.at,
    clientId: clientId ?? this.clientId,
    clientName: clientName ?? this.clientName,
    hostId: hostId.present ? hostId.value : this.hostId,
    hostLabel: hostLabel.present ? hostLabel.value : this.hostLabel,
    tool: tool ?? this.tool,
    argsJson: argsJson ?? this.argsJson,
    decision: decision ?? this.decision,
    category: category.present ? category.value : this.category,
    exitCode: exitCode.present ? exitCode.value : this.exitCode,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    outputBytes: outputBytes.present ? outputBytes.value : this.outputBytes,
    outputSha256: outputSha256.present ? outputSha256.value : this.outputSha256,
  );
  McpAuditLogData copyWithCompanion(McpAuditLogCompanion data) {
    return McpAuditLogData(
      id: data.id.present ? data.id.value : this.id,
      at: data.at.present ? data.at.value : this.at,
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      clientName: data.clientName.present
          ? data.clientName.value
          : this.clientName,
      hostId: data.hostId.present ? data.hostId.value : this.hostId,
      hostLabel: data.hostLabel.present ? data.hostLabel.value : this.hostLabel,
      tool: data.tool.present ? data.tool.value : this.tool,
      argsJson: data.argsJson.present ? data.argsJson.value : this.argsJson,
      decision: data.decision.present ? data.decision.value : this.decision,
      category: data.category.present ? data.category.value : this.category,
      exitCode: data.exitCode.present ? data.exitCode.value : this.exitCode,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      outputBytes: data.outputBytes.present
          ? data.outputBytes.value
          : this.outputBytes,
      outputSha256: data.outputSha256.present
          ? data.outputSha256.value
          : this.outputSha256,
    );
  }

  @override
  String toString() {
    return (StringBuffer('McpAuditLogData(')
          ..write('id: $id, ')
          ..write('at: $at, ')
          ..write('clientId: $clientId, ')
          ..write('clientName: $clientName, ')
          ..write('hostId: $hostId, ')
          ..write('hostLabel: $hostLabel, ')
          ..write('tool: $tool, ')
          ..write('argsJson: $argsJson, ')
          ..write('decision: $decision, ')
          ..write('category: $category, ')
          ..write('exitCode: $exitCode, ')
          ..write('durationMs: $durationMs, ')
          ..write('outputBytes: $outputBytes, ')
          ..write('outputSha256: $outputSha256')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    at,
    clientId,
    clientName,
    hostId,
    hostLabel,
    tool,
    argsJson,
    decision,
    category,
    exitCode,
    durationMs,
    outputBytes,
    outputSha256,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is McpAuditLogData &&
          other.id == this.id &&
          other.at == this.at &&
          other.clientId == this.clientId &&
          other.clientName == this.clientName &&
          other.hostId == this.hostId &&
          other.hostLabel == this.hostLabel &&
          other.tool == this.tool &&
          other.argsJson == this.argsJson &&
          other.decision == this.decision &&
          other.category == this.category &&
          other.exitCode == this.exitCode &&
          other.durationMs == this.durationMs &&
          other.outputBytes == this.outputBytes &&
          other.outputSha256 == this.outputSha256);
}

class McpAuditLogCompanion extends UpdateCompanion<McpAuditLogData> {
  final Value<String> id;
  final Value<DateTime> at;
  final Value<String> clientId;
  final Value<String> clientName;
  final Value<String?> hostId;
  final Value<String?> hostLabel;
  final Value<String> tool;
  final Value<String> argsJson;
  final Value<String> decision;
  final Value<String?> category;
  final Value<int?> exitCode;
  final Value<int?> durationMs;
  final Value<int?> outputBytes;
  final Value<String?> outputSha256;
  final Value<int> rowid;
  const McpAuditLogCompanion({
    this.id = const Value.absent(),
    this.at = const Value.absent(),
    this.clientId = const Value.absent(),
    this.clientName = const Value.absent(),
    this.hostId = const Value.absent(),
    this.hostLabel = const Value.absent(),
    this.tool = const Value.absent(),
    this.argsJson = const Value.absent(),
    this.decision = const Value.absent(),
    this.category = const Value.absent(),
    this.exitCode = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.outputBytes = const Value.absent(),
    this.outputSha256 = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  McpAuditLogCompanion.insert({
    required String id,
    required DateTime at,
    required String clientId,
    required String clientName,
    this.hostId = const Value.absent(),
    this.hostLabel = const Value.absent(),
    required String tool,
    required String argsJson,
    required String decision,
    this.category = const Value.absent(),
    this.exitCode = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.outputBytes = const Value.absent(),
    this.outputSha256 = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       at = Value(at),
       clientId = Value(clientId),
       clientName = Value(clientName),
       tool = Value(tool),
       argsJson = Value(argsJson),
       decision = Value(decision);
  static Insertable<McpAuditLogData> custom({
    Expression<String>? id,
    Expression<DateTime>? at,
    Expression<String>? clientId,
    Expression<String>? clientName,
    Expression<String>? hostId,
    Expression<String>? hostLabel,
    Expression<String>? tool,
    Expression<String>? argsJson,
    Expression<String>? decision,
    Expression<String>? category,
    Expression<int>? exitCode,
    Expression<int>? durationMs,
    Expression<int>? outputBytes,
    Expression<String>? outputSha256,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (at != null) 'at': at,
      if (clientId != null) 'client_id': clientId,
      if (clientName != null) 'client_name': clientName,
      if (hostId != null) 'host_id': hostId,
      if (hostLabel != null) 'host_label': hostLabel,
      if (tool != null) 'tool': tool,
      if (argsJson != null) 'args_json': argsJson,
      if (decision != null) 'decision': decision,
      if (category != null) 'category': category,
      if (exitCode != null) 'exit_code': exitCode,
      if (durationMs != null) 'duration_ms': durationMs,
      if (outputBytes != null) 'output_bytes': outputBytes,
      if (outputSha256 != null) 'output_sha256': outputSha256,
      if (rowid != null) 'rowid': rowid,
    });
  }

  McpAuditLogCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? at,
    Value<String>? clientId,
    Value<String>? clientName,
    Value<String?>? hostId,
    Value<String?>? hostLabel,
    Value<String>? tool,
    Value<String>? argsJson,
    Value<String>? decision,
    Value<String?>? category,
    Value<int?>? exitCode,
    Value<int?>? durationMs,
    Value<int?>? outputBytes,
    Value<String?>? outputSha256,
    Value<int>? rowid,
  }) {
    return McpAuditLogCompanion(
      id: id ?? this.id,
      at: at ?? this.at,
      clientId: clientId ?? this.clientId,
      clientName: clientName ?? this.clientName,
      hostId: hostId ?? this.hostId,
      hostLabel: hostLabel ?? this.hostLabel,
      tool: tool ?? this.tool,
      argsJson: argsJson ?? this.argsJson,
      decision: decision ?? this.decision,
      category: category ?? this.category,
      exitCode: exitCode ?? this.exitCode,
      durationMs: durationMs ?? this.durationMs,
      outputBytes: outputBytes ?? this.outputBytes,
      outputSha256: outputSha256 ?? this.outputSha256,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (at.present) {
      map['at'] = Variable<DateTime>(at.value);
    }
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (clientName.present) {
      map['client_name'] = Variable<String>(clientName.value);
    }
    if (hostId.present) {
      map['host_id'] = Variable<String>(hostId.value);
    }
    if (hostLabel.present) {
      map['host_label'] = Variable<String>(hostLabel.value);
    }
    if (tool.present) {
      map['tool'] = Variable<String>(tool.value);
    }
    if (argsJson.present) {
      map['args_json'] = Variable<String>(argsJson.value);
    }
    if (decision.present) {
      map['decision'] = Variable<String>(decision.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (exitCode.present) {
      map['exit_code'] = Variable<int>(exitCode.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (outputBytes.present) {
      map['output_bytes'] = Variable<int>(outputBytes.value);
    }
    if (outputSha256.present) {
      map['output_sha256'] = Variable<String>(outputSha256.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('McpAuditLogCompanion(')
          ..write('id: $id, ')
          ..write('at: $at, ')
          ..write('clientId: $clientId, ')
          ..write('clientName: $clientName, ')
          ..write('hostId: $hostId, ')
          ..write('hostLabel: $hostLabel, ')
          ..write('tool: $tool, ')
          ..write('argsJson: $argsJson, ')
          ..write('decision: $decision, ')
          ..write('category: $category, ')
          ..write('exitCode: $exitCode, ')
          ..write('durationMs: $durationMs, ')
          ..write('outputBytes: $outputBytes, ')
          ..write('outputSha256: $outputSha256, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BookmarksTable extends Bookmarks
    with TableInfo<$BookmarksTable, Bookmark> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookmarksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES workspaces (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _hostIdMeta = const VerificationMeta('hostId');
  @override
  late final GeneratedColumn<String> hostId = GeneratedColumn<String>(
    'host_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES hosts (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _templateIdMeta = const VerificationMeta(
    'templateId',
  );
  @override
  late final GeneratedColumn<String> templateId = GeneratedColumn<String>(
    'template_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES templates (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    hostId,
    templateId,
    position,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'bookmarks';
  @override
  VerificationContext validateIntegrity(
    Insertable<Bookmark> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('host_id')) {
      context.handle(
        _hostIdMeta,
        hostId.isAcceptableOrUnknown(data['host_id']!, _hostIdMeta),
      );
    }
    if (data.containsKey('template_id')) {
      context.handle(
        _templateIdMeta,
        templateId.isAcceptableOrUnknown(data['template_id']!, _templateIdMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Bookmark map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Bookmark(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      hostId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_id'],
      ),
      templateId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}template_id'],
      ),
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $BookmarksTable createAlias(String alias) {
    return $BookmarksTable(attachedDatabase, alias);
  }
}

class Bookmark extends DataClass implements Insertable<Bookmark> {
  final String id;
  final String workspaceId;
  final String? hostId;
  final String? templateId;
  final int position;
  final DateTime createdAt;
  const Bookmark({
    required this.id,
    required this.workspaceId,
    this.hostId,
    this.templateId,
    required this.position,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    if (!nullToAbsent || hostId != null) {
      map['host_id'] = Variable<String>(hostId);
    }
    if (!nullToAbsent || templateId != null) {
      map['template_id'] = Variable<String>(templateId);
    }
    map['position'] = Variable<int>(position);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  BookmarksCompanion toCompanion(bool nullToAbsent) {
    return BookmarksCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      hostId: hostId == null && nullToAbsent
          ? const Value.absent()
          : Value(hostId),
      templateId: templateId == null && nullToAbsent
          ? const Value.absent()
          : Value(templateId),
      position: Value(position),
      createdAt: Value(createdAt),
    );
  }

  factory Bookmark.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Bookmark(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      hostId: serializer.fromJson<String?>(json['hostId']),
      templateId: serializer.fromJson<String?>(json['templateId']),
      position: serializer.fromJson<int>(json['position']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'hostId': serializer.toJson<String?>(hostId),
      'templateId': serializer.toJson<String?>(templateId),
      'position': serializer.toJson<int>(position),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Bookmark copyWith({
    String? id,
    String? workspaceId,
    Value<String?> hostId = const Value.absent(),
    Value<String?> templateId = const Value.absent(),
    int? position,
    DateTime? createdAt,
  }) => Bookmark(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    hostId: hostId.present ? hostId.value : this.hostId,
    templateId: templateId.present ? templateId.value : this.templateId,
    position: position ?? this.position,
    createdAt: createdAt ?? this.createdAt,
  );
  Bookmark copyWithCompanion(BookmarksCompanion data) {
    return Bookmark(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      hostId: data.hostId.present ? data.hostId.value : this.hostId,
      templateId: data.templateId.present
          ? data.templateId.value
          : this.templateId,
      position: data.position.present ? data.position.value : this.position,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Bookmark(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('hostId: $hostId, ')
          ..write('templateId: $templateId, ')
          ..write('position: $position, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, workspaceId, hostId, templateId, position, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Bookmark &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.hostId == this.hostId &&
          other.templateId == this.templateId &&
          other.position == this.position &&
          other.createdAt == this.createdAt);
}

class BookmarksCompanion extends UpdateCompanion<Bookmark> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String?> hostId;
  final Value<String?> templateId;
  final Value<int> position;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const BookmarksCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.hostId = const Value.absent(),
    this.templateId = const Value.absent(),
    this.position = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BookmarksCompanion.insert({
    required String id,
    required String workspaceId,
    this.hostId = const Value.absent(),
    this.templateId = const Value.absent(),
    this.position = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       createdAt = Value(createdAt);
  static Insertable<Bookmark> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? hostId,
    Expression<String>? templateId,
    Expression<int>? position,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (hostId != null) 'host_id': hostId,
      if (templateId != null) 'template_id': templateId,
      if (position != null) 'position': position,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BookmarksCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String?>? hostId,
    Value<String?>? templateId,
    Value<int>? position,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return BookmarksCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      hostId: hostId ?? this.hostId,
      templateId: templateId ?? this.templateId,
      position: position ?? this.position,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (hostId.present) {
      map['host_id'] = Variable<String>(hostId.value);
    }
    if (templateId.present) {
      map['template_id'] = Variable<String>(templateId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookmarksCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('hostId: $hostId, ')
          ..write('templateId: $templateId, ')
          ..write('position: $position, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingOperationsTable extends PendingOperations
    with TableInfo<$PendingOperationsTable, PendingOperation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationMeta = const VerificationMeta(
    'operation',
  );
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
    'operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _beforeImageMeta = const VerificationMeta(
    'beforeImage',
  );
  @override
  late final GeneratedColumn<String> beforeImage = GeneratedColumn<String>(
    'before_image',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _logicalClockMeta = const VerificationMeta(
    'logicalClock',
  );
  @override
  late final GeneratedColumn<int> logicalClock = GeneratedColumn<int>(
    'logical_clock',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    entityType,
    entityId,
    operation,
    payload,
    beforeImage,
    logicalClock,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_operations';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingOperation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    }
    if (data.containsKey('before_image')) {
      context.handle(
        _beforeImageMeta,
        beforeImage.isAcceptableOrUnknown(
          data['before_image']!,
          _beforeImageMeta,
        ),
      );
    }
    if (data.containsKey('logical_clock')) {
      context.handle(
        _logicalClockMeta,
        logicalClock.isAcceptableOrUnknown(
          data['logical_clock']!,
          _logicalClockMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_logicalClockMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {entityType, entityId},
  ];
  @override
  PendingOperation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingOperation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      ),
      beforeImage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}before_image'],
      ),
      logicalClock: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}logical_clock'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $PendingOperationsTable createAlias(String alias) {
    return $PendingOperationsTable(attachedDatabase, alias);
  }
}

class PendingOperation extends DataClass
    implements Insertable<PendingOperation> {
  final String id;

  /// The table the row belongs to, in its plain name (`hosts`). The opaque
  /// alias is derived at send time -- storing the alias instead would make the
  /// outbox unreadable without the sync key.
  final String entityType;
  final String entityId;

  /// `upsert` or `delete`.
  final String operation;

  /// The row as JSON, or null for a delete.
  final String? payload;

  /// The row as it was before, or null when it did not exist.
  final String? beforeImage;

  /// Lamport clock this device assigned to the change.
  final int logicalClock;
  final DateTime createdAt;
  const PendingOperation({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    this.payload,
    this.beforeImage,
    required this.logicalClock,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['operation'] = Variable<String>(operation);
    if (!nullToAbsent || payload != null) {
      map['payload'] = Variable<String>(payload);
    }
    if (!nullToAbsent || beforeImage != null) {
      map['before_image'] = Variable<String>(beforeImage);
    }
    map['logical_clock'] = Variable<int>(logicalClock);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PendingOperationsCompanion toCompanion(bool nullToAbsent) {
    return PendingOperationsCompanion(
      id: Value(id),
      entityType: Value(entityType),
      entityId: Value(entityId),
      operation: Value(operation),
      payload: payload == null && nullToAbsent
          ? const Value.absent()
          : Value(payload),
      beforeImage: beforeImage == null && nullToAbsent
          ? const Value.absent()
          : Value(beforeImage),
      logicalClock: Value(logicalClock),
      createdAt: Value(createdAt),
    );
  }

  factory PendingOperation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingOperation(
      id: serializer.fromJson<String>(json['id']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      operation: serializer.fromJson<String>(json['operation']),
      payload: serializer.fromJson<String?>(json['payload']),
      beforeImage: serializer.fromJson<String?>(json['beforeImage']),
      logicalClock: serializer.fromJson<int>(json['logicalClock']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'operation': serializer.toJson<String>(operation),
      'payload': serializer.toJson<String?>(payload),
      'beforeImage': serializer.toJson<String?>(beforeImage),
      'logicalClock': serializer.toJson<int>(logicalClock),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  PendingOperation copyWith({
    String? id,
    String? entityType,
    String? entityId,
    String? operation,
    Value<String?> payload = const Value.absent(),
    Value<String?> beforeImage = const Value.absent(),
    int? logicalClock,
    DateTime? createdAt,
  }) => PendingOperation(
    id: id ?? this.id,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    operation: operation ?? this.operation,
    payload: payload.present ? payload.value : this.payload,
    beforeImage: beforeImage.present ? beforeImage.value : this.beforeImage,
    logicalClock: logicalClock ?? this.logicalClock,
    createdAt: createdAt ?? this.createdAt,
  );
  PendingOperation copyWithCompanion(PendingOperationsCompanion data) {
    return PendingOperation(
      id: data.id.present ? data.id.value : this.id,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      operation: data.operation.present ? data.operation.value : this.operation,
      payload: data.payload.present ? data.payload.value : this.payload,
      beforeImage: data.beforeImage.present
          ? data.beforeImage.value
          : this.beforeImage,
      logicalClock: data.logicalClock.present
          ? data.logicalClock.value
          : this.logicalClock,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingOperation(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('payload: $payload, ')
          ..write('beforeImage: $beforeImage, ')
          ..write('logicalClock: $logicalClock, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    entityType,
    entityId,
    operation,
    payload,
    beforeImage,
    logicalClock,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingOperation &&
          other.id == this.id &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.operation == this.operation &&
          other.payload == this.payload &&
          other.beforeImage == this.beforeImage &&
          other.logicalClock == this.logicalClock &&
          other.createdAt == this.createdAt);
}

class PendingOperationsCompanion extends UpdateCompanion<PendingOperation> {
  final Value<String> id;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> operation;
  final Value<String?> payload;
  final Value<String?> beforeImage;
  final Value<int> logicalClock;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const PendingOperationsCompanion({
    this.id = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.operation = const Value.absent(),
    this.payload = const Value.absent(),
    this.beforeImage = const Value.absent(),
    this.logicalClock = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingOperationsCompanion.insert({
    required String id,
    required String entityType,
    required String entityId,
    required String operation,
    this.payload = const Value.absent(),
    this.beforeImage = const Value.absent(),
    required int logicalClock,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       entityType = Value(entityType),
       entityId = Value(entityId),
       operation = Value(operation),
       logicalClock = Value(logicalClock),
       createdAt = Value(createdAt);
  static Insertable<PendingOperation> custom({
    Expression<String>? id,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? operation,
    Expression<String>? payload,
    Expression<String>? beforeImage,
    Expression<int>? logicalClock,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (operation != null) 'operation': operation,
      if (payload != null) 'payload': payload,
      if (beforeImage != null) 'before_image': beforeImage,
      if (logicalClock != null) 'logical_clock': logicalClock,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingOperationsCompanion copyWith({
    Value<String>? id,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? operation,
    Value<String?>? payload,
    Value<String?>? beforeImage,
    Value<int>? logicalClock,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return PendingOperationsCompanion(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      operation: operation ?? this.operation,
      payload: payload ?? this.payload,
      beforeImage: beforeImage ?? this.beforeImage,
      logicalClock: logicalClock ?? this.logicalClock,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (beforeImage.present) {
      map['before_image'] = Variable<String>(beforeImage.value);
    }
    if (logicalClock.present) {
      map['logical_clock'] = Variable<int>(logicalClock.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingOperationsCompanion(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('payload: $payload, ')
          ..write('beforeImage: $beforeImage, ')
          ..write('logicalClock: $logicalClock, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncTombstonesTable extends SyncTombstones
    with TableInfo<$SyncTombstonesTable, SyncTombstone> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncTombstonesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _logicalClockMeta = const VerificationMeta(
    'logicalClock',
  );
  @override
  late final GeneratedColumn<int> logicalClock = GeneratedColumn<int>(
    'logical_clock',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    entityType,
    entityId,
    body,
    logicalClock,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_tombstones';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncTombstone> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    }
    if (data.containsKey('logical_clock')) {
      context.handle(
        _logicalClockMeta,
        logicalClock.isAcceptableOrUnknown(
          data['logical_clock']!,
          _logicalClockMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_logicalClockMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_deletedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {entityType, entityId};
  @override
  SyncTombstone map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncTombstone(
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      ),
      logicalClock: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}logical_clock'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      )!,
    );
  }

  @override
  $SyncTombstonesTable createAlias(String alias) {
    return $SyncTombstonesTable(attachedDatabase, alias);
  }
}

class SyncTombstone extends DataClass implements Insertable<SyncTombstone> {
  final String entityType;
  final String entityId;

  /// The last known row as JSON, or null once the trash window has passed.
  ///
  /// The row is emptied rather than deleted: the id has to outlive the body,
  /// or a late `upsert` would bring the row back.
  final String? body;
  final int logicalClock;
  final DateTime deletedAt;
  const SyncTombstone({
    required this.entityType,
    required this.entityId,
    this.body,
    required this.logicalClock,
    required this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    if (!nullToAbsent || body != null) {
      map['body'] = Variable<String>(body);
    }
    map['logical_clock'] = Variable<int>(logicalClock);
    map['deleted_at'] = Variable<DateTime>(deletedAt);
    return map;
  }

  SyncTombstonesCompanion toCompanion(bool nullToAbsent) {
    return SyncTombstonesCompanion(
      entityType: Value(entityType),
      entityId: Value(entityId),
      body: body == null && nullToAbsent ? const Value.absent() : Value(body),
      logicalClock: Value(logicalClock),
      deletedAt: Value(deletedAt),
    );
  }

  factory SyncTombstone.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncTombstone(
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      body: serializer.fromJson<String?>(json['body']),
      logicalClock: serializer.fromJson<int>(json['logicalClock']),
      deletedAt: serializer.fromJson<DateTime>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'body': serializer.toJson<String?>(body),
      'logicalClock': serializer.toJson<int>(logicalClock),
      'deletedAt': serializer.toJson<DateTime>(deletedAt),
    };
  }

  SyncTombstone copyWith({
    String? entityType,
    String? entityId,
    Value<String?> body = const Value.absent(),
    int? logicalClock,
    DateTime? deletedAt,
  }) => SyncTombstone(
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    body: body.present ? body.value : this.body,
    logicalClock: logicalClock ?? this.logicalClock,
    deletedAt: deletedAt ?? this.deletedAt,
  );
  SyncTombstone copyWithCompanion(SyncTombstonesCompanion data) {
    return SyncTombstone(
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      body: data.body.present ? data.body.value : this.body,
      logicalClock: data.logicalClock.present
          ? data.logicalClock.value
          : this.logicalClock,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncTombstone(')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('body: $body, ')
          ..write('logicalClock: $logicalClock, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(entityType, entityId, body, logicalClock, deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncTombstone &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.body == this.body &&
          other.logicalClock == this.logicalClock &&
          other.deletedAt == this.deletedAt);
}

class SyncTombstonesCompanion extends UpdateCompanion<SyncTombstone> {
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String?> body;
  final Value<int> logicalClock;
  final Value<DateTime> deletedAt;
  final Value<int> rowid;
  const SyncTombstonesCompanion({
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.body = const Value.absent(),
    this.logicalClock = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncTombstonesCompanion.insert({
    required String entityType,
    required String entityId,
    this.body = const Value.absent(),
    required int logicalClock,
    required DateTime deletedAt,
    this.rowid = const Value.absent(),
  }) : entityType = Value(entityType),
       entityId = Value(entityId),
       logicalClock = Value(logicalClock),
       deletedAt = Value(deletedAt);
  static Insertable<SyncTombstone> custom({
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? body,
    Expression<int>? logicalClock,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (body != null) 'body': body,
      if (logicalClock != null) 'logical_clock': logicalClock,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncTombstonesCompanion copyWith({
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String?>? body,
    Value<int>? logicalClock,
    Value<DateTime>? deletedAt,
    Value<int>? rowid,
  }) {
    return SyncTombstonesCompanion(
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      body: body ?? this.body,
      logicalClock: logicalClock ?? this.logicalClock,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (logicalClock.present) {
      map['logical_clock'] = Variable<int>(logicalClock.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncTombstonesCompanion(')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('body: $body, ')
          ..write('logicalClock: $logicalClock, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncStateTable extends SyncState
    with TableInfo<$SyncStateTable, SyncStateData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSeenClockMeta = const VerificationMeta(
    'lastSeenClock',
  );
  @override
  late final GeneratedColumn<int> lastSeenClock = GeneratedColumn<int>(
    'last_seen_clock',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _pulledThroughClockMeta =
      const VerificationMeta('pulledThroughClock');
  @override
  late final GeneratedColumn<int> pulledThroughClock = GeneratedColumn<int>(
    'pulled_through_clock',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [id, lastSeenClock, pulledThroughClock];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncStateData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('last_seen_clock')) {
      context.handle(
        _lastSeenClockMeta,
        lastSeenClock.isAcceptableOrUnknown(
          data['last_seen_clock']!,
          _lastSeenClockMeta,
        ),
      );
    }
    if (data.containsKey('pulled_through_clock')) {
      context.handle(
        _pulledThroughClockMeta,
        pulledThroughClock.isAcceptableOrUnknown(
          data['pulled_through_clock']!,
          _pulledThroughClockMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncStateData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncStateData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      lastSeenClock: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_seen_clock'],
      )!,
      pulledThroughClock: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pulled_through_clock'],
      )!,
    );
  }

  @override
  $SyncStateTable createAlias(String alias) {
    return $SyncStateTable(attachedDatabase, alias);
  }
}

class SyncStateData extends DataClass implements Insertable<SyncStateData> {
  /// Always `1`. A table rather than a key-value blob so the clock can take
  /// part in a transaction.
  final int id;

  /// Highest clock this device has seen, from its own changes or from a pull.
  final int lastSeenClock;

  /// Clock the last pull was acknowledged at. Only ever advanced after the
  /// operations it covers have been written.
  final int pulledThroughClock;
  const SyncStateData({
    required this.id,
    required this.lastSeenClock,
    required this.pulledThroughClock,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['last_seen_clock'] = Variable<int>(lastSeenClock);
    map['pulled_through_clock'] = Variable<int>(pulledThroughClock);
    return map;
  }

  SyncStateCompanion toCompanion(bool nullToAbsent) {
    return SyncStateCompanion(
      id: Value(id),
      lastSeenClock: Value(lastSeenClock),
      pulledThroughClock: Value(pulledThroughClock),
    );
  }

  factory SyncStateData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncStateData(
      id: serializer.fromJson<int>(json['id']),
      lastSeenClock: serializer.fromJson<int>(json['lastSeenClock']),
      pulledThroughClock: serializer.fromJson<int>(json['pulledThroughClock']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'lastSeenClock': serializer.toJson<int>(lastSeenClock),
      'pulledThroughClock': serializer.toJson<int>(pulledThroughClock),
    };
  }

  SyncStateData copyWith({
    int? id,
    int? lastSeenClock,
    int? pulledThroughClock,
  }) => SyncStateData(
    id: id ?? this.id,
    lastSeenClock: lastSeenClock ?? this.lastSeenClock,
    pulledThroughClock: pulledThroughClock ?? this.pulledThroughClock,
  );
  SyncStateData copyWithCompanion(SyncStateCompanion data) {
    return SyncStateData(
      id: data.id.present ? data.id.value : this.id,
      lastSeenClock: data.lastSeenClock.present
          ? data.lastSeenClock.value
          : this.lastSeenClock,
      pulledThroughClock: data.pulledThroughClock.present
          ? data.pulledThroughClock.value
          : this.pulledThroughClock,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateData(')
          ..write('id: $id, ')
          ..write('lastSeenClock: $lastSeenClock, ')
          ..write('pulledThroughClock: $pulledThroughClock')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, lastSeenClock, pulledThroughClock);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStateData &&
          other.id == this.id &&
          other.lastSeenClock == this.lastSeenClock &&
          other.pulledThroughClock == this.pulledThroughClock);
}

class SyncStateCompanion extends UpdateCompanion<SyncStateData> {
  final Value<int> id;
  final Value<int> lastSeenClock;
  final Value<int> pulledThroughClock;
  const SyncStateCompanion({
    this.id = const Value.absent(),
    this.lastSeenClock = const Value.absent(),
    this.pulledThroughClock = const Value.absent(),
  });
  SyncStateCompanion.insert({
    this.id = const Value.absent(),
    this.lastSeenClock = const Value.absent(),
    this.pulledThroughClock = const Value.absent(),
  });
  static Insertable<SyncStateData> custom({
    Expression<int>? id,
    Expression<int>? lastSeenClock,
    Expression<int>? pulledThroughClock,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (lastSeenClock != null) 'last_seen_clock': lastSeenClock,
      if (pulledThroughClock != null)
        'pulled_through_clock': pulledThroughClock,
    });
  }

  SyncStateCompanion copyWith({
    Value<int>? id,
    Value<int>? lastSeenClock,
    Value<int>? pulledThroughClock,
  }) {
    return SyncStateCompanion(
      id: id ?? this.id,
      lastSeenClock: lastSeenClock ?? this.lastSeenClock,
      pulledThroughClock: pulledThroughClock ?? this.pulledThroughClock,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (lastSeenClock.present) {
      map['last_seen_clock'] = Variable<int>(lastSeenClock.value);
    }
    if (pulledThroughClock.present) {
      map['pulled_through_clock'] = Variable<int>(pulledThroughClock.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateCompanion(')
          ..write('id: $id, ')
          ..write('lastSeenClock: $lastSeenClock, ')
          ..write('pulledThroughClock: $pulledThroughClock')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $WorkspacesTable workspaces = $WorkspacesTable(this);
  late final $IdentitiesTable identities = $IdentitiesTable(this);
  late final $HostGroupsTable hostGroups = $HostGroupsTable(this);
  late final $HostsTable hosts = $HostsTable(this);
  late final $KnownHostsTable knownHosts = $KnownHostsTable(this);
  late final $PortForwardRulesTable portForwardRules = $PortForwardRulesTable(
    this,
  );
  late final $SnippetsTable snippets = $SnippetsTable(this);
  late final $RunbooksTable runbooks = $RunbooksTable(this);
  late final $RunbookStepsTable runbookSteps = $RunbookStepsTable(this);
  late final $TemplatesTable templates = $TemplatesTable(this);
  late final $TemplatePanesTable templatePanes = $TemplatePanesTable(this);
  late final $PairedDevicesTable pairedDevices = $PairedDevicesTable(this);
  late final $McpClientsTable mcpClients = $McpClientsTable(this);
  late final $McpHostGrantsTable mcpHostGrants = $McpHostGrantsTable(this);
  late final $McpPolicyRulesTable mcpPolicyRules = $McpPolicyRulesTable(this);
  late final $McpApprovalsTable mcpApprovals = $McpApprovalsTable(this);
  late final $McpAuditLogTable mcpAuditLog = $McpAuditLogTable(this);
  late final $BookmarksTable bookmarks = $BookmarksTable(this);
  late final $PendingOperationsTable pendingOperations =
      $PendingOperationsTable(this);
  late final $SyncTombstonesTable syncTombstones = $SyncTombstonesTable(this);
  late final $SyncStateTable syncState = $SyncStateTable(this);
  late final HostsDao hostsDao = HostsDao(this as AppDatabase);
  late final IdentitiesDao identitiesDao = IdentitiesDao(this as AppDatabase);
  late final KnownHostsDao knownHostsDao = KnownHostsDao(this as AppDatabase);
  late final TunnelsDao tunnelsDao = TunnelsDao(this as AppDatabase);
  late final WorkspacesDao workspacesDao = WorkspacesDao(this as AppDatabase);
  late final SnippetsDao snippetsDao = SnippetsDao(this as AppDatabase);
  late final RunbooksDao runbooksDao = RunbooksDao(this as AppDatabase);
  late final TemplatesDao templatesDao = TemplatesDao(this as AppDatabase);
  late final PairedDevicesDao pairedDevicesDao = PairedDevicesDao(
    this as AppDatabase,
  );
  late final McpDao mcpDao = McpDao(this as AppDatabase);
  late final BookmarksDao bookmarksDao = BookmarksDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    workspaces,
    identities,
    hostGroups,
    hosts,
    knownHosts,
    portForwardRules,
    snippets,
    runbooks,
    runbookSteps,
    templates,
    templatePanes,
    pairedDevices,
    mcpClients,
    mcpHostGrants,
    mcpPolicyRules,
    mcpApprovals,
    mcpAuditLog,
    bookmarks,
    pendingOperations,
    syncTombstones,
    syncState,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'workspaces',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('identities', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'workspaces',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('host_groups', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'host_groups',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('host_groups', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'workspaces',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('hosts', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'host_groups',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('hosts', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'identities',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('hosts', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'hosts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('hosts', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'hosts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('port_forward_rules', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'workspaces',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('snippets', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'workspaces',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('runbooks', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'runbooks',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('runbook_steps', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'workspaces',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('templates', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'templates',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('template_panes', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'workspaces',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('mcp_clients', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'mcp_clients',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('mcp_host_grants', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'hosts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('mcp_host_grants', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'workspaces',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('mcp_policy_rules', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'mcp_clients',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('mcp_approvals', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'hosts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('mcp_approvals', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'workspaces',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('bookmarks', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'hosts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('bookmarks', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'templates',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('bookmarks', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$WorkspacesTableCreateCompanionBuilder =
    WorkspacesCompanion Function({
      required String id,
      required String name,
      Value<String?> colorCode,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$WorkspacesTableUpdateCompanionBuilder =
    WorkspacesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> colorCode,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$WorkspacesTableReferences
    extends BaseReferences<_$AppDatabase, $WorkspacesTable, Workspace> {
  $$WorkspacesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$IdentitiesTable, List<Identity>>
  _identitiesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.identities,
    aliasName: 'workspaces__id__identities__workspace_id',
  );

  $$IdentitiesTableProcessedTableManager get identitiesRefs {
    final manager = $$IdentitiesTableTableManager(
      $_db,
      $_db.identities,
    ).filter((f) => f.workspaceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_identitiesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$HostGroupsTable, List<HostGroup>>
  _hostGroupsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.hostGroups,
    aliasName: 'workspaces__id__host_groups__workspace_id',
  );

  $$HostGroupsTableProcessedTableManager get hostGroupsRefs {
    final manager = $$HostGroupsTableTableManager(
      $_db,
      $_db.hostGroups,
    ).filter((f) => f.workspaceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_hostGroupsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$HostsTable, List<Host>> _hostsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.hosts,
    aliasName: 'workspaces__id__hosts__workspace_id',
  );

  $$HostsTableProcessedTableManager get hostsRefs {
    final manager = $$HostsTableTableManager(
      $_db,
      $_db.hosts,
    ).filter((f) => f.workspaceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_hostsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SnippetsTable, List<Snippet>> _snippetsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.snippets,
    aliasName: 'workspaces__id__snippets__workspace_id',
  );

  $$SnippetsTableProcessedTableManager get snippetsRefs {
    final manager = $$SnippetsTableTableManager(
      $_db,
      $_db.snippets,
    ).filter((f) => f.workspaceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_snippetsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$RunbooksTable, List<Runbook>> _runbooksRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.runbooks,
    aliasName: 'workspaces__id__runbooks__workspace_id',
  );

  $$RunbooksTableProcessedTableManager get runbooksRefs {
    final manager = $$RunbooksTableTableManager(
      $_db,
      $_db.runbooks,
    ).filter((f) => f.workspaceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_runbooksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$TemplatesTable, List<Template>>
  _templatesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.templates,
    aliasName: 'workspaces__id__templates__workspace_id',
  );

  $$TemplatesTableProcessedTableManager get templatesRefs {
    final manager = $$TemplatesTableTableManager(
      $_db,
      $_db.templates,
    ).filter((f) => f.workspaceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_templatesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$McpClientsTable, List<McpClient>>
  _mcpClientsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.mcpClients,
    aliasName: 'workspaces__id__mcp_clients__workspace_id',
  );

  $$McpClientsTableProcessedTableManager get mcpClientsRefs {
    final manager = $$McpClientsTableTableManager(
      $_db,
      $_db.mcpClients,
    ).filter((f) => f.workspaceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_mcpClientsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$McpPolicyRulesTable, List<McpPolicyRule>>
  _mcpPolicyRulesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.mcpPolicyRules,
    aliasName: 'workspaces__id__mcp_policy_rules__workspace_id',
  );

  $$McpPolicyRulesTableProcessedTableManager get mcpPolicyRulesRefs {
    final manager = $$McpPolicyRulesTableTableManager(
      $_db,
      $_db.mcpPolicyRules,
    ).filter((f) => f.workspaceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_mcpPolicyRulesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$BookmarksTable, List<Bookmark>>
  _bookmarksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.bookmarks,
    aliasName: 'workspaces__id__bookmarks__workspace_id',
  );

  $$BookmarksTableProcessedTableManager get bookmarksRefs {
    final manager = $$BookmarksTableTableManager(
      $_db,
      $_db.bookmarks,
    ).filter((f) => f.workspaceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_bookmarksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$WorkspacesTableFilterComposer
    extends Composer<_$AppDatabase, $WorkspacesTable> {
  $$WorkspacesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get colorCode => $composableBuilder(
    column: $table.colorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> identitiesRefs(
    Expression<bool> Function($$IdentitiesTableFilterComposer f) f,
  ) {
    final $$IdentitiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.identities,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IdentitiesTableFilterComposer(
            $db: $db,
            $table: $db.identities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> hostGroupsRefs(
    Expression<bool> Function($$HostGroupsTableFilterComposer f) f,
  ) {
    final $$HostGroupsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.hostGroups,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostGroupsTableFilterComposer(
            $db: $db,
            $table: $db.hostGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> hostsRefs(
    Expression<bool> Function($$HostsTableFilterComposer f) f,
  ) {
    final $$HostsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.hosts,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostsTableFilterComposer(
            $db: $db,
            $table: $db.hosts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> snippetsRefs(
    Expression<bool> Function($$SnippetsTableFilterComposer f) f,
  ) {
    final $$SnippetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.snippets,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SnippetsTableFilterComposer(
            $db: $db,
            $table: $db.snippets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> runbooksRefs(
    Expression<bool> Function($$RunbooksTableFilterComposer f) f,
  ) {
    final $$RunbooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.runbooks,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RunbooksTableFilterComposer(
            $db: $db,
            $table: $db.runbooks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> templatesRefs(
    Expression<bool> Function($$TemplatesTableFilterComposer f) f,
  ) {
    final $$TemplatesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.templates,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TemplatesTableFilterComposer(
            $db: $db,
            $table: $db.templates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> mcpClientsRefs(
    Expression<bool> Function($$McpClientsTableFilterComposer f) f,
  ) {
    final $$McpClientsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mcpClients,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$McpClientsTableFilterComposer(
            $db: $db,
            $table: $db.mcpClients,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> mcpPolicyRulesRefs(
    Expression<bool> Function($$McpPolicyRulesTableFilterComposer f) f,
  ) {
    final $$McpPolicyRulesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mcpPolicyRules,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$McpPolicyRulesTableFilterComposer(
            $db: $db,
            $table: $db.mcpPolicyRules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> bookmarksRefs(
    Expression<bool> Function($$BookmarksTableFilterComposer f) f,
  ) {
    final $$BookmarksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookmarks,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookmarksTableFilterComposer(
            $db: $db,
            $table: $db.bookmarks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$WorkspacesTableOrderingComposer
    extends Composer<_$AppDatabase, $WorkspacesTable> {
  $$WorkspacesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get colorCode => $composableBuilder(
    column: $table.colorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WorkspacesTableAnnotationComposer
    extends Composer<_$AppDatabase, $WorkspacesTable> {
  $$WorkspacesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get colorCode =>
      $composableBuilder(column: $table.colorCode, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> identitiesRefs<T extends Object>(
    Expression<T> Function($$IdentitiesTableAnnotationComposer a) f,
  ) {
    final $$IdentitiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.identities,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IdentitiesTableAnnotationComposer(
            $db: $db,
            $table: $db.identities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> hostGroupsRefs<T extends Object>(
    Expression<T> Function($$HostGroupsTableAnnotationComposer a) f,
  ) {
    final $$HostGroupsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.hostGroups,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostGroupsTableAnnotationComposer(
            $db: $db,
            $table: $db.hostGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> hostsRefs<T extends Object>(
    Expression<T> Function($$HostsTableAnnotationComposer a) f,
  ) {
    final $$HostsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.hosts,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostsTableAnnotationComposer(
            $db: $db,
            $table: $db.hosts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> snippetsRefs<T extends Object>(
    Expression<T> Function($$SnippetsTableAnnotationComposer a) f,
  ) {
    final $$SnippetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.snippets,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SnippetsTableAnnotationComposer(
            $db: $db,
            $table: $db.snippets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> runbooksRefs<T extends Object>(
    Expression<T> Function($$RunbooksTableAnnotationComposer a) f,
  ) {
    final $$RunbooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.runbooks,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RunbooksTableAnnotationComposer(
            $db: $db,
            $table: $db.runbooks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> templatesRefs<T extends Object>(
    Expression<T> Function($$TemplatesTableAnnotationComposer a) f,
  ) {
    final $$TemplatesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.templates,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TemplatesTableAnnotationComposer(
            $db: $db,
            $table: $db.templates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> mcpClientsRefs<T extends Object>(
    Expression<T> Function($$McpClientsTableAnnotationComposer a) f,
  ) {
    final $$McpClientsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mcpClients,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$McpClientsTableAnnotationComposer(
            $db: $db,
            $table: $db.mcpClients,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> mcpPolicyRulesRefs<T extends Object>(
    Expression<T> Function($$McpPolicyRulesTableAnnotationComposer a) f,
  ) {
    final $$McpPolicyRulesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mcpPolicyRules,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$McpPolicyRulesTableAnnotationComposer(
            $db: $db,
            $table: $db.mcpPolicyRules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> bookmarksRefs<T extends Object>(
    Expression<T> Function($$BookmarksTableAnnotationComposer a) f,
  ) {
    final $$BookmarksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookmarks,
      getReferencedColumn: (t) => t.workspaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookmarksTableAnnotationComposer(
            $db: $db,
            $table: $db.bookmarks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$WorkspacesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WorkspacesTable,
          Workspace,
          $$WorkspacesTableFilterComposer,
          $$WorkspacesTableOrderingComposer,
          $$WorkspacesTableAnnotationComposer,
          $$WorkspacesTableCreateCompanionBuilder,
          $$WorkspacesTableUpdateCompanionBuilder,
          (Workspace, $$WorkspacesTableReferences),
          Workspace,
          PrefetchHooks Function({
            bool identitiesRefs,
            bool hostGroupsRefs,
            bool hostsRefs,
            bool snippetsRefs,
            bool runbooksRefs,
            bool templatesRefs,
            bool mcpClientsRefs,
            bool mcpPolicyRulesRefs,
            bool bookmarksRefs,
          })
        > {
  $$WorkspacesTableTableManager(_$AppDatabase db, $WorkspacesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkspacesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorkspacesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WorkspacesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> colorCode = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WorkspacesCompanion(
                id: id,
                name: name,
                colorCode: colorCode,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> colorCode = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => WorkspacesCompanion.insert(
                id: id,
                name: name,
                colorCode: colorCode,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WorkspacesTable, Workspace>(table),
                  $$WorkspacesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                identitiesRefs = false,
                hostGroupsRefs = false,
                hostsRefs = false,
                snippetsRefs = false,
                runbooksRefs = false,
                templatesRefs = false,
                mcpClientsRefs = false,
                mcpPolicyRulesRefs = false,
                bookmarksRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (identitiesRefs) db.identities,
                    if (hostGroupsRefs) db.hostGroups,
                    if (hostsRefs) db.hosts,
                    if (snippetsRefs) db.snippets,
                    if (runbooksRefs) db.runbooks,
                    if (templatesRefs) db.templates,
                    if (mcpClientsRefs) db.mcpClients,
                    if (mcpPolicyRulesRefs) db.mcpPolicyRules,
                    if (bookmarksRefs) db.bookmarks,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (identitiesRefs)
                        await $_getPrefetchedData<
                          Workspace,
                          $WorkspacesTable,
                          Identity
                        >(
                          currentTable: table,
                          referencedTable: $$WorkspacesTableReferences
                              ._identitiesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WorkspacesTableReferences(
                                db,
                                table,
                                p0,
                              ).identitiesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.workspaceId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (hostGroupsRefs)
                        await $_getPrefetchedData<
                          Workspace,
                          $WorkspacesTable,
                          HostGroup
                        >(
                          currentTable: table,
                          referencedTable: $$WorkspacesTableReferences
                              ._hostGroupsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WorkspacesTableReferences(
                                db,
                                table,
                                p0,
                              ).hostGroupsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.workspaceId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (hostsRefs)
                        await $_getPrefetchedData<
                          Workspace,
                          $WorkspacesTable,
                          Host
                        >(
                          currentTable: table,
                          referencedTable: $$WorkspacesTableReferences
                              ._hostsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WorkspacesTableReferences(
                                db,
                                table,
                                p0,
                              ).hostsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.workspaceId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (snippetsRefs)
                        await $_getPrefetchedData<
                          Workspace,
                          $WorkspacesTable,
                          Snippet
                        >(
                          currentTable: table,
                          referencedTable: $$WorkspacesTableReferences
                              ._snippetsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WorkspacesTableReferences(
                                db,
                                table,
                                p0,
                              ).snippetsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.workspaceId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (runbooksRefs)
                        await $_getPrefetchedData<
                          Workspace,
                          $WorkspacesTable,
                          Runbook
                        >(
                          currentTable: table,
                          referencedTable: $$WorkspacesTableReferences
                              ._runbooksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WorkspacesTableReferences(
                                db,
                                table,
                                p0,
                              ).runbooksRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.workspaceId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (templatesRefs)
                        await $_getPrefetchedData<
                          Workspace,
                          $WorkspacesTable,
                          Template
                        >(
                          currentTable: table,
                          referencedTable: $$WorkspacesTableReferences
                              ._templatesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WorkspacesTableReferences(
                                db,
                                table,
                                p0,
                              ).templatesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.workspaceId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (mcpClientsRefs)
                        await $_getPrefetchedData<
                          Workspace,
                          $WorkspacesTable,
                          McpClient
                        >(
                          currentTable: table,
                          referencedTable: $$WorkspacesTableReferences
                              ._mcpClientsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WorkspacesTableReferences(
                                db,
                                table,
                                p0,
                              ).mcpClientsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.workspaceId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (mcpPolicyRulesRefs)
                        await $_getPrefetchedData<
                          Workspace,
                          $WorkspacesTable,
                          McpPolicyRule
                        >(
                          currentTable: table,
                          referencedTable: $$WorkspacesTableReferences
                              ._mcpPolicyRulesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WorkspacesTableReferences(
                                db,
                                table,
                                p0,
                              ).mcpPolicyRulesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.workspaceId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (bookmarksRefs)
                        await $_getPrefetchedData<
                          Workspace,
                          $WorkspacesTable,
                          Bookmark
                        >(
                          currentTable: table,
                          referencedTable: $$WorkspacesTableReferences
                              ._bookmarksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WorkspacesTableReferences(
                                db,
                                table,
                                p0,
                              ).bookmarksRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.workspaceId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$WorkspacesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WorkspacesTable,
      Workspace,
      $$WorkspacesTableFilterComposer,
      $$WorkspacesTableOrderingComposer,
      $$WorkspacesTableAnnotationComposer,
      $$WorkspacesTableCreateCompanionBuilder,
      $$WorkspacesTableUpdateCompanionBuilder,
      (Workspace, $$WorkspacesTableReferences),
      Workspace,
      PrefetchHooks Function({
        bool identitiesRefs,
        bool hostGroupsRefs,
        bool hostsRefs,
        bool snippetsRefs,
        bool runbooksRefs,
        bool templatesRefs,
        bool mcpClientsRefs,
        bool mcpPolicyRulesRefs,
        bool bookmarksRefs,
      })
    >;
typedef $$IdentitiesTableCreateCompanionBuilder =
    IdentitiesCompanion Function({
      required String id,
      required String workspaceId,
      required String title,
      required String username,
      required String authType,
      Value<String?> passwordEncrypted,
      Value<String?> privateKeyEncrypted,
      Value<String?> passphraseEncrypted,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$IdentitiesTableUpdateCompanionBuilder =
    IdentitiesCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String> title,
      Value<String> username,
      Value<String> authType,
      Value<String?> passwordEncrypted,
      Value<String?> privateKeyEncrypted,
      Value<String?> passphraseEncrypted,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$IdentitiesTableReferences
    extends BaseReferences<_$AppDatabase, $IdentitiesTable, Identity> {
  $$IdentitiesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $WorkspacesTable _workspaceIdTable(_$AppDatabase db) =>
      db.workspaces.createAlias('identities__workspace_id__workspaces__id');

  $$WorkspacesTableProcessedTableManager get workspaceId {
    final $_column = $_itemColumn<String>('workspace_id')!;

    final manager = $$WorkspacesTableTableManager(
      $_db,
      $_db.workspaces,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_workspaceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$HostsTable, List<Host>> _hostsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.hosts,
    aliasName: 'identities__id__hosts__identity_id',
  );

  $$HostsTableProcessedTableManager get hostsRefs {
    final manager = $$HostsTableTableManager(
      $_db,
      $_db.hosts,
    ).filter((f) => f.identityId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_hostsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$IdentitiesTableFilterComposer
    extends Composer<_$AppDatabase, $IdentitiesTable> {
  $$IdentitiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authType => $composableBuilder(
    column: $table.authType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get passwordEncrypted => $composableBuilder(
    column: $table.passwordEncrypted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get privateKeyEncrypted => $composableBuilder(
    column: $table.privateKeyEncrypted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get passphraseEncrypted => $composableBuilder(
    column: $table.passphraseEncrypted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$WorkspacesTableFilterComposer get workspaceId {
    final $$WorkspacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableFilterComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> hostsRefs(
    Expression<bool> Function($$HostsTableFilterComposer f) f,
  ) {
    final $$HostsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.hosts,
      getReferencedColumn: (t) => t.identityId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostsTableFilterComposer(
            $db: $db,
            $table: $db.hosts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$IdentitiesTableOrderingComposer
    extends Composer<_$AppDatabase, $IdentitiesTable> {
  $$IdentitiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authType => $composableBuilder(
    column: $table.authType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get passwordEncrypted => $composableBuilder(
    column: $table.passwordEncrypted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get privateKeyEncrypted => $composableBuilder(
    column: $table.privateKeyEncrypted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get passphraseEncrypted => $composableBuilder(
    column: $table.passphraseEncrypted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$WorkspacesTableOrderingComposer get workspaceId {
    final $$WorkspacesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableOrderingComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$IdentitiesTableAnnotationComposer
    extends Composer<_$AppDatabase, $IdentitiesTable> {
  $$IdentitiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get authType =>
      $composableBuilder(column: $table.authType, builder: (column) => column);

  GeneratedColumn<String> get passwordEncrypted => $composableBuilder(
    column: $table.passwordEncrypted,
    builder: (column) => column,
  );

  GeneratedColumn<String> get privateKeyEncrypted => $composableBuilder(
    column: $table.privateKeyEncrypted,
    builder: (column) => column,
  );

  GeneratedColumn<String> get passphraseEncrypted => $composableBuilder(
    column: $table.passphraseEncrypted,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$WorkspacesTableAnnotationComposer get workspaceId {
    final $$WorkspacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableAnnotationComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> hostsRefs<T extends Object>(
    Expression<T> Function($$HostsTableAnnotationComposer a) f,
  ) {
    final $$HostsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.hosts,
      getReferencedColumn: (t) => t.identityId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostsTableAnnotationComposer(
            $db: $db,
            $table: $db.hosts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$IdentitiesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $IdentitiesTable,
          Identity,
          $$IdentitiesTableFilterComposer,
          $$IdentitiesTableOrderingComposer,
          $$IdentitiesTableAnnotationComposer,
          $$IdentitiesTableCreateCompanionBuilder,
          $$IdentitiesTableUpdateCompanionBuilder,
          (Identity, $$IdentitiesTableReferences),
          Identity,
          PrefetchHooks Function({bool workspaceId, bool hostsRefs})
        > {
  $$IdentitiesTableTableManager(_$AppDatabase db, $IdentitiesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$IdentitiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$IdentitiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$IdentitiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String> authType = const Value.absent(),
                Value<String?> passwordEncrypted = const Value.absent(),
                Value<String?> privateKeyEncrypted = const Value.absent(),
                Value<String?> passphraseEncrypted = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => IdentitiesCompanion(
                id: id,
                workspaceId: workspaceId,
                title: title,
                username: username,
                authType: authType,
                passwordEncrypted: passwordEncrypted,
                privateKeyEncrypted: privateKeyEncrypted,
                passphraseEncrypted: passphraseEncrypted,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String title,
                required String username,
                required String authType,
                Value<String?> passwordEncrypted = const Value.absent(),
                Value<String?> privateKeyEncrypted = const Value.absent(),
                Value<String?> passphraseEncrypted = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => IdentitiesCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                title: title,
                username: username,
                authType: authType,
                passwordEncrypted: passwordEncrypted,
                privateKeyEncrypted: privateKeyEncrypted,
                passphraseEncrypted: passphraseEncrypted,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$IdentitiesTable, Identity>(table),
                  $$IdentitiesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({workspaceId = false, hostsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (hostsRefs) db.hosts],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (workspaceId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.workspaceId,
                                referencedTable: $$IdentitiesTableReferences
                                    ._workspaceIdTable(db),
                                referencedColumn: $$IdentitiesTableReferences
                                    ._workspaceIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (hostsRefs)
                    await $_getPrefetchedData<Identity, $IdentitiesTable, Host>(
                      currentTable: table,
                      referencedTable: $$IdentitiesTableReferences
                          ._hostsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$IdentitiesTableReferences(db, table, p0).hostsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.identityId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$IdentitiesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $IdentitiesTable,
      Identity,
      $$IdentitiesTableFilterComposer,
      $$IdentitiesTableOrderingComposer,
      $$IdentitiesTableAnnotationComposer,
      $$IdentitiesTableCreateCompanionBuilder,
      $$IdentitiesTableUpdateCompanionBuilder,
      (Identity, $$IdentitiesTableReferences),
      Identity,
      PrefetchHooks Function({bool workspaceId, bool hostsRefs})
    >;
typedef $$HostGroupsTableCreateCompanionBuilder =
    HostGroupsCompanion Function({
      required String id,
      required String workspaceId,
      Value<String?> parentId,
      required String name,
      Value<String?> colorTag,
      Value<int> rowid,
    });
typedef $$HostGroupsTableUpdateCompanionBuilder =
    HostGroupsCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String?> parentId,
      Value<String> name,
      Value<String?> colorTag,
      Value<int> rowid,
    });

final class $$HostGroupsTableReferences
    extends BaseReferences<_$AppDatabase, $HostGroupsTable, HostGroup> {
  $$HostGroupsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $WorkspacesTable _workspaceIdTable(_$AppDatabase db) =>
      db.workspaces.createAlias('host_groups__workspace_id__workspaces__id');

  $$WorkspacesTableProcessedTableManager get workspaceId {
    final $_column = $_itemColumn<String>('workspace_id')!;

    final manager = $$WorkspacesTableTableManager(
      $_db,
      $_db.workspaces,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_workspaceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $HostGroupsTable _parentIdTable(_$AppDatabase db) =>
      db.hostGroups.createAlias('host_groups__parent_id__host_groups__id');

  $$HostGroupsTableProcessedTableManager? get parentId {
    final $_column = $_itemColumn<String>('parent_id');
    if ($_column == null) return null;
    final manager = $$HostGroupsTableTableManager(
      $_db,
      $_db.hostGroups,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_parentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$HostsTable, List<Host>> _hostsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.hosts,
    aliasName: 'host_groups__id__hosts__group_id',
  );

  $$HostsTableProcessedTableManager get hostsRefs {
    final manager = $$HostsTableTableManager(
      $_db,
      $_db.hosts,
    ).filter((f) => f.groupId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_hostsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$HostGroupsTableFilterComposer
    extends Composer<_$AppDatabase, $HostGroupsTable> {
  $$HostGroupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get colorTag => $composableBuilder(
    column: $table.colorTag,
    builder: (column) => ColumnFilters(column),
  );

  $$WorkspacesTableFilterComposer get workspaceId {
    final $$WorkspacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableFilterComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$HostGroupsTableFilterComposer get parentId {
    final $$HostGroupsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.hostGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostGroupsTableFilterComposer(
            $db: $db,
            $table: $db.hostGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> hostsRefs(
    Expression<bool> Function($$HostsTableFilterComposer f) f,
  ) {
    final $$HostsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.hosts,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostsTableFilterComposer(
            $db: $db,
            $table: $db.hosts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$HostGroupsTableOrderingComposer
    extends Composer<_$AppDatabase, $HostGroupsTable> {
  $$HostGroupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get colorTag => $composableBuilder(
    column: $table.colorTag,
    builder: (column) => ColumnOrderings(column),
  );

  $$WorkspacesTableOrderingComposer get workspaceId {
    final $$WorkspacesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableOrderingComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$HostGroupsTableOrderingComposer get parentId {
    final $$HostGroupsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.hostGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostGroupsTableOrderingComposer(
            $db: $db,
            $table: $db.hostGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HostGroupsTableAnnotationComposer
    extends Composer<_$AppDatabase, $HostGroupsTable> {
  $$HostGroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get colorTag =>
      $composableBuilder(column: $table.colorTag, builder: (column) => column);

  $$WorkspacesTableAnnotationComposer get workspaceId {
    final $$WorkspacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableAnnotationComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$HostGroupsTableAnnotationComposer get parentId {
    final $$HostGroupsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.hostGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostGroupsTableAnnotationComposer(
            $db: $db,
            $table: $db.hostGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> hostsRefs<T extends Object>(
    Expression<T> Function($$HostsTableAnnotationComposer a) f,
  ) {
    final $$HostsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.hosts,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostsTableAnnotationComposer(
            $db: $db,
            $table: $db.hosts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$HostGroupsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HostGroupsTable,
          HostGroup,
          $$HostGroupsTableFilterComposer,
          $$HostGroupsTableOrderingComposer,
          $$HostGroupsTableAnnotationComposer,
          $$HostGroupsTableCreateCompanionBuilder,
          $$HostGroupsTableUpdateCompanionBuilder,
          (HostGroup, $$HostGroupsTableReferences),
          HostGroup,
          PrefetchHooks Function({
            bool workspaceId,
            bool parentId,
            bool hostsRefs,
          })
        > {
  $$HostGroupsTableTableManager(_$AppDatabase db, $HostGroupsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HostGroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HostGroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HostGroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> colorTag = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HostGroupsCompanion(
                id: id,
                workspaceId: workspaceId,
                parentId: parentId,
                name: name,
                colorTag: colorTag,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                Value<String?> parentId = const Value.absent(),
                required String name,
                Value<String?> colorTag = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HostGroupsCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                parentId: parentId,
                name: name,
                colorTag: colorTag,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$HostGroupsTable, HostGroup>(table),
                  $$HostGroupsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({workspaceId = false, parentId = false, hostsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [if (hostsRefs) db.hosts],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (workspaceId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.workspaceId,
                                    referencedTable: $$HostGroupsTableReferences
                                        ._workspaceIdTable(db),
                                    referencedColumn:
                                        $$HostGroupsTableReferences
                                            ._workspaceIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (parentId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.parentId,
                                    referencedTable: $$HostGroupsTableReferences
                                        ._parentIdTable(db),
                                    referencedColumn:
                                        $$HostGroupsTableReferences
                                            ._parentIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (hostsRefs)
                        await $_getPrefetchedData<
                          HostGroup,
                          $HostGroupsTable,
                          Host
                        >(
                          currentTable: table,
                          referencedTable: $$HostGroupsTableReferences
                              ._hostsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$HostGroupsTableReferences(
                                db,
                                table,
                                p0,
                              ).hostsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.groupId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$HostGroupsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HostGroupsTable,
      HostGroup,
      $$HostGroupsTableFilterComposer,
      $$HostGroupsTableOrderingComposer,
      $$HostGroupsTableAnnotationComposer,
      $$HostGroupsTableCreateCompanionBuilder,
      $$HostGroupsTableUpdateCompanionBuilder,
      (HostGroup, $$HostGroupsTableReferences),
      HostGroup,
      PrefetchHooks Function({bool workspaceId, bool parentId, bool hostsRefs})
    >;
typedef $$HostsTableCreateCompanionBuilder =
    HostsCompanion Function({
      required String id,
      required String workspaceId,
      Value<String?> groupId,
      Value<String?> identityId,
      required String label,
      required String hostname,
      Value<String?> username,
      Value<int> port,
      Value<String> protocol,
      Value<String?> moshServerPath,
      Value<String?> moshPortRange,
      Value<String?> colorTag,
      Value<String?> jumpHostId,
      required DateTime createdAt,
      Value<String> environment,
      Value<bool> mcpVisible,
      Value<String> mcpDefaultMode,
      Value<int> rowid,
    });
typedef $$HostsTableUpdateCompanionBuilder =
    HostsCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String?> groupId,
      Value<String?> identityId,
      Value<String> label,
      Value<String> hostname,
      Value<String?> username,
      Value<int> port,
      Value<String> protocol,
      Value<String?> moshServerPath,
      Value<String?> moshPortRange,
      Value<String?> colorTag,
      Value<String?> jumpHostId,
      Value<DateTime> createdAt,
      Value<String> environment,
      Value<bool> mcpVisible,
      Value<String> mcpDefaultMode,
      Value<int> rowid,
    });

final class $$HostsTableReferences
    extends BaseReferences<_$AppDatabase, $HostsTable, Host> {
  $$HostsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $WorkspacesTable _workspaceIdTable(_$AppDatabase db) =>
      db.workspaces.createAlias('hosts__workspace_id__workspaces__id');

  $$WorkspacesTableProcessedTableManager get workspaceId {
    final $_column = $_itemColumn<String>('workspace_id')!;

    final manager = $$WorkspacesTableTableManager(
      $_db,
      $_db.workspaces,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_workspaceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $HostGroupsTable _groupIdTable(_$AppDatabase db) =>
      db.hostGroups.createAlias('hosts__group_id__host_groups__id');

  $$HostGroupsTableProcessedTableManager? get groupId {
    final $_column = $_itemColumn<String>('group_id');
    if ($_column == null) return null;
    final manager = $$HostGroupsTableTableManager(
      $_db,
      $_db.hostGroups,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_groupIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $IdentitiesTable _identityIdTable(_$AppDatabase db) =>
      db.identities.createAlias('hosts__identity_id__identities__id');

  $$IdentitiesTableProcessedTableManager? get identityId {
    final $_column = $_itemColumn<String>('identity_id');
    if ($_column == null) return null;
    final manager = $$IdentitiesTableTableManager(
      $_db,
      $_db.identities,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_identityIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $HostsTable _jumpHostIdTable(_$AppDatabase db) =>
      db.hosts.createAlias('hosts__jump_host_id__hosts__id');

  $$HostsTableProcessedTableManager? get jumpHostId {
    final $_column = $_itemColumn<String>('jump_host_id');
    if ($_column == null) return null;
    final manager = $$HostsTableTableManager(
      $_db,
      $_db.hosts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_jumpHostIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$PortForwardRulesTable, List<PortForwardRule>>
  _portForwardRulesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.portForwardRules,
    aliasName: 'hosts__id__port_forward_rules__host_id',
  );

  $$PortForwardRulesTableProcessedTableManager get portForwardRulesRefs {
    final manager = $$PortForwardRulesTableTableManager(
      $_db,
      $_db.portForwardRules,
    ).filter((f) => f.hostId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _portForwardRulesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$McpHostGrantsTable, List<McpHostGrant>>
  _mcpHostGrantsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.mcpHostGrants,
    aliasName: 'hosts__id__mcp_host_grants__host_id',
  );

  $$McpHostGrantsTableProcessedTableManager get mcpHostGrantsRefs {
    final manager = $$McpHostGrantsTableTableManager(
      $_db,
      $_db.mcpHostGrants,
    ).filter((f) => f.hostId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_mcpHostGrantsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$McpApprovalsTable, List<McpApproval>>
  _mcpApprovalsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.mcpApprovals,
    aliasName: 'hosts__id__mcp_approvals__host_id',
  );

  $$McpApprovalsTableProcessedTableManager get mcpApprovalsRefs {
    final manager = $$McpApprovalsTableTableManager(
      $_db,
      $_db.mcpApprovals,
    ).filter((f) => f.hostId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_mcpApprovalsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$BookmarksTable, List<Bookmark>>
  _bookmarksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.bookmarks,
    aliasName: 'hosts__id__bookmarks__host_id',
  );

  $$BookmarksTableProcessedTableManager get bookmarksRefs {
    final manager = $$BookmarksTableTableManager(
      $_db,
      $_db.bookmarks,
    ).filter((f) => f.hostId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_bookmarksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$HostsTableFilterComposer extends Composer<_$AppDatabase, $HostsTable> {
  $$HostsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hostname => $composableBuilder(
    column: $table.hostname,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get protocol => $composableBuilder(
    column: $table.protocol,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get moshServerPath => $composableBuilder(
    column: $table.moshServerPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get moshPortRange => $composableBuilder(
    column: $table.moshPortRange,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get colorTag => $composableBuilder(
    column: $table.colorTag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get environment => $composableBuilder(
    column: $table.environment,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get mcpVisible => $composableBuilder(
    column: $table.mcpVisible,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mcpDefaultMode => $composableBuilder(
    column: $table.mcpDefaultMode,
    builder: (column) => ColumnFilters(column),
  );

  $$WorkspacesTableFilterComposer get workspaceId {
    final $$WorkspacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableFilterComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$HostGroupsTableFilterComposer get groupId {
    final $$HostGroupsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.hostGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostGroupsTableFilterComposer(
            $db: $db,
            $table: $db.hostGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$IdentitiesTableFilterComposer get identityId {
    final $$IdentitiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.identityId,
      referencedTable: $db.identities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IdentitiesTableFilterComposer(
            $db: $db,
            $table: $db.identities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$HostsTableFilterComposer get jumpHostId {
    final $$HostsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.jumpHostId,
      referencedTable: $db.hosts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostsTableFilterComposer(
            $db: $db,
            $table: $db.hosts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> portForwardRulesRefs(
    Expression<bool> Function($$PortForwardRulesTableFilterComposer f) f,
  ) {
    final $$PortForwardRulesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.portForwardRules,
      getReferencedColumn: (t) => t.hostId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PortForwardRulesTableFilterComposer(
            $db: $db,
            $table: $db.portForwardRules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> mcpHostGrantsRefs(
    Expression<bool> Function($$McpHostGrantsTableFilterComposer f) f,
  ) {
    final $$McpHostGrantsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mcpHostGrants,
      getReferencedColumn: (t) => t.hostId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$McpHostGrantsTableFilterComposer(
            $db: $db,
            $table: $db.mcpHostGrants,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> mcpApprovalsRefs(
    Expression<bool> Function($$McpApprovalsTableFilterComposer f) f,
  ) {
    final $$McpApprovalsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mcpApprovals,
      getReferencedColumn: (t) => t.hostId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$McpApprovalsTableFilterComposer(
            $db: $db,
            $table: $db.mcpApprovals,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> bookmarksRefs(
    Expression<bool> Function($$BookmarksTableFilterComposer f) f,
  ) {
    final $$BookmarksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookmarks,
      getReferencedColumn: (t) => t.hostId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookmarksTableFilterComposer(
            $db: $db,
            $table: $db.bookmarks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$HostsTableOrderingComposer
    extends Composer<_$AppDatabase, $HostsTable> {
  $$HostsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hostname => $composableBuilder(
    column: $table.hostname,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get protocol => $composableBuilder(
    column: $table.protocol,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get moshServerPath => $composableBuilder(
    column: $table.moshServerPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get moshPortRange => $composableBuilder(
    column: $table.moshPortRange,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get colorTag => $composableBuilder(
    column: $table.colorTag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get environment => $composableBuilder(
    column: $table.environment,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get mcpVisible => $composableBuilder(
    column: $table.mcpVisible,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mcpDefaultMode => $composableBuilder(
    column: $table.mcpDefaultMode,
    builder: (column) => ColumnOrderings(column),
  );

  $$WorkspacesTableOrderingComposer get workspaceId {
    final $$WorkspacesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableOrderingComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$HostGroupsTableOrderingComposer get groupId {
    final $$HostGroupsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.hostGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostGroupsTableOrderingComposer(
            $db: $db,
            $table: $db.hostGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$IdentitiesTableOrderingComposer get identityId {
    final $$IdentitiesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.identityId,
      referencedTable: $db.identities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IdentitiesTableOrderingComposer(
            $db: $db,
            $table: $db.identities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$HostsTableOrderingComposer get jumpHostId {
    final $$HostsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.jumpHostId,
      referencedTable: $db.hosts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostsTableOrderingComposer(
            $db: $db,
            $table: $db.hosts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HostsTableAnnotationComposer
    extends Composer<_$AppDatabase, $HostsTable> {
  $$HostsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get hostname =>
      $composableBuilder(column: $table.hostname, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<int> get port =>
      $composableBuilder(column: $table.port, builder: (column) => column);

  GeneratedColumn<String> get protocol =>
      $composableBuilder(column: $table.protocol, builder: (column) => column);

  GeneratedColumn<String> get moshServerPath => $composableBuilder(
    column: $table.moshServerPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get moshPortRange => $composableBuilder(
    column: $table.moshPortRange,
    builder: (column) => column,
  );

  GeneratedColumn<String> get colorTag =>
      $composableBuilder(column: $table.colorTag, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get environment => $composableBuilder(
    column: $table.environment,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get mcpVisible => $composableBuilder(
    column: $table.mcpVisible,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mcpDefaultMode => $composableBuilder(
    column: $table.mcpDefaultMode,
    builder: (column) => column,
  );

  $$WorkspacesTableAnnotationComposer get workspaceId {
    final $$WorkspacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableAnnotationComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$HostGroupsTableAnnotationComposer get groupId {
    final $$HostGroupsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.hostGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostGroupsTableAnnotationComposer(
            $db: $db,
            $table: $db.hostGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$IdentitiesTableAnnotationComposer get identityId {
    final $$IdentitiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.identityId,
      referencedTable: $db.identities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IdentitiesTableAnnotationComposer(
            $db: $db,
            $table: $db.identities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$HostsTableAnnotationComposer get jumpHostId {
    final $$HostsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.jumpHostId,
      referencedTable: $db.hosts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostsTableAnnotationComposer(
            $db: $db,
            $table: $db.hosts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> portForwardRulesRefs<T extends Object>(
    Expression<T> Function($$PortForwardRulesTableAnnotationComposer a) f,
  ) {
    final $$PortForwardRulesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.portForwardRules,
      getReferencedColumn: (t) => t.hostId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PortForwardRulesTableAnnotationComposer(
            $db: $db,
            $table: $db.portForwardRules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> mcpHostGrantsRefs<T extends Object>(
    Expression<T> Function($$McpHostGrantsTableAnnotationComposer a) f,
  ) {
    final $$McpHostGrantsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mcpHostGrants,
      getReferencedColumn: (t) => t.hostId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$McpHostGrantsTableAnnotationComposer(
            $db: $db,
            $table: $db.mcpHostGrants,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> mcpApprovalsRefs<T extends Object>(
    Expression<T> Function($$McpApprovalsTableAnnotationComposer a) f,
  ) {
    final $$McpApprovalsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mcpApprovals,
      getReferencedColumn: (t) => t.hostId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$McpApprovalsTableAnnotationComposer(
            $db: $db,
            $table: $db.mcpApprovals,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> bookmarksRefs<T extends Object>(
    Expression<T> Function($$BookmarksTableAnnotationComposer a) f,
  ) {
    final $$BookmarksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookmarks,
      getReferencedColumn: (t) => t.hostId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookmarksTableAnnotationComposer(
            $db: $db,
            $table: $db.bookmarks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$HostsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HostsTable,
          Host,
          $$HostsTableFilterComposer,
          $$HostsTableOrderingComposer,
          $$HostsTableAnnotationComposer,
          $$HostsTableCreateCompanionBuilder,
          $$HostsTableUpdateCompanionBuilder,
          (Host, $$HostsTableReferences),
          Host,
          PrefetchHooks Function({
            bool workspaceId,
            bool groupId,
            bool identityId,
            bool jumpHostId,
            bool portForwardRulesRefs,
            bool mcpHostGrantsRefs,
            bool mcpApprovalsRefs,
            bool bookmarksRefs,
          })
        > {
  $$HostsTableTableManager(_$AppDatabase db, $HostsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HostsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HostsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HostsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String?> groupId = const Value.absent(),
                Value<String?> identityId = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String> hostname = const Value.absent(),
                Value<String?> username = const Value.absent(),
                Value<int> port = const Value.absent(),
                Value<String> protocol = const Value.absent(),
                Value<String?> moshServerPath = const Value.absent(),
                Value<String?> moshPortRange = const Value.absent(),
                Value<String?> colorTag = const Value.absent(),
                Value<String?> jumpHostId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> environment = const Value.absent(),
                Value<bool> mcpVisible = const Value.absent(),
                Value<String> mcpDefaultMode = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HostsCompanion(
                id: id,
                workspaceId: workspaceId,
                groupId: groupId,
                identityId: identityId,
                label: label,
                hostname: hostname,
                username: username,
                port: port,
                protocol: protocol,
                moshServerPath: moshServerPath,
                moshPortRange: moshPortRange,
                colorTag: colorTag,
                jumpHostId: jumpHostId,
                createdAt: createdAt,
                environment: environment,
                mcpVisible: mcpVisible,
                mcpDefaultMode: mcpDefaultMode,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                Value<String?> groupId = const Value.absent(),
                Value<String?> identityId = const Value.absent(),
                required String label,
                required String hostname,
                Value<String?> username = const Value.absent(),
                Value<int> port = const Value.absent(),
                Value<String> protocol = const Value.absent(),
                Value<String?> moshServerPath = const Value.absent(),
                Value<String?> moshPortRange = const Value.absent(),
                Value<String?> colorTag = const Value.absent(),
                Value<String?> jumpHostId = const Value.absent(),
                required DateTime createdAt,
                Value<String> environment = const Value.absent(),
                Value<bool> mcpVisible = const Value.absent(),
                Value<String> mcpDefaultMode = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HostsCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                groupId: groupId,
                identityId: identityId,
                label: label,
                hostname: hostname,
                username: username,
                port: port,
                protocol: protocol,
                moshServerPath: moshServerPath,
                moshPortRange: moshPortRange,
                colorTag: colorTag,
                jumpHostId: jumpHostId,
                createdAt: createdAt,
                environment: environment,
                mcpVisible: mcpVisible,
                mcpDefaultMode: mcpDefaultMode,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$HostsTable, Host>(table),
                  $$HostsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                workspaceId = false,
                groupId = false,
                identityId = false,
                jumpHostId = false,
                portForwardRulesRefs = false,
                mcpHostGrantsRefs = false,
                mcpApprovalsRefs = false,
                bookmarksRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (portForwardRulesRefs) db.portForwardRules,
                    if (mcpHostGrantsRefs) db.mcpHostGrants,
                    if (mcpApprovalsRefs) db.mcpApprovals,
                    if (bookmarksRefs) db.bookmarks,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (workspaceId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.workspaceId,
                                    referencedTable: $$HostsTableReferences
                                        ._workspaceIdTable(db),
                                    referencedColumn: $$HostsTableReferences
                                        ._workspaceIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (groupId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.groupId,
                                    referencedTable: $$HostsTableReferences
                                        ._groupIdTable(db),
                                    referencedColumn: $$HostsTableReferences
                                        ._groupIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (identityId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.identityId,
                                    referencedTable: $$HostsTableReferences
                                        ._identityIdTable(db),
                                    referencedColumn: $$HostsTableReferences
                                        ._identityIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (jumpHostId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.jumpHostId,
                                    referencedTable: $$HostsTableReferences
                                        ._jumpHostIdTable(db),
                                    referencedColumn: $$HostsTableReferences
                                        ._jumpHostIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (portForwardRulesRefs)
                        await $_getPrefetchedData<
                          Host,
                          $HostsTable,
                          PortForwardRule
                        >(
                          currentTable: table,
                          referencedTable: $$HostsTableReferences
                              ._portForwardRulesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$HostsTableReferences(
                                db,
                                table,
                                p0,
                              ).portForwardRulesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.hostId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (mcpHostGrantsRefs)
                        await $_getPrefetchedData<
                          Host,
                          $HostsTable,
                          McpHostGrant
                        >(
                          currentTable: table,
                          referencedTable: $$HostsTableReferences
                              ._mcpHostGrantsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$HostsTableReferences(
                                db,
                                table,
                                p0,
                              ).mcpHostGrantsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.hostId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (mcpApprovalsRefs)
                        await $_getPrefetchedData<
                          Host,
                          $HostsTable,
                          McpApproval
                        >(
                          currentTable: table,
                          referencedTable: $$HostsTableReferences
                              ._mcpApprovalsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$HostsTableReferences(
                                db,
                                table,
                                p0,
                              ).mcpApprovalsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.hostId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (bookmarksRefs)
                        await $_getPrefetchedData<Host, $HostsTable, Bookmark>(
                          currentTable: table,
                          referencedTable: $$HostsTableReferences
                              ._bookmarksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$HostsTableReferences(
                                db,
                                table,
                                p0,
                              ).bookmarksRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.hostId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$HostsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HostsTable,
      Host,
      $$HostsTableFilterComposer,
      $$HostsTableOrderingComposer,
      $$HostsTableAnnotationComposer,
      $$HostsTableCreateCompanionBuilder,
      $$HostsTableUpdateCompanionBuilder,
      (Host, $$HostsTableReferences),
      Host,
      PrefetchHooks Function({
        bool workspaceId,
        bool groupId,
        bool identityId,
        bool jumpHostId,
        bool portForwardRulesRefs,
        bool mcpHostGrantsRefs,
        bool mcpApprovalsRefs,
        bool bookmarksRefs,
      })
    >;
typedef $$KnownHostsTableCreateCompanionBuilder =
    KnownHostsCompanion Function({
      required String id,
      required String hostname,
      required int port,
      required String keyType,
      required String fingerprintSha256,
      required DateTime firstSeenAt,
      Value<int> rowid,
    });
typedef $$KnownHostsTableUpdateCompanionBuilder =
    KnownHostsCompanion Function({
      Value<String> id,
      Value<String> hostname,
      Value<int> port,
      Value<String> keyType,
      Value<String> fingerprintSha256,
      Value<DateTime> firstSeenAt,
      Value<int> rowid,
    });

class $$KnownHostsTableFilterComposer
    extends Composer<_$AppDatabase, $KnownHostsTable> {
  $$KnownHostsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hostname => $composableBuilder(
    column: $table.hostname,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get keyType => $composableBuilder(
    column: $table.keyType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fingerprintSha256 => $composableBuilder(
    column: $table.fingerprintSha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get firstSeenAt => $composableBuilder(
    column: $table.firstSeenAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$KnownHostsTableOrderingComposer
    extends Composer<_$AppDatabase, $KnownHostsTable> {
  $$KnownHostsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hostname => $composableBuilder(
    column: $table.hostname,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get keyType => $composableBuilder(
    column: $table.keyType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fingerprintSha256 => $composableBuilder(
    column: $table.fingerprintSha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get firstSeenAt => $composableBuilder(
    column: $table.firstSeenAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$KnownHostsTableAnnotationComposer
    extends Composer<_$AppDatabase, $KnownHostsTable> {
  $$KnownHostsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get hostname =>
      $composableBuilder(column: $table.hostname, builder: (column) => column);

  GeneratedColumn<int> get port =>
      $composableBuilder(column: $table.port, builder: (column) => column);

  GeneratedColumn<String> get keyType =>
      $composableBuilder(column: $table.keyType, builder: (column) => column);

  GeneratedColumn<String> get fingerprintSha256 => $composableBuilder(
    column: $table.fingerprintSha256,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get firstSeenAt => $composableBuilder(
    column: $table.firstSeenAt,
    builder: (column) => column,
  );
}

class $$KnownHostsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $KnownHostsTable,
          KnownHost,
          $$KnownHostsTableFilterComposer,
          $$KnownHostsTableOrderingComposer,
          $$KnownHostsTableAnnotationComposer,
          $$KnownHostsTableCreateCompanionBuilder,
          $$KnownHostsTableUpdateCompanionBuilder,
          (
            KnownHost,
            BaseReferences<_$AppDatabase, $KnownHostsTable, KnownHost>,
          ),
          KnownHost,
          PrefetchHooks Function()
        > {
  $$KnownHostsTableTableManager(_$AppDatabase db, $KnownHostsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KnownHostsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KnownHostsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KnownHostsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> hostname = const Value.absent(),
                Value<int> port = const Value.absent(),
                Value<String> keyType = const Value.absent(),
                Value<String> fingerprintSha256 = const Value.absent(),
                Value<DateTime> firstSeenAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KnownHostsCompanion(
                id: id,
                hostname: hostname,
                port: port,
                keyType: keyType,
                fingerprintSha256: fingerprintSha256,
                firstSeenAt: firstSeenAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String hostname,
                required int port,
                required String keyType,
                required String fingerprintSha256,
                required DateTime firstSeenAt,
                Value<int> rowid = const Value.absent(),
              }) => KnownHostsCompanion.insert(
                id: id,
                hostname: hostname,
                port: port,
                keyType: keyType,
                fingerprintSha256: fingerprintSha256,
                firstSeenAt: firstSeenAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$KnownHostsTable, KnownHost>(table),
                  BaseReferences<_$AppDatabase, $KnownHostsTable, KnownHost>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$KnownHostsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $KnownHostsTable,
      KnownHost,
      $$KnownHostsTableFilterComposer,
      $$KnownHostsTableOrderingComposer,
      $$KnownHostsTableAnnotationComposer,
      $$KnownHostsTableCreateCompanionBuilder,
      $$KnownHostsTableUpdateCompanionBuilder,
      (KnownHost, BaseReferences<_$AppDatabase, $KnownHostsTable, KnownHost>),
      KnownHost,
      PrefetchHooks Function()
    >;
typedef $$PortForwardRulesTableCreateCompanionBuilder =
    PortForwardRulesCompanion Function({
      required String id,
      required String hostId,
      required String type,
      required int localPort,
      Value<String?> remoteHost,
      Value<int?> remotePort,
      Value<bool> autoStart,
      Value<int> rowid,
    });
typedef $$PortForwardRulesTableUpdateCompanionBuilder =
    PortForwardRulesCompanion Function({
      Value<String> id,
      Value<String> hostId,
      Value<String> type,
      Value<int> localPort,
      Value<String?> remoteHost,
      Value<int?> remotePort,
      Value<bool> autoStart,
      Value<int> rowid,
    });

final class $$PortForwardRulesTableReferences
    extends
        BaseReferences<_$AppDatabase, $PortForwardRulesTable, PortForwardRule> {
  $$PortForwardRulesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $HostsTable _hostIdTable(_$AppDatabase db) =>
      db.hosts.createAlias('port_forward_rules__host_id__hosts__id');

  $$HostsTableProcessedTableManager get hostId {
    final $_column = $_itemColumn<String>('host_id')!;

    final manager = $$HostsTableTableManager(
      $_db,
      $_db.hosts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_hostIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PortForwardRulesTableFilterComposer
    extends Composer<_$AppDatabase, $PortForwardRulesTable> {
  $$PortForwardRulesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localPort => $composableBuilder(
    column: $table.localPort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteHost => $composableBuilder(
    column: $table.remoteHost,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get remotePort => $composableBuilder(
    column: $table.remotePort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get autoStart => $composableBuilder(
    column: $table.autoStart,
    builder: (column) => ColumnFilters(column),
  );

  $$HostsTableFilterComposer get hostId {
    final $$HostsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.hostId,
      referencedTable: $db.hosts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostsTableFilterComposer(
            $db: $db,
            $table: $db.hosts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PortForwardRulesTableOrderingComposer
    extends Composer<_$AppDatabase, $PortForwardRulesTable> {
  $$PortForwardRulesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localPort => $composableBuilder(
    column: $table.localPort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteHost => $composableBuilder(
    column: $table.remoteHost,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get remotePort => $composableBuilder(
    column: $table.remotePort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get autoStart => $composableBuilder(
    column: $table.autoStart,
    builder: (column) => ColumnOrderings(column),
  );

  $$HostsTableOrderingComposer get hostId {
    final $$HostsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.hostId,
      referencedTable: $db.hosts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostsTableOrderingComposer(
            $db: $db,
            $table: $db.hosts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PortForwardRulesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PortForwardRulesTable> {
  $$PortForwardRulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get localPort =>
      $composableBuilder(column: $table.localPort, builder: (column) => column);

  GeneratedColumn<String> get remoteHost => $composableBuilder(
    column: $table.remoteHost,
    builder: (column) => column,
  );

  GeneratedColumn<int> get remotePort => $composableBuilder(
    column: $table.remotePort,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get autoStart =>
      $composableBuilder(column: $table.autoStart, builder: (column) => column);

  $$HostsTableAnnotationComposer get hostId {
    final $$HostsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.hostId,
      referencedTable: $db.hosts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostsTableAnnotationComposer(
            $db: $db,
            $table: $db.hosts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PortForwardRulesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PortForwardRulesTable,
          PortForwardRule,
          $$PortForwardRulesTableFilterComposer,
          $$PortForwardRulesTableOrderingComposer,
          $$PortForwardRulesTableAnnotationComposer,
          $$PortForwardRulesTableCreateCompanionBuilder,
          $$PortForwardRulesTableUpdateCompanionBuilder,
          (PortForwardRule, $$PortForwardRulesTableReferences),
          PortForwardRule,
          PrefetchHooks Function({bool hostId})
        > {
  $$PortForwardRulesTableTableManager(
    _$AppDatabase db,
    $PortForwardRulesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PortForwardRulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PortForwardRulesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PortForwardRulesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> hostId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<int> localPort = const Value.absent(),
                Value<String?> remoteHost = const Value.absent(),
                Value<int?> remotePort = const Value.absent(),
                Value<bool> autoStart = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PortForwardRulesCompanion(
                id: id,
                hostId: hostId,
                type: type,
                localPort: localPort,
                remoteHost: remoteHost,
                remotePort: remotePort,
                autoStart: autoStart,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String hostId,
                required String type,
                required int localPort,
                Value<String?> remoteHost = const Value.absent(),
                Value<int?> remotePort = const Value.absent(),
                Value<bool> autoStart = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PortForwardRulesCompanion.insert(
                id: id,
                hostId: hostId,
                type: type,
                localPort: localPort,
                remoteHost: remoteHost,
                remotePort: remotePort,
                autoStart: autoStart,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PortForwardRulesTable, PortForwardRule>(table),
                  $$PortForwardRulesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({hostId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (hostId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.hostId,
                                referencedTable:
                                    $$PortForwardRulesTableReferences
                                        ._hostIdTable(db),
                                referencedColumn:
                                    $$PortForwardRulesTableReferences
                                        ._hostIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PortForwardRulesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PortForwardRulesTable,
      PortForwardRule,
      $$PortForwardRulesTableFilterComposer,
      $$PortForwardRulesTableOrderingComposer,
      $$PortForwardRulesTableAnnotationComposer,
      $$PortForwardRulesTableCreateCompanionBuilder,
      $$PortForwardRulesTableUpdateCompanionBuilder,
      (PortForwardRule, $$PortForwardRulesTableReferences),
      PortForwardRule,
      PrefetchHooks Function({bool hostId})
    >;
typedef $$SnippetsTableCreateCompanionBuilder =
    SnippetsCompanion Function({
      required String id,
      required String workspaceId,
      required String title,
      required String code,
      Value<String?> tags,
      Value<int> rowid,
    });
typedef $$SnippetsTableUpdateCompanionBuilder =
    SnippetsCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String> title,
      Value<String> code,
      Value<String?> tags,
      Value<int> rowid,
    });

final class $$SnippetsTableReferences
    extends BaseReferences<_$AppDatabase, $SnippetsTable, Snippet> {
  $$SnippetsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $WorkspacesTable _workspaceIdTable(_$AppDatabase db) =>
      db.workspaces.createAlias('snippets__workspace_id__workspaces__id');

  $$WorkspacesTableProcessedTableManager get workspaceId {
    final $_column = $_itemColumn<String>('workspace_id')!;

    final manager = $$WorkspacesTableTableManager(
      $_db,
      $_db.workspaces,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_workspaceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SnippetsTableFilterComposer
    extends Composer<_$AppDatabase, $SnippetsTable> {
  $$SnippetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnFilters(column),
  );

  $$WorkspacesTableFilterComposer get workspaceId {
    final $$WorkspacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableFilterComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SnippetsTableOrderingComposer
    extends Composer<_$AppDatabase, $SnippetsTable> {
  $$SnippetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnOrderings(column),
  );

  $$WorkspacesTableOrderingComposer get workspaceId {
    final $$WorkspacesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableOrderingComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SnippetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SnippetsTable> {
  $$SnippetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);

  $$WorkspacesTableAnnotationComposer get workspaceId {
    final $$WorkspacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableAnnotationComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SnippetsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SnippetsTable,
          Snippet,
          $$SnippetsTableFilterComposer,
          $$SnippetsTableOrderingComposer,
          $$SnippetsTableAnnotationComposer,
          $$SnippetsTableCreateCompanionBuilder,
          $$SnippetsTableUpdateCompanionBuilder,
          (Snippet, $$SnippetsTableReferences),
          Snippet,
          PrefetchHooks Function({bool workspaceId})
        > {
  $$SnippetsTableTableManager(_$AppDatabase db, $SnippetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SnippetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SnippetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SnippetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<String?> tags = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SnippetsCompanion(
                id: id,
                workspaceId: workspaceId,
                title: title,
                code: code,
                tags: tags,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String title,
                required String code,
                Value<String?> tags = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SnippetsCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                title: title,
                code: code,
                tags: tags,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SnippetsTable, Snippet>(table),
                  $$SnippetsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({workspaceId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (workspaceId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.workspaceId,
                                referencedTable: $$SnippetsTableReferences
                                    ._workspaceIdTable(db),
                                referencedColumn: $$SnippetsTableReferences
                                    ._workspaceIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SnippetsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SnippetsTable,
      Snippet,
      $$SnippetsTableFilterComposer,
      $$SnippetsTableOrderingComposer,
      $$SnippetsTableAnnotationComposer,
      $$SnippetsTableCreateCompanionBuilder,
      $$SnippetsTableUpdateCompanionBuilder,
      (Snippet, $$SnippetsTableReferences),
      Snippet,
      PrefetchHooks Function({bool workspaceId})
    >;
typedef $$RunbooksTableCreateCompanionBuilder =
    RunbooksCompanion Function({
      required String id,
      required String workspaceId,
      required String title,
      Value<String?> description,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$RunbooksTableUpdateCompanionBuilder =
    RunbooksCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String> title,
      Value<String?> description,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$RunbooksTableReferences
    extends BaseReferences<_$AppDatabase, $RunbooksTable, Runbook> {
  $$RunbooksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $WorkspacesTable _workspaceIdTable(_$AppDatabase db) =>
      db.workspaces.createAlias('runbooks__workspace_id__workspaces__id');

  $$WorkspacesTableProcessedTableManager get workspaceId {
    final $_column = $_itemColumn<String>('workspace_id')!;

    final manager = $$WorkspacesTableTableManager(
      $_db,
      $_db.workspaces,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_workspaceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$RunbookStepsTable, List<RunbookStep>>
  _runbookStepsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.runbookSteps,
    aliasName: 'runbooks__id__runbook_steps__runbook_id',
  );

  $$RunbookStepsTableProcessedTableManager get runbookStepsRefs {
    final manager = $$RunbookStepsTableTableManager(
      $_db,
      $_db.runbookSteps,
    ).filter((f) => f.runbookId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_runbookStepsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$RunbooksTableFilterComposer
    extends Composer<_$AppDatabase, $RunbooksTable> {
  $$RunbooksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$WorkspacesTableFilterComposer get workspaceId {
    final $$WorkspacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableFilterComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> runbookStepsRefs(
    Expression<bool> Function($$RunbookStepsTableFilterComposer f) f,
  ) {
    final $$RunbookStepsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.runbookSteps,
      getReferencedColumn: (t) => t.runbookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RunbookStepsTableFilterComposer(
            $db: $db,
            $table: $db.runbookSteps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RunbooksTableOrderingComposer
    extends Composer<_$AppDatabase, $RunbooksTable> {
  $$RunbooksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$WorkspacesTableOrderingComposer get workspaceId {
    final $$WorkspacesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableOrderingComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RunbooksTableAnnotationComposer
    extends Composer<_$AppDatabase, $RunbooksTable> {
  $$RunbooksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$WorkspacesTableAnnotationComposer get workspaceId {
    final $$WorkspacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableAnnotationComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> runbookStepsRefs<T extends Object>(
    Expression<T> Function($$RunbookStepsTableAnnotationComposer a) f,
  ) {
    final $$RunbookStepsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.runbookSteps,
      getReferencedColumn: (t) => t.runbookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RunbookStepsTableAnnotationComposer(
            $db: $db,
            $table: $db.runbookSteps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RunbooksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RunbooksTable,
          Runbook,
          $$RunbooksTableFilterComposer,
          $$RunbooksTableOrderingComposer,
          $$RunbooksTableAnnotationComposer,
          $$RunbooksTableCreateCompanionBuilder,
          $$RunbooksTableUpdateCompanionBuilder,
          (Runbook, $$RunbooksTableReferences),
          Runbook,
          PrefetchHooks Function({bool workspaceId, bool runbookStepsRefs})
        > {
  $$RunbooksTableTableManager(_$AppDatabase db, $RunbooksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RunbooksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RunbooksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RunbooksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RunbooksCompanion(
                id: id,
                workspaceId: workspaceId,
                title: title,
                description: description,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String title,
                Value<String?> description = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => RunbooksCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                title: title,
                description: description,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RunbooksTable, Runbook>(table),
                  $$RunbooksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({workspaceId = false, runbookStepsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (runbookStepsRefs) db.runbookSteps,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (workspaceId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.workspaceId,
                                    referencedTable: $$RunbooksTableReferences
                                        ._workspaceIdTable(db),
                                    referencedColumn: $$RunbooksTableReferences
                                        ._workspaceIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (runbookStepsRefs)
                        await $_getPrefetchedData<
                          Runbook,
                          $RunbooksTable,
                          RunbookStep
                        >(
                          currentTable: table,
                          referencedTable: $$RunbooksTableReferences
                              ._runbookStepsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$RunbooksTableReferences(
                                db,
                                table,
                                p0,
                              ).runbookStepsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.runbookId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$RunbooksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RunbooksTable,
      Runbook,
      $$RunbooksTableFilterComposer,
      $$RunbooksTableOrderingComposer,
      $$RunbooksTableAnnotationComposer,
      $$RunbooksTableCreateCompanionBuilder,
      $$RunbooksTableUpdateCompanionBuilder,
      (Runbook, $$RunbooksTableReferences),
      Runbook,
      PrefetchHooks Function({bool workspaceId, bool runbookStepsRefs})
    >;
typedef $$RunbookStepsTableCreateCompanionBuilder =
    RunbookStepsCompanion Function({
      required String id,
      required String runbookId,
      required int stepOrder,
      required String command,
      Value<int> expectedExitCode,
      Value<String?> expectedOutputPattern,
      Value<int> timeoutSeconds,
      Value<int> rowid,
    });
typedef $$RunbookStepsTableUpdateCompanionBuilder =
    RunbookStepsCompanion Function({
      Value<String> id,
      Value<String> runbookId,
      Value<int> stepOrder,
      Value<String> command,
      Value<int> expectedExitCode,
      Value<String?> expectedOutputPattern,
      Value<int> timeoutSeconds,
      Value<int> rowid,
    });

final class $$RunbookStepsTableReferences
    extends BaseReferences<_$AppDatabase, $RunbookStepsTable, RunbookStep> {
  $$RunbookStepsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $RunbooksTable _runbookIdTable(_$AppDatabase db) =>
      db.runbooks.createAlias('runbook_steps__runbook_id__runbooks__id');

  $$RunbooksTableProcessedTableManager get runbookId {
    final $_column = $_itemColumn<String>('runbook_id')!;

    final manager = $$RunbooksTableTableManager(
      $_db,
      $_db.runbooks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_runbookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$RunbookStepsTableFilterComposer
    extends Composer<_$AppDatabase, $RunbookStepsTable> {
  $$RunbookStepsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get stepOrder => $composableBuilder(
    column: $table.stepOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get command => $composableBuilder(
    column: $table.command,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expectedExitCode => $composableBuilder(
    column: $table.expectedExitCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get expectedOutputPattern => $composableBuilder(
    column: $table.expectedOutputPattern,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timeoutSeconds => $composableBuilder(
    column: $table.timeoutSeconds,
    builder: (column) => ColumnFilters(column),
  );

  $$RunbooksTableFilterComposer get runbookId {
    final $$RunbooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runbookId,
      referencedTable: $db.runbooks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RunbooksTableFilterComposer(
            $db: $db,
            $table: $db.runbooks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RunbookStepsTableOrderingComposer
    extends Composer<_$AppDatabase, $RunbookStepsTable> {
  $$RunbookStepsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get stepOrder => $composableBuilder(
    column: $table.stepOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get command => $composableBuilder(
    column: $table.command,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expectedExitCode => $composableBuilder(
    column: $table.expectedExitCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get expectedOutputPattern => $composableBuilder(
    column: $table.expectedOutputPattern,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timeoutSeconds => $composableBuilder(
    column: $table.timeoutSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  $$RunbooksTableOrderingComposer get runbookId {
    final $$RunbooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runbookId,
      referencedTable: $db.runbooks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RunbooksTableOrderingComposer(
            $db: $db,
            $table: $db.runbooks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RunbookStepsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RunbookStepsTable> {
  $$RunbookStepsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get stepOrder =>
      $composableBuilder(column: $table.stepOrder, builder: (column) => column);

  GeneratedColumn<String> get command =>
      $composableBuilder(column: $table.command, builder: (column) => column);

  GeneratedColumn<int> get expectedExitCode => $composableBuilder(
    column: $table.expectedExitCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get expectedOutputPattern => $composableBuilder(
    column: $table.expectedOutputPattern,
    builder: (column) => column,
  );

  GeneratedColumn<int> get timeoutSeconds => $composableBuilder(
    column: $table.timeoutSeconds,
    builder: (column) => column,
  );

  $$RunbooksTableAnnotationComposer get runbookId {
    final $$RunbooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runbookId,
      referencedTable: $db.runbooks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RunbooksTableAnnotationComposer(
            $db: $db,
            $table: $db.runbooks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RunbookStepsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RunbookStepsTable,
          RunbookStep,
          $$RunbookStepsTableFilterComposer,
          $$RunbookStepsTableOrderingComposer,
          $$RunbookStepsTableAnnotationComposer,
          $$RunbookStepsTableCreateCompanionBuilder,
          $$RunbookStepsTableUpdateCompanionBuilder,
          (RunbookStep, $$RunbookStepsTableReferences),
          RunbookStep,
          PrefetchHooks Function({bool runbookId})
        > {
  $$RunbookStepsTableTableManager(_$AppDatabase db, $RunbookStepsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RunbookStepsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RunbookStepsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RunbookStepsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> runbookId = const Value.absent(),
                Value<int> stepOrder = const Value.absent(),
                Value<String> command = const Value.absent(),
                Value<int> expectedExitCode = const Value.absent(),
                Value<String?> expectedOutputPattern = const Value.absent(),
                Value<int> timeoutSeconds = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RunbookStepsCompanion(
                id: id,
                runbookId: runbookId,
                stepOrder: stepOrder,
                command: command,
                expectedExitCode: expectedExitCode,
                expectedOutputPattern: expectedOutputPattern,
                timeoutSeconds: timeoutSeconds,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String runbookId,
                required int stepOrder,
                required String command,
                Value<int> expectedExitCode = const Value.absent(),
                Value<String?> expectedOutputPattern = const Value.absent(),
                Value<int> timeoutSeconds = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RunbookStepsCompanion.insert(
                id: id,
                runbookId: runbookId,
                stepOrder: stepOrder,
                command: command,
                expectedExitCode: expectedExitCode,
                expectedOutputPattern: expectedOutputPattern,
                timeoutSeconds: timeoutSeconds,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RunbookStepsTable, RunbookStep>(table),
                  $$RunbookStepsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({runbookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (runbookId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.runbookId,
                                referencedTable: $$RunbookStepsTableReferences
                                    ._runbookIdTable(db),
                                referencedColumn: $$RunbookStepsTableReferences
                                    ._runbookIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$RunbookStepsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RunbookStepsTable,
      RunbookStep,
      $$RunbookStepsTableFilterComposer,
      $$RunbookStepsTableOrderingComposer,
      $$RunbookStepsTableAnnotationComposer,
      $$RunbookStepsTableCreateCompanionBuilder,
      $$RunbookStepsTableUpdateCompanionBuilder,
      (RunbookStep, $$RunbookStepsTableReferences),
      RunbookStep,
      PrefetchHooks Function({bool runbookId})
    >;
typedef $$TemplatesTableCreateCompanionBuilder =
    TemplatesCompanion Function({
      required String id,
      required String workspaceId,
      required String name,
      Value<String?> description,
      Value<String?> activePaneId,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$TemplatesTableUpdateCompanionBuilder =
    TemplatesCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String> name,
      Value<String?> description,
      Value<String?> activePaneId,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$TemplatesTableReferences
    extends BaseReferences<_$AppDatabase, $TemplatesTable, Template> {
  $$TemplatesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $WorkspacesTable _workspaceIdTable(_$AppDatabase db) =>
      db.workspaces.createAlias('templates__workspace_id__workspaces__id');

  $$WorkspacesTableProcessedTableManager get workspaceId {
    final $_column = $_itemColumn<String>('workspace_id')!;

    final manager = $$WorkspacesTableTableManager(
      $_db,
      $_db.workspaces,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_workspaceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$TemplatePanesTable, List<TemplatePane>>
  _templatePanesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.templatePanes,
    aliasName: 'templates__id__template_panes__template_id',
  );

  $$TemplatePanesTableProcessedTableManager get templatePanesRefs {
    final manager = $$TemplatePanesTableTableManager(
      $_db,
      $_db.templatePanes,
    ).filter((f) => f.templateId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_templatePanesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$BookmarksTable, List<Bookmark>>
  _bookmarksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.bookmarks,
    aliasName: 'templates__id__bookmarks__template_id',
  );

  $$BookmarksTableProcessedTableManager get bookmarksRefs {
    final manager = $$BookmarksTableTableManager(
      $_db,
      $_db.bookmarks,
    ).filter((f) => f.templateId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_bookmarksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TemplatesTableFilterComposer
    extends Composer<_$AppDatabase, $TemplatesTable> {
  $$TemplatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get activePaneId => $composableBuilder(
    column: $table.activePaneId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$WorkspacesTableFilterComposer get workspaceId {
    final $$WorkspacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableFilterComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> templatePanesRefs(
    Expression<bool> Function($$TemplatePanesTableFilterComposer f) f,
  ) {
    final $$TemplatePanesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.templatePanes,
      getReferencedColumn: (t) => t.templateId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TemplatePanesTableFilterComposer(
            $db: $db,
            $table: $db.templatePanes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> bookmarksRefs(
    Expression<bool> Function($$BookmarksTableFilterComposer f) f,
  ) {
    final $$BookmarksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookmarks,
      getReferencedColumn: (t) => t.templateId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookmarksTableFilterComposer(
            $db: $db,
            $table: $db.bookmarks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TemplatesTableOrderingComposer
    extends Composer<_$AppDatabase, $TemplatesTable> {
  $$TemplatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get activePaneId => $composableBuilder(
    column: $table.activePaneId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$WorkspacesTableOrderingComposer get workspaceId {
    final $$WorkspacesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableOrderingComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TemplatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TemplatesTable> {
  $$TemplatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get activePaneId => $composableBuilder(
    column: $table.activePaneId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$WorkspacesTableAnnotationComposer get workspaceId {
    final $$WorkspacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableAnnotationComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> templatePanesRefs<T extends Object>(
    Expression<T> Function($$TemplatePanesTableAnnotationComposer a) f,
  ) {
    final $$TemplatePanesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.templatePanes,
      getReferencedColumn: (t) => t.templateId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TemplatePanesTableAnnotationComposer(
            $db: $db,
            $table: $db.templatePanes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> bookmarksRefs<T extends Object>(
    Expression<T> Function($$BookmarksTableAnnotationComposer a) f,
  ) {
    final $$BookmarksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookmarks,
      getReferencedColumn: (t) => t.templateId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookmarksTableAnnotationComposer(
            $db: $db,
            $table: $db.bookmarks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TemplatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TemplatesTable,
          Template,
          $$TemplatesTableFilterComposer,
          $$TemplatesTableOrderingComposer,
          $$TemplatesTableAnnotationComposer,
          $$TemplatesTableCreateCompanionBuilder,
          $$TemplatesTableUpdateCompanionBuilder,
          (Template, $$TemplatesTableReferences),
          Template,
          PrefetchHooks Function({
            bool workspaceId,
            bool templatePanesRefs,
            bool bookmarksRefs,
          })
        > {
  $$TemplatesTableTableManager(_$AppDatabase db, $TemplatesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TemplatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TemplatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TemplatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> activePaneId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TemplatesCompanion(
                id: id,
                workspaceId: workspaceId,
                name: name,
                description: description,
                activePaneId: activePaneId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String name,
                Value<String?> description = const Value.absent(),
                Value<String?> activePaneId = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => TemplatesCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                name: name,
                description: description,
                activePaneId: activePaneId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TemplatesTable, Template>(table),
                  $$TemplatesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                workspaceId = false,
                templatePanesRefs = false,
                bookmarksRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (templatePanesRefs) db.templatePanes,
                    if (bookmarksRefs) db.bookmarks,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (workspaceId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.workspaceId,
                                    referencedTable: $$TemplatesTableReferences
                                        ._workspaceIdTable(db),
                                    referencedColumn: $$TemplatesTableReferences
                                        ._workspaceIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (templatePanesRefs)
                        await $_getPrefetchedData<
                          Template,
                          $TemplatesTable,
                          TemplatePane
                        >(
                          currentTable: table,
                          referencedTable: $$TemplatesTableReferences
                              ._templatePanesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TemplatesTableReferences(
                                db,
                                table,
                                p0,
                              ).templatePanesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.templateId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (bookmarksRefs)
                        await $_getPrefetchedData<
                          Template,
                          $TemplatesTable,
                          Bookmark
                        >(
                          currentTable: table,
                          referencedTable: $$TemplatesTableReferences
                              ._bookmarksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TemplatesTableReferences(
                                db,
                                table,
                                p0,
                              ).bookmarksRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.templateId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$TemplatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TemplatesTable,
      Template,
      $$TemplatesTableFilterComposer,
      $$TemplatesTableOrderingComposer,
      $$TemplatesTableAnnotationComposer,
      $$TemplatesTableCreateCompanionBuilder,
      $$TemplatesTableUpdateCompanionBuilder,
      (Template, $$TemplatesTableReferences),
      Template,
      PrefetchHooks Function({
        bool workspaceId,
        bool templatePanesRefs,
        bool bookmarksRefs,
      })
    >;
typedef $$TemplatePanesTableCreateCompanionBuilder =
    TemplatePanesCompanion Function({
      required String id,
      required String templateId,
      required int paneOrder,
      Value<String?> parentPaneId,
      Value<String?> splitDirection,
      Value<double> splitRatio,
      required String sessionType,
      Value<String?> hostId,
      Value<String?> title,
      Value<int> rowid,
    });
typedef $$TemplatePanesTableUpdateCompanionBuilder =
    TemplatePanesCompanion Function({
      Value<String> id,
      Value<String> templateId,
      Value<int> paneOrder,
      Value<String?> parentPaneId,
      Value<String?> splitDirection,
      Value<double> splitRatio,
      Value<String> sessionType,
      Value<String?> hostId,
      Value<String?> title,
      Value<int> rowid,
    });

final class $$TemplatePanesTableReferences
    extends BaseReferences<_$AppDatabase, $TemplatePanesTable, TemplatePane> {
  $$TemplatePanesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $TemplatesTable _templateIdTable(_$AppDatabase db) =>
      db.templates.createAlias('template_panes__template_id__templates__id');

  $$TemplatesTableProcessedTableManager get templateId {
    final $_column = $_itemColumn<String>('template_id')!;

    final manager = $$TemplatesTableTableManager(
      $_db,
      $_db.templates,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_templateIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TemplatePanesTableFilterComposer
    extends Composer<_$AppDatabase, $TemplatePanesTable> {
  $$TemplatePanesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get paneOrder => $composableBuilder(
    column: $table.paneOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentPaneId => $composableBuilder(
    column: $table.parentPaneId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get splitDirection => $composableBuilder(
    column: $table.splitDirection,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get splitRatio => $composableBuilder(
    column: $table.splitRatio,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionType => $composableBuilder(
    column: $table.sessionType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hostId => $composableBuilder(
    column: $table.hostId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  $$TemplatesTableFilterComposer get templateId {
    final $$TemplatesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.templateId,
      referencedTable: $db.templates,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TemplatesTableFilterComposer(
            $db: $db,
            $table: $db.templates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TemplatePanesTableOrderingComposer
    extends Composer<_$AppDatabase, $TemplatePanesTable> {
  $$TemplatePanesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get paneOrder => $composableBuilder(
    column: $table.paneOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentPaneId => $composableBuilder(
    column: $table.parentPaneId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get splitDirection => $composableBuilder(
    column: $table.splitDirection,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get splitRatio => $composableBuilder(
    column: $table.splitRatio,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionType => $composableBuilder(
    column: $table.sessionType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hostId => $composableBuilder(
    column: $table.hostId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  $$TemplatesTableOrderingComposer get templateId {
    final $$TemplatesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.templateId,
      referencedTable: $db.templates,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TemplatesTableOrderingComposer(
            $db: $db,
            $table: $db.templates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TemplatePanesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TemplatePanesTable> {
  $$TemplatePanesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get paneOrder =>
      $composableBuilder(column: $table.paneOrder, builder: (column) => column);

  GeneratedColumn<String> get parentPaneId => $composableBuilder(
    column: $table.parentPaneId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get splitDirection => $composableBuilder(
    column: $table.splitDirection,
    builder: (column) => column,
  );

  GeneratedColumn<double> get splitRatio => $composableBuilder(
    column: $table.splitRatio,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sessionType => $composableBuilder(
    column: $table.sessionType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hostId =>
      $composableBuilder(column: $table.hostId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  $$TemplatesTableAnnotationComposer get templateId {
    final $$TemplatesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.templateId,
      referencedTable: $db.templates,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TemplatesTableAnnotationComposer(
            $db: $db,
            $table: $db.templates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TemplatePanesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TemplatePanesTable,
          TemplatePane,
          $$TemplatePanesTableFilterComposer,
          $$TemplatePanesTableOrderingComposer,
          $$TemplatePanesTableAnnotationComposer,
          $$TemplatePanesTableCreateCompanionBuilder,
          $$TemplatePanesTableUpdateCompanionBuilder,
          (TemplatePane, $$TemplatePanesTableReferences),
          TemplatePane,
          PrefetchHooks Function({bool templateId})
        > {
  $$TemplatePanesTableTableManager(_$AppDatabase db, $TemplatePanesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TemplatePanesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TemplatePanesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TemplatePanesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> templateId = const Value.absent(),
                Value<int> paneOrder = const Value.absent(),
                Value<String?> parentPaneId = const Value.absent(),
                Value<String?> splitDirection = const Value.absent(),
                Value<double> splitRatio = const Value.absent(),
                Value<String> sessionType = const Value.absent(),
                Value<String?> hostId = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TemplatePanesCompanion(
                id: id,
                templateId: templateId,
                paneOrder: paneOrder,
                parentPaneId: parentPaneId,
                splitDirection: splitDirection,
                splitRatio: splitRatio,
                sessionType: sessionType,
                hostId: hostId,
                title: title,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String templateId,
                required int paneOrder,
                Value<String?> parentPaneId = const Value.absent(),
                Value<String?> splitDirection = const Value.absent(),
                Value<double> splitRatio = const Value.absent(),
                required String sessionType,
                Value<String?> hostId = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TemplatePanesCompanion.insert(
                id: id,
                templateId: templateId,
                paneOrder: paneOrder,
                parentPaneId: parentPaneId,
                splitDirection: splitDirection,
                splitRatio: splitRatio,
                sessionType: sessionType,
                hostId: hostId,
                title: title,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TemplatePanesTable, TemplatePane>(table),
                  $$TemplatePanesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({templateId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (templateId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.templateId,
                                referencedTable: $$TemplatePanesTableReferences
                                    ._templateIdTable(db),
                                referencedColumn: $$TemplatePanesTableReferences
                                    ._templateIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TemplatePanesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TemplatePanesTable,
      TemplatePane,
      $$TemplatePanesTableFilterComposer,
      $$TemplatePanesTableOrderingComposer,
      $$TemplatePanesTableAnnotationComposer,
      $$TemplatePanesTableCreateCompanionBuilder,
      $$TemplatePanesTableUpdateCompanionBuilder,
      (TemplatePane, $$TemplatePanesTableReferences),
      TemplatePane,
      PrefetchHooks Function({bool templateId})
    >;
typedef $$PairedDevicesTableCreateCompanionBuilder =
    PairedDevicesCompanion Function({
      required String id,
      required String name,
      required String platform,
      required String secretHash,
      required String publicKey,
      required DateTime pairedAt,
      required DateTime lastSeenAt,
      Value<int> rowid,
    });
typedef $$PairedDevicesTableUpdateCompanionBuilder =
    PairedDevicesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> platform,
      Value<String> secretHash,
      Value<String> publicKey,
      Value<DateTime> pairedAt,
      Value<DateTime> lastSeenAt,
      Value<int> rowid,
    });

class $$PairedDevicesTableFilterComposer
    extends Composer<_$AppDatabase, $PairedDevicesTable> {
  $$PairedDevicesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get secretHash => $composableBuilder(
    column: $table.secretHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get publicKey => $composableBuilder(
    column: $table.publicKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get pairedAt => $composableBuilder(
    column: $table.pairedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PairedDevicesTableOrderingComposer
    extends Composer<_$AppDatabase, $PairedDevicesTable> {
  $$PairedDevicesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get secretHash => $composableBuilder(
    column: $table.secretHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get publicKey => $composableBuilder(
    column: $table.publicKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get pairedAt => $composableBuilder(
    column: $table.pairedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PairedDevicesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PairedDevicesTable> {
  $$PairedDevicesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get platform =>
      $composableBuilder(column: $table.platform, builder: (column) => column);

  GeneratedColumn<String> get secretHash => $composableBuilder(
    column: $table.secretHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get publicKey =>
      $composableBuilder(column: $table.publicKey, builder: (column) => column);

  GeneratedColumn<DateTime> get pairedAt =>
      $composableBuilder(column: $table.pairedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => column,
  );
}

class $$PairedDevicesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PairedDevicesTable,
          PairedDevice,
          $$PairedDevicesTableFilterComposer,
          $$PairedDevicesTableOrderingComposer,
          $$PairedDevicesTableAnnotationComposer,
          $$PairedDevicesTableCreateCompanionBuilder,
          $$PairedDevicesTableUpdateCompanionBuilder,
          (
            PairedDevice,
            BaseReferences<_$AppDatabase, $PairedDevicesTable, PairedDevice>,
          ),
          PairedDevice,
          PrefetchHooks Function()
        > {
  $$PairedDevicesTableTableManager(_$AppDatabase db, $PairedDevicesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PairedDevicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PairedDevicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PairedDevicesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> platform = const Value.absent(),
                Value<String> secretHash = const Value.absent(),
                Value<String> publicKey = const Value.absent(),
                Value<DateTime> pairedAt = const Value.absent(),
                Value<DateTime> lastSeenAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PairedDevicesCompanion(
                id: id,
                name: name,
                platform: platform,
                secretHash: secretHash,
                publicKey: publicKey,
                pairedAt: pairedAt,
                lastSeenAt: lastSeenAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String platform,
                required String secretHash,
                required String publicKey,
                required DateTime pairedAt,
                required DateTime lastSeenAt,
                Value<int> rowid = const Value.absent(),
              }) => PairedDevicesCompanion.insert(
                id: id,
                name: name,
                platform: platform,
                secretHash: secretHash,
                publicKey: publicKey,
                pairedAt: pairedAt,
                lastSeenAt: lastSeenAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PairedDevicesTable, PairedDevice>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $PairedDevicesTable,
                    PairedDevice
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PairedDevicesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PairedDevicesTable,
      PairedDevice,
      $$PairedDevicesTableFilterComposer,
      $$PairedDevicesTableOrderingComposer,
      $$PairedDevicesTableAnnotationComposer,
      $$PairedDevicesTableCreateCompanionBuilder,
      $$PairedDevicesTableUpdateCompanionBuilder,
      (
        PairedDevice,
        BaseReferences<_$AppDatabase, $PairedDevicesTable, PairedDevice>,
      ),
      PairedDevice,
      PrefetchHooks Function()
    >;
typedef $$McpClientsTableCreateCompanionBuilder =
    McpClientsCompanion Function({
      required String id,
      required String workspaceId,
      required String name,
      required String tokenHash,
      required DateTime createdAt,
      Value<DateTime?> lastSeenAt,
      Value<DateTime?> expiresAt,
      Value<DateTime?> revokedAt,
      Value<int> rowid,
    });
typedef $$McpClientsTableUpdateCompanionBuilder =
    McpClientsCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String> name,
      Value<String> tokenHash,
      Value<DateTime> createdAt,
      Value<DateTime?> lastSeenAt,
      Value<DateTime?> expiresAt,
      Value<DateTime?> revokedAt,
      Value<int> rowid,
    });

final class $$McpClientsTableReferences
    extends BaseReferences<_$AppDatabase, $McpClientsTable, McpClient> {
  $$McpClientsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $WorkspacesTable _workspaceIdTable(_$AppDatabase db) =>
      db.workspaces.createAlias('mcp_clients__workspace_id__workspaces__id');

  $$WorkspacesTableProcessedTableManager get workspaceId {
    final $_column = $_itemColumn<String>('workspace_id')!;

    final manager = $$WorkspacesTableTableManager(
      $_db,
      $_db.workspaces,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_workspaceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$McpHostGrantsTable, List<McpHostGrant>>
  _mcpHostGrantsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.mcpHostGrants,
    aliasName: 'mcp_clients__id__mcp_host_grants__client_id',
  );

  $$McpHostGrantsTableProcessedTableManager get mcpHostGrantsRefs {
    final manager = $$McpHostGrantsTableTableManager(
      $_db,
      $_db.mcpHostGrants,
    ).filter((f) => f.clientId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_mcpHostGrantsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$McpApprovalsTable, List<McpApproval>>
  _mcpApprovalsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.mcpApprovals,
    aliasName: 'mcp_clients__id__mcp_approvals__client_id',
  );

  $$McpApprovalsTableProcessedTableManager get mcpApprovalsRefs {
    final manager = $$McpApprovalsTableTableManager(
      $_db,
      $_db.mcpApprovals,
    ).filter((f) => f.clientId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_mcpApprovalsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$McpClientsTableFilterComposer
    extends Composer<_$AppDatabase, $McpClientsTable> {
  $$McpClientsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tokenHash => $composableBuilder(
    column: $table.tokenHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get revokedAt => $composableBuilder(
    column: $table.revokedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$WorkspacesTableFilterComposer get workspaceId {
    final $$WorkspacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableFilterComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> mcpHostGrantsRefs(
    Expression<bool> Function($$McpHostGrantsTableFilterComposer f) f,
  ) {
    final $$McpHostGrantsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mcpHostGrants,
      getReferencedColumn: (t) => t.clientId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$McpHostGrantsTableFilterComposer(
            $db: $db,
            $table: $db.mcpHostGrants,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> mcpApprovalsRefs(
    Expression<bool> Function($$McpApprovalsTableFilterComposer f) f,
  ) {
    final $$McpApprovalsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mcpApprovals,
      getReferencedColumn: (t) => t.clientId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$McpApprovalsTableFilterComposer(
            $db: $db,
            $table: $db.mcpApprovals,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$McpClientsTableOrderingComposer
    extends Composer<_$AppDatabase, $McpClientsTable> {
  $$McpClientsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tokenHash => $composableBuilder(
    column: $table.tokenHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get revokedAt => $composableBuilder(
    column: $table.revokedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$WorkspacesTableOrderingComposer get workspaceId {
    final $$WorkspacesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableOrderingComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$McpClientsTableAnnotationComposer
    extends Composer<_$AppDatabase, $McpClientsTable> {
  $$McpClientsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get tokenHash =>
      $composableBuilder(column: $table.tokenHash, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<DateTime> get revokedAt =>
      $composableBuilder(column: $table.revokedAt, builder: (column) => column);

  $$WorkspacesTableAnnotationComposer get workspaceId {
    final $$WorkspacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableAnnotationComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> mcpHostGrantsRefs<T extends Object>(
    Expression<T> Function($$McpHostGrantsTableAnnotationComposer a) f,
  ) {
    final $$McpHostGrantsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mcpHostGrants,
      getReferencedColumn: (t) => t.clientId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$McpHostGrantsTableAnnotationComposer(
            $db: $db,
            $table: $db.mcpHostGrants,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> mcpApprovalsRefs<T extends Object>(
    Expression<T> Function($$McpApprovalsTableAnnotationComposer a) f,
  ) {
    final $$McpApprovalsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mcpApprovals,
      getReferencedColumn: (t) => t.clientId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$McpApprovalsTableAnnotationComposer(
            $db: $db,
            $table: $db.mcpApprovals,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$McpClientsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $McpClientsTable,
          McpClient,
          $$McpClientsTableFilterComposer,
          $$McpClientsTableOrderingComposer,
          $$McpClientsTableAnnotationComposer,
          $$McpClientsTableCreateCompanionBuilder,
          $$McpClientsTableUpdateCompanionBuilder,
          (McpClient, $$McpClientsTableReferences),
          McpClient,
          PrefetchHooks Function({
            bool workspaceId,
            bool mcpHostGrantsRefs,
            bool mcpApprovalsRefs,
          })
        > {
  $$McpClientsTableTableManager(_$AppDatabase db, $McpClientsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$McpClientsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$McpClientsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$McpClientsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> tokenHash = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> lastSeenAt = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<DateTime?> revokedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => McpClientsCompanion(
                id: id,
                workspaceId: workspaceId,
                name: name,
                tokenHash: tokenHash,
                createdAt: createdAt,
                lastSeenAt: lastSeenAt,
                expiresAt: expiresAt,
                revokedAt: revokedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String name,
                required String tokenHash,
                required DateTime createdAt,
                Value<DateTime?> lastSeenAt = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<DateTime?> revokedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => McpClientsCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                name: name,
                tokenHash: tokenHash,
                createdAt: createdAt,
                lastSeenAt: lastSeenAt,
                expiresAt: expiresAt,
                revokedAt: revokedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$McpClientsTable, McpClient>(table),
                  $$McpClientsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                workspaceId = false,
                mcpHostGrantsRefs = false,
                mcpApprovalsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (mcpHostGrantsRefs) db.mcpHostGrants,
                    if (mcpApprovalsRefs) db.mcpApprovals,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (workspaceId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.workspaceId,
                                    referencedTable: $$McpClientsTableReferences
                                        ._workspaceIdTable(db),
                                    referencedColumn:
                                        $$McpClientsTableReferences
                                            ._workspaceIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (mcpHostGrantsRefs)
                        await $_getPrefetchedData<
                          McpClient,
                          $McpClientsTable,
                          McpHostGrant
                        >(
                          currentTable: table,
                          referencedTable: $$McpClientsTableReferences
                              ._mcpHostGrantsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$McpClientsTableReferences(
                                db,
                                table,
                                p0,
                              ).mcpHostGrantsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.clientId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (mcpApprovalsRefs)
                        await $_getPrefetchedData<
                          McpClient,
                          $McpClientsTable,
                          McpApproval
                        >(
                          currentTable: table,
                          referencedTable: $$McpClientsTableReferences
                              ._mcpApprovalsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$McpClientsTableReferences(
                                db,
                                table,
                                p0,
                              ).mcpApprovalsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.clientId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$McpClientsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $McpClientsTable,
      McpClient,
      $$McpClientsTableFilterComposer,
      $$McpClientsTableOrderingComposer,
      $$McpClientsTableAnnotationComposer,
      $$McpClientsTableCreateCompanionBuilder,
      $$McpClientsTableUpdateCompanionBuilder,
      (McpClient, $$McpClientsTableReferences),
      McpClient,
      PrefetchHooks Function({
        bool workspaceId,
        bool mcpHostGrantsRefs,
        bool mcpApprovalsRefs,
      })
    >;
typedef $$McpHostGrantsTableCreateCompanionBuilder =
    McpHostGrantsCompanion Function({
      required String id,
      required String clientId,
      required String hostId,
      required String mode,
      required DateTime grantedAt,
      Value<DateTime?> expiresAt,
      Value<String?> connectionScopeId,
      Value<DateTime?> cooldownUntil,
      Value<int> rowid,
    });
typedef $$McpHostGrantsTableUpdateCompanionBuilder =
    McpHostGrantsCompanion Function({
      Value<String> id,
      Value<String> clientId,
      Value<String> hostId,
      Value<String> mode,
      Value<DateTime> grantedAt,
      Value<DateTime?> expiresAt,
      Value<String?> connectionScopeId,
      Value<DateTime?> cooldownUntil,
      Value<int> rowid,
    });

final class $$McpHostGrantsTableReferences
    extends BaseReferences<_$AppDatabase, $McpHostGrantsTable, McpHostGrant> {
  $$McpHostGrantsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $McpClientsTable _clientIdTable(_$AppDatabase db) =>
      db.mcpClients.createAlias('mcp_host_grants__client_id__mcp_clients__id');

  $$McpClientsTableProcessedTableManager get clientId {
    final $_column = $_itemColumn<String>('client_id')!;

    final manager = $$McpClientsTableTableManager(
      $_db,
      $_db.mcpClients,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_clientIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $HostsTable _hostIdTable(_$AppDatabase db) =>
      db.hosts.createAlias('mcp_host_grants__host_id__hosts__id');

  $$HostsTableProcessedTableManager get hostId {
    final $_column = $_itemColumn<String>('host_id')!;

    final manager = $$HostsTableTableManager(
      $_db,
      $_db.hosts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_hostIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$McpHostGrantsTableFilterComposer
    extends Composer<_$AppDatabase, $McpHostGrantsTable> {
  $$McpHostGrantsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get grantedAt => $composableBuilder(
    column: $table.grantedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get connectionScopeId => $composableBuilder(
    column: $table.connectionScopeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cooldownUntil => $composableBuilder(
    column: $table.cooldownUntil,
    builder: (column) => ColumnFilters(column),
  );

  $$McpClientsTableFilterComposer get clientId {
    final $$McpClientsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.clientId,
      referencedTable: $db.mcpClients,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$McpClientsTableFilterComposer(
            $db: $db,
            $table: $db.mcpClients,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$HostsTableFilterComposer get hostId {
    final $$HostsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.hostId,
      referencedTable: $db.hosts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostsTableFilterComposer(
            $db: $db,
            $table: $db.hosts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$McpHostGrantsTableOrderingComposer
    extends Composer<_$AppDatabase, $McpHostGrantsTable> {
  $$McpHostGrantsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get grantedAt => $composableBuilder(
    column: $table.grantedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get connectionScopeId => $composableBuilder(
    column: $table.connectionScopeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cooldownUntil => $composableBuilder(
    column: $table.cooldownUntil,
    builder: (column) => ColumnOrderings(column),
  );

  $$McpClientsTableOrderingComposer get clientId {
    final $$McpClientsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.clientId,
      referencedTable: $db.mcpClients,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$McpClientsTableOrderingComposer(
            $db: $db,
            $table: $db.mcpClients,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$HostsTableOrderingComposer get hostId {
    final $$HostsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.hostId,
      referencedTable: $db.hosts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostsTableOrderingComposer(
            $db: $db,
            $table: $db.hosts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$McpHostGrantsTableAnnotationComposer
    extends Composer<_$AppDatabase, $McpHostGrantsTable> {
  $$McpHostGrantsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<DateTime> get grantedAt =>
      $composableBuilder(column: $table.grantedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<String> get connectionScopeId => $composableBuilder(
    column: $table.connectionScopeId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get cooldownUntil => $composableBuilder(
    column: $table.cooldownUntil,
    builder: (column) => column,
  );

  $$McpClientsTableAnnotationComposer get clientId {
    final $$McpClientsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.clientId,
      referencedTable: $db.mcpClients,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$McpClientsTableAnnotationComposer(
            $db: $db,
            $table: $db.mcpClients,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$HostsTableAnnotationComposer get hostId {
    final $$HostsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.hostId,
      referencedTable: $db.hosts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostsTableAnnotationComposer(
            $db: $db,
            $table: $db.hosts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$McpHostGrantsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $McpHostGrantsTable,
          McpHostGrant,
          $$McpHostGrantsTableFilterComposer,
          $$McpHostGrantsTableOrderingComposer,
          $$McpHostGrantsTableAnnotationComposer,
          $$McpHostGrantsTableCreateCompanionBuilder,
          $$McpHostGrantsTableUpdateCompanionBuilder,
          (McpHostGrant, $$McpHostGrantsTableReferences),
          McpHostGrant,
          PrefetchHooks Function({bool clientId, bool hostId})
        > {
  $$McpHostGrantsTableTableManager(_$AppDatabase db, $McpHostGrantsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$McpHostGrantsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$McpHostGrantsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$McpHostGrantsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> clientId = const Value.absent(),
                Value<String> hostId = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<DateTime> grantedAt = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<String?> connectionScopeId = const Value.absent(),
                Value<DateTime?> cooldownUntil = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => McpHostGrantsCompanion(
                id: id,
                clientId: clientId,
                hostId: hostId,
                mode: mode,
                grantedAt: grantedAt,
                expiresAt: expiresAt,
                connectionScopeId: connectionScopeId,
                cooldownUntil: cooldownUntil,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String clientId,
                required String hostId,
                required String mode,
                required DateTime grantedAt,
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<String?> connectionScopeId = const Value.absent(),
                Value<DateTime?> cooldownUntil = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => McpHostGrantsCompanion.insert(
                id: id,
                clientId: clientId,
                hostId: hostId,
                mode: mode,
                grantedAt: grantedAt,
                expiresAt: expiresAt,
                connectionScopeId: connectionScopeId,
                cooldownUntil: cooldownUntil,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$McpHostGrantsTable, McpHostGrant>(table),
                  $$McpHostGrantsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({clientId = false, hostId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (clientId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.clientId,
                                referencedTable: $$McpHostGrantsTableReferences
                                    ._clientIdTable(db),
                                referencedColumn: $$McpHostGrantsTableReferences
                                    ._clientIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (hostId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.hostId,
                                referencedTable: $$McpHostGrantsTableReferences
                                    ._hostIdTable(db),
                                referencedColumn: $$McpHostGrantsTableReferences
                                    ._hostIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$McpHostGrantsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $McpHostGrantsTable,
      McpHostGrant,
      $$McpHostGrantsTableFilterComposer,
      $$McpHostGrantsTableOrderingComposer,
      $$McpHostGrantsTableAnnotationComposer,
      $$McpHostGrantsTableCreateCompanionBuilder,
      $$McpHostGrantsTableUpdateCompanionBuilder,
      (McpHostGrant, $$McpHostGrantsTableReferences),
      McpHostGrant,
      PrefetchHooks Function({bool clientId, bool hostId})
    >;
typedef $$McpPolicyRulesTableCreateCompanionBuilder =
    McpPolicyRulesCompanion Function({
      required String id,
      required String workspaceId,
      required String scopeType,
      Value<String?> scopeId,
      required String matchType,
      required String pattern,
      required String action,
      required int priority,
      Value<bool> enabled,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$McpPolicyRulesTableUpdateCompanionBuilder =
    McpPolicyRulesCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String> scopeType,
      Value<String?> scopeId,
      Value<String> matchType,
      Value<String> pattern,
      Value<String> action,
      Value<int> priority,
      Value<bool> enabled,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$McpPolicyRulesTableReferences
    extends BaseReferences<_$AppDatabase, $McpPolicyRulesTable, McpPolicyRule> {
  $$McpPolicyRulesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $WorkspacesTable _workspaceIdTable(_$AppDatabase db) => db.workspaces
      .createAlias('mcp_policy_rules__workspace_id__workspaces__id');

  $$WorkspacesTableProcessedTableManager get workspaceId {
    final $_column = $_itemColumn<String>('workspace_id')!;

    final manager = $$WorkspacesTableTableManager(
      $_db,
      $_db.workspaces,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_workspaceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$McpPolicyRulesTableFilterComposer
    extends Composer<_$AppDatabase, $McpPolicyRulesTable> {
  $$McpPolicyRulesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scopeType => $composableBuilder(
    column: $table.scopeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scopeId => $composableBuilder(
    column: $table.scopeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get matchType => $composableBuilder(
    column: $table.matchType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pattern => $composableBuilder(
    column: $table.pattern,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$WorkspacesTableFilterComposer get workspaceId {
    final $$WorkspacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableFilterComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$McpPolicyRulesTableOrderingComposer
    extends Composer<_$AppDatabase, $McpPolicyRulesTable> {
  $$McpPolicyRulesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scopeType => $composableBuilder(
    column: $table.scopeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scopeId => $composableBuilder(
    column: $table.scopeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get matchType => $composableBuilder(
    column: $table.matchType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pattern => $composableBuilder(
    column: $table.pattern,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$WorkspacesTableOrderingComposer get workspaceId {
    final $$WorkspacesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableOrderingComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$McpPolicyRulesTableAnnotationComposer
    extends Composer<_$AppDatabase, $McpPolicyRulesTable> {
  $$McpPolicyRulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get scopeType =>
      $composableBuilder(column: $table.scopeType, builder: (column) => column);

  GeneratedColumn<String> get scopeId =>
      $composableBuilder(column: $table.scopeId, builder: (column) => column);

  GeneratedColumn<String> get matchType =>
      $composableBuilder(column: $table.matchType, builder: (column) => column);

  GeneratedColumn<String> get pattern =>
      $composableBuilder(column: $table.pattern, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$WorkspacesTableAnnotationComposer get workspaceId {
    final $$WorkspacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableAnnotationComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$McpPolicyRulesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $McpPolicyRulesTable,
          McpPolicyRule,
          $$McpPolicyRulesTableFilterComposer,
          $$McpPolicyRulesTableOrderingComposer,
          $$McpPolicyRulesTableAnnotationComposer,
          $$McpPolicyRulesTableCreateCompanionBuilder,
          $$McpPolicyRulesTableUpdateCompanionBuilder,
          (McpPolicyRule, $$McpPolicyRulesTableReferences),
          McpPolicyRule,
          PrefetchHooks Function({bool workspaceId})
        > {
  $$McpPolicyRulesTableTableManager(
    _$AppDatabase db,
    $McpPolicyRulesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$McpPolicyRulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$McpPolicyRulesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$McpPolicyRulesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> scopeType = const Value.absent(),
                Value<String?> scopeId = const Value.absent(),
                Value<String> matchType = const Value.absent(),
                Value<String> pattern = const Value.absent(),
                Value<String> action = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => McpPolicyRulesCompanion(
                id: id,
                workspaceId: workspaceId,
                scopeType: scopeType,
                scopeId: scopeId,
                matchType: matchType,
                pattern: pattern,
                action: action,
                priority: priority,
                enabled: enabled,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String scopeType,
                Value<String?> scopeId = const Value.absent(),
                required String matchType,
                required String pattern,
                required String action,
                required int priority,
                Value<bool> enabled = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => McpPolicyRulesCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                scopeType: scopeType,
                scopeId: scopeId,
                matchType: matchType,
                pattern: pattern,
                action: action,
                priority: priority,
                enabled: enabled,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$McpPolicyRulesTable, McpPolicyRule>(table),
                  $$McpPolicyRulesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({workspaceId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (workspaceId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.workspaceId,
                                referencedTable: $$McpPolicyRulesTableReferences
                                    ._workspaceIdTable(db),
                                referencedColumn:
                                    $$McpPolicyRulesTableReferences
                                        ._workspaceIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$McpPolicyRulesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $McpPolicyRulesTable,
      McpPolicyRule,
      $$McpPolicyRulesTableFilterComposer,
      $$McpPolicyRulesTableOrderingComposer,
      $$McpPolicyRulesTableAnnotationComposer,
      $$McpPolicyRulesTableCreateCompanionBuilder,
      $$McpPolicyRulesTableUpdateCompanionBuilder,
      (McpPolicyRule, $$McpPolicyRulesTableReferences),
      McpPolicyRule,
      PrefetchHooks Function({bool workspaceId})
    >;
typedef $$McpApprovalsTableCreateCompanionBuilder =
    McpApprovalsCompanion Function({
      required String id,
      required String clientId,
      required String hostId,
      required String cwd,
      required String commandNormalized,
      required String commandSha256,
      required DateTime approvedAt,
      Value<DateTime?> expiresAt,
      Value<String?> connectionScopeId,
      Value<int> rowid,
    });
typedef $$McpApprovalsTableUpdateCompanionBuilder =
    McpApprovalsCompanion Function({
      Value<String> id,
      Value<String> clientId,
      Value<String> hostId,
      Value<String> cwd,
      Value<String> commandNormalized,
      Value<String> commandSha256,
      Value<DateTime> approvedAt,
      Value<DateTime?> expiresAt,
      Value<String?> connectionScopeId,
      Value<int> rowid,
    });

final class $$McpApprovalsTableReferences
    extends BaseReferences<_$AppDatabase, $McpApprovalsTable, McpApproval> {
  $$McpApprovalsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $McpClientsTable _clientIdTable(_$AppDatabase db) =>
      db.mcpClients.createAlias('mcp_approvals__client_id__mcp_clients__id');

  $$McpClientsTableProcessedTableManager get clientId {
    final $_column = $_itemColumn<String>('client_id')!;

    final manager = $$McpClientsTableTableManager(
      $_db,
      $_db.mcpClients,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_clientIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $HostsTable _hostIdTable(_$AppDatabase db) =>
      db.hosts.createAlias('mcp_approvals__host_id__hosts__id');

  $$HostsTableProcessedTableManager get hostId {
    final $_column = $_itemColumn<String>('host_id')!;

    final manager = $$HostsTableTableManager(
      $_db,
      $_db.hosts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_hostIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$McpApprovalsTableFilterComposer
    extends Composer<_$AppDatabase, $McpApprovalsTable> {
  $$McpApprovalsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cwd => $composableBuilder(
    column: $table.cwd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get commandNormalized => $composableBuilder(
    column: $table.commandNormalized,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get commandSha256 => $composableBuilder(
    column: $table.commandSha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get approvedAt => $composableBuilder(
    column: $table.approvedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get connectionScopeId => $composableBuilder(
    column: $table.connectionScopeId,
    builder: (column) => ColumnFilters(column),
  );

  $$McpClientsTableFilterComposer get clientId {
    final $$McpClientsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.clientId,
      referencedTable: $db.mcpClients,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$McpClientsTableFilterComposer(
            $db: $db,
            $table: $db.mcpClients,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$HostsTableFilterComposer get hostId {
    final $$HostsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.hostId,
      referencedTable: $db.hosts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostsTableFilterComposer(
            $db: $db,
            $table: $db.hosts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$McpApprovalsTableOrderingComposer
    extends Composer<_$AppDatabase, $McpApprovalsTable> {
  $$McpApprovalsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cwd => $composableBuilder(
    column: $table.cwd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get commandNormalized => $composableBuilder(
    column: $table.commandNormalized,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get commandSha256 => $composableBuilder(
    column: $table.commandSha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get approvedAt => $composableBuilder(
    column: $table.approvedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get connectionScopeId => $composableBuilder(
    column: $table.connectionScopeId,
    builder: (column) => ColumnOrderings(column),
  );

  $$McpClientsTableOrderingComposer get clientId {
    final $$McpClientsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.clientId,
      referencedTable: $db.mcpClients,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$McpClientsTableOrderingComposer(
            $db: $db,
            $table: $db.mcpClients,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$HostsTableOrderingComposer get hostId {
    final $$HostsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.hostId,
      referencedTable: $db.hosts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostsTableOrderingComposer(
            $db: $db,
            $table: $db.hosts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$McpApprovalsTableAnnotationComposer
    extends Composer<_$AppDatabase, $McpApprovalsTable> {
  $$McpApprovalsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cwd =>
      $composableBuilder(column: $table.cwd, builder: (column) => column);

  GeneratedColumn<String> get commandNormalized => $composableBuilder(
    column: $table.commandNormalized,
    builder: (column) => column,
  );

  GeneratedColumn<String> get commandSha256 => $composableBuilder(
    column: $table.commandSha256,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get approvedAt => $composableBuilder(
    column: $table.approvedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<String> get connectionScopeId => $composableBuilder(
    column: $table.connectionScopeId,
    builder: (column) => column,
  );

  $$McpClientsTableAnnotationComposer get clientId {
    final $$McpClientsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.clientId,
      referencedTable: $db.mcpClients,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$McpClientsTableAnnotationComposer(
            $db: $db,
            $table: $db.mcpClients,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$HostsTableAnnotationComposer get hostId {
    final $$HostsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.hostId,
      referencedTable: $db.hosts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostsTableAnnotationComposer(
            $db: $db,
            $table: $db.hosts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$McpApprovalsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $McpApprovalsTable,
          McpApproval,
          $$McpApprovalsTableFilterComposer,
          $$McpApprovalsTableOrderingComposer,
          $$McpApprovalsTableAnnotationComposer,
          $$McpApprovalsTableCreateCompanionBuilder,
          $$McpApprovalsTableUpdateCompanionBuilder,
          (McpApproval, $$McpApprovalsTableReferences),
          McpApproval,
          PrefetchHooks Function({bool clientId, bool hostId})
        > {
  $$McpApprovalsTableTableManager(_$AppDatabase db, $McpApprovalsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$McpApprovalsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$McpApprovalsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$McpApprovalsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> clientId = const Value.absent(),
                Value<String> hostId = const Value.absent(),
                Value<String> cwd = const Value.absent(),
                Value<String> commandNormalized = const Value.absent(),
                Value<String> commandSha256 = const Value.absent(),
                Value<DateTime> approvedAt = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<String?> connectionScopeId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => McpApprovalsCompanion(
                id: id,
                clientId: clientId,
                hostId: hostId,
                cwd: cwd,
                commandNormalized: commandNormalized,
                commandSha256: commandSha256,
                approvedAt: approvedAt,
                expiresAt: expiresAt,
                connectionScopeId: connectionScopeId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String clientId,
                required String hostId,
                required String cwd,
                required String commandNormalized,
                required String commandSha256,
                required DateTime approvedAt,
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<String?> connectionScopeId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => McpApprovalsCompanion.insert(
                id: id,
                clientId: clientId,
                hostId: hostId,
                cwd: cwd,
                commandNormalized: commandNormalized,
                commandSha256: commandSha256,
                approvedAt: approvedAt,
                expiresAt: expiresAt,
                connectionScopeId: connectionScopeId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$McpApprovalsTable, McpApproval>(table),
                  $$McpApprovalsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({clientId = false, hostId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (clientId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.clientId,
                                referencedTable: $$McpApprovalsTableReferences
                                    ._clientIdTable(db),
                                referencedColumn: $$McpApprovalsTableReferences
                                    ._clientIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (hostId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.hostId,
                                referencedTable: $$McpApprovalsTableReferences
                                    ._hostIdTable(db),
                                referencedColumn: $$McpApprovalsTableReferences
                                    ._hostIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$McpApprovalsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $McpApprovalsTable,
      McpApproval,
      $$McpApprovalsTableFilterComposer,
      $$McpApprovalsTableOrderingComposer,
      $$McpApprovalsTableAnnotationComposer,
      $$McpApprovalsTableCreateCompanionBuilder,
      $$McpApprovalsTableUpdateCompanionBuilder,
      (McpApproval, $$McpApprovalsTableReferences),
      McpApproval,
      PrefetchHooks Function({bool clientId, bool hostId})
    >;
typedef $$McpAuditLogTableCreateCompanionBuilder =
    McpAuditLogCompanion Function({
      required String id,
      required DateTime at,
      required String clientId,
      required String clientName,
      Value<String?> hostId,
      Value<String?> hostLabel,
      required String tool,
      required String argsJson,
      required String decision,
      Value<String?> category,
      Value<int?> exitCode,
      Value<int?> durationMs,
      Value<int?> outputBytes,
      Value<String?> outputSha256,
      Value<int> rowid,
    });
typedef $$McpAuditLogTableUpdateCompanionBuilder =
    McpAuditLogCompanion Function({
      Value<String> id,
      Value<DateTime> at,
      Value<String> clientId,
      Value<String> clientName,
      Value<String?> hostId,
      Value<String?> hostLabel,
      Value<String> tool,
      Value<String> argsJson,
      Value<String> decision,
      Value<String?> category,
      Value<int?> exitCode,
      Value<int?> durationMs,
      Value<int?> outputBytes,
      Value<String?> outputSha256,
      Value<int> rowid,
    });

class $$McpAuditLogTableFilterComposer
    extends Composer<_$AppDatabase, $McpAuditLogTable> {
  $$McpAuditLogTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientName => $composableBuilder(
    column: $table.clientName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hostId => $composableBuilder(
    column: $table.hostId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hostLabel => $composableBuilder(
    column: $table.hostLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tool => $composableBuilder(
    column: $table.tool,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get argsJson => $composableBuilder(
    column: $table.argsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get decision => $composableBuilder(
    column: $table.decision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get exitCode => $composableBuilder(
    column: $table.exitCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get outputBytes => $composableBuilder(
    column: $table.outputBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get outputSha256 => $composableBuilder(
    column: $table.outputSha256,
    builder: (column) => ColumnFilters(column),
  );
}

class $$McpAuditLogTableOrderingComposer
    extends Composer<_$AppDatabase, $McpAuditLogTable> {
  $$McpAuditLogTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientName => $composableBuilder(
    column: $table.clientName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hostId => $composableBuilder(
    column: $table.hostId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hostLabel => $composableBuilder(
    column: $table.hostLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tool => $composableBuilder(
    column: $table.tool,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get argsJson => $composableBuilder(
    column: $table.argsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get decision => $composableBuilder(
    column: $table.decision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get exitCode => $composableBuilder(
    column: $table.exitCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get outputBytes => $composableBuilder(
    column: $table.outputBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get outputSha256 => $composableBuilder(
    column: $table.outputSha256,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$McpAuditLogTableAnnotationComposer
    extends Composer<_$AppDatabase, $McpAuditLogTable> {
  $$McpAuditLogTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get at =>
      $composableBuilder(column: $table.at, builder: (column) => column);

  GeneratedColumn<String> get clientId =>
      $composableBuilder(column: $table.clientId, builder: (column) => column);

  GeneratedColumn<String> get clientName => $composableBuilder(
    column: $table.clientName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hostId =>
      $composableBuilder(column: $table.hostId, builder: (column) => column);

  GeneratedColumn<String> get hostLabel =>
      $composableBuilder(column: $table.hostLabel, builder: (column) => column);

  GeneratedColumn<String> get tool =>
      $composableBuilder(column: $table.tool, builder: (column) => column);

  GeneratedColumn<String> get argsJson =>
      $composableBuilder(column: $table.argsJson, builder: (column) => column);

  GeneratedColumn<String> get decision =>
      $composableBuilder(column: $table.decision, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<int> get exitCode =>
      $composableBuilder(column: $table.exitCode, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get outputBytes => $composableBuilder(
    column: $table.outputBytes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get outputSha256 => $composableBuilder(
    column: $table.outputSha256,
    builder: (column) => column,
  );
}

class $$McpAuditLogTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $McpAuditLogTable,
          McpAuditLogData,
          $$McpAuditLogTableFilterComposer,
          $$McpAuditLogTableOrderingComposer,
          $$McpAuditLogTableAnnotationComposer,
          $$McpAuditLogTableCreateCompanionBuilder,
          $$McpAuditLogTableUpdateCompanionBuilder,
          (
            McpAuditLogData,
            BaseReferences<_$AppDatabase, $McpAuditLogTable, McpAuditLogData>,
          ),
          McpAuditLogData,
          PrefetchHooks Function()
        > {
  $$McpAuditLogTableTableManager(_$AppDatabase db, $McpAuditLogTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$McpAuditLogTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$McpAuditLogTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$McpAuditLogTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> at = const Value.absent(),
                Value<String> clientId = const Value.absent(),
                Value<String> clientName = const Value.absent(),
                Value<String?> hostId = const Value.absent(),
                Value<String?> hostLabel = const Value.absent(),
                Value<String> tool = const Value.absent(),
                Value<String> argsJson = const Value.absent(),
                Value<String> decision = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<int?> exitCode = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<int?> outputBytes = const Value.absent(),
                Value<String?> outputSha256 = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => McpAuditLogCompanion(
                id: id,
                at: at,
                clientId: clientId,
                clientName: clientName,
                hostId: hostId,
                hostLabel: hostLabel,
                tool: tool,
                argsJson: argsJson,
                decision: decision,
                category: category,
                exitCode: exitCode,
                durationMs: durationMs,
                outputBytes: outputBytes,
                outputSha256: outputSha256,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required DateTime at,
                required String clientId,
                required String clientName,
                Value<String?> hostId = const Value.absent(),
                Value<String?> hostLabel = const Value.absent(),
                required String tool,
                required String argsJson,
                required String decision,
                Value<String?> category = const Value.absent(),
                Value<int?> exitCode = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<int?> outputBytes = const Value.absent(),
                Value<String?> outputSha256 = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => McpAuditLogCompanion.insert(
                id: id,
                at: at,
                clientId: clientId,
                clientName: clientName,
                hostId: hostId,
                hostLabel: hostLabel,
                tool: tool,
                argsJson: argsJson,
                decision: decision,
                category: category,
                exitCode: exitCode,
                durationMs: durationMs,
                outputBytes: outputBytes,
                outputSha256: outputSha256,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$McpAuditLogTable, McpAuditLogData>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $McpAuditLogTable,
                    McpAuditLogData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$McpAuditLogTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $McpAuditLogTable,
      McpAuditLogData,
      $$McpAuditLogTableFilterComposer,
      $$McpAuditLogTableOrderingComposer,
      $$McpAuditLogTableAnnotationComposer,
      $$McpAuditLogTableCreateCompanionBuilder,
      $$McpAuditLogTableUpdateCompanionBuilder,
      (
        McpAuditLogData,
        BaseReferences<_$AppDatabase, $McpAuditLogTable, McpAuditLogData>,
      ),
      McpAuditLogData,
      PrefetchHooks Function()
    >;
typedef $$BookmarksTableCreateCompanionBuilder =
    BookmarksCompanion Function({
      required String id,
      required String workspaceId,
      Value<String?> hostId,
      Value<String?> templateId,
      Value<int> position,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$BookmarksTableUpdateCompanionBuilder =
    BookmarksCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String?> hostId,
      Value<String?> templateId,
      Value<int> position,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$BookmarksTableReferences
    extends BaseReferences<_$AppDatabase, $BookmarksTable, Bookmark> {
  $$BookmarksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $WorkspacesTable _workspaceIdTable(_$AppDatabase db) =>
      db.workspaces.createAlias('bookmarks__workspace_id__workspaces__id');

  $$WorkspacesTableProcessedTableManager get workspaceId {
    final $_column = $_itemColumn<String>('workspace_id')!;

    final manager = $$WorkspacesTableTableManager(
      $_db,
      $_db.workspaces,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_workspaceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $HostsTable _hostIdTable(_$AppDatabase db) =>
      db.hosts.createAlias('bookmarks__host_id__hosts__id');

  $$HostsTableProcessedTableManager? get hostId {
    final $_column = $_itemColumn<String>('host_id');
    if ($_column == null) return null;
    final manager = $$HostsTableTableManager(
      $_db,
      $_db.hosts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_hostIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $TemplatesTable _templateIdTable(_$AppDatabase db) =>
      db.templates.createAlias('bookmarks__template_id__templates__id');

  $$TemplatesTableProcessedTableManager? get templateId {
    final $_column = $_itemColumn<String>('template_id');
    if ($_column == null) return null;
    final manager = $$TemplatesTableTableManager(
      $_db,
      $_db.templates,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_templateIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$BookmarksTableFilterComposer
    extends Composer<_$AppDatabase, $BookmarksTable> {
  $$BookmarksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$WorkspacesTableFilterComposer get workspaceId {
    final $$WorkspacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableFilterComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$HostsTableFilterComposer get hostId {
    final $$HostsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.hostId,
      referencedTable: $db.hosts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostsTableFilterComposer(
            $db: $db,
            $table: $db.hosts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TemplatesTableFilterComposer get templateId {
    final $$TemplatesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.templateId,
      referencedTable: $db.templates,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TemplatesTableFilterComposer(
            $db: $db,
            $table: $db.templates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookmarksTableOrderingComposer
    extends Composer<_$AppDatabase, $BookmarksTable> {
  $$BookmarksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$WorkspacesTableOrderingComposer get workspaceId {
    final $$WorkspacesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableOrderingComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$HostsTableOrderingComposer get hostId {
    final $$HostsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.hostId,
      referencedTable: $db.hosts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostsTableOrderingComposer(
            $db: $db,
            $table: $db.hosts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TemplatesTableOrderingComposer get templateId {
    final $$TemplatesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.templateId,
      referencedTable: $db.templates,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TemplatesTableOrderingComposer(
            $db: $db,
            $table: $db.templates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookmarksTableAnnotationComposer
    extends Composer<_$AppDatabase, $BookmarksTable> {
  $$BookmarksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$WorkspacesTableAnnotationComposer get workspaceId {
    final $$WorkspacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workspaceId,
      referencedTable: $db.workspaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkspacesTableAnnotationComposer(
            $db: $db,
            $table: $db.workspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$HostsTableAnnotationComposer get hostId {
    final $$HostsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.hostId,
      referencedTable: $db.hosts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HostsTableAnnotationComposer(
            $db: $db,
            $table: $db.hosts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TemplatesTableAnnotationComposer get templateId {
    final $$TemplatesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.templateId,
      referencedTable: $db.templates,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TemplatesTableAnnotationComposer(
            $db: $db,
            $table: $db.templates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookmarksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BookmarksTable,
          Bookmark,
          $$BookmarksTableFilterComposer,
          $$BookmarksTableOrderingComposer,
          $$BookmarksTableAnnotationComposer,
          $$BookmarksTableCreateCompanionBuilder,
          $$BookmarksTableUpdateCompanionBuilder,
          (Bookmark, $$BookmarksTableReferences),
          Bookmark,
          PrefetchHooks Function({
            bool workspaceId,
            bool hostId,
            bool templateId,
          })
        > {
  $$BookmarksTableTableManager(_$AppDatabase db, $BookmarksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BookmarksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BookmarksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BookmarksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String?> hostId = const Value.absent(),
                Value<String?> templateId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookmarksCompanion(
                id: id,
                workspaceId: workspaceId,
                hostId: hostId,
                templateId: templateId,
                position: position,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                Value<String?> hostId = const Value.absent(),
                Value<String?> templateId = const Value.absent(),
                Value<int> position = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => BookmarksCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                hostId: hostId,
                templateId: templateId,
                position: position,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BookmarksTable, Bookmark>(table),
                  $$BookmarksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({workspaceId = false, hostId = false, templateId = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (workspaceId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.workspaceId,
                                    referencedTable: $$BookmarksTableReferences
                                        ._workspaceIdTable(db),
                                    referencedColumn: $$BookmarksTableReferences
                                        ._workspaceIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (hostId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.hostId,
                                    referencedTable: $$BookmarksTableReferences
                                        ._hostIdTable(db),
                                    referencedColumn: $$BookmarksTableReferences
                                        ._hostIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (templateId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.templateId,
                                    referencedTable: $$BookmarksTableReferences
                                        ._templateIdTable(db),
                                    referencedColumn: $$BookmarksTableReferences
                                        ._templateIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$BookmarksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BookmarksTable,
      Bookmark,
      $$BookmarksTableFilterComposer,
      $$BookmarksTableOrderingComposer,
      $$BookmarksTableAnnotationComposer,
      $$BookmarksTableCreateCompanionBuilder,
      $$BookmarksTableUpdateCompanionBuilder,
      (Bookmark, $$BookmarksTableReferences),
      Bookmark,
      PrefetchHooks Function({bool workspaceId, bool hostId, bool templateId})
    >;
typedef $$PendingOperationsTableCreateCompanionBuilder =
    PendingOperationsCompanion Function({
      required String id,
      required String entityType,
      required String entityId,
      required String operation,
      Value<String?> payload,
      Value<String?> beforeImage,
      required int logicalClock,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$PendingOperationsTableUpdateCompanionBuilder =
    PendingOperationsCompanion Function({
      Value<String> id,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> operation,
      Value<String?> payload,
      Value<String?> beforeImage,
      Value<int> logicalClock,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$PendingOperationsTableFilterComposer
    extends Composer<_$AppDatabase, $PendingOperationsTable> {
  $$PendingOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get beforeImage => $composableBuilder(
    column: $table.beforeImage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get logicalClock => $composableBuilder(
    column: $table.logicalClock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingOperationsTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingOperationsTable> {
  $$PendingOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get beforeImage => $composableBuilder(
    column: $table.beforeImage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get logicalClock => $composableBuilder(
    column: $table.logicalClock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingOperationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingOperationsTable> {
  $$PendingOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get beforeImage => $composableBuilder(
    column: $table.beforeImage,
    builder: (column) => column,
  );

  GeneratedColumn<int> get logicalClock => $composableBuilder(
    column: $table.logicalClock,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$PendingOperationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PendingOperationsTable,
          PendingOperation,
          $$PendingOperationsTableFilterComposer,
          $$PendingOperationsTableOrderingComposer,
          $$PendingOperationsTableAnnotationComposer,
          $$PendingOperationsTableCreateCompanionBuilder,
          $$PendingOperationsTableUpdateCompanionBuilder,
          (
            PendingOperation,
            BaseReferences<
              _$AppDatabase,
              $PendingOperationsTable,
              PendingOperation
            >,
          ),
          PendingOperation,
          PrefetchHooks Function()
        > {
  $$PendingOperationsTableTableManager(
    _$AppDatabase db,
    $PendingOperationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingOperationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingOperationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingOperationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> operation = const Value.absent(),
                Value<String?> payload = const Value.absent(),
                Value<String?> beforeImage = const Value.absent(),
                Value<int> logicalClock = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingOperationsCompanion(
                id: id,
                entityType: entityType,
                entityId: entityId,
                operation: operation,
                payload: payload,
                beforeImage: beforeImage,
                logicalClock: logicalClock,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String entityType,
                required String entityId,
                required String operation,
                Value<String?> payload = const Value.absent(),
                Value<String?> beforeImage = const Value.absent(),
                required int logicalClock,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => PendingOperationsCompanion.insert(
                id: id,
                entityType: entityType,
                entityId: entityId,
                operation: operation,
                payload: payload,
                beforeImage: beforeImage,
                logicalClock: logicalClock,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PendingOperationsTable, PendingOperation>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $PendingOperationsTable,
                    PendingOperation
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingOperationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PendingOperationsTable,
      PendingOperation,
      $$PendingOperationsTableFilterComposer,
      $$PendingOperationsTableOrderingComposer,
      $$PendingOperationsTableAnnotationComposer,
      $$PendingOperationsTableCreateCompanionBuilder,
      $$PendingOperationsTableUpdateCompanionBuilder,
      (
        PendingOperation,
        BaseReferences<
          _$AppDatabase,
          $PendingOperationsTable,
          PendingOperation
        >,
      ),
      PendingOperation,
      PrefetchHooks Function()
    >;
typedef $$SyncTombstonesTableCreateCompanionBuilder =
    SyncTombstonesCompanion Function({
      required String entityType,
      required String entityId,
      Value<String?> body,
      required int logicalClock,
      required DateTime deletedAt,
      Value<int> rowid,
    });
typedef $$SyncTombstonesTableUpdateCompanionBuilder =
    SyncTombstonesCompanion Function({
      Value<String> entityType,
      Value<String> entityId,
      Value<String?> body,
      Value<int> logicalClock,
      Value<DateTime> deletedAt,
      Value<int> rowid,
    });

class $$SyncTombstonesTableFilterComposer
    extends Composer<_$AppDatabase, $SyncTombstonesTable> {
  $$SyncTombstonesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get logicalClock => $composableBuilder(
    column: $table.logicalClock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncTombstonesTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncTombstonesTable> {
  $$SyncTombstonesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get logicalClock => $composableBuilder(
    column: $table.logicalClock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncTombstonesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncTombstonesTable> {
  $$SyncTombstonesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<int> get logicalClock => $composableBuilder(
    column: $table.logicalClock,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$SyncTombstonesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncTombstonesTable,
          SyncTombstone,
          $$SyncTombstonesTableFilterComposer,
          $$SyncTombstonesTableOrderingComposer,
          $$SyncTombstonesTableAnnotationComposer,
          $$SyncTombstonesTableCreateCompanionBuilder,
          $$SyncTombstonesTableUpdateCompanionBuilder,
          (
            SyncTombstone,
            BaseReferences<_$AppDatabase, $SyncTombstonesTable, SyncTombstone>,
          ),
          SyncTombstone,
          PrefetchHooks Function()
        > {
  $$SyncTombstonesTableTableManager(
    _$AppDatabase db,
    $SyncTombstonesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncTombstonesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncTombstonesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncTombstonesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String?> body = const Value.absent(),
                Value<int> logicalClock = const Value.absent(),
                Value<DateTime> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncTombstonesCompanion(
                entityType: entityType,
                entityId: entityId,
                body: body,
                logicalClock: logicalClock,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String entityType,
                required String entityId,
                Value<String?> body = const Value.absent(),
                required int logicalClock,
                required DateTime deletedAt,
                Value<int> rowid = const Value.absent(),
              }) => SyncTombstonesCompanion.insert(
                entityType: entityType,
                entityId: entityId,
                body: body,
                logicalClock: logicalClock,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncTombstonesTable, SyncTombstone>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SyncTombstonesTable,
                    SyncTombstone
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncTombstonesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncTombstonesTable,
      SyncTombstone,
      $$SyncTombstonesTableFilterComposer,
      $$SyncTombstonesTableOrderingComposer,
      $$SyncTombstonesTableAnnotationComposer,
      $$SyncTombstonesTableCreateCompanionBuilder,
      $$SyncTombstonesTableUpdateCompanionBuilder,
      (
        SyncTombstone,
        BaseReferences<_$AppDatabase, $SyncTombstonesTable, SyncTombstone>,
      ),
      SyncTombstone,
      PrefetchHooks Function()
    >;
typedef $$SyncStateTableCreateCompanionBuilder =
    SyncStateCompanion Function({
      Value<int> id,
      Value<int> lastSeenClock,
      Value<int> pulledThroughClock,
    });
typedef $$SyncStateTableUpdateCompanionBuilder =
    SyncStateCompanion Function({
      Value<int> id,
      Value<int> lastSeenClock,
      Value<int> pulledThroughClock,
    });

class $$SyncStateTableFilterComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSeenClock => $composableBuilder(
    column: $table.lastSeenClock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pulledThroughClock => $composableBuilder(
    column: $table.pulledThroughClock,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncStateTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSeenClock => $composableBuilder(
    column: $table.lastSeenClock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pulledThroughClock => $composableBuilder(
    column: $table.pulledThroughClock,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncStateTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get lastSeenClock => $composableBuilder(
    column: $table.lastSeenClock,
    builder: (column) => column,
  );

  GeneratedColumn<int> get pulledThroughClock => $composableBuilder(
    column: $table.pulledThroughClock,
    builder: (column) => column,
  );
}

class $$SyncStateTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncStateTable,
          SyncStateData,
          $$SyncStateTableFilterComposer,
          $$SyncStateTableOrderingComposer,
          $$SyncStateTableAnnotationComposer,
          $$SyncStateTableCreateCompanionBuilder,
          $$SyncStateTableUpdateCompanionBuilder,
          (
            SyncStateData,
            BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateData>,
          ),
          SyncStateData,
          PrefetchHooks Function()
        > {
  $$SyncStateTableTableManager(_$AppDatabase db, $SyncStateTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> lastSeenClock = const Value.absent(),
                Value<int> pulledThroughClock = const Value.absent(),
              }) => SyncStateCompanion(
                id: id,
                lastSeenClock: lastSeenClock,
                pulledThroughClock: pulledThroughClock,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> lastSeenClock = const Value.absent(),
                Value<int> pulledThroughClock = const Value.absent(),
              }) => SyncStateCompanion.insert(
                id: id,
                lastSeenClock: lastSeenClock,
                pulledThroughClock: pulledThroughClock,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncStateTable, SyncStateData>(table),
                  BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncStateTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncStateTable,
      SyncStateData,
      $$SyncStateTableFilterComposer,
      $$SyncStateTableOrderingComposer,
      $$SyncStateTableAnnotationComposer,
      $$SyncStateTableCreateCompanionBuilder,
      $$SyncStateTableUpdateCompanionBuilder,
      (
        SyncStateData,
        BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateData>,
      ),
      SyncStateData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$WorkspacesTableTableManager get workspaces =>
      $$WorkspacesTableTableManager(_db, _db.workspaces);
  $$IdentitiesTableTableManager get identities =>
      $$IdentitiesTableTableManager(_db, _db.identities);
  $$HostGroupsTableTableManager get hostGroups =>
      $$HostGroupsTableTableManager(_db, _db.hostGroups);
  $$HostsTableTableManager get hosts =>
      $$HostsTableTableManager(_db, _db.hosts);
  $$KnownHostsTableTableManager get knownHosts =>
      $$KnownHostsTableTableManager(_db, _db.knownHosts);
  $$PortForwardRulesTableTableManager get portForwardRules =>
      $$PortForwardRulesTableTableManager(_db, _db.portForwardRules);
  $$SnippetsTableTableManager get snippets =>
      $$SnippetsTableTableManager(_db, _db.snippets);
  $$RunbooksTableTableManager get runbooks =>
      $$RunbooksTableTableManager(_db, _db.runbooks);
  $$RunbookStepsTableTableManager get runbookSteps =>
      $$RunbookStepsTableTableManager(_db, _db.runbookSteps);
  $$TemplatesTableTableManager get templates =>
      $$TemplatesTableTableManager(_db, _db.templates);
  $$TemplatePanesTableTableManager get templatePanes =>
      $$TemplatePanesTableTableManager(_db, _db.templatePanes);
  $$PairedDevicesTableTableManager get pairedDevices =>
      $$PairedDevicesTableTableManager(_db, _db.pairedDevices);
  $$McpClientsTableTableManager get mcpClients =>
      $$McpClientsTableTableManager(_db, _db.mcpClients);
  $$McpHostGrantsTableTableManager get mcpHostGrants =>
      $$McpHostGrantsTableTableManager(_db, _db.mcpHostGrants);
  $$McpPolicyRulesTableTableManager get mcpPolicyRules =>
      $$McpPolicyRulesTableTableManager(_db, _db.mcpPolicyRules);
  $$McpApprovalsTableTableManager get mcpApprovals =>
      $$McpApprovalsTableTableManager(_db, _db.mcpApprovals);
  $$McpAuditLogTableTableManager get mcpAuditLog =>
      $$McpAuditLogTableTableManager(_db, _db.mcpAuditLog);
  $$BookmarksTableTableManager get bookmarks =>
      $$BookmarksTableTableManager(_db, _db.bookmarks);
  $$PendingOperationsTableTableManager get pendingOperations =>
      $$PendingOperationsTableTableManager(_db, _db.pendingOperations);
  $$SyncTombstonesTableTableManager get syncTombstones =>
      $$SyncTombstonesTableTableManager(_db, _db.syncTombstones);
  $$SyncStateTableTableManager get syncState =>
      $$SyncStateTableTableManager(_db, _db.syncState);
}
