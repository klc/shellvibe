class WorkspaceModel {
  final String id;
  final String name;
  final String? colorCode;
  final DateTime createdAt;

  const WorkspaceModel({
    required this.id,
    required this.name,
    this.colorCode,
    required this.createdAt,
  });
}
