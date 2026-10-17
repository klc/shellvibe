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
}
