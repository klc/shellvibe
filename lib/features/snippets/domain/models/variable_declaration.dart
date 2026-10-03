import 'dart:convert';

/// How a `${INPUT:name}` placeholder is asked for.
enum VariableType {
  /// Free text.
  text,

  /// One of [VariableDeclaration.options].
  enumeration,

  /// Free text that is hidden as typed, never prefilled and never remembered.
  secret;

  /// The stored form (`text` / `enum` / `secret`), shared by the database and
  /// sync.
  String get wireName => this == enumeration ? 'enum' : name;

  static VariableType parse(String? value) => switch (value) {
    'enum' => enumeration,
    'secret' => secret,
    _ => text,
  };
}

/// What a snippet or runbook says about one of its `${INPUT:name}`
/// placeholders. A placeholder with no declaration is required free text, as
/// it always was.
class VariableDeclaration {
  final String name;
  final VariableType type;
  final String? label;
  final String? description;
  final String? defaultValue;

  /// The choices of an [VariableType.enumeration].
  final List<String> options;
  final bool required;

  const VariableDeclaration({
    required this.name,
    this.type = VariableType.text,
    this.label,
    this.description,
    this.defaultValue,
    this.options = const [],
    this.required = true,
  });

  /// Says nothing beyond "required free text", which an undeclared placeholder
  /// is anyway, so there is nothing to store.
  bool get isPlain =>
      type == VariableType.text &&
      required &&
      (label?.isEmpty ?? true) &&
      (description?.isEmpty ?? true) &&
      (defaultValue?.isEmpty ?? true);

  /// What the prompt calls it.
  String get displayLabel =>
      (label?.trim().isNotEmpty ?? false) ? label! : name;

  VariableDeclaration copyWith({
    VariableType? type,
    String? label,
    String? description,
    String? defaultValue,
    List<String>? options,
    bool? required,
    bool clearLabel = false,
    bool clearDescription = false,
    bool clearDefault = false,
  }) => VariableDeclaration(
    name: name,
    type: type ?? this.type,
    label: clearLabel ? null : (label ?? this.label),
    description: clearDescription ? null : (description ?? this.description),
    defaultValue: clearDefault ? null : (defaultValue ?? this.defaultValue),
    options: options ?? this.options,
    required: required ?? this.required,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type.wireName,
    if (label != null) 'label': label,
    if (description != null) 'description': description,
    // A secret never has a stored default: it would be a secret on disk.
    if (defaultValue != null && type != VariableType.secret)
      'defaultValue': defaultValue,
    if (type == VariableType.enumeration) 'options': options,
    'required': required,
  };

  static VariableDeclaration? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    if (name is! String || name.isEmpty) return null;
    final type = VariableType.parse(json['type'] as String?);
    return VariableDeclaration(
      name: name,
      type: type,
      label: json['label'] as String?,
      description: json['description'] as String?,
      defaultValue: type == VariableType.secret
          ? null
          : json['defaultValue'] as String?,
      options:
          (json['options'] as List?)?.whereType<String>().toList() ?? const [],
      required: json['required'] as bool? ?? true,
    );
  }

  /// The JSON a declarations column stores, or null for none.
  static String? encodeList(List<VariableDeclaration> declarations) =>
      declarations.isEmpty
      ? null
      : jsonEncode([for (final d in declarations) d.toJson()]);

  /// Reads a declarations column; anything unreadable is no declarations.
  static List<VariableDeclaration> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded) ?VariableDeclaration.tryFromJson(item),
      ];
    } catch (_) {
      return const [];
    }
  }
}
