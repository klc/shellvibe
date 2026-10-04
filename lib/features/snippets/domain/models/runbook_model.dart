import 'runbook_step_model.dart';
import 'variable_declaration.dart';

/// Model representing an Executable Runbook.
class RunbookModel {
  final String id;
  final String workspaceId;
  final String title;
  final String? description;
  final List<RunbookStepModel> steps;
  final DateTime createdAt;

  /// Hosts the run-target sheet preselects. May name hosts that no longer
  /// exist; readers drop those.
  final List<String> defaultHostIds;

  /// What the runbook says about its `${INPUT:...}` placeholders.
  final List<VariableDeclaration> variables;
  final List<String> tags;

  const RunbookModel({
    required this.id,
    required this.workspaceId,
    required this.title,
    this.description,
    this.steps = const [],
    required this.createdAt,
    this.defaultHostIds = const [],
    this.variables = const [],
    this.tags = const [],
  });

  RunbookModel copyWith({
    String? id,
    String? workspaceId,
    String? title,
    String? description,
    List<RunbookStepModel>? steps,
    DateTime? createdAt,
    List<String>? defaultHostIds,
    List<VariableDeclaration>? variables,
    List<String>? tags,
  }) {
    return RunbookModel(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      title: title ?? this.title,
      description: description ?? this.description,
      steps: steps ?? this.steps,
      createdAt: createdAt ?? this.createdAt,
      defaultHostIds: defaultHostIds ?? this.defaultHostIds,
      variables: variables ?? this.variables,
      tags: tags ?? this.tags,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'workspaceId': workspaceId,
    'title': title,
    'description': description,
    'steps': steps.map((s) => s.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'defaultHostIds': defaultHostIds,
    'variables': [for (final v in variables) v.toJson()],
    'tags': tags,
  };

  factory RunbookModel.fromJson(Map<String, dynamic> json) => RunbookModel(
    id: json['id'] as String,
    workspaceId: json['workspaceId'] as String,
    title: json['title'] as String,
    description: json['description'] as String?,
    steps:
        (json['steps'] as List<dynamic>?)
            ?.map((e) => RunbookStepModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [],
    createdAt: DateTime.parse(json['createdAt'] as String),
    defaultHostIds:
        (json['defaultHostIds'] as List<dynamic>?)
            ?.whereType<String>()
            .toList() ??
        const [],
    variables: [
      for (final v in (json['variables'] as List?) ?? const [])
        ?VariableDeclaration.tryFromJson(v),
    ],
    tags: (json['tags'] as List?)?.whereType<String>().toList() ?? const [],
  );
}
