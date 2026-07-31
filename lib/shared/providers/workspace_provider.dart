import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorkspaceItem {
  final String id;
  final String name;
  final String description;

  const WorkspaceItem({
    required this.id,
    required this.name,
    required this.description,
  });
}

const defaultWorkspaces = [
  WorkspaceItem(id: 'default', name: 'Default Workspace', description: 'Primary environment'),
  WorkspaceItem(id: 'production', name: 'Production', description: 'Production infrastructure'),
  WorkspaceItem(id: 'staging', name: 'Staging', description: 'Staging & test environments'),
];

final activeWorkspaceIdProvider = StateProvider<String>((ref) => 'default');

final workspacesProvider = Provider<List<WorkspaceItem>>((ref) => defaultWorkspaces);
