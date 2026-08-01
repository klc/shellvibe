import 'package:uuid/uuid.dart';

import '../../../../shared/database/app_database.dart';
import '../../../../shared/database/daos/workspaces_dao.dart';
import '../../../../shared/database/models/workspace_usage.dart';
import '../../domain/models/workspace_model.dart';

class WorkspaceRepository {
  final WorkspacesDao _dao;
  static const _uuid = Uuid();

  WorkspaceRepository(this._dao);

  Stream<List<WorkspaceModel>> watchWorkspaces() {
    return _dao.watchAllWorkspaces().map((items) => items.map(_map).toList());
  }

  Future<List<WorkspaceModel>> getWorkspaces() async {
    final items = await _dao.getAllWorkspaces();
    return items.map(_map).toList();
  }

  Future<WorkspaceModel> createWorkspace(String rawName) async {
    final name = _normalizeName(rawName);
    await _ensureNameAvailable(name);

    final workspace = WorkspacesCompanion.insert(
      id: _uuid.v4(),
      name: name,
      createdAt: DateTime.now(),
    );
    await _dao.insertWorkspace(workspace);
    return _map((await _dao.getWorkspaceById(workspace.id.value))!);
  }

  Future<void> renameWorkspace(String id, String rawName) async {
    final name = _normalizeName(rawName);
    final current = await _dao.getWorkspaceById(id);
    if (current == null) {
      throw StateError('Workspace not found.');
    }
    await _ensureNameAvailable(name, excludingId: id);
    await _dao.updateWorkspaceName(id, name);
  }

  Future<WorkspaceUsage> getUsage(String id) => _dao.getWorkspaceUsage(id);

  Future<void> deleteWorkspace(String id) async {
    if (id == 'default') {
      throw StateError('Default Workspace cannot be deleted.');
    }
    final deleted = await _dao.deleteWorkspace(id);
    if (deleted == 0) {
      throw StateError('Workspace not found.');
    }
  }

  String _normalizeName(String rawName) {
    final name = rawName.trim();
    if (name.isEmpty) {
      throw ArgumentError('Workspace name is required.');
    }
    return name;
  }

  Future<void> _ensureNameAvailable(String name, {String? excludingId}) async {
    final normalized = name.toLowerCase();
    final existing = await _dao.getAllWorkspaces();
    final duplicate = existing.any(
      (workspace) =>
          workspace.id != excludingId &&
          workspace.name.trim().toLowerCase() == normalized,
    );
    if (duplicate) {
      throw StateError('A workspace with this name already exists.');
    }
  }

  WorkspaceModel _map(Workspace workspace) {
    return WorkspaceModel(
      id: workspace.id,
      name: workspace.name,
      colorCode: workspace.colorCode,
      createdAt: workspace.createdAt,
    );
  }
}
