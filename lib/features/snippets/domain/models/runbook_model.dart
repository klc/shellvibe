import 'runbook_step_model.dart';

/// Model representing an Executable Runbook.
class RunbookModel {
  final String id;
  final String workspaceId;
  final String title;
  final String? description;
  final List<RunbookStepModel> steps;
  final DateTime createdAt;

  const RunbookModel({
    required this.id,
    required this.workspaceId,
    required this.title,
    this.description,
    this.steps = const [],
    required this.createdAt,
  });

  RunbookModel copyWith({
    String? id,
    String? workspaceId,
    String? title,
    String? description,
    List<RunbookStepModel>? steps,
    DateTime? createdAt,
  }) {
    return RunbookModel(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      title: title ?? this.title,
      description: description ?? this.description,
      steps: steps ?? this.steps,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'workspaceId': workspaceId,
        'title': title,
        'description': description,
        'steps': steps.map((s) => s.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory RunbookModel.fromJson(Map<String, dynamic> json) => RunbookModel(
        id: json['id'] as String,
        workspaceId: json['workspaceId'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        steps: (json['steps'] as List<dynamic>?)
                ?.map((e) => RunbookStepModel.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
