import 'dart:convert';

import 'variable_declaration.dart';

/// Model representing a code snippet.
class SnippetModel {
  final String id;
  final String workspaceId;
  final String title;
  final String code;
  final List<String> tags;

  /// What the snippet says about its `${INPUT:...}` placeholders.
  final List<VariableDeclaration> variables;

  const SnippetModel({
    required this.id,
    required this.workspaceId,
    required this.title,
    required this.code,
    this.tags = const [],
    this.variables = const [],
  });

  SnippetModel copyWith({
    String? id,
    String? workspaceId,
    String? title,
    String? code,
    List<String>? tags,
    List<VariableDeclaration>? variables,
  }) {
    return SnippetModel(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      title: title ?? this.title,
      code: code ?? this.code,
      tags: tags ?? this.tags,
      variables: variables ?? this.variables,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'workspaceId': workspaceId,
        'title': title,
        'code': code,
        'tags': tags,
        'variables': [for (final v in variables) v.toJson()],
      };

  factory SnippetModel.fromJson(Map<String, dynamic> json) {
    List<String> tagsList = [];
    if (json['tags'] is String) {
      try {
        final decoded = jsonDecode(json['tags'] as String);
        if (decoded is List) {
          tagsList = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    } else if (json['tags'] is List) {
      tagsList = (json['tags'] as List).map((e) => e.toString()).toList();
    }

    return SnippetModel(
      id: json['id'] as String,
      workspaceId: json['workspaceId'] as String,
      title: json['title'] as String,
      code: json['code'] as String,
      tags: tagsList,
      variables: [
        for (final v in (json['variables'] as List?) ?? const [])
          ?VariableDeclaration.tryFromJson(v),
      ],
    );
  }
}
