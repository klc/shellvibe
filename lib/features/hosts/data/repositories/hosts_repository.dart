import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../../shared/database/app_database.dart';
import '../../../../shared/database/daos/hosts_dao.dart';
import '../../domain/models/host_group_model.dart';
import '../../domain/models/host_model.dart';

class HostsRepository {
  final HostsDao hostsDao;

  HostsRepository({required this.hostsDao});

  // --- Hosts CRUD ---

  Future<HostModel> saveHost({
    String? id,
    required String workspaceId,
    String? groupId,
    String? identityId,
    required String label,
    required String hostname,
    String? username,
    int port = 22,
    String protocol = 'ssh',
    String? moshServerPath,
    String? moshPortRange,
    String? colorTag,
    String? jumpHostId,
  }) async {
    final hostId = id ?? const Uuid().v4();
    final now = DateTime.now();

    final companion = HostsCompanion(
      id: Value(hostId),
      workspaceId: Value(workspaceId),
      // A present null is required on edits so cleared optional fields are
      // written as NULL instead of leaving the previous value untouched.
      groupId: Value<String?>(groupId),
      identityId: Value<String?>(identityId),
      label: Value(label),
      hostname: Value(hostname),
      username: Value<String?>(username),
      port: Value(port),
      protocol: Value(protocol),
      moshServerPath: Value<String?>(moshServerPath),
      moshPortRange: Value<String?>(moshPortRange),
      colorTag: Value<String?>(colorTag),
      jumpHostId: Value<String?>(jumpHostId),
      // Keep the original creation date on edits.
      createdAt: id == null ? Value(now) : const Value.absent(),
    );

    if (id == null) {
      await hostsDao.insertHost(companion);
    } else {
      final updated = await hostsDao.updateHostById(hostId, companion);
      if (updated != 1) {
        throw StateError('Host not found: $hostId');
      }
    }

    return HostModel(
      id: hostId,
      workspaceId: workspaceId,
      groupId: groupId,
      identityId: identityId,
      label: label,
      hostname: hostname,
      username: username,
      port: port,
      protocol: protocol,
      moshServerPath: moshServerPath,
      moshPortRange: moshPortRange,
      colorTag: colorTag,
      jumpHostId: jumpHostId,
      createdAt: now,
    );
  }

  Future<List<HostModel>> getAllHosts() async {
    final rows = await hostsDao.getAllHosts();
    return rows
        .map(
          (row) => HostModel(
            id: row.id,
            workspaceId: row.workspaceId,
            groupId: row.groupId,
            identityId: row.identityId,
            label: row.label,
            hostname: row.hostname,
            username: row.username,
            port: row.port,
            protocol: row.protocol,
            moshServerPath: row.moshServerPath,
            moshPortRange: row.moshPortRange,
            colorTag: row.colorTag,
            jumpHostId: row.jumpHostId,
            createdAt: row.createdAt,
          ),
        )
        .toList();
  }

  Future<List<HostModel>> getHostsByWorkspace(String workspaceId) async {
    final rows = await hostsDao.getHostsByWorkspace(workspaceId);
    return rows.map(_mapHost).toList();
  }

  Future<HostModel?> getHostById(String id) async {
    final row = await hostsDao.getHostById(id);
    if (row == null) return null;
    return HostModel(
      id: row.id,
      workspaceId: row.workspaceId,
      groupId: row.groupId,
      identityId: row.identityId,
      label: row.label,
      hostname: row.hostname,
      username: row.username,
      port: row.port,
      protocol: row.protocol,
      moshServerPath: row.moshServerPath,
      moshPortRange: row.moshPortRange,
      colorTag: row.colorTag,
      jumpHostId: row.jumpHostId,
      createdAt: row.createdAt,
    );
  }

  Future<void> deleteHost(String id) async {
    await hostsDao.deleteHost(id);
  }

  Stream<List<Host>> watchHosts() {
    return hostsDao.watchAllHosts();
  }

  // --- Host Groups CRUD ---

  Future<HostGroupModel> saveHostGroup({
    String? id,
    required String workspaceId,
    String? parentId,
    required String name,
    String? colorTag,
  }) async {
    final groupId = id ?? const Uuid().v4();

    final companion = HostGroupsCompanion(
      id: Value(groupId),
      workspaceId: Value(workspaceId),
      parentId: Value<String?>(parentId),
      name: Value(name),
      colorTag: Value<String?>(colorTag),
    );

    if (id == null) {
      await hostsDao.insertHostGroup(companion);
    } else {
      final updated = await hostsDao.updateHostGroupById(groupId, companion);
      if (updated != 1) {
        throw StateError('Host group not found: $groupId');
      }
    }

    return HostGroupModel(
      id: groupId,
      workspaceId: workspaceId,
      parentId: parentId,
      name: name,
      colorTag: colorTag,
    );
  }

  Future<List<HostGroupModel>> getAllHostGroups() async {
    final rows = await hostsDao.getAllHostGroups();
    return rows
        .map(
          (row) => HostGroupModel(
            id: row.id,
            workspaceId: row.workspaceId,
            parentId: row.parentId,
            name: row.name,
            colorTag: row.colorTag,
          ),
        )
        .toList();
  }

  Future<List<HostGroupModel>> getHostGroupsByWorkspace(
    String workspaceId,
  ) async {
    final rows = await hostsDao.getHostGroupsByWorkspace(workspaceId);
    return rows.map(_mapGroup).toList();
  }

  Future<HostGroupModel?> getHostGroupById(String id) async {
    final row = await hostsDao.getHostGroupById(id);
    if (row == null) return null;
    return HostGroupModel(
      id: row.id,
      workspaceId: row.workspaceId,
      parentId: row.parentId,
      name: row.name,
      colorTag: row.colorTag,
    );
  }

  Future<void> deleteHostGroup(String id) async {
    await hostsDao.deleteHostGroup(id);
  }

  Stream<List<HostGroup>> watchHostGroups() {
    return hostsDao.watchAllHostGroups();
  }

  HostModel _mapHost(Host row) {
    return HostModel(
      id: row.id,
      workspaceId: row.workspaceId,
      groupId: row.groupId,
      identityId: row.identityId,
      label: row.label,
      hostname: row.hostname,
      username: row.username,
      port: row.port,
      protocol: row.protocol,
      moshServerPath: row.moshServerPath,
      moshPortRange: row.moshPortRange,
      colorTag: row.colorTag,
      jumpHostId: row.jumpHostId,
      createdAt: row.createdAt,
    );
  }

  HostGroupModel _mapGroup(HostGroup row) {
    return HostGroupModel(
      id: row.id,
      workspaceId: row.workspaceId,
      parentId: row.parentId,
      name: row.name,
      colorTag: row.colorTag,
    );
  }
}
