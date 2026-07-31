import 'dart:convert';

/// Model representing a code snippet.
class SnippetModel {
  final String id;
  final String workspaceId;
  final String title;
  final String code;
  final List<String> tags;

  const SnippetModel({
    required this.id,
    required this.workspaceId,
    required this.title,
    required this.code,
    this.tags = const [],
  });

  SnippetModel copyWith({
    String? id,
    String? workspaceId,
    String? title,
    String? code,
    List<String>? tags,
  }) {
    return SnippetModel(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      title: title ?? this.title,
      code: code ?? this.code,
      tags: tags ?? this.tags,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'workspaceId': workspaceId,
        'title': title,
        'code': code,
        'tags': tags,
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
    );
  }
}
