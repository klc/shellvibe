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

  /// The same runbook with other steps; only tests use it.
  RunbookModel copyWith({List<RunbookStepModel>? steps}) => RunbookModel(
    id: id,
    workspaceId: workspaceId,
    title: title,
    description: description,
    steps: steps ?? this.steps,
    createdAt: createdAt,
    defaultHostIds: defaultHostIds,
    variables: variables,
    tags: tags,
  );

  /// The steps in run order.
  List<RunbookStepModel> get orderedSteps =>
      [...steps]..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));
}
